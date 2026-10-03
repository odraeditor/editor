#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         racket/file
         racket/path
         racket/port
         racket/runtime-path
         racket/system)

(define-runtime-path repository-root "../..")
(define script-path (find-executable-path "script"))
(check-not-false script-path "util-linux script is required for language-service PTY scenarios")
(define configured-odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false configured-odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")
(define odra-path (path->complete-path configured-odra-path repository-root))
(define fixture-server
  (simplify-path (build-path repository-root "tests" "fixtures" "language-service-server.rkt")))

(define enter (bytes 13))
(define control-g (bytes 7))
(define control-n (bytes 14))
(define control-e (bytes 5))
(define control-x (bytes 24))
(define control-s (bytes 19))
(define control-c (bytes 3))
(define down #"\33[B")
(define meta-x #"\33x")
(define exit-editor (bytes-append control-x control-c))

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define (utf8 value)
  (string->bytes/utf-8 value))

(define (contains? output value)
  (regexp-match? (byte-regexp (regexp-quote value)) output))

(define (open-directory-input directory-name)
  (bytes-append down down enter (utf8 (string-append "~/" directory-name)) enter))

(define (write-project-record directory)
  (define metadata-root (build-path directory ".odra"))
  (make-directory metadata-root)
  (call-with-output-file (build-path metadata-root "project.rkt")
    (lambda (output)
      (fprintf
       output
       "#lang odra/config\n(local-project #:format-version 2 #:id ~s #:generation 1 #:name ~s #:root ~s #:trust trusted)\n"
       "language-service"
       "Language Service"
       (path->string directory)))
    #:exists 'truncate/replace))

(define (write-language-support-configuration home)
  (define configuration-root (build-path home ".config" "odra"))
  (make-directory* configuration-root)
  (call-with-output-file (build-path configuration-root "init.rkt")
    (lambda (output)
      (fprintf
       output
       #<<CONFIGURATION
#lang racket/base

(require odra/languages)

(provide odra-language-support)

(define odra-language-support
  (language-support
   #:language 'fixture
   #:display-name "Fixture"
   #:suffixes '(".fixture")
   #:server
   (language-service
    #:id 'fixture-language-server
    #:display-name "Fixture Language Server"
    #:command (list "/usr/bin/racket" ~s "lsp")
    #:root-markers '(".odra/project.rkt")
    #:initialization-options (hasheq 'profile "fixture")
    #:settings (hasheq 'fixture (hasheq 'enabled #t))
    #:environment (hash "ODRA_FIXTURE_PROFILE" "configured")
    #:features '(diagnostics completion))))
CONFIGURATION
       (path->string fixture-server)))
    #:exists 'truncate/replace))

(define (run-editor name home project search-path actions)
  (define command
    (string-append
     "stty rows 18 cols 118; "
     "(sleep 2.0; stty rows 24 cols 132 < /dev/tty; kill -WINCH $$) & "
     "exec env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor HOME="
     (shell-quote (path->string home))
     " PATH="
     (shell-quote search-path)
     " "
     (shell-quote (path->string odra-path))))
  (define-values (process output input error-output)
    (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
  (define output-box (box #""))
  (define output-lock (make-semaphore 1))
  (define output-updated (make-semaphore 0))
  (define error-box (box #""))
  (define output-reader
    (thread
     (lambda ()
       (define buffer (make-bytes 4096))
       (let read-output ()
         (define count (read-bytes-avail! buffer output))
         (unless (eof-object? count)
           (define chunk (subbytes buffer 0 count))
           (call-with-semaphore
            output-lock
            (lambda () (set-box! output-box (bytes-append (unbox output-box) chunk))))
           (semaphore-post output-updated)
           (read-output))))))
  (define error-reader (thread (lambda () (set-box! error-box (port->bytes error-output)))))
  (define input-open? #t)
  (define (output-snapshot)
    (call-with-semaphore output-lock (lambda () (unbox output-box))))
  (define (output-length)
    (bytes-length (output-snapshot)))
  (define (wait-output pattern start timeout)
    (define deadline (+ (current-inexact-milliseconds) (* timeout 1000.0)))
    (let wait ()
      (define snapshot (output-snapshot))
      (define match
        (regexp-match pattern (subbytes snapshot (min start (bytes-length snapshot)))))
      (cond
        [match match]
        [else
         (define remaining (/ (- deadline (current-inexact-milliseconds)) 1000.0))
         (and (positive? remaining)
              (sync/timeout remaining output-updated)
              (wait))])))
  (define (send bytes [pause 0.25])
    (when input-open?
      (with-handlers ([exn:fail? (lambda (_) (set! input-open? #f))])
        (write-bytes bytes input)
        (flush-output input)))
    (sleep pause))
  (check-not-false
   (wait-output #rx#"Open Project" 0 15.0)
   (string-append name ": editor startup did not become ready"))
  (send (open-directory-input "project") 0.8)
  (send enter 1.4)
  (actions send output-length wait-output)
  (define completed? (sync/timeout 30 process))
  (unless completed? (subprocess-kill process #t))
  (subprocess-wait process)
  (thread-wait output-reader)
  (thread-wait error-reader)
  (close-output-port input)
  (close-input-port output)
  (close-input-port error-output)
  (define output-bytes (unbox output-box))
  (define diagnostic-start (max 0 (- (bytes-length output-bytes) 4096)))
  (check-not-false completed? (string-append name ": completion timeout"))
  (check-equal?
   (subprocess-status process)
   0
   (string-append
    name
    "\n"
    (bytes->string/utf-8 (subbytes output-bytes diagnostic-start) #\?)))
  (check-equal? (unbox error-box) #"" name)
  (check-true (contains? output-bytes #"\33[?25h\33[0m") name)
  output-bytes)

(define root (make-temporary-file "odra-language-service-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (define home (build-path root "home"))
   (define project (build-path home "project"))
   (define fake-bin (build-path root "bin"))
   (define missing-bin (build-path root "missing-bin"))
   (make-directory* project)
   (make-directory fake-bin)
   (make-directory missing-bin)
   (write-project-record project)
   (define source-path (build-path project "main.odin"))
   (call-with-output-file source-path
     (lambda (output)
       (display "package main\n\nmain :: proc() {\n\tmissing_name()\n}\n" output)))
   (define fake-ols (build-path fake-bin "ols"))
   (call-with-output-file fake-ols
     (lambda (output)
       (fprintf output "#!/bin/sh\nexec /usr/bin/racket ~a lsp\n"
                (shell-quote (path->string fixture-server)))))
   (file-or-directory-permissions fake-ols #o755)

   (define workflow-output
     (run-editor
      "factory language-service workflow"
      home
      project
      (string-append (path->string fake-bin) ":/usr/bin")
      (lambda (send _output-length _wait-output)
        (send (bytes-append meta-x #"describe-language-service" enter) 0.8)
        (send control-g 0.25)
        (send (bytes-append meta-x #"restart-language-service" enter) 0.35)
        (send (bytes-append meta-x #"list-language-diagnostics" enter) 0.7)
        (send control-g 0.25)
        (send #"\33gn" 0.35)
        (send (bytes-append control-x (bytes (char->integer #\3))) 0.35)
        (send (bytes-append control-x (bytes (char->integer #\o))) 0.25)
        (send #"\33gp" 0.35)
        (send #"x" 0.35)
        (send (bytes-append control-x control-s) 0.5)
        (send (bytes-append meta-x #"select-theme" enter #"sunset" enter) 0.5)
        (send (bytes-append meta-x #"describe-language-service" enter) 0.8)
        (for ([_row (in-range 24)]) (send down 0.05))
        (send control-g 0.2)
        (send exit-editor 0.3)
        (send #"n" 0))))

   (check-true (contains? workflow-output #"Provider: name=ols kind=Factory state=Selected"))
   (check-true (contains? workflow-output #"Executable: requested=\"ols\""))
   (check-true (contains? workflow-output #"Session: phase=Active"))
   (check-true (contains? workflow-output #"Process: state=Running"))
   (check-true (contains? workflow-output #"Documents: count=1 revoked=false"))
   (check-true (contains? workflow-output #"Diagnostics: generations=1 current=1"))
   (check-true (contains? workflow-output #"Document 1: buffer="))
   (check-true (contains? workflow-output #"fixture diagnostic"))
   (check-true (contains? workflow-output #"Language service restart rejected: Invalid_Session"))
   (check-true (contains? workflow-output #"\33[48;2;243;235;221m\33[2J"))
   (check-true (>= (length (regexp-match* (byte-regexp (regexp-quote #"\33[2J")) workflow-output)) 5))
   (check-true (regexp-match? #rx"^xpackage main" (file->string source-path)))

   (call-with-output-file source-path
     #:exists 'truncate/replace
     (lambda (output) (display "alpha\nbeta\n" output)))
   (define completion-output
     (run-editor
      "language completion workflow"
      home
      project
      (string-append (path->string fake-bin) ":/usr/bin")
      (lambda (send output-length wait-output)
        (define service-ready? #f)
        (for ([_attempt (in-range 6)] #:break service-ready?)
          (define start (output-length))
          (send (bytes-append meta-x #"describe-language-service" enter) 0)
          (set! service-ready?
                (and (wait-output #rx#"Session: phase=Active" start 2.0) #t))
          (send control-g 0))
        (check-true service-ready? "completion language service did not become ready")
        (send control-n 0)
        (send control-e 0)
        (define completion-start (output-length))
        (send (bytes-append meta-x #"complete-at-point" enter) 0)
        (define candidates-ready?
          (and (wait-output #rx#"alphaValue" completion-start 2.0) #t))
        (unless candidates-ready?
          (send (bytes-append meta-x #"describe-completion-state" enter) 0.4))
        (when candidates-ready?
          (send enter 0.3)
          (send (bytes-append control-x control-s) 0.4)
          (check-equal?
           (file->string source-path)
           "# completion\nalpha\nalpha_value\n"
           "completion acceptance did not save both edits")
          (define undo-start (output-length))
          (send (bytes-append control-x #"u") 0)
          (check-not-false
           (wait-output #rx#"beta" undo-start 2.0)
           "completion undo did not become visible")
          (send (bytes-append control-x control-s) 0.4)
          (check-equal?
           (file->string source-path)
           "alpha\nbeta\n"
           "completion acceptance was not one undo unit")
          (define redo-start (output-length))
          (send (bytes-append meta-x #"redo" enter) 0)
          (check-not-false
           (wait-output #rx#"alpha_value" redo-start 2.0)
           "completion redo did not become visible")
          (send (bytes-append control-x control-s) 0.4)
          (check-equal?
           (file->string source-path)
           "# completion\nalpha\nalpha_value\n"
           "completion acceptance did not redo atomically"))
        (send control-g 0.2)
        (send exit-editor 0.3))))
   (check-true
    (contains? completion-output #"alphaValue")
    (bytes->string/utf-8
     (subbytes completion-output (max 0 (- (bytes-length completion-output) 4096)))
     #\?))

   (define configured-home (build-path root "configured-home"))
   (define configured-project (build-path configured-home "project"))
   (make-directory* configured-project)
   (write-project-record configured-project)
   (write-language-support-configuration configured-home)
   (define configured-source (build-path configured-project "main.fixture"))
   (call-with-output-file configured-source
     (lambda (output) (display "fixture source\n" output)))
   (define configured-output
     (run-editor
      "configured language-service workflow"
      configured-home
      configured-project
      "/usr/bin"
      (lambda (send output-length wait-output)
        (define service-ready? #f)
        (for ([_attempt (in-range 6)] #:break service-ready?)
          (define start (output-length))
          (send (bytes-append meta-x #"describe-language-service" enter) 0)
          (set! service-ready?
                (and (wait-output #rx#"Session: phase=Active" start 2.0) #t))
          (unless service-ready? (send control-g 0)))
        (check-true service-ready? "configured language service did not become ready")
        (for ([_row (in-range 24)]) (send down 0.03))
        (send control-g 0.2)
        (define diagnostic-start (output-length))
        (send (bytes-append meta-x #"list-language-diagnostics" enter) 0)
        (check-not-false
         (wait-output #rx#"fixture diagnostic" diagnostic-start 2.0)
         "configured language service diagnostic was not presented")
        (send control-g 0.2)
        (send exit-editor 0.3))))
   (check-true
    (contains? configured-output #"Provider: name=Fixture Language Server kind=Programmable"))
   (check-true
    (contains? configured-output #"Executable: requested=\"/usr/bin/racket\""))
   (check-true (contains? configured-output #"environment-applied"))
   (check-true (contains? configured-output #"initialization-options-applied"))
   (check-true (contains? configured-output #"settings-applied"))
   (check-true (contains? configured-output #"source=Personal"))
   (check-true (contains? configured-output #"fixture diagnostic"))

   (call-with-output-file source-path
     #:exists 'truncate/replace
     (lambda (output)
       (display "package main\n\nmain :: proc() {\n\tvalue := )\n}\n" output)))
   (define real-ols-output
     (run-editor
      "real OLS diagnostic workflow"
      home
      project
      "/usr/bin"
      (lambda (send output-length wait-output)
        (define diagnostics-ready? #f)
        (for ([_attempt (in-range 6)] #:break diagnostics-ready?)
          (define start (output-length))
          (send (bytes-append meta-x #"describe-language-service" enter) 0)
          (define status
            (wait-output #rx#"Diagnostics: generations=[0-9]+ current=[0-9]+" start 2.0))
          (set! diagnostics-ready?
                (and status
                     (regexp-match?
                      #rx#"Diagnostics: generations=[0-9]+ current=[1-9][0-9]*"
                      (car status))))
          (send control-g 0))
        (check-true diagnostics-ready? "real OLS diagnostics did not become ready")
        (define diagnostic-start 0)
        (define diagnostics-presented? #f)
        (for ([_attempt (in-range 3)] #:break diagnostics-presented?)
          (set! diagnostic-start (output-length))
          (send (bytes-append meta-x #"list-language-diagnostics" enter) 0)
          (set! diagnostics-presented?
                (and
                 (wait-output #rx#"Diagnostics \\[current scope\\]" diagnostic-start 2.0)
                 #t))
          (unless diagnostics-presented? (send control-g 0)))
        (check-true diagnostics-presented? "real OLS diagnostic list was not presented")
        (check-not-false
         (wait-output #rx#"expected" diagnostic-start 2.0)
         "real OLS diagnostic text was not presented")
        (send control-g 0.2)
        (send (bytes-append meta-x #"describe-language-service" enter) 0.8)
        (send control-g 0.2)
        (send exit-editor 0.3))))
   (check-true (contains? real-ols-output #"expected an operand"))
   (check-true
    (regexp-match? #rx#"Diagnostics: generations=[0-9]+ current=[1-9][0-9]*" real-ols-output))

   (call-with-output-file source-path
     #:exists 'truncate/replace
     (lambda (output) (display "package main\n\nmain :: proc() {}\n" output)))
   (define missing-output
     (run-editor
      "missing language-service fallback"
      home
      project
      (path->string missing-bin)
      (lambda (send _output-length _wait-output)
        (send (bytes-append meta-x #"describe-language-service" enter) 0.6)
        (send control-g 0.2)
        (send #"x" 0.25)
        (send (bytes-append control-x control-s) 0.35)
        (send exit-editor 0.25)
        (send #"n" 0))))
   (check-true (contains? missing-output #"Executable_Not_Found"))
   (check-true (contains? missing-output #"package main"))
   (check-true (regexp-match? #rx"^xpackage main" (file->string source-path))))
 (lambda ()
   (when (directory-exists? root) (delete-directory/files root))))
