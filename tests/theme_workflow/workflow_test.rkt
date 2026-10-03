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

(define document-path (make-temporary-file "odra-theme-workflow-~a.odin"))
(call-with-output-file
 document-path
 #:exists 'truncate/replace
 (lambda (output)
   (display "package main\n\nmain :: proc() {}\n" output)))

(define command
  (string-append
   "stty rows 18 cols 140; "
   "exec env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor "
   odra-path " " (path->string document-path)))
(define-values (process output input error-output)
  (subprocess #f #f #f script-path "-qfec" command "/dev/null"))

(define transcript (open-output-bytes))
(wait-for-terminal-readiness!
 'theme-workflow process output input error-output transcript
 #:content-marker
 (string->bytes/utf-8 (path->string (file-name-from-path document-path))))

(define output-reader (thread (lambda () (copy-port output transcript))))
(define error-channel (make-channel))
(define error-reader
  (thread (lambda () (channel-put error-channel (port->bytes error-output)))))

(define input-written?
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (write-bytes
     (bytes-append
      #"\33xselect-theme\r"
      #"sunrise\r"
      #"\33xselect-theme\r"
      #"morning\r"
      #"\33xselect-theme\r"
      #"sunset\r"
      #"\33xselect-theme\r"
      #"night\r"
      #"\33xselect-theme\r"
      #"terminal-default\r"
      #"\33xselect-theme\r"
      #"sunset\r"
      #"\33xselect-theme\r"
      #"sunrise" (bytes 7)
      #"\33xdescribe-theme\r"
      #"q"
      (bytes 24 3) #"d")
     input)
    (flush-output input)
    #t))
(define completed? (sync/timeout 20 process))
(unless completed? (subprocess-kill process #t))
(subprocess-wait process)

(thread-wait output-reader)
(define output-bytes (get-output-bytes transcript))
(define error-bytes (channel-get error-channel))
(close-output-port input)
(close-input-port output)
(close-input-port error-output)
(delete-file document-path)

(define (contains? value)
  (regexp-match? (byte-regexp (regexp-quote value)) output-bytes))

(check-not-false completed? "theme workflow completion timeout")
(check-equal? (subprocess-status process) 0
              (bytes->string/utf-8 output-bytes #\?))
(check-true input-written?)
(check-equal? error-bytes #"")
(check-true (contains? #"Themes [session] 1/5 Select theme:"))
(check-true
 (contains?
  (string->bytes/utf-8
   "Wrocław Night  [wroclaw-night]  [odra-factory]  active, fallback")))
(check-true (contains? #"Themes [session] 1/1 Select theme:"))
(check-true
 (contains?
  (string->bytes/utf-8
   "Wrocław Sunrise  [wroclaw-sunrise]  [odra-factory]  available")))
(check-true
 (contains?
  (string->bytes/utf-8
   "Wrocław Morning  [wroclaw-morning]  [odra-factory]  available")))
(check-true
 (contains?
  (string->bytes/utf-8
   "Wrocław Sunset  [wroclaw-sunset]  [odra-factory]  available")))
(check-true
 (contains?
  (string->bytes/utf-8
   "Terminal Default  [terminal-default]  [odra-factory]  safe baseline")))
(check-true (contains? #"\33[38;2;26;32;44m"))
(check-true (contains? #"\33[48;2;176;222;243m\33[2J"))
(check-true (contains? #"\33[38;2;26;31;37m"))
(check-true (contains? #"\33[48;2;247;253;253m\33[2J"))
(check-true (contains? #"\33[38;2;17;19;14m"))
(check-true (contains? #"\33[48;2;243;235;221m\33[2J"))
(check-true (contains? #"\33[38;2;214;214;179m"))
(check-true (contains? #"\33[48;2;26;27;38m\33[2J"))
(check-true (contains? #"Selection: state=Selected"))
(check-true
 (contains?
  (string->bytes/utf-8 "Active: Wrocław Sunset [wroclaw-sunset]")))
(check-true (contains? #"Provider: odra-factory kind=Factory state=Confirmed"))
(check-true (contains? #"Semantic roles: current=66 maximum=66"))
(check-true (contains? #"Renderer: id=1 color=True_Color"))
(check-true (contains? #"Registry usage: providers=1 definitions=5"))
(check-true (contains? #"Latest rejection: operation=None code=None"))
(check-true (contains? #"\33[?25h\33[0m\r\n"))
