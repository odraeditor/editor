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
(check-not-false script-path "util-linux script is required for syntax PTY scenarios")
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
           "(sleep 1.4; stty rows 22 cols 120 < /dev/tty; kill -WINCH $$) & "
           ""))
     (define command
       (string-append
        "stty rows 18 cols 100; "
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
      'syntax-presentation process output input error-output transcript
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
     (define exited? (sync/timeout 10 process))
     (unless exited? (subprocess-kill process #t))
     (subprocess-wait process)
     (thread-wait output-reader)
     (define output-bytes (get-output-bytes transcript))
     (define error-bytes (channel-get error-channel))
     (close-output-port input)
     (close-input-port output)
     (close-input-port error-output)
     (check-equal? (subprocess-status process) 0 name)
     (check-not-false exited? name)
     (check-equal? error-bytes #"" name)
     (check-true (contains? output-bytes #"\33[?25h\33[0m\r\n") name)
     (values output-bytes document-path))
   (lambda ()
     (when (file-exists? document-path) (delete-file document-path)))))

(define odin-contents
  (string-append
   "package main\n"
   "import \"core:fmt\"\n\n"
   "// factory syntax evidence\n"
   "answer :: 42\n\n"
   "main :: proc(input: int) -> int {\n"
   "\tfmt.println(\"hello\", input)\n"
   "\treturn input\n"
   "}\n"
   (apply string-append
          (for/list ([index (in-range 40)])
            (format "value_~a :: ~a\n" index index)))))

(define-values (inspection-output _inspection-path)
  (run-scenario
   "syntax-inspection"
   ".odin"
   odin-contents
   (lambda (send _path)
     (send (bytes 24 (char->integer #\3)) 0.35) ; second view, shared analysis
     (send (bytes 24 (char->integer #\o)) 0.25)
     (send (bytes 24 (char->integer #\1)) 0.25)
     (send #"\33[6~" 0.25)                      ; viewport movement
     (send #"\33xdescribe-language-state\r" 0.6)
     (send #"q" 0.25)
     (send (bytes 24 3) 0))
   #:resize? #t))

(check-true (contains? inspection-output #"\33[38;2;120;160;250m")) ; keyword
(check-true (contains? inspection-output #"\33[38;2;132;133;135m")) ; comment
(check-true (contains? inspection-output #"\33[38;2;191;187;64m"))  ; number
(check-true (contains? inspection-output #"\33[38;2;178;164;75m"))  ; string
(check-true (contains? inspection-output #"\33[38;2;89;129;227m"))  ; function
(check-true (contains? inspection-output #"\33[38;2;81;182;245m"))  ; type
(check-true (contains? inspection-output #"\33[38;2;180;119;69m"))  ; parameter
(check-true (contains? inspection-output #"Language: odin"))
(check-true (contains? inspection-output #"Provider: factory-odin-tree-sitter"))
(check-true (contains? inspection-output #"Styles: factory semantic roles=16 color=True_Color"))
(check-true (>= (length (regexp-match* (byte-regexp (regexp-quote #"\33[2J")) inspection-output)) 4))

(define medium-odin-contents
  (string-append
   "package main\n"
   (apply string-append
          (for/list ([index (in-range 900)])
            (format "value_~a :: proc(input: int) -> int { return input + ~a }\n" index index)))))

(define-values (medium-output _medium-path)
  (run-scenario
   "syntax-medium-source"
   ".odin"
   medium-odin-contents
   (lambda (send _path)
     (send #"\33xdescribe-language-state\r" 0.6)
     (send #"q" 0.25)
     (send (bytes 24 3) 0))))

(check-true (contains? medium-output #"Parser: lifecycle=Ready status=Current"))
(check-true (contains? medium-output #"\33[38;2;120;160;250m"))
(check-false (contains? medium-output #"Capture_Limit"))

(define saved-edit #f)
(define-values (editing-output _editing-path)
  (run-scenario
   "syntax-editing"
   ".odin"
   "package main\nanswer :: 42\n"
   (lambda (send path)
     (send #"x" 0.35)                  ; incremental analysis
     (send (bytes 31) 0.35)            ; undo
     (send #"\33xredo\r" 0.5)          ; redo
     (send (bytes 24 19) 0.4)          ; save
     (send (bytes 19) 0.15)            ; search
     (send #"answer\r" 0.35)
     (send (bytes 0) 0.15)             ; region
     (send #"\33[C\33[C" 0.25)
     (send (bytes 7) 0.2)
     (set! saved-edit (file->string path))
     (send (bytes 24 3) 0))))

(check-true (contains? editing-output #"Search \342\206\222"))
(check-true
 (contains? editing-output
            #"\33[1m\33[38;2;26;27;38m\33[48;2;213;146;79m"))
(check-true (contains? editing-output #"\33[38;2;120;160;250m"))
(check-true (and saved-edit (regexp-match? #rx"^xpackage" saved-edit)))

(define-values (plain-output _plain-path)
  (run-scenario
   "syntax-unsupported"
   ".txt"
   "plain unsupported text\n"
   (lambda (send _path)
     (send #"\33xdescribe-language-state\r" 0.6)
     (send #"q" 0.2)
     (send (bytes 24 3) 0))))

(check-true (contains? plain-output #"plain unsupported text"))
(check-true (contains? plain-output #"status=Plain_Text"))
(check-false (contains? plain-output #"\33[38;2;120;160;250m"))
