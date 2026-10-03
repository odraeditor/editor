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
(check-not-false script-path "util-linux script is required for Buffer Menu scenarios")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define control-x (bytes 24))
(define control-c (bytes 3))
(define control-g (bytes 7))
(define control-s (bytes 19))
(define enter (bytes 13))
(define down #"\33[B")
(define exit-editor (bytes-append control-x control-c))
(define list-buffers (bytes-append control-x (bytes 2)))
(define restoration-sequence #"\33[?25h\33[0m\r\n")

(define (utf8 text)
  (string->bytes/utf-8 text))

(define (contains? haystack needle)
  (regexp-match? (byte-regexp (regexp-quote needle)) haystack))

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define (run-editor name initial-path input-bytes
                    #:before-input [before-input void]
                    #:first-input [first-input #f]
                    #:second-input [second-input #f]
                    #:resize? [resize? #f])
  (define resize-command
    (if resize?
        "(sleep 0.7; stty rows 18 cols 72 < /dev/tty; kill -WINCH $$) & "
        ""))
  (define path-argument
    (if initial-path
        (string-append " " (shell-quote (path->string initial-path)))
        ""))
  (define command
    (string-append
     "stty rows 12 cols 100; "
     resize-command
     "exec "
     (shell-quote odra-path)
     path-argument))
  (define-values (process output input error-output)
    (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
  (define transcript (open-output-bytes))
  (define error-result (make-channel))
  (wait-for-terminal-readiness!
   'buffer-menu process output input error-output transcript
   #:content-marker
   (if initial-path
       (utf8 (path->string (file-name-from-path initial-path)))
       #"Open Dir"))
  (define output-reader (thread (lambda () (copy-port output transcript))))
  (thread (lambda () (channel-put error-result (port->bytes error-output))))
  (before-input)
  (when first-input
    (write-bytes first-input input)
    (flush-output input)
    (sleep 0.5))
  (when second-input
    (write-bytes second-input input)
    (flush-output input)
    (sleep 0.5))
  (write-bytes input-bytes input)
  (flush-output input)
  (subprocess-wait process)
  (thread-wait output-reader)
  (define output-bytes (get-output-bytes transcript))
  (define error-bytes (channel-get error-result))
  (close-output-port input)
  (close-input-port output)
  (close-input-port error-output)
  (check-equal? (subprocess-status process) 0 name)
  (check-equal? error-bytes #"" name)
  (check-true (contains? output-bytes restoration-sequence)
              (string-append name ": terminal restoration"))
  output-bytes)

(define fixture-directory (make-temporary-file "odra-buffer-menu-~a" 'directory))
;; Exercise clipped labels even when the temporary parent has a short path.
(define test-directory
  (build-path fixture-directory (string-append "long-parent-" (make-string 120 #\p))))
(make-directory test-directory)

(dynamic-wind
 void
 (lambda ()
   (define primary-path (build-path test-directory "primary.txt"))
   (call-with-output-file primary-path #:exists 'truncate/replace
     (lambda (output) (display "base" output)))

   (define startup-create-output
     (run-editor
      "startup create action"
      #f
      (bytes-append #"notes" enter exit-editor)
      #:first-input enter))
   (check-true (contains? startup-create-output #"Create a new buffer"))
   (check-true (contains? startup-create-output #"Open File"))
   (check-true (contains? startup-create-output #"Switch to buffer: "))

   (define startup-open-output
     (run-editor
      "startup open action"
      #f
      exit-editor
      #:first-input (bytes-append down enter)
      #:second-input control-g))
   (check-true (contains? startup-open-output #"Find file [local]"))

   (define navigation-output
     (run-editor
      "Buffer Menu navigation and local marks"
      primary-path
      (bytes-append
       control-x #"b" #"notes" enter
       list-buffers
       #"s"
       #"q"
       list-buffers
       down enter
       #"N" control-x control-s
       exit-editor)))
   ;; Selecting the associated buffer must save to that exact file, regardless of clipping.
   (check-equal? (file->bytes primary-path) #"Nbase")
   (check-true (contains? navigation-output #"primary.txt"))
   (check-true (contains? navigation-output #". U  notes"))
   (define navigation-plain
     (regexp-replace*
      (byte-pregexp #"\33\\[[0-?]*[ -/]*[@-~]")
      navigation-output
      #""))
   (check-true (contains? navigation-plain #"S . U  notes"))

   (call-with-output-file primary-path #:exists 'truncate/replace
     (lambda (output) (display "base" output)))
   (define save-output
     (run-editor
      "marked associated save"
      primary-path
      (bytes-append #"X" list-buffers #"sxq" exit-editor)))
   (check-equal? (file->bytes primary-path) #"Xbase")
   (check-true (contains? save-output #"Marked operations complete"))

   (call-with-output-file primary-path #:exists 'truncate/replace
     (lambda (output) (display "base" output)))
   (define cancel-output
     (run-editor
      "marked dirty kill cancellation"
      primary-path
      (bytes-append #"X" list-buffers #"dxcq" exit-editor #"d")))
   (check-equal? (file->bytes primary-path) #"base")
   (check-true (contains? cancel-output #"Marked buffer: [s]ave [d]iscard [c]ancel"))
   (check-true (contains? cancel-output #"Marked operations cancelled"))

   (define discard-output
     (run-editor
      "marked associated discard"
      primary-path
      (bytes-append #"X" list-buffers #"dxd" exit-editor)))
   (check-equal? (file->bytes primary-path) #"base")
   (check-true (contains? discard-output #"Marked operations complete"))
   (check-true (contains? discard-output #"Create a new buffer"))

   (define saved-kill-output
     (run-editor
      "marked associated save and kill"
      primary-path
      (bytes-append #"Y" list-buffers #"dxs" exit-editor)))
   (check-equal? (file->bytes primary-path) #"Ybase")
   (check-true (contains? saved-kill-output #"Marked operations complete"))

   (define named-save-path (build-path test-directory "named-save.txt"))
   (define named-save-output
     (run-editor
      "marked unassociated first save"
      #f
      (bytes-append
       enter #"draft" enter
       #"text"
       list-buffers #"dxs"
       (utf8 (path->string named-save-path)) enter
       exit-editor)))
   (check-equal? (file->bytes named-save-path) #"text")
   (check-true (contains? named-save-output #"Save marked buffer as: "))

   (define removed-directory (build-path test-directory "removed"))
   (make-directory removed-directory)
   (define removed-path (build-path removed-directory "partial.txt"))
   (call-with-output-file removed-path
     (lambda (output) (display "base" output)))
   (define partial-save-path (build-path test-directory "partial-saved-note.txt"))
   (define partial-save-output
     (run-editor
      "truthful partial marked save"
      removed-path
      (bytes-append
       #"P"
       control-x #"b" #"partial-note" enter #"N"
       list-buffers #"ssx"
       (utf8 (path->string partial-save-path)) enter
       #"q" exit-editor #"d")
      #:before-input (lambda () (delete-directory/files removed-directory))))
   (check-equal? (file->bytes partial-save-path) #"N")
   (check-false (file-exists? removed-path))
   (check-true (contains? partial-save-output #"Marked operations failed"))

   (call-with-output-file primary-path #:exists 'truncate/replace
     (lambda (output) (display "base" output)))
   (define resize-output
     (run-editor
      "Buffer Menu resize"
      primary-path
      (bytes-append #"qR" control-x control-s exit-editor)
      #:first-input list-buffers
      #:resize? #t))
   ;; Returning from a resized menu must preserve the associated editable buffer.
   (check-equal? (file->bytes primary-path) #"Rbase")
   (check-true (contains? resize-output #"primary.txt"))
   (check-false (contains? resize-output #"Presentation failed")))
 (lambda ()
   (when (directory-exists? fixture-directory)
     (delete-directory/files fixture-directory))))
