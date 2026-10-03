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
(check-not-false script-path "util-linux script is required for Jan product acceptance")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define (contains? output value)
  (regexp-match? (byte-regexp (regexp-quote value)) output))

(define (run-scenario suffix modal?)
  (define root (make-temporary-file "odra-jan-product-~a" 'directory))
  (define document-path (build-path root (string-append "product" suffix)))
  (define configuration-base (build-path root "config"))
  (define configuration-root (build-path configuration-base "odra"))
  (define source
    #"* TODO Ship release\nSCHEDULED: <2026-09-17>\n* NEXT Totals\n| Day | Samples |\n|-----+---------|\n| Mon |       3 |\n| Tue |       4 |\n| Wed |       5 |\n|-----+---------|\n| Total |      12 |\n#+TBLFM: @>$2=vsum(@2..@4)\n#+begin_src racket\n(displayln \"not executed\")\n#+end_src\n")
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
        "stty rows 24 cols 144; exec env -u NO_COLOR TERM=xterm-256color "
        "HOME=" (shell-quote (path->string root)) " "
        "XDG_CONFIG_HOME=" (shell-quote (path->string configuration-base)) " "
        (shell-quote odra-path) " " (shell-quote (path->string document-path))))
     (define-values (process output input error-output)
       (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
     (define transcript (open-output-bytes))
     (wait-for-terminal-readiness!
      'jan-product process output input error-output transcript
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
     (execute-command "jan-agenda")
     (send #"\r" 0.7)
     (if modal?
         (execute-command "jan-todo")
         (send (bytes 3 (char->integer #\j) (char->integer #\t)) 0.8))
     (if modal? (send #"u" 0.7) (send (bytes 31) 0.7))
     (if modal? (send (bytes 18) 0.7) (execute-command "redo"))
     (execute-command "jan-planning-status")
     (execute-command "jan-agenda")
     (send #"\33[B" 0.3)
     (send #"\r" 0.7)
     (execute-command "jan-computation-status")
     (execute-command "jan-table-debug-formula")
     (send #"\r" 0.7)
     (execute-command "jan-export")
     (execute-command "jan-output-status")
     (execute-command "jan-provider-status")
     (execute-command "jan-execute")
     (execute-command "jan-help-at-point")
     (execute-command "save-associated-document")
     (execute-command "request-editor-exit")
     (define exited? (sync/timeout 20 process))
     (unless exited? (subprocess-kill process #t))
     (subprocess-wait process)
     (thread-wait reader)
     (define transcript-bytes (get-output-bytes transcript))
     (define errors (port->bytes error-output))
     (close-output-port input)
     (close-input-port output)
     (close-input-port error-output)
     (define diagnostic-start (max 0 (- (bytes-length transcript-bytes) 12288)))
     (check-not-false exited? suffix)
     (check-equal?
      (subprocess-status process) 0
      (string-append suffix "\n"
                     (bytes->string/utf-8 (subbytes transcript-bytes diagnostic-start) #\?)))
     (check-equal? errors #"" suffix)
     (for ([expected (in-list
                      (list #"Jan planning: generation="
                            #"Jan agenda: sources=1 headings=2 tasks=2 timestamps=1"
                            #"SCHEDULED: <2026-09-17>"
                            #"Jan computation: generation="
                            #"Jan computation: tables=1 formula-forms=1"
                            #"@>$2 = vsum(@2..@4)"
                            #"result=12"
                            #"Jan export: backend=Normalized_Jan"
                            #"Jan output: native=5"
                            #"Jan providers: native=5"
                            #"Jan help: node="
                            #"Jan task: TODO -> NEXT committed as one undo unit"))])
       (check-true
        (contains? transcript-bytes expected)
        (string-append
         suffix ": " (bytes->string/utf-8 expected) "\n"
         (bytes->string/utf-8 (subbytes transcript-bytes diagnostic-start) #\?))))
     (values transcript-bytes (file->bytes document-path) source))
   (lambda () (delete-directory/files root))))

(define-values (org-output org-saved original) (run-scenario ".org" #f))
(define-values (jan-output jan-saved ignored) (run-scenario ".jan" #t))
(define expected
  #"* NEXT Ship release\nSCHEDULED: <2026-09-17>\n* NEXT Totals\n| Day | Samples |\n|-----+---------|\n| Mon |       3 |\n| Tue |       4 |\n| Wed |       5 |\n|-----+---------|\n| Total |      12 |\n#+TBLFM: @>$2=vsum(@2..@4)\n#+begin_src racket\n(displayln \"not executed\")\n#+end_src\n")
(check-equal? org-saved expected)
(check-equal? jan-saved expected)
(check-true (contains? org-output #"source-preserved=true"))
(check-true (contains? jan-output #"source-preserved=true"))
