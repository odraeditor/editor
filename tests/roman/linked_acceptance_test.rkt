#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         rackunit
         racket/date
         racket/file
         racket/format
         racket/list
         racket/path
         racket/port
         racket/string
         racket/system
         "../support/terminal-readiness.rkt"
         "../../src/package/acquisition.rkt"
         "../../src/package/lifecycle-service.rkt"
         (submod "../../src/package/lifecycle-service.rkt" test-support)
         "../../src/package/manifest-contracts.rkt"
         "../../src/package/resolution.rkt"
         "../../src/package/state-records.rkt"
         "../../src/package_catalog/curation-records.rkt"
         "../../src/package_catalog/curation-resolution.rkt"
         "../../src/project/promotion.rkt"
         "../../src/storage/record-codec.rkt")

(define script-path (find-executable-path "script"))
(check-not-false script-path "util-linux script is required for Roman acceptance")
(define bash-path (find-executable-path "bash"))
(check-not-false bash-path "bash is required for Roman acceptance")
(define dirname-path (find-executable-path "dirname"))
(check-not-false dirname-path "dirname is required for Roman acceptance")
(define odra-path (getenv "ODRA_PTY_EXECUTABLE"))
(check-not-false odra-path "ODRA_PTY_EXECUTABLE must identify the built executable")
(define manifest-path (getenv "ROMAN_PACKAGE_MANIFEST"))
(check-not-false manifest-path "ROMAN_PACKAGE_MANIFEST is required")
(define archive-path (getenv "ROMAN_PACKAGE_ARCHIVE"))
(check-not-false archive-path "ROMAN_PACKAGE_ARCHIVE is required")

