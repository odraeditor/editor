#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit racket/file racket/port racket/system)

(define script-path (find-executable-path "script"))
(check-not-false script-path "util-linux script is required for the PTY scenario")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")
(define document-path (make-temporary-file "odra-symbol-navigation-~a.odin"))
(call-with-output-file document-path #:exists 'truncate/replace
  (lambda (output)
    (display "package main\n\nouter :: proc() {\n  inner := proc() {}\n  _ = inner\n}\n" output)))
(define command (string-append "stty rows 24 cols 100; exec " odra-path " " (path->string document-path)))
(define-values (process output input error-output)
  (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
(define transcript (open-output-bytes))
(define read-buffer (make-bytes 4096))
(define (contains? value)
  (regexp-match? (byte-regexp (regexp-quote value)) (get-output-bytes transcript)))
(define (wait-for! value [timeout 10])
  (define deadline (+ (current-inexact-milliseconds) (* timeout 1000)))
  (let loop ()
    (cond [(contains? value) #t]
          [(<= deadline (current-inexact-milliseconds)) #f]
          [(sync/timeout 0.25 output)
           (define count (read-bytes-avail!* read-buffer output))
           (when (exact-positive-integer? count) (write-bytes read-buffer transcript 0 count))
           (loop)]
          [else (loop)])))
(define (send! value) (write-bytes value input) (flush-output input))
(define input-written?
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (check-true (wait-for! #"outer") "Odra did not render the Odin fixture")
    (send! #"\33xsymbol-navigator\r")
    (check-true (wait-for! #"Results [current set]") "The symbol navigator did not open")
    (check-true (wait-for! #"function") "Symbol kind annotations were not rendered")
    (send! #"inner")
    (check-true (wait-for! #"1/1") "Typed symbol filtering did not narrow the result set")
    (send! #"q")
    (sleep 0.5)
    (send! (bytes 24 3))
    #t))
(define completed? (sync/timeout 20 process))
(unless completed? (subprocess-kill process #t))
(subprocess-wait process)
(copy-port output transcript)
(define error-bytes (port->bytes error-output))
(close-input-port output)
(close-input-port error-output)
(delete-file document-path)
(check-equal? (subprocess-status process) 0)
(check-not-false completed? "Odra did not complete the symbol navigation scenario")
(check-true input-written?)
(check-equal? error-bytes #"")
(check-true (contains? #"inner"))
(check-true (contains? #"\33[?25h\33[0m\r\n"))
