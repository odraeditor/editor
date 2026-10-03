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
(check-not-false script-path "util-linux script is required for structured syntax PTY scenarios")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define (contains? output value)
  (regexp-match? (byte-regexp (regexp-quote value)) output))

(define (run-scenario name suffix contents actions #:resize? [resize? #f])
  (define document-path (make-temporary-file (string-append "odra-" name "-~a" suffix)))
  (dynamic-wind
   void
   (lambda ()
     (call-with-output-file
      document-path
      #:exists 'truncate/replace
      (lambda (output) (display contents output)))
     (define resize-command
       (if resize?
           "(sleep 2.0; stty rows 24 cols 132 < /dev/tty; kill -WINCH $$) & "
           ""))
     (define command
       (string-append
        "stty rows 20 cols 112; "
        resize-command
        "exec env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor "
        (shell-quote odra-path)
        " "
        (shell-quote (path->string document-path))))
     (define-values (process output input error-output)
       (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
     (define transcript (open-output-bytes))
     (define error-channel (make-channel))
     (wait-for-terminal-readiness!
      'structured-syntax process output input error-output transcript
      #:content-marker
      (string->bytes/utf-8 (path->string (file-name-from-path document-path))))
     (define output-reader
       (thread (lambda () (copy-port output transcript))))
     (thread (lambda () (channel-put error-channel (port->bytes error-output))))
     (define input-open? #t)
     (define (send bytes [pause 0.25])
       (when input-open?
         (with-handlers ([exn:fail? (lambda (_) (set! input-open? #f))])
           (write-bytes bytes input)
           (flush-output input)))
       (sleep pause))
     (actions send document-path)
     (define exited? (sync/timeout 12 process))
     (unless exited? (subprocess-kill process #t))
     (subprocess-wait process)
     (thread-wait output-reader)
     (define output-bytes (get-output-bytes transcript))
     (define error-bytes (channel-get error-channel))
     (close-output-port input)
     (close-input-port output)
     (close-input-port error-output)
     (define diagnostic-start (max 0 (- (bytes-length output-bytes) 2048)))
     (check-equal?
      (subprocess-status process)
      0
      (string-append
       name
       "\n"
       (bytes->string/utf-8 (subbytes output-bytes diagnostic-start) #\?)))
     (check-not-false exited? name)
     (check-equal? error-bytes #"" name)
     (check-true (contains? output-bytes #"\33[?25h\33[0m\r\n") name)
     output-bytes)
   (lambda ()
     (when (file-exists? document-path) (delete-file document-path)))))

(define (inspect send)
  (send #"\33xdescribe-structural-state\r" 0.5)
  (send #"q" 0.2))

(define odin-contents
  (string-append
   "package main\n\n"
   "import \"core:fmt\"\n\n"
   "// structural workflow evidence\n"
   "main :: proc(input: int) -> int {\n"
   "fmt.println(\"hello\", input)\n"
   "return input\n"
   "}\n"))

(define saved-odin #f)
(define workflow-output
  (run-scenario
   "structured-syntax-workflow"
   ".odin"
   odin-contents
   (lambda (send path)
     (send #"\33xselect-theme\r")
     (send #"sunset\r" 0.4)
     (send (bytes 19))
     (send #"fmt.println\r" 0.4)
     (send #"\33xstructural-indent\r" 0.4)
     (inspect send)
     (send (bytes 31) 0.35)                ; undo
     (send #"\33xredo\r" 0.4)
     (send (bytes 24 19) 0.4)              ; save
     (set! saved-odin (file->string path))
     (send #"\33xstructural-forward\r" 0.4) ; canonical M-x command
     (inspect send)
     (send (bytes 27 6) 0.3)               ; C-M-f: structural-forward
     (inspect send)
     (send (bytes 27 2) 0.3)               ; C-M-b: structural-backward
     (inspect send)
     (send (bytes 27 21) 0.3)              ; C-M-u: structural-up
     (inspect send)
     (send (bytes 27 4) 0.3)               ; C-M-d: structural-down
     (inspect send)
     (send (bytes 27 0) 0.3)               ; C-M-SPC: structural-select
     (inspect send)
     (send (bytes 27 0) 0.3)               ; expand selection
     (inspect send)
     (send (bytes 24 (char->integer #\3))) ; second view
     (send (bytes 24 (char->integer #\o))) ; focus next view
     (send (bytes 27 6) 0.4)
     (send (bytes 7) 0.2)
     (send (bytes 24 3) 0))
   #:resize? #t))

(check-true (and saved-odin (regexp-match? #rx"\n    fmt[.]println" saved-odin)))
(for ([operation '(#"Indent" #"Forward" #"Backward" #"Up" #"Down" #"Select")])
  (check-true
   (contains? workflow-output (bytes-append #"Last operation: operation=" operation))
   (bytes->string/utf-8 operation)))
(check-true (contains? workflow-output #"Last indentation: range="))
(check-true (contains? workflow-output #"active=true"))
(check-true (contains? workflow-output #"Capability: available=true generation=1 grammar=Odin"))
(check-true (contains? workflow-output #"\33[38;2;120;160;250m"))
(check-true (contains? workflow-output (string->bytes/utf-8 "│")))
(check-true (contains? workflow-output #"\33[48;2;243;235;221m\33[2J"))
(check-true (>= (length (regexp-match* (byte-regexp (regexp-quote #"\33[2J")) workflow-output)) 8))

(define saved-plain #f)
(define unsupported-output
  (run-scenario
   "structured-syntax-unsupported"
   ".txt"
   "plain text remains editable\n"
   (lambda (send path)
     (send (bytes 27 6) 0.4)
     (inspect send)
     (send #"x" 0.25)
     (send (bytes 24 19) 0.35)
     (set! saved-plain (file->string path))
     (send (bytes 24 3) 0))))

(check-equal? saved-plain "xplain text remains editable\n")
(check-true (contains? unsupported-output #"Capability: available=false generation=1 grammar=Odin"))
(check-true (contains? unsupported-output #"structural=Analysis_Rejected"))
(check-true (contains? unsupported-output #"plain text remains editable"))
