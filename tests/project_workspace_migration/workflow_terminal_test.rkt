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
         "../support/product-composition.rkt"
         "../support/terminal-readiness.rkt"
         "../support/terminal-scenario-result.rkt"
         "../../scripts/migrate-project-workspaces.rkt"
         "legacy_fixture.rkt")

(define script-path (find-executable-path "script"))
(check-not-false script-path "util-linux script is required for migration scenarios")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")
(define product-module-manifest (getenv "ODRA_PRODUCT_MODULE_MANIFEST"))
(check-not-false product-module-manifest
                 "ODRA_PRODUCT_MODULE_MANIFEST must identify the official module manifest")

(define enter (bytes 13))
(define control-x (bytes 24))
(define control-c (bytes 3))
(define down #"\33[B")
(define close-component #"q")
(define exit-editor (bytes-append control-x control-c))
(define restoration-sequence #"\33[?25h\33[0m\r\n")
(define diagnostic-byte-limit 4096)

(define (contains? haystack needle)
  (regexp-match? (byte-regexp (regexp-quote needle)) haystack))

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define (bounded-tail value)
  (define count (bytes-length value))
  (if (<= count diagnostic-byte-limit)
      value
      (subbytes value (- count diagnostic-byte-limit))))

(define (check-scenario! name result)
  (define failure (classify-terminal-scenario result))
  (when failure
    (fail-check
     (format
      "~a: failure=~a cleanup=~a process-status=~a output-tail=~s error-tail=~s"
      name
      (terminal-scenario-failure-code failure)
      (terminal-scenario-failure-cleanup failure)
      (terminal-scenario-failure-process-status failure)
      (bounded-tail (terminal-scenario-result-output result))
      (bounded-tail (terminal-scenario-result-errors result)))))
  (printf "migration-acceptance: scenario=~a status=passed exit=~a restoration=present\n"
          name
          (terminal-scenario-result-process-status result))
  (flush-output))

(define (run-editor name home input-bytes #:executable [executable odra-path]
                    #:argument [argument #f]
                    #:later-inputs [later-inputs '()])
  (define command
    (string-append
     "stty rows 18 cols 120; XDG_CONFIG_HOME="
     (shell-quote (path->string (build-path home ".config")))
     " HOME="
     (shell-quote (path->string home))
     " exec "
     (shell-quote (path->string executable))
     (if argument
         (string-append " " (shell-quote (path->string argument)))
         "")))
  (define-values (process output input error-output)
    (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
  (define transcript (open-output-bytes))
  (define error-channel (make-channel))
  (wait-for-terminal-readiness!
   (string->symbol name) process output input error-output transcript
   #:content-marker (if argument #"Files [active Project]" #"Create a new buffer"))
  (write-bytes input-bytes input)
  (flush-output input)
  (for ([later-step (in-list later-inputs)])
    (wait-for-terminal-readiness!
     (string->symbol name) process output input error-output transcript
     #:content-marker (car later-step))
    (write-bytes (cdr later-step) input)
    (flush-output input))
  (define output-reader (thread (lambda () (copy-port output transcript))))
  (thread (lambda () (channel-put error-channel (port->bytes error-output))))
  (define completed? (sync/timeout 60 process))
  (unless completed? (subprocess-kill process #t))
  (subprocess-wait process)
  (thread-wait output-reader)
  (define output-bytes (get-output-bytes transcript))
  (define error-bytes (channel-get error-channel))
  (close-output-port input)
  (close-input-port output)
  (close-input-port error-output)
  (terminal-scenario-result
   (and completed? #t)
   (subprocess-status process)
   output-bytes
   error-bytes
   (contains? output-bytes restoration-sequence)
   (if completed? 'none 'forced-process-termination)))

(define (publish-legacy legacy-root id name roots trusts)
  (write-legacy-project-record legacy-root id name roots trusts))

(define root (make-temporary-file "odra-migration-terminal-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (define home (build-path root "home"))
   (define legacy-root (build-path home ".odra"))
   (define single (build-path root "single"))
   (define first (build-path root "first"))
   (define second (build-path root "second"))
   (for ([dir (in-list (list home legacy-root single first second))])
     (make-directory dir)
     (file-or-directory-permissions dir #o700))
   (call-with-output-file (build-path single "main.odin")
     (lambda (output) (display "package main\n" output)))
   (publish-legacy legacy-root "single" "Single" (list single) '(trusted))
   (publish-legacy legacy-root "group" "Group" (list first second)
                   '(trusted untrusted))
   (define configuration-root (build-path home ".config" "odra"))
   (test-case "migration publishes Project and Workspace records"
     (check-equal? (run-legacy-migration legacy-root configuration-root #t) 0)
     (printf "migration-acceptance: scenario=migration-publication status=passed\n")
     (flush-output))

   (define missing-module-root (build-path root "missing-module"))
   (define missing-module-binary (build-path missing-module-root "odra"))
   (make-directory missing-module-root)
   (copy-file odra-path missing-module-binary)
   (test-case "missing Darek rejects Workspace opening"
     (define result
       (run-editor
        "workspace-missing-module"
        home
        (bytes-append down down down down enter)
        #:executable missing-module-binary
        #:later-inputs
        (list
         (cons #"Group  [2 Projects]" enter)
         (cons #"Workspace-hierarchy module is unavailable" exit-editor))))
     (check-scenario! "workspace-missing-module" result)
     (check-true
      (contains? (terminal-scenario-result-output result)
                 #"Workspace-hierarchy module is unavailable")))

   (define composed-root (build-path root "official-composition"))
   (define composed-binary
     (stage-product-composition! odra-path product-module-manifest composed-root))

   (test-case "migrated Project opens and exits"
     (define result
       (run-editor
        "project-open-and-exit"
        home
        (bytes-append #"main" enter)
        #:executable composed-binary
        #:argument single
        #:later-inputs (list (cons #"Project: Single" exit-editor))))
     (check-scenario! "project-open-and-exit" result)
     (check-true
      (contains? (terminal-scenario-result-output result) #"Project: Single")))

   (test-case "migrated Workspace opens through Darek and exits"
     (define result
       (run-editor
        "workspace-open-and-exit"
        home
        (bytes-append down down down down enter)
        #:executable composed-binary
        #:later-inputs
        (list
         (cons #"Group  [2 Projects]" enter)
         (cons #"Opened Workspace in Darek" close-component)
         (cons #"Project: Group / first" exit-editor))))
     (check-scenario! "workspace-open-and-exit" result)
     (define workspace-output (terminal-scenario-result-output result))
     (check-true
      (and (contains? workspace-output #"Group  [2 Projects]")
           (contains? workspace-output #"Workspace: Group")
           (contains? workspace-output #"Project: Group / first")))))
 (lambda ()
   (when (directory-exists? root)
     (delete-directory/files root))))
