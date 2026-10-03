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
(check-not-false script-path "util-linux script is required for personal command reload acceptance")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define (command-module-source command-name transform)
  (string-append
   "(module text-commands racket/base\n"
   "(require odra/commands odra/keymaps)\n"
   "(provide odra-personal-commands odra-interaction-profile)\n"
   "(define (transform-line context)\n"
   "  (define line (command-context-current-line context))\n"
   "  (command-context-replace!\n"
   "   context line (" transform " (command-context-read context line))))\n"
   "(define odra-personal-commands\n"
   "  (list (make-command '" command-name " transform-line)))\n"
   "(define provenance (odra-provenance \"personal\" \"init.rkt\" \"\"))\n"
   "(define factory (factory-interaction-profile))\n"
   "(define personal-map\n"
   "  (odra-keymap\n"
   "   3 1 \"personal\" 0 0 'user-global 0 0 0 0 0 'fallthrough\n"
   "     (list\n"
   "      (keymap-bind\n"
   "       (key-sequence\n"
   "        (odra-key-stroke 1 (char->integer #\\c) 1)\n"
   "        (odra-key-stroke 1 (char->integer #\\u) 0))\n"
   "       \"" command-name "\" provenance))\n"
   "   '() '() provenance))\n"
   "(define odra-interaction-profile\n"
   "  (compose-interaction-profile\n"
   "   1 2 \"personal-direct\"\n"
   "   (list (odra-interaction-profile-maps factory) (list personal-map))\n"
   "   \"insert-text\"))\n"
   ")\n"))

(define active-init-source
  (string-append
   "#lang racket/base\n"
   "(require \"modules/text-commands.rkt\")\n"
   "(provide odra-personal-commands odra-interaction-profile)\n"))

(define deactivated-init-source
  (string-append
   "#lang racket/base\n"
   "(provide odra-personal-commands)\n"
   "(define odra-personal-commands '())\n"))

(define root (make-temporary-file "odra-personal-command-reload-~a" 'directory))
(dynamic-wind
 void
 (lambda ()
   (define configuration-base (build-path root "config"))
   (define configuration-root (build-path configuration-base "odra"))
   (make-directory* configuration-root)
   (define module-root (build-path configuration-root "modules"))
   (make-directory* module-root)
   (define init-path (build-path configuration-root "init.rkt"))
   (define module-path (build-path module-root "text-commands.rkt"))
   (define (write-file path content)
     (call-with-output-file path
       (lambda (output) (display content output))
       #:exists 'truncate/replace))
   (define (write-configuration command-name transform)
     (write-file module-path (command-module-source command-name transform))
     (write-file init-path active-init-source))
   (define (write-malformed-configuration)
     (write-file module-path "(module text-commands racket/base\n(define broken\n"))
   (define (write-deactivated-configuration)
     (call-with-output-file init-path
       (lambda (output)
         (display deactivated-init-source output))
       #:exists 'truncate/replace))
   (write-configuration "personal-uppercase-line" "string-upcase")

   (define document-path (build-path root "sample.txt"))
   (call-with-output-file document-path
     #:exists 'truncate/replace
     (lambda (output) (display "Hello αSk\n" output)))
   (define command
     (string-append
      "stty rows 18 cols 112; before=$(stty -g); "
      "env -u NO_COLOR TERM=xterm-256color "
      "HOME=" (shell-quote (path->string root)) " "
      "XDG_CONFIG_HOME=" (shell-quote (path->string configuration-base)) " "
      (shell-quote odra-path) " " (shell-quote (path->string document-path)) "; "
      "odra_status=$?; after=$(stty -g); "
      "if [ \"$before\" = \"$after\" ]; then printf '\\nODRA_TERMINAL_RESTORED\\n'; fi; "
      "exit $odra_status"))
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
   (send (bytes 31) 0.4)
   (send (bytes 3 117) 0.5)
   (send (bytes 31) 0.4)
   (write-configuration "personal-lowercase-line" "string-downcase")
   (send #"\33xreload-personal-commands\r" 0.8)
   (send (bytes 3 117) 0.6)
   (send (bytes 31) 0.4)
   (write-malformed-configuration)
   (send #"\33xreload-personal-commands\r" 0.8)
   (send (bytes 3 117) 0.5)
   (write-deactivated-configuration)
   (send #"\33xreload-personal-commands\r" 0.8)
   (send #"\33xreload-personal-commands\r" 0.8)
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

   (check-not-false exited? "personal command reload editor session did not exit")
   (check-equal? (subprocess-status process) 0)
   (check-equal? errors #"")
   (check-true
    (regexp-match?
     (byte-regexp (regexp-quote #"Personal commands reloaded"))
     transcript))
   (check-true
    (regexp-match?
     (byte-regexp (regexp-quote #"Personal command reload rejected"))
     transcript))
   (check-true
    (regexp-match?
     (byte-regexp (regexp-quote #"ODRA_TERMINAL_RESTORED"))
     transcript))
   (check-equal? (file->string document-path) "hello αsk\n"))
 (lambda () (delete-directory/files root)))
