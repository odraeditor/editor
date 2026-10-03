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

(define document-path (make-temporary-file "odra-area-balance-navigation-~a.txt"))
(call-with-output-file
 document-path
 #:exists 'truncate/replace
 (lambda (output)
   (display "one alpha\n" output)))

(define command
  (string-append
   "stty rows 14 cols 120; exec " odra-path " " (path->string document-path)))
(define-values (process output input error-output)
  (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
(define transcript (open-output-bytes))
(define error-result (make-channel))
(wait-for-terminal-readiness!
 'command-area-balance process output input error-output transcript
 #:content-marker
 (string->bytes/utf-8 (path->string (file-name-from-path document-path))))
(define output-reader
  (thread (lambda () (copy-port output transcript))))
(define error-reader
  (thread (lambda () (channel-put error-result (port->bytes error-output)))))

(define input-written?
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (for ([stage (in-list (list #"\33x"
                                #"balance-pane-areas"
                                (bytes 7)
                                (bytes-append (bytes 24 3) #"d")))])
      (write-bytes stage input)
      (flush-output input)
      (sleep 0.25))
    #t))
(subprocess-wait process)

(thread-wait output-reader)
(define output-bytes (get-output-bytes transcript))
(define error-bytes (channel-get error-result))
(close-input-port output)
(close-input-port error-output)
(delete-file document-path)

(define (contains? value)
  (regexp-match? (byte-regexp (regexp-quote value)) output-bytes))

(check-equal? (subprocess-status process) 0)
(check-true input-written?)
(check-equal? error-bytes #"")
(define header-match
  (regexp-match
   #px#"\33\\[([0-9]+);1H(?:\33\\[[0-9;]*m)*Commands \\[active editor context\\] 1/1 M-x"
   output-bytes))
(define candidate-match
  (regexp-match
   #px#"\33\\[([0-9]+);1H(?:(?:\33\\[[0-9;]*m)|[^\33\r\n])*balance-pane-areas    Balance visible pane areas\\."
   output-bytes))
(check-not-false header-match)
(check-not-false candidate-match)
(when (and header-match candidate-match)
  (check-equal?
   (string->number (bytes->string/utf-8 (cadr candidate-match)))
   (add1 (string->number (bytes->string/utf-8 (cadr header-match))))))
(check-true (contains? #"\33[?25h\33[0m\r\n"))
