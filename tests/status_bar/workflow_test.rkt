#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         racket/file
         racket/path
         racket/port
         racket/system)

(define script-path (find-executable-path "script"))
(check-not-false script-path "util-linux script is required for the Status Bar PTY scenario")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define (contains? haystack needle)
  (regexp-match? (byte-regexp (regexp-quote needle)) haystack))

(define document-path (make-temporary-file "odra-status-bar-~a.odin"))
(define document-name (path->string (file-name-from-path document-path)))
(define configuration-home (make-temporary-file "odra-status-bar-config-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (call-with-output-file
    document-path
    #:exists 'truncate/replace
    (lambda (output)
      (display "package main\n\nmain :: proc() {\n}\n" output)))
   (define configuration-root (build-path configuration-home "odra"))
   (make-directory* configuration-root)
   (call-with-output-file
    (build-path configuration-root "init.rkt")
    #:exists 'truncate/replace
    (lambda (output)
      (display
       (string-append
        "#lang racket/base\n"
        "(provide odra-status-bar-configuration)\n"
        "(define odra-status-bar-configuration\n"
        "  (hash 'position 'line-column\n"
        "        'visible '(editing-context)\n"
        "        'compact 'automatic))\n")
       output)))
   (define command
     (string-append
      "stty rows 20 cols 80; "
      "(sleep 4.0; stty rows 12 cols 52 < /dev/tty; kill -WINCH $$) & "
      "exec env XDG_CONFIG_HOME=" (shell-quote (path->string configuration-home))
      " " (shell-quote odra-path) " " (shell-quote (path->string document-path))))
   (define-values (process output input error-output)
     (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
   (define output-box (box #""))
   (define output-reader
     (thread (lambda () (set-box! output-box (port->bytes output)))))
   (define input-open? #t)
   (define (send bytes)
     (when input-open?
       (with-handlers ([exn:fail? (lambda (_) (set! input-open? #f))])
         (write-bytes bytes input)
         (flush-output input))))
   (sleep 1.0)
   (send #"\33xstatus-bar-inspect\r")
   (sleep 0.3)
   (send (bytes 7))
   (sleep 0.2)
   (send #"\33xstatus-bar-actions\r")
   (sleep 0.3)
   (send (bytes 7))
   (sleep 2.2)
   (send (bytes 19))
   (sleep 0.2)
   (send (bytes 7 24 3))
   (define completed? (sync/timeout 20 process))
   (unless completed? (subprocess-kill process #t))
   (subprocess-wait process)
   (thread-wait output-reader)
   (define output-bytes (unbox output-box))
   (define error-bytes (port->bytes error-output))
   (close-output-port input)
   (close-input-port output)
   (close-input-port error-output)

   (check-not-false completed?)
   (check-equal? (subprocess-status process) 0
                 (bytes->string/utf-8 output-bytes #\?))
   (check-equal? error-bytes #"" (bytes->string/utf-8 output-bytes #\?))
   (check-true (contains? output-bytes (string->bytes/utf-8 document-name)))
   (check-false (contains? output-bytes #"UTF-8 LF")
                (bytes->string/utf-8 output-bytes #\?))
   (check-true (contains? output-bytes #"odin"))
   (check-false (contains? output-bytes #"(odin)"))
   (check-true (contains? output-bytes #"1:1"))
   (check-false (contains? output-bytes #"1:1 Top")
                (bytes->string/utf-8 output-bytes #\?))
   (check-true (contains? output-bytes #"Status Bar [active pane]"))
   (check-true (contains? output-bytes #"Segment:"))
   (check-false (contains? output-bytes #"0% (1,1)"))
   (check-true (contains? output-bytes (string->bytes/utf-8 "──")))
   (check-true (contains? output-bytes (string->bytes/utf-8 "Search →")))
   (check-true (>= (length (regexp-match* (byte-regexp (regexp-quote #"\33[2J")) output-bytes)) 2))
   (check-false (contains? output-bytes (string->bytes/utf-8 (path->string document-path)))))
 (lambda ()
   (when (file-exists? document-path)
     (delete-file document-path))
   (when (directory-exists? configuration-home)
     (delete-directory/files configuration-home))))
