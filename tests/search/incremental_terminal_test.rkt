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

(define document-path (make-temporary-file "odra-search-~a.txt"))
(call-with-output-file
 document-path
 #:exists 'truncate/replace
 (lambda (output)
   (display "zero alpha one alpha end\n" output)))

(define command
  (string-append
   "stty rows 12 cols 80; exec " odra-path " " (path->string document-path)))
(define-values (process output input error-output)
  (subprocess #f #f #f script-path "-qfec" command "/dev/null"))

(define startup-output (open-output-bytes))
(wait-for-terminal-readiness!
 'incremental-search process output input error-output startup-output
 #:content-marker
 (string->bytes/utf-8 (path->string (file-name-from-path document-path))))
(define input-written?
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (write-bytes
     (bytes-append
      (bytes 19)       ; C-s, start forward search
      #"alpha"
      (bytes 19 18)    ; repeat forward, then reverse
      #"x"
      (bytes 18 7 13)  ; finish failed scan, recover, accept
      (bytes 24 3))    ; C-x C-c
     input)
    (flush-output input)
    #t))
(subprocess-wait process)

(define output-bytes (bytes-append (get-output-bytes startup-output) (port->bytes output)))
(define error-bytes (port->bytes error-output))
(close-input-port output)
(close-input-port error-output)
(delete-file document-path)

(define (contains? value)
  (regexp-match? (byte-regexp (regexp-quote value)) output-bytes))

(check-equal? (subprocess-status process) 0)
(check-true input-written?)
(check-equal? error-bytes #"")
(check-true (contains? #"Search \342\206\222 [smart any exact]: "))
(check-true (contains? #"Search \342\206\222 [smart/insensitive any exact]: "))
(check-true (contains? #"Wrapped Search \342\206\220 [smart/insensitive any exact]: "))
(check-true (contains? #"Failing Search \342\206\220 [smart/insensitive any exact]: "))
(check-true (contains? #"Search \342\206\220 [smart/insensitive any exact]: "))
(check-true
 (>= (length (regexp-match* (byte-regexp (regexp-quote #"\33[1m\33[4m")) output-bytes)) 3))
(check-true (contains? #"alphax"))
(check-true (contains? #"alpha"))
(check-true (contains? #"\33[?25h\33[0m\r\n"))
