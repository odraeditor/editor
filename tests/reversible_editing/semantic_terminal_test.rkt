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
(check-not-false script-path "util-linux script is required for the reversible-editing PTY scenario")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define control-x (bytes 24))
(define control-s (bytes 19))
(define control-slash-or-underscore (bytes 31))
(define backspace (bytes 127))
(define exit-sequence (bytes 24 3))
(define restoration-sequence #"\33[?25h\33[0m\r\n")

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define (contains? haystack needle)
  (regexp-match? (byte-regexp (regexp-quote needle)) haystack))

(define test-root (make-temporary-file "odra-semantic-undo-~a" 'directory))
(define document-path (build-path test-root "sample.txt"))

(dynamic-wind
 void
 (lambda ()
   (call-with-output-file
    document-path
    #:exists 'truncate/replace
    (lambda (output) (display "base" output)))
   (define configuration-home (build-path test-root "config"))
   (define state-home (build-path test-root "state"))
   (define cache-home (build-path test-root "cache"))
   (define data-home (build-path test-root "data"))
   (for ([directory (in-list
                     (list configuration-home state-home cache-home data-home))])
     (make-directory* directory))
   (define command
     (string-append
      "stty rows 24 cols 80; exec env "
      "HOME=" (shell-quote (path->string test-root)) " "
      "XDG_CONFIG_HOME=" (shell-quote (path->string configuration-home)) " "
      "XDG_STATE_HOME=" (shell-quote (path->string state-home)) " "
      "XDG_CACHE_HOME=" (shell-quote (path->string cache-home)) " "
      "XDG_DATA_HOME=" (shell-quote (path->string data-home)) " "
      (shell-quote odra-path)
      " "
      (shell-quote (path->string document-path))))
   (define-values (process output input error-output)
     (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
   (define startup-output (open-output-bytes))
   (wait-for-terminal-readiness!
    'reversible-editing process output input error-output startup-output
    #:content-marker
    (string->bytes/utf-8 (path->string (file-name-from-path document-path))))
   (define output-reader (thread (lambda () (copy-port output startup-output))))
   (define (wait-for-output! value [timeout 12])
     (define deadline (+ (current-inexact-milliseconds) (* timeout 1000)))
     (let loop ()
       (cond
         [(contains? (get-output-bytes startup-output) value) #t]
         [(>= (current-inexact-milliseconds) deadline) #f]
         [else
          (sleep 0.05)
          (loop)])))
   (write-bytes
    (bytes-append
     #"ax"
     backspace
     (string->bytes/utf-8 "界")
     control-slash-or-underscore
     (bytes 9)
     control-x
     control-s)
    input)
   (flush-output input)
   (check-true (wait-for-output! #"Saved")
               "saving must publish readable feedback")
   (write-bytes
    (bytes-append
     control-x
     #"u"
     #"\33xredo\r"
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
     (byte-regexp (regexp-quote (string->bytes/utf-8 "    base")))
     output-bytes))
   (check-true
    (regexp-match?
     (byte-regexp (regexp-quote restoration-sequence))
     output-bytes))
   (check-equal? (file->string document-path) "    base"))
 (lambda ()
   (when (directory-exists? test-root)
     (delete-directory/files test-root))))
