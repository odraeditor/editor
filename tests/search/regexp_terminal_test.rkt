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

(define (contains-bytes? haystack needle)
  (regexp-match? (byte-regexp (regexp-quote needle)) haystack))

(define document-path (make-temporary-file "odra-regexp-search-~a.txt"))
(call-with-output-file
 document-path
 #:exists 'truncate/replace
 (lambda (output)
   (display "zero alpha-42 one beta-7 end\n" output)))

(define command
  (string-append
   "stty rows 12 cols 80; exec " odra-path " " (path->string document-path)))
(define-values (process output input error-output)
  (subprocess #f #f #f script-path "-qfec" command "/dev/null"))

(define transcript (open-output-bytes))
(wait-for-terminal-readiness!
 'regexp-search process output input error-output transcript
 #:content-marker
 (string->bytes/utf-8 (path->string (file-name-from-path document-path))))
(define output-reader (thread (lambda () (copy-port output transcript))))
(define input-written?
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (write-bytes
     (bytes-append
      (bytes 27 19)     ; C-M-s, start forward regexp search
      #"([a-z]+)-([0-9]+)"
      (bytes 27 19)     ; repeat forward
      (bytes 27 18)     ; reverse
      #"("              ; malformed suffix
      (bytes 7 13)      ; recover last valid pattern, then accept
      (bytes 24 3))     ; C-x C-c
     input)
    (flush-output input)
    #t))
(define completed? (sync/timeout 30 process))
(unless completed? (subprocess-kill process #t))
(subprocess-wait process)
(thread-wait output-reader)

(define output-bytes (get-output-bytes transcript))
(define error-bytes (port->bytes error-output))
(close-input-port output)
(close-input-port error-output)
(delete-file document-path)

(define (contains? value)
  (contains-bytes? output-bytes value))

(check-equal? (subprocess-status process) 0)
(check-not-false completed? "regexp search scenario completion timeout")
(check-true input-written?)
(check-equal? error-bytes #"")
(check-true (contains? #"Regexp \342\206\222 [smart any exact]: "))
(check-true (contains? #"Regexp \342\206\222 [smart/insensitive any exact]: "))
(check-true
 (>= (length (regexp-match* (byte-regexp (regexp-quote #"\33[1m\33[4m")) output-bytes)) 3))
(check-true (contains? #"([a-z]+)-([0-9]+)"))
(check-true (contains? #"alpha-42"))
(check-true (contains? #"beta-7"))
(check-true (contains? #" at "))
(check-true (contains? #"\33[?25h\33[0m\r\n"))
