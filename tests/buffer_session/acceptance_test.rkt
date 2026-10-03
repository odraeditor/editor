#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         racket/file
         racket/path
         racket/port
         racket/system)

(define script-path (find-executable-path "script"))
(check-not-false script-path "util-linux script is required for buffer acceptance")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define control-g (bytes 7))
(define control-s (bytes 19))
(define control-x (bytes 24))
(define control-y (bytes 25))
(define control-space (bytes 0))
(define enter (bytes 13))
(define tab (bytes 9))
(define meta-w #"\33w")
(define right #"\33[C")
(define down #"\33[B")
(define exit-editor (bytes-append control-x (bytes 3)))
(define list-buffers (bytes-append control-x (bytes 2)))
(define restoration-sequence #"\33[?25h\33[0m\r\n")

(define (utf8 text)
  (string->bytes/utf-8 text))

(define (contains? haystack needle)
  (regexp-match? (byte-regexp (regexp-quote needle)) haystack))

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define (run-editor initial-path input-stages)
  (define command
    (string-append
     "stty rows 14 cols 100; exec "
     (shell-quote odra-path)
     " "
     (shell-quote (path->string initial-path))))
  (define-values (process output input error-output)
    (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
  (define output-result (make-channel))
  (define error-result (make-channel))
  (thread (lambda () (channel-put output-result (port->bytes output))))
  (thread (lambda () (channel-put error-result (port->bytes error-output))))
  (sleep 0.5)
  (for ([stage (in-list input-stages)])
    (write-bytes stage input)
    (flush-output input)
    (sleep 0.3))
  (define completed? (sync/timeout 20 process))
  (unless completed?
    (subprocess-kill process #t))
  (subprocess-wait process)
  (define output-bytes (channel-get output-result))
  (define error-bytes (channel-get error-result))
  (close-output-port input)
  (close-input-port output)
  (close-input-port error-output)
  (check-not-false completed?
                   (bytes->string/utf-8 output-bytes #\?))
  (check-equal? (subprocess-status process) 0)
  (check-equal? error-bytes #"")
  (check-true (contains? output-bytes restoration-sequence))
  output-bytes)

(define acceptance-directory
  (make-temporary-file "odra-buffer-acceptance-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (define primary-path (build-path acceptance-directory "primary.txt"))
   (define secondary-path (build-path acceptance-directory "secondary.txt"))
   (define notes-path (build-path acceptance-directory "notes.txt"))
   (call-with-output-file primary-path #:exists 'truncate/replace
     (lambda (output) (display "alpha beta alpha\n" output)))
   (call-with-output-file secondary-path #:exists 'truncate/replace
     (lambda (output) (display "second\n" output)))
   (define primary-label (path->string (normalize-path primary-path)))
   (define secondary-label (path->string (normalize-path secondary-path)))
   (define secondary-alias
     (string-append (path->string acceptance-directory) "/./secondary.txt"))
   (define output
     (run-editor
      primary-path
      (list
       (bytes-append
        control-space right right right right right meta-w control-g
        control-x #"b")
       (bytes-append #"notes" enter)
       (bytes-append
        control-y
        control-s #"alpha" enter
        control-x control-s)
       (bytes-append (utf8 (path->string notes-path)) enter)
       (bytes-append control-x (bytes 6))
       (utf8 secondary-label)
       tab
       enter
       (bytes-append #"X" control-x #"u" control-x control-s)
       (bytes-append control-x (bytes 6))
       (utf8 secondary-alias)
       tab
       enter
       list-buffers
       (bytes-append down down enter)
       list-buffers
       #"q"
       (bytes-append control-x #"k")
       enter
       exit-editor)))
   (check-equal? (file->bytes primary-path) #"alpha beta alpha\n")
   (check-equal? (file->bytes secondary-path) #"second\n")
   (check-equal? (file->bytes notes-path) #"alpha")
   (check-true (contains? output #"Switch to buffer: "))
   (check-true (contains? output #"Find file [local]"))
   (check-true (contains? output #"Search \342\206\222"))
   (check-true (contains? output (utf8 primary-label)))
   (check-true (contains? output (utf8 secondary-label)))
   (check-true (contains? output #"Killed buffer")))
 (lambda ()
   (when (directory-exists? acceptance-directory)
     (delete-directory/files acceptance-directory))))
