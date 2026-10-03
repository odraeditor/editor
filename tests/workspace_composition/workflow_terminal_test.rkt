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
         "../support/terminal-readiness.rkt"
         "../../src/project/persistence.rkt"
         "../../src/project/records.rkt"
         "../../src/workspace/management.rkt"
         (submod "../../src/workspace/management.rkt" test-support))

(define script-path (find-executable-path "script"))
(check-not-false script-path "util-linux script is required for Workspace scenarios")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")

(define enter (bytes 13))
(define control-g (bytes 7))
(define control-x (bytes 24))
(define control-c (bytes 3))
(define down #"\33[B")
(define close-component #"q")
(define exit-editor (bytes-append control-x control-c))
(define restoration-sequence #"\33[?25h\33[0m\r\n")

(define (contains? haystack needle)
  (regexp-match? (byte-regexp (regexp-quote needle)) haystack))

(define (check-output output needle context)
  (check-true (contains? output needle)
              (format "~a: missing ~s in output ~s" context needle output)))

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define (run-editor name home input-bytes #:later-inputs [later-inputs '()])
  (define command
    (string-append
     "stty rows 18 cols 120; XDG_CONFIG_HOME="
     (shell-quote (path->string (build-path home ".config")))
     " HOME="
     (shell-quote (path->string home))
     " exec "
     (shell-quote odra-path)))
  (define-values (process output input error-output)
    (subprocess #f #f #f script-path "-qfec" command "/dev/null"))
  (define transcript (open-output-bytes))
  (define error-channel (make-channel))
  (wait-for-terminal-readiness!
   'workspace-workflow process output input error-output transcript
   #:content-marker #"Create a new buffer")
  (define output-reader (thread (lambda () (copy-port output transcript))))
  (thread (lambda () (channel-put error-channel (port->bytes error-output))))
  (write-bytes input-bytes input)
  (flush-output input)
  (for ([later-input (in-list later-inputs)])
    (sleep 0.7)
    (write-bytes later-input input)
    (flush-output input))
  (define completed? (sync/timeout 60 process))
  (unless completed? (subprocess-kill process #t))
  (subprocess-wait process)
  (thread-wait output-reader)
  (define output-bytes (get-output-bytes transcript))
  (define error-bytes (channel-get error-channel))
  (close-output-port input)
  (close-input-port output)
  (close-input-port error-output)
  (check-not-false completed? (string-append name ": completion timeout"))
  (check-equal? (subprocess-status process) 0
                (format "~a output: ~s" name output-bytes))
  (check-equal? error-bytes #"" name)
  (check-true (contains? output-bytes restoration-sequence)
              (string-append name ": terminal restoration"))
  output-bytes)

(define (publish-project dir id name trust)
  (check-true
   (odra-record-publication?
    (local-project-record-persist
     dir
     (local-project-record
      #:format-version current-local-project-format-version
      #:id id
      #:generation 1
      #:name name
      #:root (path->string dir)
      #:trust trust)))))

(define root (make-temporary-file "odra-workspace-terminal-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (define home (build-path root "home"))
   (define first (build-path root "first"))
   (define second (build-path root "second"))
   (for ([dir (in-list (list home first second))]) (make-directory dir))
   (publish-project first "first" "First" 'untrusted)
   (publish-project second "second" "Second" 'trusted)
   (define configuration-root (build-path home ".config" "odra"))
   (for ([entry (in-list (list (list "first" first) (list "second" second)))])
     (check-true
      (odra-record-publication?
       (project-discovery-record-persist
        configuration-root
        (project-discovery-record
         #:format-version current-project-discovery-format-version
         #:id (car entry)
         #:expected-project-generation 1
         #:root (path->string (cadr entry)))))))
   (define created
     (parameterize ([current-workspace-identity (lambda () "daily")])
       (workspace-create-compose configuration-root "Daily" (list first second))))
   (check-true (odra-workspace-publication? (workspace-publish configuration-root created)))

   (define project-output
     (run-editor
      "open Project"
      home
      (bytes-append down down down enter)
      #:later-inputs (list #"Second" enter control-g exit-editor)))
   (check-output project-output #"Projects [global] 1/1 Open Project: " "open Project")
   (check-output project-output #"Second" "open Project")
   (check-output project-output #"Project: Second" "open Project")

   (define opened-output
     (run-editor
      "open Workspace"
      home
      (bytes-append down down down down enter)
      #:later-inputs (list enter close-component exit-editor)))
   (check-output opened-output #"Open Workspace" "open Workspace")
   (check-output opened-output #"Workspaces [global] 1/1 Open Workspace: " "open Workspace")
   (check-output opened-output #"Daily  [2 Projects]" "open Workspace")
   (check-output opened-output #"Opened Workspace in Darek" "open Workspace")
   (check-output opened-output #"First" "open Workspace")
   (check-output opened-output #"Second" "open Workspace")
   (check-false (contains? opened-output #"Root [Untrusted; Unknown]:"))

   (define cancelled-output
     (run-editor
      "cancel Workspace navigation"
      home
      (bytes-append down down down down enter)
      #:later-inputs (list control-g exit-editor)))
   (check-true (contains? cancelled-output #"Workspaces [global] 1/1 Open Workspace: "))
   (check-true (contains? cancelled-output #"Open Workspace"))

   (define updated
     (workspace-update-compose configuration-root "daily" 1 "Daily Work" (list second first)))
   (check-true (odra-workspace-publication? (workspace-publish configuration-root updated)))
   (define restart-output
     (run-editor
      "reopen updated Workspace"
      home
      (bytes-append down down down down enter)
      #:later-inputs (list enter close-component exit-editor)))
   (check-true (contains? restart-output #"Daily Work  [2 Projects]"))
   (check-true (contains? restart-output #"Opened Workspace in Darek"))
   (check-true (contains? restart-output #"First"))
   (check-true (contains? restart-output #"Second"))
   (check-false (contains? restart-output #"Root [Untrusted; Unknown]:"))

   (delete-directory/files first)
   (define unavailable-output
     (run-editor
      "unavailable Workspace member"
      home
      (bytes-append down down down down enter)
      #:later-inputs (list enter control-g exit-editor)))
   (check-true (contains? unavailable-output #"Workspace unavailable: 1 member: Project root is unavailable")))
 (lambda ()
   (when (directory-exists? root)
     (delete-directory/files root))))
