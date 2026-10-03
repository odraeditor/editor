#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/path
         racket/port
         racket/system
         rackunit)

(define script-path (find-executable-path "script"))
(check-not-false script-path "util-linux script is required for personal command acceptance")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define root (make-temporary-file "odra-personal-command-~a" 'directory))
(dynamic-wind
 void
 (lambda ()
   (define configuration-base (build-path root "config"))
   (define configuration-root (build-path configuration-base "odra"))
   (make-directory* configuration-root)
   (call-with-output-file
    (build-path configuration-root "init.rkt")
    #:exists 'truncate/replace
    (lambda (output)
      (display
       (string-append
        "#lang racket/base\n"
        "(require odra/commands)\n"
        "(define (uppercase-line context)\n"
        "  (define line (command-context-current-line context))\n"
        "  (command-context-replace!\n"
        "   context line (string-upcase (command-context-read context line))))\n"
        "(provide odra-personal-commands)\n"
        "(define odra-personal-commands\n"
        "  (list\n"
        "   (make-command\n"
        "    'personal-uppercase-line uppercase-line\n"
        "    #:description \"Uppercase the current line.\")))\n")
       output)))
   (define document-path (build-path root "sample.txt"))
   (call-with-output-file document-path
     #:exists 'truncate/replace
     (lambda (output) (display "hello αsk\n" output)))

   (define command
     (string-append
      "stty rows 18 cols 112; exec env -u NO_COLOR TERM=xterm-256color "
      "HOME=" (shell-quote (path->string root)) " "
      "XDG_CONFIG_HOME=" (shell-quote (path->string configuration-base)) " "
      (shell-quote odra-path) " " (shell-quote (path->string document-path))))
   (define-values (process output input error-output)
     (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
   (define transcript-box (box #""))
   (define reader
     (thread (lambda () (set-box! transcript-box (port->bytes output)))))
   (define (send bytes [pause 0.3])
     (write-bytes bytes input)
     (flush-output input)
     (sleep pause))
   (sleep 1.0)
   (send #"\33xpersonal-uppercase-line\r" 0.6)
   (send (bytes 24 19) 0.4)
   (send (bytes 24 3) 0)
   (define exited? (sync/timeout 12 process))
   (unless exited? (subprocess-kill process #t))
   (subprocess-wait process)
   (thread-wait reader)
   (define transcript (unbox transcript-box))
   (define errors (port->bytes error-output))
   (close-output-port input)
   (close-input-port output)
   (close-input-port error-output)

   (check-not-false exited? "personal command editor session did not exit")
   (check-equal? (subprocess-status process) 0)
   (check-equal? errors #"")
   (check-true
    (regexp-match?
     (byte-regexp (regexp-quote #"personal-uppercase-line"))
     transcript))
   (check-equal? (file->string document-path) "HELLO ΑSK\n"))
 (lambda () (delete-directory/files root)))
