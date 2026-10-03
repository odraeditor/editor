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
(check-not-false script-path "util-linux script is required for path navigation scenarios")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define down #"\33[B")
(define enter (bytes 13))
(define tab (bytes 9))
(define exit-editor (bytes 24 3))
(define restoration #"\33[?25h\33[0m\r\n")

(define (contains? output value)
  (regexp-match? (byte-regexp (regexp-quote value)) output))

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define root (make-temporary-file "odra-path-navigation-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (define home (build-path root "home"))
   (define projects (build-path home "Projects"))
   (define main-path (build-path projects "main.odin"))
   (make-directory* (build-path home ".odra" "projects"))
   (make-directory projects)
   (call-with-output-file main-path
     (lambda (output) (display "package path_navigation_demo\n" output)))

   (define command
     (string-append
      "stty rows 16 cols 100; HOME="
      (shell-quote (path->string home))
      " exec "
      (shell-quote odra-path)))
   (define-values (process output input error-output)
     (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
   (define transcript (open-output-bytes))
   (define error-result (make-channel))
   (wait-for-terminal-readiness!
    'filesystem-path-navigation process output input error-output transcript
    #:content-marker #"Open Dir")
   (define output-reader (thread (lambda () (copy-port output transcript))))
   (thread (lambda () (channel-put error-result (port->bytes error-output))))
   (define (send bytes [pause 0.25])
     (write-bytes bytes input)
     (flush-output input)
     (sleep pause))
   (send (bytes-append down enter))
   (send #"~/Projects/mai")
   (send tab)
   (send enter)
   (send exit-editor 0)
   (define completed? (sync/timeout 30 process))
   (unless completed? (subprocess-kill process #t))
   (subprocess-wait process)
   (thread-wait output-reader)
   (define output-bytes (get-output-bytes transcript))
   (define error-bytes (channel-get error-result))
   (close-output-port input)
   (close-input-port output)
   (close-input-port error-output)

   (check-not-false completed? (bytes->string/utf-8 output-bytes #\?))
   (check-equal? (subprocess-status process) 0)
   (check-equal? error-bytes #"")
   (check-true (contains? output-bytes #"~/Projects/"))
   (define header-match
     (regexp-match
      #px#"\33\\[([0-9]+);1H(?:\33\\[[0-9;]*m)*Find file \\[local\\] 1/1"
      output-bytes))
   (define candidate-match
     (regexp-match
      #px#"\33\\[([0-9]+);1H(?:(?:\33\\[[0-9;]*m)|[^\33\r\n])*main\\.odin"
      output-bytes))
   (check-not-false header-match)
   (check-not-false candidate-match)
   (when (and header-match candidate-match)
     (check-equal?
      (string->number (bytes->string/utf-8 (cadr candidate-match)))
      (add1 (string->number (bytes->string/utf-8 (cadr header-match))))))
   (check-true (contains? output-bytes #"path_navigation_demo"))
   (check-true (contains? output-bytes restoration)))
 (lambda ()
   (when (directory-exists? root)
     (delete-directory/files root))))
