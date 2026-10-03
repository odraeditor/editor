#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         racket/file
         racket/port
         racket/system
         "../support/terminal-readiness.rkt")

(define script-path (find-executable-path "script"))
(check-not-false script-path "util-linux script is required for the pane buffer PTY scenario")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define document-path (make-temporary-file "odra-pane-buffers-~a.txt"))
(call-with-output-file
 document-path
 #:exists 'truncate/replace
 (lambda (output)
   (display "alpha-buffer\n" output)))

(define command
  (string-append "stty rows 12 cols 48; exec " odra-path " " (path->string document-path)))
(define-values (process output input error-output)
  (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
(define transcript (open-output-bytes))
(wait-for-terminal-readiness!
 'pane-buffer-lifecycle process output input error-output transcript
 #:content-marker #"alpha-buffer")
(define output-reader (thread (lambda () (copy-port output transcript))))

(define input-open? #t)
(define (send bytes [pause 0.15])
  (when input-open?
    (with-handlers ([exn:fail? (lambda (_) (set! input-open? #f))])
      (write-bytes bytes input)
      (flush-output input)))
  (sleep pause))

(send (bytes 24 (char->integer #\2)))       ; split below
(send (bytes 24 (char->integer #\b)))       ; switch active pane buffer
(send #"notes")
(send #"\r")
(send #"omega-buffer")
(send (bytes 24 (char->integer #\o)) 0.4)   ; focus pane retaining the file buffer
(send (bytes 24 (char->integer #\k)))       ; kill current file buffer
(send #"\r" 0.4)
(send (bytes 24 3) 0.4)                     ; request exit
(send #"d" 0)                               ; discard scratch buffer edit

(define exited? (sync/timeout 10 process))
(unless exited?
  (subprocess-kill process #t))
(subprocess-wait process)

(thread-wait output-reader)
(define output-bytes (get-output-bytes transcript))
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
 (regexp-match? (byte-regexp (regexp-quote #"omega-buffer")) output-bytes))
(check-true
 (regexp-match? (byte-regexp (regexp-quote #"alpha-buffer")) output-bytes))
(check-true
 (regexp-match? (byte-regexp (regexp-quote #"Killed buffer")) output-bytes))
(check-true
 (regexp-match? (byte-regexp (regexp-quote #"\33[?25h\33[0m\r\n")) output-bytes))
