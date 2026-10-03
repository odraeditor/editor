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
(check-not-false script-path "util-linux script is required for Jan structured editing acceptance")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define (contains? output value)
  (regexp-match? (byte-regexp (regexp-quote value)) output))

(define (run-scenario name suffix source modal? actions)
  (define root (make-temporary-file "odra-jan-editing-~a" 'directory))
  (define document-path (build-path root (string-append name suffix)))
  (define configuration-base (build-path root "config"))
  (define configuration-root (build-path configuration-base "odra"))
  (dynamic-wind
   void
   (lambda ()
     (make-directory* configuration-root)
     (when modal?
       (call-with-output-file
        (build-path configuration-root "init.rkt")
        #:exists 'truncate/replace
        (lambda (output)
          (display
           (string-append
            "#lang racket/base\n"
            "(require odra/keymaps)\n"
            "(provide odra-interaction-profile)\n"
            "(define odra-interaction-profile (factory-modal-interaction-profile))\n")
           output))))
     (call-with-output-file document-path #:exists 'truncate/replace
       (lambda (output) (write-bytes source output)))
     (define command
       (string-append
        "stty rows 22 cols 132; exec env -u NO_COLOR TERM=xterm-256color "
        "HOME=" (shell-quote (path->string root)) " "
        "XDG_CONFIG_HOME=" (shell-quote (path->string configuration-base)) " "
        (shell-quote odra-path) " " (shell-quote (path->string document-path))))
     (define-values (process output input error-output)
       (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
     (define transcript (open-output-bytes))
     (wait-for-terminal-readiness!
      'jan-structured-editing process output input error-output transcript
      #:content-marker
      (string->bytes/utf-8 (path->string (file-name-from-path document-path))))
     (define reader (thread (lambda () (copy-port output transcript))))
     (define input-open? #t)
     (define (send bytes [pause 0.45])
       (when input-open?
         (with-handlers ([exn:fail? (lambda (_) (set! input-open? #f))])
           (write-bytes bytes input)
           (flush-output input)))
       (sleep pause))
     (define (execute-command name)
       (send (if modal? #":" #"\33x") 0.2)
       (send (string->bytes/utf-8 name) 0.2)
       (send #"\r" 0.7))
     (actions send execute-command)
     (define exited? (sync/timeout 15 process))
     (unless exited? (subprocess-kill process #t))
     (subprocess-wait process)
     (thread-wait reader)
     (define transcript-bytes (get-output-bytes transcript))
     (define errors (port->bytes error-output))
     (close-output-port input)
     (close-input-port output)
     (close-input-port error-output)
     (define diagnostic-start (max 0 (- (bytes-length transcript-bytes) 8192)))
     (check-not-false exited? name)
     (check-equal?
      (subprocess-status process) 0
      (string-append name "\n"
                     (bytes->string/utf-8 (subbytes transcript-bytes diagnostic-start) #\?)))
     (check-equal? errors #"" name)
     (check-true (contains? transcript-bytes #"\33[?25h\33[?2026l") name)
     (values transcript-bytes (file->bytes document-path)))
   (lambda () (delete-directory/files root))))

(define outline-source #"* Alpha\n* Beta\n")

(define (outline-actions modal?)
  (lambda (send execute-command)
    (if modal?
        (begin
          (send #"za" 0.7)
          (send #"]h" 0.7)
          (send #"gg" 0.4)
          (send #"ga" 0.7))
        (begin
          (send (bytes 3 (char->integer #\j) (char->integer #\c)) 0.7)
          (send (bytes 3 (char->integer #\j) (char->integer #\n)) 0.7)
          (execute-command "cursor-buffer-start")
          (send (bytes 3 (char->integer #\j) (char->integer #\a)) 0.7)))
    (execute-command "jan-show-all")
    (execute-command "jan-present")
    (execute-command "jan-inspect-availability")
    (execute-command "jan-insert-heading-after")
    (if modal? (send #"u" 0.7) (send (bytes 31) 1.0))
    (if modal? (send (bytes 18) 0.7) (execute-command "redo"))
    (if modal?
        (execute-command "save-associated-document")
        (send (bytes 24 19) 0.7))
    (if modal?
        (execute-command "request-editor-exit")
        (send (bytes 24 3) 0.2))))

(define-values (org-output org-saved)
  (run-scenario "outline" ".org" outline-source #f (outline-actions #f)))
(define-values (jan-output jan-saved)
  (run-scenario "outline" ".jan" outline-source #f (outline-actions #f)))
(define-values (modal-output modal-saved)
  (run-scenario "outline-modal" ".org" outline-source #t (outline-actions #t)))

(define expected-outline #"* Alpha\n* Heading\n* Beta\n")
(check-equal? org-saved expected-outline)
(check-equal? jan-saved expected-outline)
(check-equal? modal-saved expected-outline)
(for ([output (in-list (list org-output jan-output modal-output))])
  (check-true (contains? output #"Jan visibility:"))
  (check-true (contains? output #"Jan navigation:"))
  (check-true (contains? output #"Jan context:"))
  (check-true (contains? output #"Jan presentation: terminal-source=true"))
  (check-true (contains? output #"Jan availability: operational=13 optional-unavailable=6 future-stage=0 total=19"))
  (check-true (contains? output #"Jan rewrite committed as one undo unit")))

(define (rewrite-scenario name source command expected)
  (define-values (output saved)
    (run-scenario
     name ".org" source #f
     (lambda (send execute-command)
       (execute-command command)
       (execute-command "save-associated-document")
       (send (bytes 24 3) 0.2))))
  (check-equal? saved expected name)
  (check-true (contains? output #"Jan rewrite committed as one undo unit") name))

(rewrite-scenario "list" #"- Alpha\n" "jan-insert-list-item-after"
                  #"- Alpha\n- item\n")
(rewrite-scenario "block" #"#+begin_quote\nbody\n#+end_quote\n" "jan-insert-block"
                  #"#+begin_quote\nbody\n#+end_quote\n#+begin_src odin\n#+end_src\n")
(rewrite-scenario "table" #"| a | b |\n" "jan-insert-table-row"
                  #"| a | b |\n|  |  |\n")
(rewrite-scenario "footnote" #"Paragraph\n" "jan-create-footnote"
                  #"Paragraph\n[fn:note] Footnote\n")

(define-values (failure-output failure-saved)
  (run-scenario
   "checked-failure" ".org" #"Paragraph\n" #f
   (lambda (send execute-command)
     (execute-command "jan-move-subtree-up")
     (send (bytes 24 3) 0.2))))
(check-equal? failure-saved #"Paragraph\n")
(check-true (contains? failure-output #"Jan rewrite rejected:"))