(define control-c (bytes 3))
(define control-x (bytes 24))
(define control-s (bytes 19))
(define control-g (bytes 7))
(define control-a (bytes 1))
(define control-n (bytes 14))
(define control-space (bytes 0))
(define control-underscore (bytes 31))
(define right #"\33[C")
(define restoration-sequence #"\33[?25h\33[0m")
(define roman-version "0.1.1")

(define (sha256-file path)
  (call-with-input-file path
    (lambda (input) (bytes->hex-string (sha256-bytes input)))
    #:mode 'binary))

(define (shell-quote value)
  (string-append "'" (regexp-replace* #rx"'" value "'\"'\"'") "'"))

(define (manifest-or-fail path)
  (define manifest (package-manifest-module-load path))
  (when (odra-record-diagnostic? manifest)
    (raise-user-error 'roman-acceptance
                      "manifest rejected: ~a"
                      (odra-record-diagnostic-message manifest)))
  manifest)

(define (release-candidate manifest archive)
  (define manifest-digest (package-manifest-digest manifest))
  (define archive-digest (sha256-file archive))
  (define artifact
    (odra-package-artifact-reference
     'linux 'x86-64 (list (format "odra.roman-~a.tar.zst" roman-version)) archive-digest
     (file-size archive) "roman-linked-acceptance" #f 'reproduced))
  (define release
    (odra-package-release-reference
     1
     (odra-package-manifest-package-id manifest)
     manifest-digest
     (odra-package-manifest-version manifest)
     (odra-package-manifest-publisher-id manifest)
     "https://forge.adrianpk.com/odra/packages"
     (odra-package-manifest-source-revision manifest)
     #f manifest-digest (list artifact)
     manifest-digest manifest-digest manifest-digest manifest-digest))
  (odra-package-installation-candidate
   manifest manifest-digest release artifact
   (odra-package-provenance
    'manual #f archive-digest manifest-digest
    (odra-package-manifest-publisher-id manifest)
    (odra-package-manifest-source-revision manifest))
   'manual-uncurated))

(define sandbox
  (make-temporary-file "odra-roman-linked-acceptance-~a" 'directory))
(define configuration-base (build-path sandbox "config"))
(define data-base (build-path sandbox "data"))
(define state-base (build-path sandbox "state"))
(define cache-base (build-path sandbox "cache"))
(define configuration-root (build-path configuration-base "odra"))
(define package-root (build-path data-base "odra"))
(define project-root (build-path sandbox "brain"))
(define start-path (build-path project-root "00-start-here.org"))
(define draft-path (build-path project-root "draft.org"))
(define reference-path (build-path project-root "reference.org"))
(define metadata-path (build-path project-root "metadata.org"))
(define inbox-path (build-path project-root "roman-inbox.org"))
(define daily-root (build-path project-root "daily"))
(define package-data-root
  (build-path package-root "packages" "data" "odra.roman"))
(define recovery-path (build-path sandbox "recovery-path"))

(define (today-key)
  (define date (seconds->date (current-seconds)))
  (format "~a-~a-~a"
          (date-year date)
          (~r (date-month date) #:min-width 2 #:pad-string "0")
          (~r (date-day date) #:min-width 2 #:pad-string "0")))

(define today-daily-path
  (build-path daily-root (string-append (today-key) ".org")))
(define previous-daily-path (build-path daily-root "0001-01-01.org"))
(define next-daily-path (build-path daily-root "9999-12-31.org"))

(define (ensure-lifecycle-success operation result)
  (unless (eq? (odra-package-lifecycle-runtime-result-status result) 'success)
    (raise-user-error
     'roman-acceptance "~a: ~a" operation
     (odra-package-lifecycle-runtime-result-detail result))))

(define (install-package!)
  (define manifest (manifest-or-fail manifest-path))
  (define candidate (release-candidate manifest archive-path))
  (define acquisition
    (acquire-package-candidate
     package-root candidate
     #:location-resolver (lambda (_location) archive-path)))
  (unless (odra-package-acquisition? acquisition)
    (raise-user-error 'roman-acceptance
                      "artifact acquisition rejected: ~s" acquisition))
  (ensure-lifecycle-success
   "install"
   (package-lifecycle-runtime-install
    package-root (format "odra.roman@~a" roman-version)
    #:installer (lambda (_root _id _version)
                  (list candidate acquisition))))
  (ensure-lifecycle-success
   "enable"
   (package-lifecycle-runtime-enable
    package-root (format "odra.roman@~a" roman-version))))

(define (promote-project!)
  (define proposal
    (project-promotion-compose configuration-root project-root "Roman Acceptance"))
  (when (odra-project-promotion-failure? proposal)
    (raise-user-error 'roman-acceptance
                      "Project proposal failed: ~a"
                      (odra-project-promotion-failure-message proposal)))
  (define published (project-promotion-publish configuration-root proposal))
  (when (odra-project-promotion-failure? published)
    (raise-user-error 'roman-acceptance
                      "Project publication failed: ~a"
                      (odra-project-promotion-failure-message published))))

(define (write-project-fixtures!)
  (make-directory* project-root)
  (call-with-output-file start-path
    #:exists 'truncate/replace
    (lambda (output)
      (display
       (string-append
        "#+TITLE: Roman Acceptance\n\n"
        "* Ada Lovelace\n"
        ":PROPERTIES:\n:ID: person-ada\n:ROAM_ALIASES: Ada\n"
        ":ROAM_REFS: cite:lovelace\n:END:\n"
        "See [[id:topic-engine][Analytical Engine]].\n"
        "See [[cite:lovelace-notes][Lovelace notes]].\n\n"
        "* Analytical Engine\n"
        ":PROPERTIES:\n:ID: topic-engine\n:END:\n"
        "The engine links to [[id:person-ada][Ada]].\n")
       output)))
  (call-with-output-file draft-path
    #:exists 'truncate/replace
    (lambda (output)
      (display
       (string-append
        "#+TITLE: Insertion Work\n\n"
        "* Draft Link\n"
        ":PROPERTIES:\n:ID: draft-link\n:END:\n"
        "Analytical Engine\n")
       output)))
  (call-with-output-file reference-path
    #:exists 'truncate/replace
    (lambda (output)
      (display "#+TITLE: Reference Lookup\ncite:lovelace\n" output)))
  (call-with-output-file metadata-path
    #:exists 'truncate/replace
    (lambda (output)
      (display
       (string-append
        "#+TITLE: Metadata Work\n\n"
        "* Test metadata editing\n"
        ":PROPERTIES:\n:ID: task-test-metadata\n:END:\n"
        "experiment\n")
       output)))
  (make-directory daily-root)
  (for ([fixture
         (in-list
          (list (cons previous-daily-path "Previous Daily Acceptance")
                (cons today-daily-path "Today Daily Acceptance")
                (cons next-daily-path "Next Daily Acceptance")))])
    (call-with-output-file (car fixture)
      #:exists 'truncate/replace
      (lambda (output)
        (fprintf output "#+TITLE: ~a\n" (cdr fixture))))))

(define (terminal-command [path-value #f])
  (string-append
   "stty rows 30 cols 120; "
   "exec /usr/bin/env -u NO_COLOR COLORTERM=truecolor TERM=xterm-256color "
   (if path-value (string-append "PATH=" (shell-quote path-value) " ") "")
   "HOME=" (shell-quote (path->string sandbox))
   " XDG_DATA_HOME=" (shell-quote (path->string data-base))
   " XDG_STATE_HOME=" (shell-quote (path->string state-base))
   " XDG_CACHE_HOME=" (shell-quote (path->string cache-base))
   " XDG_CONFIG_HOME=" (shell-quote (path->string configuration-base))
   " " (shell-quote odra-path)
   " " (shell-quote (path->string project-root))))

(define (send-command! send name wait-for mark)
  (define start (mark))
  (send #"\33x")
  (sleep 0.2)
  (for ([value (in-bytes (string->bytes/utf-8 name))])
    (send (bytes value))
    (sleep 0.05))
  (wait-for (string->bytes/utf-8 name) start)
  (sleep 0.8)
  (send #"\r")
  (sleep 0.2))

(define (send-roman-binding! send suffix)
  (send control-c)
  (sleep 0.1)
  (send #"n")
  (sleep 0.1)
  (send (bytes suffix)))

(define (run-editor-session action #:path [path-value #f])
  (define-values (process output input error-output)
    (subprocess #f #f #f script-path "-qfec" (terminal-command path-value) "/dev/null"))
  (define transcript (open-output-bytes))
  (wait-for-terminal-readiness!
   'roman-acceptance process output input error-output transcript #:timeout 20)
  (define output-reader (thread (lambda () (copy-port output transcript))))
  (sleep 3.0)
  (define (tail)
    (define content (get-output-bytes transcript))
    (subbytes content (max 0 (- (bytes-length content) 8192))))
  (define (send bytes)
    (with-handlers
        ([exn:fail?
          (lambda (observed)
            (raise-user-error
             'roman-acceptance
             "editor input failed: ~a; status=~s; transcript tail: ~s"
             (exn-message observed) (subprocess-status process) (tail)))])
      (write-bytes bytes input)
      (flush-output input)))
  (define (mark) (bytes-length (get-output-bytes transcript)))
  (define (slice start)
    (define content (get-output-bytes transcript))
    (if (<= start (bytes-length content)) (subbytes content start) #""))
  (define (wait-for marker [start 0])
    (define deadline (+ (current-inexact-milliseconds) 15000))
    (let wait ()
      (define content (get-output-bytes transcript))
      (cond
        [(and (<= start (bytes-length content))
              (regexp-match? (byte-regexp (regexp-quote marker))
                             (subbytes content start)))
         (void)]
        [(< (current-inexact-milliseconds) deadline)
         (sleep 0.05)
         (wait)]
        [else
         (subprocess-kill process #t)
         (subprocess-wait process)
         (raise-user-error
          'roman-acceptance
          "editor did not report ~s; stderr: ~s; transcript tail: ~s"
          marker (port->bytes error-output) (tail))])))
  (define (command name marker)
    (define start (mark))
    (send-command! send name wait-for mark)
    (wait-for marker start))
  (define (open-start-file!)
    (define start (mark))
    (send #"\r")
    (wait-for #"Roman Acceptance" start))
  (dynamic-wind
    void
    (lambda ()
      (action send mark slice wait-for command open-start-file!)
      (send-command! send "request-editor-exit" wait-for mark)
      (unless (sync/timeout 15 process)
        (subprocess-kill process #t)
        (subprocess-wait process)
        (raise-user-error
         'roman-acceptance "editor did not exit; transcript tail: ~s" (tail)))
      (thread-wait output-reader)
      (define output-bytes (get-output-bytes transcript))
      (define error-bytes (port->bytes error-output))
      (check-equal? (subprocess-status process) 0)
      (check-equal? error-bytes #"")
      (check-true
       (regexp-match? (byte-regexp (regexp-quote restoration-sequence))
                      output-bytes)))
    (lambda ()
      (when (eq? (subprocess-status process) 'running)
        (subprocess-kill process #t)
        (subprocess-wait process))
      (unless (thread-dead? output-reader) (thread-wait output-reader))
      (unless (port-closed? input) (close-output-port input))
      (unless (port-closed? output) (close-input-port output))
      (unless (port-closed? error-output) (close-input-port error-output)))))

(define (wait-for-file-content path expected)
  (define deadline (+ (current-inexact-milliseconds) 5000))
  (let wait ()
    (cond
      [(and (file-exists? path) (string=? (file->string path) expected)) (void)]
      [(< (current-inexact-milliseconds) deadline)
       (sleep 0.05)
       (wait)]
      [else
       (raise-user-error
        'roman-acceptance "file did not reach expected content: ~a" path)])))

(define (wait-for-file-containing path expected)
  (define deadline (+ (current-inexact-milliseconds) 5000))
  (let wait ()
    (cond
      [(and (file-exists? path)
            (string-contains? (file->string path) expected))
       (void)]
      [(< (current-inexact-milliseconds) deadline)
       (sleep 0.05)
       (wait)]
      [else
       (raise-user-error
        'roman-acceptance "file did not contain expected text: ~a" path)])))

(define draft-original
  (string-append
   "#+TITLE: Insertion Work\n\n"
   "* Draft Link\n"
   ":PROPERTIES:\n:ID: draft-link\n:END:\n"
   "Analytical Engine\n"))
(define draft-linked
  (string-replace
   draft-original "Analytical Engine"
   "[[id:topic-engine][Analytical Engine]]"))
(define metadata-with-alias
  (string-append
   "#+TITLE: Metadata Work\n\n"
   "* Test metadata editing\n"
   ":PROPERTIES:\n:ID: task-test-metadata\n:ROAM_ALIASES: experiment\n:END:\n"
   "experiment\n"))

(define (open-node! send mark slice wait-for name)
  (define started (mark))
  (send-roman-binding! send (char->integer #\f))
  (wait-for #"Candidates" started)
  (define query-start (mark))
  (send (string->bytes/utf-8 name))
  (wait-for (string->bytes/utf-8 name) query-start)
  (wait-for #"1/1" query-start)
  (define surface (slice started))
  (check-false (regexp-match? #rx#"resource-[0-9]" surface))
  (check-false
   (regexp-match? (byte-regexp (regexp-quote (path->bytes sandbox))) surface))
  (define activation (mark))
  (send #"\r")
  (wait-for #"Opened " activation)
  (sleep 0.5))

(define (select-line-text! send line-count text)
  (send control-a)
  (for ([_index (in-range line-count)])
    (send control-n))
  (send control-a)
  (send control-space)
  (for ([_index (in-range (string-length text))])
    (send right)))

(define (save! send)
  (send (bytes-append control-x control-s)))

(define (first-session send mark slice wait-for command open-start-file!)
  (open-start-file!)
  (command "roman-space-inspect" #"Roman default brain: state active")
  (command "roman-index-refresh" #"Roman indexed 7 Jan sources")

  ;; Reference discovery works without a region and activates its owner.
  (send control-a)
  (send control-n)
  (define all-references-start (mark))
  (send-command! send "roman-ref-find" wait-for mark)
  (wait-for #"Roman references" all-references-start)
  (wait-for (string->bytes/utf-8 "Ada Lovelace — cite:lovelace")
            all-references-start)
  (define all-references-activation (mark))
  (send #"\r")
  (wait-for #"Opened " all-references-activation)

  ;; Node discovery exposes semantic labels, filters, and activates navigation.
  (open-node! send mark slice wait-for "Ada Lovelace")
  (command "roman-node-at-point" #"Roman node: Ada Lovelace")

  ;; Relations are categorized and one exact occurrence is navigable.
  (define relations-start (mark))
  (send-roman-binding! send (char->integer #\l))
  (wait-for #"Roman relations: Ada Lovelace" relations-start)
  (wait-for (string->bytes/utf-8 "Summary · Ada Lovelace") relations-start)
  (wait-for
   (string->bytes/utf-8 "Backlink · Analytical Engine → Ada Lovelace")
   relations-start)
  (wait-for
   (string->bytes/utf-8 "Outgoing link · Ada Lovelace → Analytical Engine")
   relations-start)
  (wait-for
   (string->bytes/utf-8 "External reference · Ada Lovelace")
   relations-start)
  (send #"Backlink")
  (wait-for #"1/1" relations-start)
  (define relation-refresh (mark))
  (send #"g")
  (wait-for #"Roman relations: Ada Lovelace" relation-refresh)
  (wait-for #"1/1" relation-refresh)
  (define relation-activation (mark))
  (send #"\r")
  (wait-for #"Opened " relation-activation)

  ;; The textual graph is inspectable and the DOT export names its destination.
  (define graph-start (mark))
  (send-roman-binding! send (char->integer #\g))
  (wait-for #"Roman graph:" graph-start)
  (wait-for (string->bytes/utf-8 "Node · Ada Lovelace") graph-start)
  (wait-for
   (string->bytes/utf-8 "Link · Ada Lovelace → Analytical Engine")
   graph-start)
  (wait-for #"unresolved destination" graph-start)
  (send control-g)
  (command "roman-graph-export" #"Exported Roman graph: .build/roman/")
  (define graph-export-root (build-path project-root ".build" "roman"))
  (check-true
   (and (directory-exists? graph-export-root)
        (ormap
         (lambda (path)
           (regexp-match? #rx#"^roman-graph-generation-[0-9]+\\.dot$"
                          (path->bytes path)))
         (directory-list graph-export-root))))
  (define graph-details-start (mark))
  (send-command! send "roman-graph-details" wait-for mark)
  (wait-for #"Roman graph details:" graph-details-start)
  (wait-for #"00-start-here.org" graph-details-start)
  (send control-g)

  ;; The canonical reference at point seeds discovery without a selected region.
  (open-node! send mark slice wait-for "Reference Lookup")
  (send control-a)
  (send control-n)
  (for ([_index (in-range 6)]) (send right))
  (define reference-start (mark))
  (send-command! send "roman-ref-find" wait-for mark)
  (wait-for #"Roman references" reference-start)
  (wait-for #"Ada Lovelace" reference-start)
  (wait-for #"1/1" reference-start)
  (define reference-activation (mark))
  (send #"\r")
  (wait-for #"Opened " reference-activation)

  ;; Stable-link insertion is one edit unit across undo and redo.
  (open-node! send mark slice wait-for "Draft Link")
  (select-line-text! send 4 "Analytical Engine")
  (define destination-start (mark))
  (send-roman-binding! send (char->integer #\i))
  (wait-for #"Roman link destination" destination-start)
  (wait-for #"1/1" destination-start)
  (define destination-activation (mark))
  (send #"\r")
  (wait-for #"Inserted a stable link to topic-engine" destination-activation)
  (save! send)
  (wait-for-file-content draft-path draft-linked)
  (define undo-start (mark))
  (send control-underscore)
  (wait-for #"Analytical Engine" undo-start)
  (save! send)
  (wait-for-file-content draft-path draft-original)
  (define redo-start (mark))
  (send-command! send "redo" wait-for mark)
  (wait-for #"[[id:topic-engine][Analytical Engine]]" redo-start)
  (save! send)
  (wait-for-file-content draft-path draft-linked)

  ;; Metadata editing resolves the word at point and aliases remain searchable.
  (open-node! send mark slice wait-for "Test metadata editing")
  (send control-a)
  (for ([_index (in-range 4)]) (send control-n))
  (for ([_index (in-range 4)]) (send right))
  (command "roman-alias-add"
           #"Added alias \"experiment\" to \"Test metadata editing\".")
  (save! send)
  (wait-for-file-content metadata-path metadata-with-alias)
  (command "roman-index-refresh" #"generation 2")
  (open-node! send mark slice wait-for "peri")
  (command "roman-node-at-point" #"Roman node: Test metadata editing")

  ;; Daily navigation opens the existing documents directly.
  (command "roman-daily-visit" #"Today Daily Acceptance")
  (command "roman-daily-next" #"Next Daily Acceptance")
  (command "roman-daily-previous" #"Previous Daily Acceptance")

  (send-roman-binding! send (char->integer #\c))
  (wait-for-file-containing inbox-path "* #+TITLE: Previous Daily Acceptance")
  (send-roman-binding! send (char->integer #\j))
  (wait-for-file-containing today-daily-path
                            "* #+TITLE: Previous Daily Acceptance")
  (command "roman-index-refresh" #"generation 3"))

(define (recovery-session send mark _slice wait-for command open-start-file!)
  (open-start-file!)
  (command "roman-space-inspect" #"Roman default brain: state active")
  (command "roman-index-refresh" #"Roman indexed 8 Jan sources")
  (command "roman-index-status" #"Roman generation 1: 8 sources")
  (define render-start (mark))
  (send-command! send "roman-graph-render" wait-for mark)
  (wait-for #"Graphviz is not installed; DOT: .build/roman/" render-start)
  (send control-g))

(dynamic-wind
  void
  (lambda ()
    (make-directory* configuration-root)
    (make-directory* package-root)
    (make-directory recovery-path)
    (make-file-or-directory-link bash-path (build-path recovery-path "bash"))
    (make-file-or-directory-link dirname-path (build-path recovery-path "dirname"))
    (file-or-directory-permissions configuration-base #o700)
    (file-or-directory-permissions data-base #o700)
    (file-or-directory-permissions configuration-root #o700)
    (file-or-directory-permissions package-root #o700)
    (write-project-fixtures!)
    ;; The personal corpus is configured explicitly, never inferred from promotion.
    (call-with-output-file
     (build-path configuration-root "init.rkt")
     (lambda (output)
       (fprintf output
                "#lang racket/base\n(require odra/commands)\n(provide odra-package-resources)\n(define odra-package-resources (list (make-package-resource #:package \"odra.roman\" #:name 'brain #:root ~s #:access 'read-write)))\n"
                (path->string project-root))))
    (promote-project!)
    (install-package!)
    ;; Release the installer process runtime before the editor restores the
    ;; same enabled package from durable lifecycle state.
    (reset-package-lifecycle-runtime!)
    (run-editor-session first-session)
    (check-true (file-exists? inbox-path))
    (check-true
     (string-contains? (file->string inbox-path)
                       "* #+TITLE: Previous Daily Acceptance"))
    (define database (build-path package-data-root "roman.sqlite3"))
    (check-true (file-exists? database))
    (delete-file database)
    (run-editor-session recovery-session #:path (path->string recovery-path))
    (check-true (file-exists? database))
    (ensure-lifecycle-success
     "disable"
     (package-lifecycle-runtime-disable package-root "odra.roman"))
    (define state
      (package-state-module-load (build-path package-root "packages" "state.rktd")))
    (check-true (odra-package-state? state))
    (define installed (package-state-find state "odra.roman" roman-version))
    (check-true (odra-installed-package? installed))
    (check-eq? (odra-installed-package-lifecycle installed) 'installed-disabled)
    (check-true (file-exists? start-path))
    (check-true (file-exists? inbox-path)))
  (lambda ()
    (let cleanup ([attempts 10])
      (when (directory-exists? sandbox)
        (with-handlers
            ([exn:fail:filesystem?
              (lambda (observed)
                (if (> attempts 1)
                    (begin
                      (sleep 0.1)
                      (cleanup (sub1 attempts)))
                    (raise observed)))])
          (delete-directory/files sandbox))))))
