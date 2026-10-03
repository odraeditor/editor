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
(check-not-false script-path "util-linux script is required for PTY save-path tests")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define control-x (bytes 24))
(define control-s (bytes 19))
(define control-g (bytes 7))
(define enter (bytes 13))
(define exit-sequence (bytes 24 3 100))
(define create-buffer-sequence (bytes-append (bytes 13) #"untitled" (bytes 13)))
(define restoration-sequence #"\33[?25h\33[0m\r\n")

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define (run-pathless-pty input-bytes)
  (define command
    (string-append
     "stty rows 24 cols 80; exec "
     (shell-quote odra-path)))
  (define-values (process output input error-output)
    (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
  (define startup-output (open-output-bytes))
  (wait-for-terminal-readiness!
   'document-save-path process output input error-output startup-output
   #:content-marker #"Open Dir")
  (define output-reader (thread (lambda () (copy-port output startup-output))))
  (write-bytes (bytes-append create-buffer-sequence input-bytes) input)
  (flush-output input)
  (subprocess-wait process)
  (thread-wait output-reader)
  (define output-bytes (get-output-bytes startup-output))
  (define error-bytes (port->bytes error-output))
  (close-output-port input)
  (close-input-port output)
  (close-input-port error-output)
  (values (subprocess-status process) output-bytes error-bytes))

(define (save-input text path [after-save #""])
  (bytes-append
   (string->bytes/utf-8 text)
   control-x
   control-s
   (string->bytes/utf-8 (path->string path))
   enter
   after-save
   exit-sequence))

(define (check-restored status output error-output)
  (check-equal? status 0)
  (check-equal? error-output #"")
  (check-true
   (regexp-match?
    (byte-regexp (regexp-quote restoration-sequence))
    output)))

(define (check-output-matches pattern output)
  (define diagnostic-limit 4096)
  (define diagnostic-output
    (if (> (bytes-length output) diagnostic-limit)
        (subbytes output (- (bytes-length output) diagnostic-limit))
        output))
  (check-true
   (regexp-match? pattern output)
   (format "terminal output did not match ~s; output tail: ~s"
           pattern
           diagnostic-output)))

(define temporary-directory (make-temporary-file "odra-save-path-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (define accepted-path (build-path temporary-directory "accepted.md"))
   (define-values (accepted-status accepted-output accepted-error)
     (run-pathless-pty (save-input "draft 🙂" accepted-path)))
   (check-restored accepted-status accepted-output accepted-error)
   (check-equal? (file->string accepted-path) "draft 🙂")
   (check-true (regexp-match? #rx#"Save as: " accepted-output))
   (check-true (regexp-match? #rx#"Saved" accepted-output))

   (define existing-path (build-path temporary-directory "existing.md"))
   (call-with-output-file
    existing-path
    #:exists 'truncate/replace
    (lambda (output) (display "external" output)))
   (define-values (existing-status existing-output existing-error)
     (run-pathless-pty (save-input "authoritative" existing-path)))
   (check-restored existing-status existing-output existing-error)
   (check-equal? (file->string existing-path) "authoritative")

   (define cancelled-path (build-path temporary-directory "cancelled.md"))
   (define cancelled-input
     (bytes-append
      #"unsaved"
      control-x
      control-s
      (string->bytes/utf-8 (path->string cancelled-path))
      control-g
      #"z"
      exit-sequence))
   (define-values (cancelled-status cancelled-output cancelled-error)
     (run-pathless-pty cancelled-input))
   (check-restored cancelled-status cancelled-output cancelled-error)
   (check-false (file-exists? cancelled-path))
   (check-true (regexp-match? #rx#"unsavedz" cancelled-output))

   (define empty-input
     (bytes-append #"empty" control-x control-s enter control-g exit-sequence))
   (define-values (empty-status empty-output empty-error)
     (run-pathless-pty empty-input))
   (check-restored empty-status empty-output empty-error)
   (check-output-matches
    (byte-regexp (regexp-quote #"Save as (invalid): "))
    empty-output)

   (define missing-path
     (build-path temporary-directory "missing-parent" "invalid.md"))
   (define-values (missing-status missing-output missing-error)
     (run-pathless-pty (save-input "recover" missing-path #"z")))
   (check-restored missing-status missing-output missing-error)
   (check-false (file-exists? missing-path))
   (check-output-matches #rx#"The file could not be saved" missing-output)
   (check-true (regexp-match? #rx#"recoverz" missing-output))

   (define directory-target (build-path temporary-directory "target-directory"))
   (make-directory directory-target)
   (define-values (directory-status directory-output directory-error)
     (run-pathless-pty (save-input "directory" directory-target)))
   (check-restored directory-status directory-output directory-error)
   (check-true (directory-exists? directory-target))
   (check-output-matches #rx#"The file could not be saved" directory-output)

   (define inaccessible-parent (build-path temporary-directory "inaccessible"))
   (make-directory inaccessible-parent)
   (file-or-directory-permissions inaccessible-parent #o500)
   (define inaccessible-path (build-path inaccessible-parent "denied.md"))
   (define-values (inaccessible-status inaccessible-output inaccessible-error)
     (run-pathless-pty (save-input "denied" inaccessible-path)))
   (file-or-directory-permissions inaccessible-parent #o700)
   (check-restored inaccessible-status inaccessible-output inaccessible-error)
   (check-false (file-exists? inaccessible-path))
   (check-output-matches #rx#"The file could not be saved" inaccessible-output))
 (lambda ()
   (when (directory-exists? temporary-directory)
     (delete-directory/files temporary-directory))))
