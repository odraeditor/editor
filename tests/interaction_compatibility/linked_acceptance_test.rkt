#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/path
         racket/port
         racket/system
         rackunit
         "../support/terminal-readiness.rkt")

(define script-path (find-executable-path "script"))
(check-not-false script-path "util-linux script is required for interaction acceptance")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the development editor")

(define control-g (bytes 7))
(define control-h (bytes 8))
(define control-n (bytes 14))
(define control-s (bytes 19))
(define control-u (bytes 21))
(define control-x (bytes 24))
(define meta-x #"\33x")
(define enter (bytes 13))
(define exit-editor (bytes-append control-x (bytes 3)))
(define restoration #"\33[?25h\33[0m")

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define (contains? output value)
  (regexp-match? (byte-regexp (regexp-quote value)) output))

(define root (make-temporary-file "odra-interaction-compatibility-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (define home (build-path root "home"))
   (define document-path (build-path root "interaction.txt"))
   (make-directory* (build-path home ".config" "odra"))
   (call-with-output-file document-path
     (lambda (output)
       (display
        (string-append
         "alpha beta gamma delta\n"
         "line one\nline two\nline three\nline four\nline five\n")
        output)))
   (define command
     (string-append
      "stty rows 22 cols 120; HOME=" (shell-quote (path->string home))
      " XDG_CONFIG_HOME=" (shell-quote (path->string (build-path home ".config")))
      " exec env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor "
      (shell-quote odra-path) " " (shell-quote (path->string document-path))))
   (define-values (process output input error-output)
     (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
   (define transcript (open-output-bytes))
   (wait-for-terminal-readiness!
    'interaction-compatibility process output input error-output transcript
    #:content-marker #"interaction.txt")
   (define reader (thread (lambda () (copy-port output transcript))))
   (define (send bytes [pause 0.3])
     (write-bytes bytes input)
     (flush-output input)
     (sleep pause))

   ;; Numeric and universal arguments are owned by Direct and apply once.
   (send (bytes-append #"\33" #"3" #"\33f"))
   (send #"X")
   (send control-u)
   (send control-n)
   (send #"Y")

   ;; The help prefix and M-x inspect the same canonical keymap state.
   (send (bytes-append control-h #"k" control-x control-s) 0.8)
   (send #"q")
   (send (bytes-append meta-x #"describe-keymap-state" enter) 0.8)
   (send #"q")

   ;; A cancelled prefix must not leak into the following command.
   (send control-u)
   (send control-g)
   (send (bytes-append control-x control-s) 0.6)
   (send exit-editor 0)

   (define completed? (sync/timeout 20 process))
   (unless completed? (subprocess-kill process #t))
   (subprocess-wait process)
   (thread-wait reader)
   (define output-bytes (get-output-bytes transcript))
   (define errors (port->bytes error-output))
   (close-output-port input)
   (close-input-port output)
   (close-input-port error-output)

   (check-not-false completed? (bytes->string/utf-8 output-bytes #\?))
   (check-equal? (subprocess-status process) 0)
   (check-equal? errors #"")
   (check-true (contains? output-bytes #"save-associated-document"))
   (check-true (contains? output-bytes #"profile direct"))
   (check-true (contains? output-bytes restoration))
   (check-true (regexp-match? #rx#"gammaX|Xdelta" (file->bytes document-path)))
   (check-true (contains? (file->bytes document-path) #"Y")))
 (lambda ()
   (when (directory-exists? root)
     (delete-directory/files root))))
