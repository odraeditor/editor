#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         racket/file
         racket/port
         racket/system)

(define script-path (find-executable-path "script"))
(check-not-false script-path "util-linux script is required for the pane PTY scenario")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define document-path (make-temporary-file "odra-panes-~a.txt"))
(call-with-output-file
 document-path
 #:exists 'truncate/replace
 (lambda (output)
   (display "alpha\nbeta\ngamma\ndelta\n" output)))

(define command
  (string-append
   "stty rows 12 cols 40; "
   "(sleep 3.0; stty rows 3 cols 20 < /dev/tty; kill -WINCH $$; "
   "sleep 1.5; stty rows 12 cols 40 < /dev/tty; kill -WINCH $$) & "
   "exec " odra-path " " (path->string document-path)))

(define-values (process output input error-output)
  (subprocess #f #f #f script-path "-qfec" command "/dev/null"))

(define input-open? #t)
(define (send bytes [pause 0.12])
  (when input-open?
    (with-handlers ([exn:fail? (lambda (_) (set! input-open? #f))])
      (write-bytes bytes input)
      (flush-output input)))
  (sleep pause))

(sleep 1.2)
(send (bytes 24 (char->integer #\2))) ; split below
(send (bytes 24 (char->integer #\3))) ; split right inside the upper branch
(send (bytes 24 (char->integer #\}))) ; enlarge the active pane horizontally
(send (bytes 24 (char->integer #\}))) ; repeat exact one-column movement
(send (bytes 24 (char->integer #\{))) ; shrink the active pane horizontally
(send (bytes 24 (char->integer #\^))) ; enlarge the active pane vertically
(send (bytes 24 (char->integer #\+))) ; balance visible pane dimensions
(send (bytes 24 (char->integer #\o))) ; focus next in spatial order
(sleep 1.7)                            ; observe the insufficient resize
(send (bytes 24 (char->integer #\}))) ; rejected resize in recovery
(send (bytes 24 (char->integer #\1)) 0.35) ; keep only active pane and recover
(sleep 1.3)                            ; observe growth and normal rematerialization
(send (bytes 24 (char->integer #\3))) ; split right
(send (bytes 24 (char->integer #\o))) ; focus right
(send (bytes 24 (char->integer #\0))) ; close active pane
(send (bytes 24 (char->integer #\0))) ; request exit instead of closing the final pane
(send #"n")                            ; keep the final pane and continue editing
(send (bytes 24 (char->integer #\2))) ; split below
(send (bytes 24 (char->integer #\1))) ; maximize active pane
(send #"z")                            ; normal editing resumed
(send (bytes 24 (char->integer #\0))) ; request exit from the final pane
(send #"y")                            ; continue through the normal exit workflow
(send #"d" 0)                           ; discard the intentional edit on exit
(define exited? (sync/timeout 10 process))
(unless exited?
  (subprocess-kill process #t))
(subprocess-wait process)

(define output-bytes (port->bytes output))
(define error-bytes (port->bytes error-output))
(close-input-port output)
(close-input-port error-output)
(delete-file document-path)

(check-equal?
 (subprocess-status process)
 0
 (bytes->string/utf-8 output-bytes #\?))
(check-not-false exited?)
(check-equal? error-bytes #"")
(check-true
 (>= (length (regexp-match* (byte-regexp (regexp-quote #"alpha")) output-bytes)) 6))
(check-true
 (regexp-match?
  (byte-regexp (regexp-quote (string->bytes/utf-8 "│")))
  output-bytes))
(check-true
 (regexp-match?
  (byte-regexp (regexp-quote #"Terminal geometry is"))
  output-bytes))
(check-true
 (regexp-match?
  (byte-regexp (regexp-quote #"Last pane. Exit Odra?"))
  output-bytes)
 (bytes->string/utf-8 output-bytes #\?))
(check-true
 (regexp-match?
  (byte-regexp (regexp-quote #"zalpha"))
  output-bytes))
(check-true
 (>= (length (regexp-match* (byte-regexp (regexp-quote #"\33[1m")) output-bytes)) 5))
(check-true
 (regexp-match? (byte-regexp (regexp-quote #"\33[?25h\33[0m\r\n")) output-bytes))
