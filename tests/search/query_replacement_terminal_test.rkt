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
(check-not-false script-path "util-linux script is required for the PTY scenarios")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define (contains? haystack needle)
  (regexp-match? (byte-regexp (regexp-quote needle)) haystack))

(define (run-scenario name initial input-bytes expected)
  (define document-path (make-temporary-file (string-append "odra-" name "-~a.txt")))
  (call-with-output-file
   document-path
   #:exists 'truncate/replace
   (lambda (output) (display initial output)))
  (define command
    (string-append
     "stty rows 12 cols 100; exec " odra-path " " (path->string document-path)))
  (define-values (process output input error-output)
    (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
  (define startup-output (open-output-bytes))
  (wait-for-terminal-readiness!
   'query-replacement process output input error-output startup-output
   #:content-marker
   (string->bytes/utf-8 (path->string (file-name-from-path document-path))))
  (define input-written?
    (with-handlers ([exn:fail? (lambda (_) #f)])
      (write-bytes input-bytes input)
      (flush-output input)
      #t))
  (subprocess-wait process)
  (define output-bytes (bytes-append (get-output-bytes startup-output) (port->bytes output)))
  (define error-bytes (port->bytes error-output))
  (close-input-port output)
  (close-input-port error-output)
  (define saved (file->bytes document-path))
  (delete-file document-path)
  (check-equal? (subprocess-status process) 0 name)
  (check-true input-written? name)
  (check-equal? error-bytes #"" name)
  (check-equal? saved expected name)
  (check-true
   (contains? output-bytes #"\33[?25h\33[0m\r\n")
   (string-append name ": terminal restoration"))
  output-bytes)

(define literal-output
  (run-scenario
   "query-replace-responses"
   "one one one one one one\n"
   (bytes-append
    (bytes 27) #"%"          ; M-%
    #"one" (bytes 13)
    #"two" (bytes 13)
    #"y n" (bytes 127) #"!" ; y, SPC, n, DEL, !
    (bytes 24 19)             ; C-x C-s
    (bytes 24 3))             ; C-x C-c
   #"two two one one two two\n"))
(check-true (contains? literal-output #"Query replace [insensitive; 0 replaced, 0 skipped]"))
(check-true (contains? literal-output #"one -> two"))
(check-true (contains? literal-output #"Replaced 4; skipped 2"))

(define quit-output
  (run-scenario
   "query-replace-quit"
   "one one\n"
   (bytes-append
    (bytes 27) #"%"
    #"one" (bytes 13)
    #"two" (bytes 13)
    #"yq"
    (bytes 24 19)
    (bytes 24 3))
   #"two one\n"))
(check-true (contains? quit-output #"two one"))

(define return-output
  (run-scenario
   "query-replace-return"
   "one one\n"
   (bytes-append
    (bytes 27) #"%"
    #"one" (bytes 13)
    #"two" (bytes 13)
    (bytes 13)                ; RET
    (bytes 24 3))
   #"one one\n"))
(check-true (contains? return-output #"one -> two"))

(define cancel-output
  (run-scenario
   "query-replace-cancel"
   "one one\n"
   (bytes-append
    (bytes 27) #"%"
    #"one" (bytes 13)
    #"two" (bytes 13)
    (bytes 7)                 ; C-g
    (bytes 24 3))
   #"one one\n"))
(check-true (contains? cancel-output #"one -> two"))

(define regexp-output
  (run-scenario
   "query-replace-regexp"
   "alpha-42 beta-7\n"
   (bytes-append
    (bytes 27 29)             ; C-M-%
    #"([a-z]+)-([0-9]+)" (bytes 13)
    #"\\2/\\1" (bytes 13)
    #"."
    (bytes 24 19)
    (bytes 24 3))
   #"42/alpha beta-7\n"))
(check-true (contains? regexp-output #"Query replace regexp:"))
(check-true (contains? regexp-output #"Replaced 1; skipped 0"))
