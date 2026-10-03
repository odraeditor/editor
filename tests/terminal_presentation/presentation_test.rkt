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
(check-not-false script-path "util-linux script is required for the PTY scenario")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define test-root (make-temporary-file "odra-presentation-~a" 'directory))
(define document-path (build-path test-root "presentation.txt"))
(call-with-output-file
 document-path
 #:exists 'truncate/replace
 (lambda (output)
   (display
    #<<DOCUMENT
Odra — frontend-independent editor

The canonical UTF-8 text lives in an Odin rope.
This terminal renders an immutable display snapshot.

Unicode: café · é · 界 · 🙂
Tabs:	one	two

Resize the terminal to reproject this view.
Press Control-X, then x to exit.
DOCUMENT
    output)))

(define command
  (string-append
   "stty rows 24 cols 80; "
   "(sleep 0.6; stty rows 30 cols 100 < /dev/tty; kill -WINCH $$) & "
   "exec env "
   "HOME=" (shell-quote (path->string test-root)) " "
   "XDG_CONFIG_HOME="
   (shell-quote (path->string (build-path test-root "config"))) " "
   "XDG_STATE_HOME="
   (shell-quote (path->string (build-path test-root "state"))) " "
   "XDG_CACHE_HOME="
   (shell-quote (path->string (build-path test-root "cache"))) " "
   "XDG_DATA_HOME="
   (shell-quote (path->string (build-path test-root "data"))) " "
   (shell-quote odra-path) " "
   (shell-quote (path->string document-path))))

(define-values (process output input error-output)
  (subprocess #f #f #f script-path "-qfec" command "/dev/null"))

(define transcript (open-output-bytes))
(wait-for-terminal-readiness!
 'terminal-presentation process output input error-output transcript
 #:content-marker #"presentation.txt")
(define output-reader (thread (lambda () (copy-port output transcript))))
(sleep 0.9)
(define input-written?
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (write-bytes
     (bytes-append
      #"x"
      (bytes 127)
      #"\33[3~\rab"
      (bytes 24 7)
      #"c"
      (bytes 24 63 255 27 122 24 117)
      #"\33[B\33[A\33OF\33OH"
      (bytes 24 3 100))
     input)
    (flush-output input)
    #t))
(subprocess-wait process)

(thread-wait output-reader)
(define output-bytes (get-output-bytes transcript))
(define error-bytes (port->bytes error-output))
(close-input-port output)
(close-input-port error-output)
(delete-directory/files test-root)

(check-equal? (subprocess-status process) 0)
(check-true input-written?)
(check-equal? error-bytes #"")
(check-true
 (regexp-match?
  (byte-regexp (regexp-quote (string->bytes/utf-8 "Odra — frontend-independent editor")))
  output-bytes))
(check-true
 (regexp-match?
  (byte-regexp (regexp-quote (string->bytes/utf-8 "Unicode: café")))
  output-bytes))
(check-true
 (regexp-match?
  (byte-regexp (regexp-quote (string->bytes/utf-8 "xOdra — frontend-independent editor")))
  output-bytes))
(define clear-pattern (byte-regexp (regexp-quote #"\33[2J")))
(check-true (>= (length (regexp-match* clear-pattern output-bytes)) 2))
(check-true (regexp-match? (byte-regexp (regexp-quote #"\33[?25h\33[0m\r\n")) output-bytes))
