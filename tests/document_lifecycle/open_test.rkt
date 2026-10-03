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
(check-not-false script-path "util-linux script is required for PTY document tests")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define (run-direct . arguments)
  (define-values (process output input error-output)
    (apply subprocess #f #f #f odra-path arguments))
  (close-output-port input)
  (subprocess-wait process)
  (define output-bytes (port->bytes output))
  (define error-bytes (port->bytes error-output))
  (close-input-port output)
  (close-input-port error-output)
  (values (subprocess-status process) output-bytes error-bytes))

(define (run-pty path input-bytes)
  (define command
    (string-append
     "stty rows 24 cols 80; exec "
     (shell-quote odra-path)
     " "
     (shell-quote (path->string path))))
  (define-values (process output input error-output)
    (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
  (define startup-output (open-output-bytes))
  (wait-for-terminal-readiness!
   'document-open process output input error-output startup-output
   #:content-marker
   (string->bytes/utf-8 (path->string (file-name-from-path path))))
  (define output-reader (thread (lambda () (copy-port output startup-output))))
  (write-bytes input-bytes input)
  (flush-output input)
  (subprocess-wait process)
  (thread-wait output-reader)
  (define output-bytes (get-output-bytes startup-output))
  (define error-bytes (port->bytes error-output))
  (close-output-port input)
  (close-input-port output)
  (close-input-port error-output)
  (values (subprocess-status process) output-bytes error-bytes))

(define temporary-directory (make-temporary-file "odra-open-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (define existing-path (build-path temporary-directory "existing.txt"))
   (call-with-output-file
    existing-path
    #:exists 'truncate/replace
    (lambda (output)
      (display "Visible file text\r\nUnicode: 🙂\n" output)))
   (define-values (existing-status existing-output existing-error)
     (run-pty existing-path (bytes 24 3)))
   (check-equal? existing-status 0)
   (check-equal? existing-error #"")
   (check-true
    (regexp-match?
     (byte-regexp (regexp-quote (string->bytes/utf-8 "Visible file text")))
     existing-output))
   (check-true
    (regexp-match? (byte-regexp (regexp-quote #"\33[?25h\33[0m\r\n")) existing-output))

   (define save-path (build-path temporary-directory "save.txt"))
   (call-with-output-file
    save-path
    #:exists 'truncate/replace
    (lambda (output) (display "base" output)))
   (define-values (save-status save-output save-error)
     (run-pty save-path (bytes-append #"new" (bytes 24 19 24 3))))
   (check-equal? save-status 0)
   (check-equal? save-error #"")
   (check-true (regexp-match? #rx#"newbase" save-output))
   (check-equal? (file->string save-path) "newbase")

   (define missing-path (build-path temporary-directory "missing.txt"))
   (define-values (missing-status missing-output missing-error)
     (run-pty missing-path (bytes-append #"new" (bytes 24 3 100))))
   (check-equal? missing-status 0)
   (check-equal? missing-error #"")
   (check-false (file-exists? missing-path))
   (check-true (regexp-match? #rx#"new" missing-output))
   (check-true
    (regexp-match? (byte-regexp (regexp-quote #"\33[?25h\33[0m\r\n")) missing-output))

   (define invalid-path (build-path temporary-directory "invalid.txt"))
   (call-with-output-file
    invalid-path
    #:exists 'truncate/replace
    (lambda (output) (write-bytes (bytes #x61 #xff #x62) output)))
   (define-values (invalid-status invalid-output invalid-error)
     (run-direct (path->string invalid-path)))
   (check-equal? invalid-status 1)
   (check-equal? invalid-output #"")
   (check-true (regexp-match? #rx#"stage=Document_Prepare" invalid-error))
   (check-true (regexp-match? #rx#"document=Malformed_UTF8" invalid-error))

   (define-values (argument-status argument-output argument-error)
     (run-direct "first.txt" "second.txt"))
   (check-equal? argument-status 1)
   (check-equal? argument-output #"")
   (check-true (regexp-match? #rx#"stage=Argument_Admission" argument-error))
   (check-true (regexp-match? #rx#"arguments=2" argument-error)))
 (lambda () (delete-directory/files temporary-directory)))
