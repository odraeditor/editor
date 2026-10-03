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
(check-not-false script-path "util-linux script is required for maintained-service PTY acceptance")
(define configured-odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false configured-odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")
(define odra-path (path->complete-path configured-odra-path repository-root))
(define fixture-server
  (simplify-path (build-path repository-root "tests" "fixtures" "language-service-server.rkt")))

(define enter (bytes 13))
(define control-g (bytes 7))
(define control-x (bytes 24))
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

(define (transcript-tail output)
  (define start (max 0 (- (bytes-length output) 4096)))
  (bytes->string/utf-8 (subbytes output start) #\?))

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
       "maintained-language-services"
       "Maintained Language Services"
       (path->string directory)))
    #:exists 'truncate/replace))

(define (run-editor name home project search-path actions)
  (define command
    (string-append
     "stty rows 18 cols 180; "
     "(sleep 2.0; stty rows 24 cols 200 < /dev/tty; kill -WINCH $$) & "
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
  (define (execute-command command-name [pause 0.4])
    (send meta-x 0.25)
    (send (utf8 command-name) 0.25)
    (send enter pause))
  (check-not-false
   (wait-output #rx#"Open Project" 0 15.0)
   (string-append name ": editor startup did not become ready"))
  (send (open-directory-input "project") 0.8)
  (send enter 1.4)
  (actions send execute-command output-length output-snapshot wait-output)
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

(define root (make-temporary-file "odra-maintained-language-services-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (define home (build-path root "home"))
   (define project (build-path home "project"))
   (define fake-bin (build-path root "bin"))
   (make-directory* project)
   (make-directory fake-bin)
   (write-project-record project)
   (define odin-source-path (build-path project "main.odin"))
   (define racket-source-path (build-path project "main.rkt"))
   (define racket-root-marker (build-path project "info.rkt"))
   (call-with-output-file odin-source-path
     (lambda (output) (display "package main\n\nmain :: proc() {}\n" output)))
   (define fake-ols (build-path fake-bin "ols"))
   (call-with-output-file fake-ols
     (lambda (output)
       (fprintf output "#!/bin/sh\nexec /usr/bin/racket ~a lsp\n"
                (shell-quote (path->string fixture-server)))))
   (file-or-directory-permissions fake-ols #o755)

   (define workflow-output
     (run-editor
      "concurrent maintained language services"
      home
      project
      (string-append (path->string fake-bin) ":/usr/bin")
      (lambda (send execute-command output-length output-snapshot wait-output)
        (define odin-ready? #f)
        (for ([_attempt (in-range 8)] #:break odin-ready?)
          (define start (output-length))
          (execute-command "describe-language-service" 0)
          (define provider-match (wait-output #rx#"Provider: name=ols" start 2.0))
          (define active-match
            (and provider-match (wait-output #rx#"Session: phase=Active" start 2.0)))
          (set! odin-ready? (and provider-match active-match #t))
          (send control-g 0.1))
        (check-true
         odin-ready?
         (string-append "maintained OLS did not become ready\n"
                        (transcript-tail (output-snapshot))))

        (call-with-output-file racket-source-path
          (lambda (output) (display "#lang racket/base\n(define answer 42)\n" output)))
        (call-with-output-file racket-root-marker
          (lambda (output) (display "#lang info\n" output)))
        (define open-racket-start (output-length))
        (execute-command "find-file")
        (send #"~/project/main.rkt\r" 0.8)
        (check-not-false
         (wait-output #rx#"main.rkt" open-racket-start 3.0)
         "maintained Racket source did not open")

        (define racket-ready? #f)
        (define racket-process-id #f)
        (for ([_attempt (in-range 10)] #:break racket-ready?)
          (define start (output-length))
          (execute-command "describe-language-service" 0)
          (define provider-match
            (wait-output #rx#"Provider: name=Racket Language Server" start 2.0))
          (define active-match
            (and provider-match (wait-output #rx#"Session: phase=Active" start 2.0)))
          (define process-match
            (and active-match
                 (wait-output #rx#"Process: state=Running pid=([0-9]+)" start 2.0)))
          (when process-match
            (set! racket-process-id (bytes->string/utf-8 (cadr process-match))))
          (set! racket-ready? (and provider-match active-match process-match #t))
          (unless racket-ready? (send control-g 0.1)))
        (check-true
         racket-ready?
         (string-append "maintained Racket service did not become ready\n"
                        (transcript-tail (output-snapshot))))
        (when racket-ready?
          (for ([_row (in-range 30)]) (send down 0.02))
          (send control-g 0.2)
          (execute-command "describe-language-support" 0.6)
          (for ([_row (in-range 30)]) (send down 0.02))
          (send control-g 0.2))

        (check-not-false racket-process-id "maintained Racket service PID was unavailable")
        (when racket-process-id
          (check-true
           (system* (find-executable-path "kill") "-9" racket-process-id)
           "maintained Racket service process could not be killed"))
        (define racket-failed? #f)
        (when racket-process-id
          (for ([_attempt (in-range 8)] #:break racket-failed?)
            (define start (output-length))
            (execute-command "describe-language-service" 0)
            (define provider-match
              (wait-output #rx#"Provider: name=Racket Language Server" start 2.0))
            (define failed-match
              (and provider-match (wait-output #rx#"Session: phase=Failed" start 2.0)))
            (set! racket-failed? (and provider-match failed-match #t))
            (send control-g 0.1)))
        (check-true racket-failed? "Racket service failure was not isolated")

        (define open-odin-start (output-length))
        (execute-command "find-file")
        (send #"~/project/main.odin\r" 0.8)
        (check-not-false
         (wait-output #rx#"main.odin" open-odin-start 3.0)
         "maintained Odin source did not reopen")
        (define odin-still-active?
          (and (wait-output #rx#"odin LS" open-odin-start 3.0) #t))
        (check-true
         odin-still-active?
         (string-append "maintained OLS did not survive the Racket failure\n"
                        (transcript-tail (output-snapshot))))
        (send exit-editor 0.3)
        (send #"d" 0.1))))

   (check-true
    (contains? workflow-output #"Workflow sessions: total=2 active=2 initializing=0 failed=0"))
   (check-true (contains? workflow-output #"Provider: name=Racket Language Server"))
   (check-true (contains? workflow-output #"Provider: name=ols"))
   (check-true (contains? workflow-output #"identity=\"racket-langserver\""))
   (check-true
    (contains? workflow-output #"provenance=\"Odra maintained language support\""))
   (check-true (contains? workflow-output #"racket LS"))
   (check-true (contains? workflow-output #"racket LS:failed"))
   (check-true (contains? workflow-output #"odin LS")))
 (lambda ()
   (when (directory-exists? root) (delete-directory/files root))))
