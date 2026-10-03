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

(define (contains-bold? haystack value)
  (regexp-match?
   (byte-pregexp
    (bytes-append
     #"\33\\[1m(?:\33\\[[0-9;]*[A-Za-z])*"
     (regexp-quote value)
     #"\33\\[22m"))
   haystack))

(define (run-scenario name input-chunks expected-output #:bold [expected-bold '()])
  (define document-path (make-temporary-file (string-append "odra-" name "-~a.txt")))
  (call-with-output-file
   document-path
   #:exists 'truncate/replace
   (lambda (output)
     (display "inspection evidence\n" output)))
  (define command
    (string-append
     "stty rows 40 cols 240; exec " odra-path " " (path->string document-path)))
  (define-values (process output input error-output)
    (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
  (define transcript (open-output-bytes))
  (define error-channel (make-channel))
  (wait-for-terminal-readiness!
   'keymap-inspection process output input error-output transcript
   #:content-marker
   (string->bytes/utf-8 (path->string (file-name-from-path document-path))))
  (define output-reader (thread (lambda () (copy-port output transcript))))
  (thread (lambda () (channel-put error-channel (port->bytes error-output))))
  (define input-written?
    (with-handlers ([exn:fail? (lambda (_) #f)])
      (for ([chunk (in-list input-chunks)])
        (write-bytes chunk input)
        (flush-output input)
        (sleep 0.5))
      #t))
  (define completed? (sync/timeout 30 process))
  (unless completed? (subprocess-kill process #t))
  (subprocess-wait process)
  (thread-wait output-reader)
  (define output-bytes (get-output-bytes transcript))
  (define error-bytes (channel-get error-channel))
  (define diagnostic-limit 4096)
  (define diagnostic-output
    (if (> (bytes-length output-bytes) diagnostic-limit)
        (subbytes output-bytes (- (bytes-length output-bytes) diagnostic-limit))
        output-bytes))
  (close-input-port output)
  (close-input-port error-output)
  (delete-file document-path)
  (check-not-false completed? (string-append name ": completion timeout"))
  (check-equal?
   (subprocess-status process)
   0
   (format "~a; output tail: ~s" name diagnostic-output))
  (check-true
   input-written?
   (format "~a; output tail: ~s" name diagnostic-output))
  (check-equal? error-bytes #"" name)
  (for ([expected (in-list expected-output)])
    (check-true (contains? output-bytes expected) name))
  (for ([expected (in-list expected-bold)])
    (check-true (contains-bold? output-bytes expected) name))
  (check-true (contains? output-bytes #"\33[?25h\33[0m\r\n") name))

(run-scenario
 "describe-bindings"
 (list #"\33xdescribe-bindings\r" #"q" (bytes 24 3))
 (list
  #"M-x"
  #"C-g -> keyboard-quit [effective; available; protected]"
  #"map protected-recovery@1")
 #:bold (list #"describe-bindings"))

(run-scenario
 "where-is"
 (list #"\33xwhere-is\r" #"undo\r" #"q" (bytes 24 3))
 (list #"Where is command: " #"C-/ -> undo" #"C-x u -> undo"))

(run-scenario
 "describe-key"
 (list #"\33xdescribe-key\r" (bytes 24) #"u" #"q" (bytes 24 3))
 (list #"Describe key: " #"C-x u -> undo"))

(run-scenario
 "describe-keymap-state"
 (list #"\33xdescribe-keymap-state\r" #"q" (bytes 24 3))
 (list
  #"M-x"
  #"profile 1@1 registry 2 snapshot 1"
  #"pending none"
  #"catalog 2 [effective]"
  #"profile direct 1@1 [effective]"
  #"state direct-editing 1@1 [effective]"
  #"surface extended-command 1@1 [effective; not applicable]")
 #:bold (list #"describe-keymap-state"))
