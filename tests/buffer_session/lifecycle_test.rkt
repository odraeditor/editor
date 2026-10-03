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
(check-not-false script-path "util-linux script is required for buffer lifecycle scenarios")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define control-x (bytes 24))
(define control-c (bytes 3))
(define control-s (bytes 19))
(define enter (bytes 13))

(define (utf8 text)
  (string->bytes/utf-8 text))

(define (contains? haystack needle)
  (regexp-match? (byte-regexp (regexp-quote needle)) haystack))

(define (run-editor name initial-path input-bytes)
  (define command
    (string-append
     "stty rows 12 cols 100; exec " odra-path " " (path->string initial-path)))
  (define-values (process output input error-output)
    (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
  (define startup-output (open-output-bytes))
  (wait-for-terminal-readiness!
   'buffer-lifecycle process output input error-output startup-output
   #:content-marker
   (string->bytes/utf-8 (path->string (file-name-from-path initial-path))))
  (define output-reader (thread (lambda () (copy-port output startup-output))))
  (write-bytes input-bytes input)
  (flush-output input)
  (subprocess-wait process)
  (thread-wait output-reader)
  (define output-bytes (get-output-bytes startup-output))
  (define error-bytes (port->bytes error-output))
  (close-input-port output)
  (close-input-port error-output)
  (check-equal? (subprocess-status process) 0 name)
  (check-equal? error-bytes #"" name)
  (check-true (contains? output-bytes #"\33[?25h\33[0m\r\n")
              (string-append name ": terminal restoration"))
  output-bytes)

(define lifecycle-directory (make-temporary-file "odra-buffer-lifecycle-~a" 'directory))
(dynamic-wind
 void
 (lambda ()
   (define primary-path (build-path lifecycle-directory "primary.txt"))
   (call-with-output-file primary-path #:exists 'truncate/replace
     (lambda (output) (display "base" output)))

   (define clean-output
     (run-editor
      "clean final buffer kill"
      primary-path
      (bytes-append control-x #"k" enter control-x control-c)))
   (check-equal? (file->bytes primary-path) #"base")
   (check-true (contains? clean-output #"Kill buffer: "))
   (check-true (contains? clean-output #"Killed buffer"))

   (define discard-output
     (run-editor
      "dirty file discard confirmation"
      primary-path
      (bytes-append
       #"X" control-x #"k" enter #"n"
       control-x #"k" enter #"y"
       control-x control-c)))
   (check-equal? (file->bytes primary-path) #"base")
   (check-true (contains? discard-output #"Discard changes and kill buffer? "))

   (define saved-path (build-path lifecycle-directory "saved-notes.txt"))
   (define saved-label (path->string (normalize-path saved-path)))
   (define first-save-output
     (run-editor
      "unassociated save before kill"
      primary-path
      (bytes-append
       control-x #"b" #"notes" enter
       #"draft"
       control-x #"k" enter #"s" (utf8 saved-label) enter
       control-x control-c)))
   (check-equal? (file->bytes saved-path) #"draft")
   (check-true (contains? first-save-output #"Modified buffer: "))
   (check-true (contains? first-save-output #"Saved and killed buffer"))

   (define exit-output
     (run-editor
      "multi-buffer dirty exit"
      primary-path
      (bytes-append
       #"P"
       control-x #"b" #"exit-notes" enter #"N"
       control-x control-c #"d" #"s")))
   (check-equal? (file->bytes primary-path) #"Pbase")
   (check-true (contains? exit-output #"Save changes? ")))
 (lambda ()
   (delete-directory/files lifecycle-directory)))
