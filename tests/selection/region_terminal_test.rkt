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
         "../support/terminal-readiness.rkt")

(define script-path (find-executable-path "script"))
(check-not-false script-path "util-linux script is required for the region PTY scenario")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define control-space (bytes 0))
(define control-g (bytes 7))
(define control-x (bytes 24))
(define control-s (bytes 19))
(define right #"\33[C")
(define exit-sequence (bytes 24 3))
(define restoration-sequence #"\33[?25h\33[0m\r\n")

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define document-path (make-temporary-file "odra-region-~a.txt"))

(dynamic-wind
 void
 (lambda ()
   (call-with-output-file
    document-path
    #:exists 'truncate/replace
    (lambda (output) (display "base" output)))
   (define command
     (string-append
      "stty rows 24 cols 80; exec env -u NO_COLOR COLORTERM=truecolor TERM=xterm-256color "
      (shell-quote odra-path)
      " "
      (shell-quote (path->string document-path))))
   (define-values (process output input error-output)
     (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
   (define startup-output (open-output-bytes))
   (wait-for-terminal-readiness!
    'region-workflow process output input error-output startup-output
    #:content-marker
    (string->bytes/utf-8 (path->string (file-name-from-path document-path))))
   (define output-reader (thread (lambda () (copy-port output startup-output))))
   (write-bytes
    (bytes-append
     control-space
     right
     right
     #"Z"
     control-x
     #"u"
     control-x
     control-x
     control-g
     control-x
     control-s
     exit-sequence)
    input)
   (flush-output input)
   (subprocess-wait process)
   (thread-wait output-reader)
   (define output-bytes (get-output-bytes startup-output))
   (define error-bytes (port->bytes error-output))
   (close-output-port input)
   (close-input-port output)
   (close-input-port error-output)

   (check-equal? (subprocess-status process) 0)
   (check-equal? error-bytes #"")
   (check-true
    (regexp-match?
     (byte-regexp
      (regexp-quote
       #"\33[1m\33[38;2;26;27;38m\33[48;2;213;146;79mba"))
     output-bytes))
   (check-true
    (regexp-match?
     (byte-regexp (regexp-quote restoration-sequence))
     output-bytes))
   (check-equal? (file->string document-path) "base"))
 (lambda ()
   (when (file-exists? document-path)
     (delete-file document-path))))
