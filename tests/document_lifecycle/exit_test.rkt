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
(check-not-false script-path "util-linux script is required for PTY exit tests")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define control-x (bytes 24))
(define control-g (bytes 7))
(define enter (bytes 13))
(define request-exit (bytes 24 3))
(define discard #"d")
(define save #"s")
(define cancel #"c")
(define restoration-sequence #"\33[?25h\33[0m\r\n")
(define exit-prompt #"Save changes? [s]ave [d]iscard [c]ancel")
(define create-buffer-sequence (bytes-append enter #"untitled" enter))

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define (run-pty path input-bytes
                 #:before-input [before-input void]
                 #:resize? [resize? #f])
  (define resize-command
    (if resize?
        "(sleep 0.2; stty rows 30 cols 100 < /dev/tty; kill -WINCH $$) & "
        ""))
  (define path-argument
    (if path (string-append " " (shell-quote (path->string path))) ""))
  (define command
    (string-append
     "stty rows 24 cols 80; "
     resize-command
     "exec "
     (shell-quote odra-path)
     path-argument))
  (define-values (process output input error-output)
    (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
  (define startup-output (open-output-bytes))
  (wait-for-terminal-readiness!
   'document-exit process output input error-output startup-output
   #:content-marker
   (if path
       (string->bytes/utf-8 (path->string (file-name-from-path path)))
       #"Open Dir"))
  (define output-reader (thread (lambda () (copy-port output startup-output))))
  (before-input)
  (write-bytes
   (if path input-bytes (bytes-append create-buffer-sequence input-bytes))
   input)
  (flush-output input)
  (subprocess-wait process)
  (thread-wait output-reader)
  (define output-bytes (get-output-bytes startup-output))
  (define error-bytes (port->bytes error-output))
  (close-output-port input)
  (close-input-port output)
  (close-input-port error-output)
  (values (subprocess-status process) output-bytes error-bytes))

(define (check-orderly-exit status output error-output)
  (check-equal? status 0)
  (check-equal? error-output #"")
  (check-true
   (regexp-match?
    (byte-regexp (regexp-quote restoration-sequence))
    output)))

(define (check-exit-prompt output)
  (check-true (regexp-match? (byte-regexp (regexp-quote exit-prompt)) output)))

(define temporary-directory (make-temporary-file "odra-exit-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (define clean-path (build-path temporary-directory "clean.txt"))
   (call-with-output-file
    clean-path
    #:exists 'truncate/replace
    (lambda (output) (display "saved" output)))
   (define-values (clean-status clean-output clean-error)
     (run-pty clean-path request-exit))
   (check-orderly-exit clean-status clean-output clean-error)
   (check-false (regexp-match? (byte-regexp (regexp-quote exit-prompt)) clean-output))

   (define discard-path (build-path temporary-directory "discard.txt"))
   (call-with-output-file discard-path (lambda (output) (display "base" output)))
   (define-values (discard-status discard-output discard-error)
     (run-pty discard-path (bytes-append #"x" request-exit discard)))
   (check-orderly-exit discard-status discard-output discard-error)
   (check-exit-prompt discard-output)
   (check-equal? (file->string discard-path) "base")

   (define cancel-path (build-path temporary-directory "cancel.txt"))
   (call-with-output-file cancel-path (lambda (output) (display "base" output)))
   (define-values (cancel-status cancel-output cancel-error)
     (run-pty cancel-path
              (bytes-append #"x" request-exit cancel #"y" request-exit discard)))
   (check-orderly-exit cancel-status cancel-output cancel-error)
   (check-exit-prompt cancel-output)
   (check-true (regexp-match? #rx#"xybase" cancel-output))
   (check-equal? (file->string cancel-path) "base")

   (define save-path (build-path temporary-directory "save.txt"))
   (call-with-output-file save-path (lambda (output) (display "base" output)))
   (define-values (save-status save-output save-error)
     (run-pty save-path (bytes-append #"x" request-exit save)))
   (check-orderly-exit save-status save-output save-error)
   (check-exit-prompt save-output)
   (check-equal? (file->string save-path) "xbase")

   (define unmaterialized-path (build-path temporary-directory "new.txt"))
   (define-values (new-status new-output new-error)
     (run-pty unmaterialized-path (bytes-append #"new" request-exit save)))
   (check-orderly-exit new-status new-output new-error)
   (check-exit-prompt new-output)
   (check-equal? (file->string unmaterialized-path) "new")

   (define unassociated-path (build-path temporary-directory "named.txt"))
   (define-values (named-status named-output named-error)
     (run-pty
      #f
      (bytes-append
       #"draft"
       request-exit
       save
       (string->bytes/utf-8 (path->string unassociated-path))
       enter)))
   (check-orderly-exit named-status named-output named-error)
   (check-exit-prompt named-output)
   (check-true (regexp-match? #rx#"Save as: " named-output))
   (check-equal? (file->string unassociated-path) "draft")

   (define cancelled-path (build-path temporary-directory "cancelled.txt"))
   (define-values (path-cancel-status path-cancel-output path-cancel-error)
     (run-pty
      #f
      (bytes-append
       #"draft"
       request-exit
       save
       (string->bytes/utf-8 (path->string cancelled-path))
       control-g
       #"z"
       request-exit
       discard)))
   (check-orderly-exit path-cancel-status path-cancel-output path-cancel-error)
   (check-false (file-exists? cancelled-path))
   (check-true (regexp-match? #rx#"draftz" path-cancel-output))

   (define-values (control-cancel-status control-cancel-output control-cancel-error)
     (run-pty #f (bytes-append #"draft" request-exit control-g #"z" request-exit discard)))
   (check-orderly-exit control-cancel-status control-cancel-output control-cancel-error)
   (check-true (regexp-match? #rx#"draftz" control-cancel-output))

   (define failing-directory (build-path temporary-directory "removed-parent"))
   (make-directory failing-directory)
   (define failing-path (build-path failing-directory "failed.txt"))
   (define-values (failure-status failure-output failure-error)
     (run-pty
      failing-path
      (bytes-append #"draft" request-exit save #"z" request-exit discard)
      #:before-input (lambda () (delete-directory failing-directory))))
   (check-orderly-exit failure-status failure-output failure-error)
   (check-true (regexp-match? #rx#"The file could not be saved" failure-output))
   (check-true (regexp-match? #rx#"draftz" failure-output))
   (check-false (file-exists? failing-path))

   (define signal-path (build-path temporary-directory "resize.txt"))
   (call-with-output-file signal-path (lambda (output) (display "base" output)))
   (define-values (signal-status signal-output signal-error)
     (run-pty signal-path (bytes-append #"x" request-exit discard) #:resize? #t))
   (check-orderly-exit signal-status signal-output signal-error)
   (check-exit-prompt signal-output))
 (lambda ()
   (when (directory-exists? temporary-directory)
     (delete-directory/files temporary-directory))))
