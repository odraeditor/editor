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
(check-not-false script-path "util-linux script is required for the PTY scenario")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define document-path (make-temporary-file "odra-search-controls-~a.txt"))
(call-with-output-file
 document-path
 #:exists 'truncate/replace
 (lambda (output)
   (display "alpha beta alpha   beta\n" output)))

(define command
  (string-append
   "stty rows 12 cols 80; exec " odra-path " " (path->string document-path)))
(define-values (process output input error-output)
  (subprocess #f #f #f script-path "-qfec" command "/dev/null"))

(sleep 0.6)
(define input-written?
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (write-bytes
     (bytes-append
      (bytes 19) #"alpha" (bytes 13) ; accept one literal query
      (bytes 19 19)                  ; reuse it from an empty search
      (bytes 27) #"sc"               ; M-s c: case-sensitive
      (bytes 27) #"sw"               ; M-s w: word boundaries
      (bytes 27) #"s "               ; M-s SPC: flexible whitespace
      (bytes 27) #"sr"               ; M-s r: regular expression
      (bytes 7)                       ; cancel and restore the origin
      (bytes 19 23)                  ; C-s C-w: extend with nearby text
      (bytes 27) #"p"                ; M-p: recall the older query
      (bytes 27) #"n"                ; M-n: restore live input
      (bytes 7)
      (bytes 24 3))                   ; C-x C-c
     input)
    (flush-output input)
    #t))
(subprocess-wait process)

(define output-bytes (port->bytes output))
(define error-bytes (port->bytes error-output))
(close-input-port output)
(close-input-port error-output)
(delete-file document-path)

(define (contains? value)
  (regexp-match? (byte-regexp (regexp-quote value)) output-bytes))

(check-equal? (subprocess-status process) 0)
(check-true input-written?)
(check-equal? error-bytes #"")
(check-true (contains? #"alpha"))
(check-true (contains? #"beta"))
(check-true (contains? #"Search \342\206\222 [sensitive word flex]: "))
(check-true (contains? #"Regexp \342\206\222 [sensitive word flex]: "))
(check-true (contains? #"\33[?25h\33[0m\r\n"))
