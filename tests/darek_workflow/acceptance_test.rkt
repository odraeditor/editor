#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         racket/file
         racket/path
         racket/port
         racket/system
         "../support/terminal-readiness.rkt"
         "../../src/project/persistence.rkt"
         "../../src/project/records.rkt"
         "../../src/workspace/management.rkt"
         (submod "../../src/workspace/management.rkt" test-support))

(define script-path (find-executable-path "script"))
(check-not-false script-path "util-linux script is required for Darek workflow scenarios")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define control-x (bytes 24))
(define control-c (bytes 3))
(define control-w (bytes 23))
(define enter (bytes 13))
(define tab (bytes 9))
(define down #"\33[B")
(define exit-editor (bytes-append control-x (bytes 3)))
(define restoration #"\33[?25h\33[0m\r\n")

(define (contains? output value)
  (regexp-match? (byte-regexp (regexp-quote value)) output))

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define (publish-project dir id name)
  (check-true
   (odra-record-publication?
    (local-project-record-persist
     dir
     (local-project-record
      #:format-version current-local-project-format-version
      #:id id
      #:generation 1
      #:name name
      #:root (path->string dir)
      #:trust 'trusted)))))

(define root (make-temporary-file "odra-darek-workflow-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (define home (build-path root "home"))
   (define directory (build-path home "darek-demo"))
   (define child (build-path directory "folder"))
   (define second-directory (build-path home "second-project"))
   (define start-path (build-path directory "start.odin"))
   (define nested-path (build-path child "nested.rkt"))
   (define second-path (build-path second-directory "second.txt"))
   (make-directory* (build-path home ".config" "odra"))
   (file-or-directory-permissions (build-path home ".config" "odra") #o700)
   (make-directory directory)
   (make-directory child)
   (make-directory second-directory)
   (call-with-output-file start-path
     (lambda (output) (display "package darek_acceptance\n" output)))
   (call-with-output-file nested-path
     (lambda (output) (display "#lang racket/base\n" output)))
   (call-with-output-file second-path
     (lambda (output) (display "second Project\n" output)))
   (publish-project directory "darek-demo" "Darek Demo")
   (publish-project second-directory "second-project" "Second Project")
   (define configuration-root (build-path home ".config" "odra"))
   (for ([entry (in-list (list (list "darek-demo" directory)
                               (list "second-project" second-directory)))])
     (check-true
      (odra-record-publication?
       (project-discovery-record-persist
        configuration-root
        (project-discovery-record
         #:format-version current-project-discovery-format-version
         #:id (car entry)
         #:expected-project-generation 1
         #:root (path->string (cadr entry)))))))
   (define workspace
     (parameterize ([current-workspace-identity (lambda () "daily")])
       (workspace-create-compose configuration-root "Daily" (list directory second-directory))))
   (check-true (odra-workspace-publication? (workspace-publish configuration-root workspace)))

   (define command
     (string-append
      "stty rows 18 cols 100; XDG_CONFIG_HOME="
      (shell-quote (path->string (build-path home ".config")))
      " HOME="
      (shell-quote (path->string home))
      " exec env NO_COLOR=1 TERM=xterm-256color "
      (shell-quote odra-path)))
   (define-values (process output input error-output)
     (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
   (define transcript (open-output-bytes))
   (define error-result (make-channel))
   (wait-for-terminal-readiness!
    'darek-workflow process output input error-output transcript
    #:content-marker #"Create a new buffer")
   (define output-reader (thread (lambda () (copy-port output transcript))))
   (thread (lambda () (channel-put error-result (port->bytes error-output))))
   (define (send bytes [pause 0.2])
     (with-handlers ([exn:fail?
                      (lambda (failure)
                        (displayln (bytes->string/utf-8 (get-output-bytes transcript) #\?)
                                   (current-error-port))
                        (raise failure))])
       (write-bytes bytes input)
       (flush-output input))
     (sleep pause))
   (define (await-from value start [seconds 12])
     (define deadline (+ (current-inexact-milliseconds) (* seconds 1000)))
     (let wait ()
       (define current (get-output-bytes transcript))
       (cond
         [(and (<= start (bytes-length current))
               (contains? (subbytes current start) value))
          #t]
         [(>= (current-inexact-milliseconds) deadline)
         (displayln (bytes->string/utf-8 current #\?) (current-error-port))
         (fail-check (format "timed out waiting for ~s" value))]
         [(sync/timeout 0 process)
          (define process-error (channel-get error-result))
          (displayln (bytes->string/utf-8 current #\?) (current-error-port))
          (fail-check
           (format "editor exited (~a) while waiting for ~s: ~a"
                   (subprocess-status process)
                   value
                   (bytes->string/utf-8 process-error #\?)))]
         [else
          (sleep 0.05)
          (wait)])))
   (define project-start (bytes-length (get-output-bytes transcript)))
   (send (bytes-append down down down enter))
   (await-from #"Projects [global]" project-start)
   (send #"Darek Demo")
   (await-from #"Darek Demo" project-start)
   (send enter)
   (await-from #"Files [active Project]" project-start)
   (send #"start.odin")
   (send enter)
   (await-from #"darek_acceptance" project-start)

   (define open-start (bytes-length (get-output-bytes transcript)))
   (send (bytes-append control-x #"tt"))
   (await-from #"Opened Project in Darek" open-start)
   (await-from #"Darek Demo" open-start)
   (await-from #"folder" open-start)
   (await-from #"start.odin" open-start)
   (send down)
   (send #"\33[C")
   (await-from #"nested.rkt" open-start)
   (send #"\33[D")
   (send #"\33[C")
   (send #"n")
   (send enter)
   (await-from #"Opened Darek file" open-start)
   (await-from #"darek_acceptance" open-start)

   (send (bytes-append control-x #"to"))
   (define create-start (bytes-length (get-output-bytes transcript)))
   (send #"cf")
   (send #"created.txt")
   (send enter)
   (await-from #"Created Darek resource" create-start)
   (await-from #"created.txt" create-start)
   (send #"n")
   (define rename-start (bytes-length (get-output-bytes transcript)))
   (send #"R")
   (await-from #"Rename to:" rename-start)
   (send (make-bytes 11 127) 0.1)
   (send #"renamed.txt" 0.1)
   (send enter)
   (await-from #"Renamed Darek resource" rename-start)
   (await-from #"renamed.txt" rename-start)
   (define copy-path-start (bytes-length (get-output-bytes transcript)))
   (send #"ya")
   (await-from #"Copied Darek path" copy-path-start)

   (define follow-start (bytes-length (get-output-bytes transcript)))
   (send #"tf" 1)
   (await-from #"Darek file follow enabled" follow-start)

   (define preview-start (bytes-length (get-output-bytes transcript)))
   (send #"n")
   (send #"P")
   (await-from #"Darek preview enabled" preview-start)
   (send #"P")
   (await-from #"Darek preview disabled" preview-start)

   (define help-start (bytes-length (get-output-bytes transcript)))
   (send #"?")
   (await-from #"darek-toggle-peek" help-start)
   (send #"q")
   (await-from #"Darek Demo" help-start)
   (define advanced-help-start (bytes-length (get-output-bytes transcript)))
   (send (bytes 127))
   (await-from #"Darek advanced help:" advanced-help-start)
   (send #"q")
   (await-from #"Darek Demo" advanced-help-start)

   (define workspace-start (bytes-length (get-output-bytes transcript)))
   (send (bytes-append control-c control-w #"s"))
   (await-from #"Workspaces [global]" workspace-start)
   (await-from #"Daily" workspace-start)
   (send enter)
   (await-from #"Opened Workspace in Darek" workspace-start)
   (await-from #"Darek Demo" workspace-start)
   (await-from #"Second Project" workspace-start)

   (define hide-start (bytes-length (get-output-bytes transcript)))
   (send #"q")
   (send (bytes-append control-x #"tt"))
   (await-from #"Darek Demo" hide-start)
   (define close-start (bytes-length (get-output-bytes transcript)))
   (send #"Q")
   (await-from #"Closed Darek" close-start)
   (send exit-editor 0)
   (define completed? (sync/timeout 30 process))
   (unless completed? (subprocess-kill process #t))
   (subprocess-wait process)
   (thread-wait output-reader)
   (define output-bytes (get-output-bytes transcript))
   (define error-bytes (channel-get error-result))
   (close-output-port input)
   (close-input-port output)
   (close-input-port error-output)

   (check-not-false completed? (bytes->string/utf-8 output-bytes #\?))
   (check-equal? (subprocess-status process) 0)
   (check-equal? error-bytes #"")
   (check-true (contains? output-bytes #"Opened Project in Darek"))
   (check-true (contains? output-bytes #"Opened Workspace in Darek"))
   (check-true (contains? output-bytes #"darek-demo"))
   (check-true (contains? output-bytes #"folder"))
   (check-true (contains? output-bytes #"nested.rkt"))
   (check-true (contains? output-bytes #"start.odin"))
   (check-true (contains? output-bytes #"Opened Darek file"))
   (check-true (contains? output-bytes #"Created Darek resource"))
   (check-true (contains? output-bytes #"Renamed Darek resource"))
   (check-true (contains? output-bytes #"Copied Darek path"))
   (check-true (contains? output-bytes #"Darek file follow enabled"))
   (check-true (contains? output-bytes #"Closed Darek"))
   (check-true (contains? output-bytes #"Second Project"))
   (check-true (contains? output-bytes #"darek_acceptance"))
   (check-true (file-exists? (build-path child "created.txt")))
   (check-true (file-exists? (build-path directory "renamed.txt")))
   (check-true (contains? output-bytes restoration)))
 (lambda ()
   (when (directory-exists? root)
     (delete-directory/files root))))
