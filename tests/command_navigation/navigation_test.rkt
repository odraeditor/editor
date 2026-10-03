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

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define test-root (make-temporary-file "odra-command-navigation-~a" 'directory))
(define document-path (build-path test-root "navigation.txt"))
(call-with-output-file
 document-path
 #:exists 'truncate/replace
 (lambda (output)
   (display "one alpha\n" output)))

(define command
  (string-append
   "stty rows 14 cols 120; exec env "
   "HOME=" (shell-quote (path->string test-root)) " "
   "XDG_CONFIG_HOME="
   (shell-quote (path->string (build-path test-root "config"))) " "
   "XDG_STATE_HOME="
   (shell-quote (path->string (build-path test-root "state"))) " "
   "XDG_CACHE_HOME="
   (shell-quote (path->string (build-path test-root "cache"))) " "
   "XDG_DATA_HOME="
   (shell-quote (path->string (build-path test-root "data"))) " "
   (shell-quote odra-path) " "
   (shell-quote (path->string document-path))))
(define-values (process output input error-output)
  (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
(define transcript (open-output-bytes))
(wait-for-terminal-readiness!
 'command-navigation process output input error-output transcript
 #:content-marker
 (string->bytes/utf-8 (path->string (file-name-from-path document-path))))
(define output-reader
  (thread (lambda () (copy-port output transcript))))

(define input-written?
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (write-bytes
     (bytes-append
      #"\33xcursor-line-endx" (bytes 127) #"\r"
      #"\33xcursor-line" (bytes 14 16 7)
      #"\33x^uppercase-current-line$\r"
      #"\33x[" (bytes 7)
      #"\33xredo" (bytes 7)
      #"\33xcopy-region\r" (bytes 7)
      (bytes 24 3) #"d")
     input)
    (flush-output input)
    #t))
(subprocess-wait process)

(thread-wait output-reader)
(define output-bytes (get-output-bytes transcript))
(define error-bytes (port->bytes error-output))
(close-input-port output)
(close-input-port error-output)
(delete-directory/files test-root)

(define (contains? value)
  (regexp-match? (byte-regexp (regexp-quote value)) output-bytes))

(define (matches? pattern)
  (regexp-match? (byte-regexp pattern) output-bytes))

(define (contains-bold? value)
  (regexp-match?
   (byte-pregexp
    (bytes-append
     #"\33\\[1m(?:\33\\[[0-9;]*[A-Za-z])*"
     (regexp-quote value)
     #"\33\\[22m"))
   output-bytes))

(check-equal? (subprocess-status process) 0)
(check-true input-written?)
(check-equal? error-bytes #"")
(check-true (contains-bold? #"cursor-line-end"))
(check-true
 (contains? #"Commands [active editor context] 1/1 M-x"))
(check-true
 (contains? #"cursor-line-end  [C-e, END]  Move to the logical line end."))
(check-true
 (matches? #"Commands \\[active editor context\\] 2/[0-9]+ M-x"))
(check-true (contains? #"uppercase-current-line    Uppercase the current logical line."))
(check-true (contains? #"ONE ALPHA"))
(check-true
 (contains? #"Commands [active editor context] 0/0 M-x"))
(check-true (contains? #"redo    Redo the preferred user-visible edit unit."))
(check-true
 (contains?
  #"copy-region  [M-w]  Copy the active region into retained text."))
(check-true (contains? #"\33[?25h\33[0m\r\n"))
