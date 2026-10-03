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
         "../../src/project/records.rkt")

(define script-path (find-executable-path "script"))
(check-not-false script-path "util-linux script is required for Project scenarios")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define control-x (bytes 24))
(define control-f (bytes 6))
(define control-c (bytes 3))
(define control-g (bytes 7))
(define enter (bytes 13))
(define down #"\33[B")
(define up #"\33[A")

(define (utf8 text)
  (string->bytes/utf-8 text))

(define (contains? haystack needle)
  (regexp-match? (byte-regexp (regexp-quote needle)) haystack))

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define root (make-temporary-file "odra-project-context-~a" 'directory))
(dynamic-wind
 void
 (lambda ()
   (define primary (build-path root "primary"))
   (define secondary (build-path root "secondary"))
   (make-directory primary)
   (make-directory secondary)
   (define external-path (build-path secondary "external.md"))
   (call-with-output-file external-path #:exists 'truncate/replace
     (lambda (output) (display "external\n" output)))
   (check-true
    (odra-record-publication?
     (local-project-record-persist
      primary
      (local-project-record
       #:format-version current-local-project-format-version
       #:id "primary"
       #:generation 1
       #:name "Primary"
       #:root (path->string primary)
       #:trust 'untrusted))))

   (define command
     (string-append
      "stty rows 16 cols 120; HOME="
      (shell-quote (path->string root))
      " exec "
      (shell-quote odra-path)))
   (define-values (process output input error-output)
     (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
   (define transcript (open-output-bytes))
   (define error-bytes #f)
   (wait-for-terminal-readiness!
    'project-membership-workflow process output input error-output transcript
    #:content-marker #"Open Dir")
   (define output-reader
     (thread (lambda () (copy-port output transcript))))
   (define error-reader
     (thread (lambda () (set! error-bytes (port->bytes error-output)))))
   (write-bytes
    (bytes-append
     down down enter #"~/primary" enter
     control-g
     up up enter (utf8 "notes") enter
     control-x control-f #"~/secondary/external.md" enter down
     #"\33xdescribe-project\r"
     control-c #"pf" control-g
     control-x control-c)
    input)
   (flush-output input)
   (define completed? (sync/timeout 20 process))
   (unless completed?
     (subprocess-kill process #t))
   (subprocess-wait process)
   (thread-wait output-reader)
   (thread-wait error-reader)
   (define output-bytes (get-output-bytes transcript))
   (close-input-port output)
   (close-input-port error-output)

   (check-not-false completed? "Project scenario completion timeout")
   (check-equal? (subprocess-status process) 0
                 (format "Project scenario output: ~s" output-bytes))
   (check-equal? error-bytes #"")
   (check-true (contains? output-bytes #"Open directory [local]"))
   (check-true (contains? output-bytes #"Files [active Project]"))
   (check-true (contains? output-bytes #"Project: Primary"))
   (check-true (contains? output-bytes #"~/primary"))
   (check-true (contains? output-bytes #"\33[?25h\33[0m\r\n")))
 (lambda ()
   (delete-directory/files root)))
