#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/file
         racket/list
         racket/path
         racket/sandbox
         racket/string
         rackunit
         "../../src/agent/registry.rkt"
         "../../src/command/catalog.rkt"
         "../../src/command/context.rkt"
         "../../src/command/package-resources.rkt"
         (prefix-in bundle: "../../src/command/language-bundles.rkt")
         "../../src/command/personal-limits.rkt"
         "../../src/command/transaction.rkt"
         "../../src/package/acquisition.rkt"
         "../../src/package/manifest-contracts.rkt"
         "../../src/package/runtime.rkt"
         "../../src/package/state-records.rkt")

(define (digest character) (make-string 64 character))

(define (sha256 value)
  (bytes->hex-string (sha256-bytes (open-input-bytes value))))

(define (write-content root content)
  (define content-digest (sha256 content))
  (define path (package-content-path root content-digest))
  (make-parent-directory* path)
  (call-with-output-file path
    (lambda (output) (write-bytes content output))
    #:mode 'binary
    #:permissions #o600)
  content-digest)

(define (make-runtime-fixture root module-source
                              #:package-id [package-id "odra.fixture"]
                              #:version [version "1.0.0"]
                              #:command-id [command-id "fixture-command"]
                              #:requirements [requirements '(active-buffer)]
                              #:effects [effects '(buffer)]
                              #:contributions [contributions #f]
                              #:grant-generation [grant-generation 1]
                              #:authorities [authorities '(racket-extension)]
                              #:modules [modules '()])
  (define normalized-authorities (sort authorities symbol<?))
  (define module-sources (cons (cons "main.rkt" module-source) modules))
  (define module-records
    (for/list ([module (in-list module-sources)]
               [index (in-naturals 1)])
      (define module-bytes (string->bytes/utf-8 (cdr module)))
      (define module-digest (write-content root module-bytes))
      (list index (car module) module-bytes module-digest)))
  (define-values (manifest rejection)
    (confirm-package-manifest
     (odra-package-manifest-proposal
      1 package-id 'extension "Fixture" version "" "MIT" #f
      "odra.publisher" (make-string 40 #\a) "1.0.0" "2.0.0"
      (list (odra-package-target 'linux 'x86-64)) '() normalized-authorities
      (for/list ([record (in-list module-records)])
        (odra-package-artifact
         (format "module-~a" (car record))
         'racket-module (cadr record) (cadddr record)
         (bytes-length (caddr record)) #f #f 'racket-extension '()))
      (odra-package-entrypoint "main.rkt" 'odra-package-contributions)
      (or contributions
          (list
           (odra-package-contribution
            command-id 'command requirements effects)))
      '() (odra-package-state-compatibility #f #f #f 'none))))
  (check-false rejection)
  (define installed
    (odra-installed-package
     package-id 'extension version 1
     (package-manifest-digest manifest) #f
     (sort (map cadddr module-records) string<?) '()
     (odra-package-provenance
      'catalog (digest #\1) (digest #\2) (digest #\3)
      "odra.publisher" (make-string 40 #\a))
     'linux 'x86-64 normalized-authorities '() ""
     'installed-disabled 0 #f #f #f #f ""))
  (values installed manifest
          (odra-package-authority-grant
           package-id version grant-generation normalized-authorities "test grant")))

(define valid-module
  (string-append
   "#lang racket/base\n"
   "(require odra/commands)\n"
   "(provide odra-package-contributions)\n"
   "(define odra-package-contributions\n"
   "  (list (make-command 'fixture-command (lambda (_context) 'called)\n"
   "                      #:requirements '(active-buffer)\n"
   "                      #:effects '(buffer))))\n"))

(define (command-module expression)
  (string-append
   "#lang racket/base\n"
   "(require odra/commands)\n"
   "(provide odra-package-contributions)\n"
   "(define odra-package-contributions\n"
   "  (list (make-command 'fixture-command (lambda (_context) " expression ")\n"
   "                      #:requirements '(active-buffer)\n"
   "                      #:effects '(buffer))))\n"))

(define agent-module
  (string-append
   "#lang racket/base\n"
   "(require odra/agents)\n"
   "(provide odra-package-contributions)\n"
   "(define odra-package-contributions\n"
   "  (list\n"
   "   (make-agent 'fixture-agent\n"
   "               #:provider-requirements '(odra.agent-driver)\n"
   "               #:requested-capabilities '(fixture.observe))\n"
   "   (make-agent-capability\n"
   "    'fixture.observe 'fixture\n"
   "    (lambda (_context)\n"
   "      (make-agent-capability-owner-result\n"
   "       'succeeded #:result '() #:safe-summary \"fixture\"))\n"
   "    #:effects '(observe)\n"
   "    #:required-authorities '(project-read))))\n"))

(define agent-contributions
  (list
   (odra-package-contribution
    "fixture-agent" 'agent '(odra.agent-driver) '(fixture.observe))
   (odra-package-contribution
    "fixture.observe" 'agent-capability '(project-read) '(observe))))

(define keymap-module
  (string-append
   "#lang racket/base\n"
   "(require odra/commands)\n"
   "(provide odra-package-contributions)\n"
   "(define odra-package-contributions\n"
   "  (list\n"
   "   (make-command 'fixture-command (lambda (_context) 'called)\n"
   "                 #:requirements '(active-buffer)\n"
   "                 #:effects '(buffer))\n"
   "   (language-keymap #:id 'fixture.direct #:languages '(jan)\n"
   "                    #:states '(direct)\n"
   "                    #:context 'language-context\n"
   "                    #:bindings (hash \"C-c n f\" 'fixture-command))))\n"))

(define keymap-contributions
  (list
   (odra-package-contribution
    "fixture-command" 'command '(active-buffer) '(buffer))
   (odra-package-contribution
    "fixture.direct" 'keymap '(jan) '())))

(define (prepare-source-result source #:limits [limits default-package-runtime-limits])
  (define root (make-temporary-file "package-runtime-result-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define-values (installed manifest grant)
        (make-runtime-fixture root source))
      (prepare-package-runtime root installed manifest grant 2 #:limits limits))
    (lambda () (delete-directory/files root))))

(test-case "package entrypoint forms one unpublished command candidate"
  (define root (make-temporary-file "package-runtime-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define-values (installed manifest grant)
        (make-runtime-fixture root valid-module))
      (define candidate
        (prepare-package-runtime root installed manifest grant 2))
      (check-true (odra-package-runtime-candidate? candidate)
                  (format "~s" candidate))
      (check-equal? (package-runtime-candidate-command-names candidate)
                    '("fixture-command"))
      (check-eq? (package-runtime-candidate-state candidate) 'prepared)
      (check-equal?
       (length
        (odra-command-catalog-definitions
         (package-runtime-candidate-catalog candidate)))
       8)
      (discard-package-runtime-candidate! candidate)
      (check-eq? (package-runtime-candidate-state candidate) 'retired)
      (check-equal? (package-runtime-candidate-command-names candidate) '()))
    (lambda () (delete-directory/files root))))

(test-case "package entrypoint admits the JSON library and its dependencies"
  (define root (make-temporary-file "package-runtime-json-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define source
        (string-append
         "#lang racket/base\n"
         "(require odra/commands \"value.rkt\")\n"
         "(provide odra-package-contributions)\n"
         "(define odra-package-contributions\n"
         "  (list (make-command 'fixture-command\n"
         "                      (lambda (_context) (package-value))\n"
         "                      #:requirements '(active-buffer)\n"
         "                      #:effects '(buffer))))\n"))
      (define helper
        (string-append
         "#lang racket/base\n"
         "(require json)\n"
         "(provide package-value)\n"
         "(define (package-value) (jsexpr->string (hash 'ok #t)))\n"))
      (define-values (installed manifest grant)
        (make-runtime-fixture
         root source #:modules (list (cons "value.rkt" helper))))
      (define candidate
        (prepare-package-runtime root installed manifest grant 2))
      (check-true (odra-package-runtime-candidate? candidate)
                  (format "~s" candidate))
      (define runtime (make-package-runtime))
      (check-true (void? (package-runtime-activate! runtime candidate)))
      (check-equal?
       (package-runtime-call runtime "odra.fixture" 2 "fixture-command" #f)
       "{\"ok\":true}")
      (package-runtime-close! runtime))
    (lambda () (delete-directory/files root))))

(test-case "package keymaps activate replace and deactivate with commands"
  (define first-root (make-temporary-file "package-keymap-first-~a" 'directory))
  (define second-root (make-temporary-file "package-keymap-second-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define-values (first-installed first-manifest first-grant)
        (make-runtime-fixture
         first-root keymap-module #:contributions keymap-contributions))
      (define-values (second-installed second-manifest second-grant)
        (make-runtime-fixture
         second-root keymap-module
         #:version "1.1.0"
         #:grant-generation 2
         #:contributions keymap-contributions))
      (define first
        (prepare-package-runtime
         first-root first-installed first-manifest first-grant 2))
      (check-true (odra-package-runtime-candidate? first) (format "~s" first))
      (check-equal?
       (map bundle:odra-language-keymap-id
            (package-runtime-candidate-keymaps first))
       '(fixture.direct))
      (define runtime (make-package-runtime))
      (check-true (void? (package-runtime-activate! runtime first)))
      (check-equal?
       (hash-ref
        (bundle:odra-language-keymap-bindings
         (car (package-runtime-keymaps runtime)))
        "C-c n f")
       'fixture-command)
      (define second
        (prepare-package-runtime
         second-root second-installed second-manifest second-grant 3))
      (check-true (void? (package-runtime-activate! runtime second)))
      (check-eq? (package-runtime-candidate-state first) 'retired)
      (check-equal? (length (package-runtime-keymaps runtime)) 1)
      (check-true
       (void? (package-runtime-deactivate! runtime "odra.fixture" 3 4)))
      (check-equal? (package-runtime-keymaps runtime) '())
      (check-eq? (package-runtime-candidate-state second) 'retired)
      (package-runtime-close! runtime))
    (lambda ()
      (delete-directory/files first-root)
      (delete-directory/files second-root))))

(test-case "package entrypoint loads its declared local module tree"
  (define root (make-temporary-file "package-runtime-modules-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define entrypoint
        (string-append
         "#lang racket/base\n"
         "(require odra/commands \"lib/value.rkt\")\n"
         "(provide odra-package-contributions)\n"
         "(define odra-package-contributions\n"
         "  (list (make-command 'fixture-command (lambda (_context) (package-value))\n"
         "                      #:requirements '(active-buffer)\n"
         "                      #:effects '(buffer))))\n"))
      (define helper
        (string-append
         "#lang racket/base\n"
         "(require racket/list \"../shared/nested.rkt\")\n"
         "(provide package-value)\n"
         "(define (package-value) (car (list (nested-value))))\n"))
      (define nested-helper
        (string-append
         "#lang racket/base\n"
         "(provide nested-value)\n"
         "(define (nested-value) 'from-local-module)\n"))
      (define-values (installed manifest grant)
        (make-runtime-fixture
         root entrypoint
         #:modules
         (list (cons "lib/value.rkt" helper)
               (cons "shared/nested.rkt" nested-helper))))
      (define candidate
        (prepare-package-runtime root installed manifest grant 2))
      (check-true (odra-package-runtime-candidate? candidate)
                  (format "~s" candidate))
      (define runtime (make-package-runtime))
      (check-true (void? (package-runtime-activate! runtime candidate)))
      (check-equal?
       (package-runtime-call runtime "odra.fixture" 2 "fixture-command" #f)
       'from-local-module)
      (package-runtime-close! runtime))
    (lambda () (delete-directory/files root))))

(test-case "package modules cannot escape their declared module tree"
  (define root (make-temporary-file "package-runtime-module-escape-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define entrypoint
        (string-append
         "#lang racket/base\n"
         "(require odra/commands \"lib/value.rkt\")\n"
         "(provide odra-package-contributions)\n"
         "(define odra-package-contributions\n"
         "  (list (make-command 'fixture-command (lambda (_context) package-value)\n"
         "                      #:requirements '(active-buffer)\n"
         "                      #:effects '(buffer))))\n"))
      (define helper
        (string-append
         "#lang racket/base\n"
         "(require \"../../outside.rkt\")\n"
         "(provide package-value)\n"
         "(define package-value 'unreachable)\n"))
      (define-values (installed manifest grant)
        (make-runtime-fixture
         root entrypoint #:modules (list (cons "lib/value.rkt" helper))))
      (define result (prepare-package-runtime root installed manifest grant 2))
      (check-true (odra-package-runtime-failure? result) (format "~s" result))
      (check-eq? (odra-package-runtime-failure-code result) 'denied))
    (lambda () (delete-directory/files root))))

(test-case "package source admits only the racket/base language preamble"
  (define source-body
    (substring valid-module (string-length "#lang racket/base\n")))
  (define admitted-source
    (string-append
     "; package comment\n"
     "#| outer comment #| nested comment |# |#\n"
     "#lang racket/base ; supported package language\n"
     source-body))
  (define admitted (prepare-source-result admitted-source))
  (check-true (odra-package-runtime-candidate? admitted) (format "~s" admitted))
  (discard-package-runtime-candidate! admitted)
  (for ([denied-source
         (in-list
          (list
           (string-append "#lang s-exp racket/base\n" source-body)
           (string-append "#lang racket/base-extra\n" source-body)
           (string-append "#lang\n" source-body)
           (string-append "#reader racket/base\n" source-body)))])
    (define denied (prepare-source-result denied-source))
    (check-true (odra-package-runtime-failure? denied) (format "~s" denied))
    (check-eq? (odra-package-runtime-failure-code denied) 'denied)))

(test-case "package-local reader rejects before its side effect"
  (define root (make-temporary-file "package-runtime-reader-~a" 'directory))
  (define marker (build-path root "reader-executed"))
  (dynamic-wind
    void
    (lambda ()
      (define reader
        (string-append
         "#lang racket/base\n"
         (format
          "(call-with-output-file ~s (lambda (output) (display \"executed\" output)))\n"
          (path->string marker))
         "(provide read read-syntax get-info)\n"
         "(define (read . _arguments) eof)\n"
         "(define (read-syntax . _arguments) eof)\n"
         "(define (get-info . _arguments) (lambda (_key default) default))\n"))
      (define-values (installed manifest grant)
        (make-runtime-fixture
         root
         "#lang racket/base\n#reader \"reader.rkt\"\n"
         #:modules (list (cons "reader.rkt" reader))))
      (define result
        (prepare-package-runtime root installed manifest grant 2))
      (check-true (odra-package-runtime-failure? result) (format "~s" result))
      (check-eq? (odra-package-runtime-failure-code result) 'denied)
      (check-false (file-exists? marker)))
    (lambda () (delete-directory/files root))))

(test-case "package command receives bounded resource storage and feedback context"
  (define root (make-temporary-file "package-runtime-context-roots-~a" 'directory))
  (define project (build-path root "project"))
  (define data-root (build-path root "package-data"))
  (make-directory project)
  (define document-path (build-path project "note.org"))
  (call-with-output-file document-path
    (lambda (output) (display "Roman source" output)))
  (dynamic-wind
    void
    (lambda ()
      (define entrypoint
        (string-append
         "#lang racket/base\n"
         "(require odra/commands \"lib/context.rkt\")\n"
         "(provide odra-package-contributions)\n"
         "(define odra-package-contributions\n"
         "  (list (make-command 'fixture-command exercise-context\n"
         "                      #:requirements '(active-buffer active-document)\n"
         "                      #:effects '(buffer))))\n"))
      (define helper
        (string-append
         "#lang racket/base\n"
         "(require odra/commands racket/file racket/path)\n"
         "(provide exercise-context)\n"
         "(define (exercise-context context)\n"
         "  (define source (file->string (command-context-document-path context)))\n"
         "  (define state (build-path (command-context-package-data-root context) \"state.txt\"))\n"
         "  (call-with-output-file state (lambda (out) (display source out)) #:exists 'truncate)\n"
         "  (command-context-message! context (string-append \"Indexed \" source))\n"
         "  (void))\n"))
      (define-values (installed manifest grant)
        (make-runtime-fixture
         root entrypoint
         #:requirements '(active-buffer active-document)
         #:effects '(buffer)
         #:authorities '(racket-extension project-read project-write)
         #:modules (list (cons "lib/context.rkt" helper))))
      (define candidate
        (prepare-package-runtime root installed manifest grant 2))
      (check-true (odra-package-runtime-candidate? candidate)
                  (format "~s" candidate))
      (define runtime (make-package-runtime))
      (check-true (void? (package-runtime-activate! runtime candidate)))
      (call-with-transaction
       1
       (lambda (_token _operation _payload) (list 'ok #t))
       (lambda (transaction)
         (call-with-command-context
          transaction 1 0 #f #f 0 0 0 '(buffer) (lambda () #f)
          (lambda (context)
            (check-true (void?
             (call-with-contained-package-command
              (lambda ()
                (package-runtime-call
                 runtime "odra.fixture" 2 "fixture-command" context)))))
            (check-equal? (command-context-message context)
                          "Indexed Roman source"))
          #:document-path (path->string document-path)
          #:project-root (path->string project)
          #:package-data-root (path->string data-root))))
      (check-equal? (file->string (build-path data-root "state.txt"))
                    "Roman source")
      (package-runtime-close! runtime))
    (lambda () (delete-directory/files root))))

;; A personal corpus is independent of the current Project and cannot self-grant access.
(test-case "configured resources stay package scoped and honor access modes"
  (define root (make-temporary-file "package-resource-grant-~a" 'directory))
  (define brain (build-path root "brain"))
  (define foreign (build-path root "foreign"))
  (make-directory brain)
  (make-directory foreign)
  (make-file-or-directory-link foreign (build-path brain "outside"))
  (define note (build-path brain "note.org"))
  (call-with-output-file note (lambda (output) (display "Personal source" output)))
  (dynamic-wind
    void
    (lambda ()
      (for ([case-data
             (in-list
              '((read read project-read success)
                (write read-write project-write success)
                (write read project-write denied)
                (write read-write project-read denied)
                (foreign read-write project-write denied)
                (escape read-write project-write denied)
                (symlink read-write project-write denied)))])
        (define operation (car case-data))
        (define access (cadr case-data))
        (define authority (caddr case-data))
        (define expected (cadddr case-data))
        (define expression
          (case operation
            [(read) (format "(file->string ~s)" (path->string note))]
            [(write) (format "(call-with-output-file ~s (lambda (out) (display \"entry\" out)) #:exists 'truncate)"
                             (path->string (build-path brain "capture.org")))]
            [(foreign) (format "(directory-list ~s)" (path->string foreign))]
            [(escape) (format "(directory-list ~s)" (path->string (build-path brain 'up "foreign")))]
            [(symlink) (format "(directory-list ~s)" (path->string (build-path brain "outside")))]))
        (define source
          (string-append
           "#lang racket/base\n(require odra/commands \"resource.rkt\")\n"
           "(provide odra-package-contributions)\n"
           "(define odra-package-contributions\n"
           " (list (make-command 'fixture-command exercise-resource\n"
           " #:requirements '(active-buffer) #:effects '(buffer))))\n"))
        (define helper
          (string-append "#lang racket/base\n(require racket/file)\n"
                         "(provide exercise-resource)\n"
                         "(define (exercise-resource context) " expression ")\n"))
        (define-values (installed manifest grant)
          (make-runtime-fixture (build-path root (symbol->string operation)
                                            (symbol->string access) (symbol->string authority))
                                source #:modules (list (cons "resource.rkt" helper))
                                #:authorities (remove-duplicates
                                               (list 'racket-extension 'project-read authority))))
        (define candidate
          (prepare-package-runtime
           (build-path root (symbol->string operation)
                       (symbol->string access) (symbol->string authority))
           installed manifest grant 2))
        (check-true (odra-package-runtime-candidate? candidate) (format "~s" candidate))
        (define runtime (make-package-runtime))
        (package-runtime-activate! runtime candidate)
        (call-with-transaction
         1 (lambda (_token _operation _payload) (list 'ok #t))
         (lambda (transaction)
           (call-with-command-context
            transaction 1 0 #f #f 0 0 0 '(buffer) (lambda () #f)
            (lambda (context)
              (define (call)
                (call-with-contained-package-command
                 (lambda () (package-runtime-call runtime "odra.fixture" 2 "fixture-command" context))))
              (if (eq? expected 'success)
                  (check-not-exn call (format "~s" case-data))
                  (check-exn #rx"file access denied" call (format "~s" case-data))))
            #:package-resources
            (list (make-package-resource #:package "odra.fixture" #:name 'brain
                                         #:root brain #:access access)
                  (make-package-resource #:package "odra.other" #:name 'private
                                         #:root foreign #:access 'read-write)))))
        (package-runtime-close! runtime)))
    (lambda () (delete-directory/files root))))

(test-case "external-process authority admits only the Graphviz package tool"
  (define root (make-temporary-file "package-runtime-graphviz-~a" 'directory))
  (define data-root (build-path root "package-data"))
  (dynamic-wind
    void
    (lambda ()
      (define source
        (string-append
         "#lang racket/base\n"
         "(require odra/commands)\n"
         "(provide odra-package-contributions)\n"
         "(define (render context)\n"
         "  (command-context-write-package-artifact! context \"exports/fixture.dot\" #\"digraph fixture {}\")\n"
         "  (define result (command-context-render-graphviz! context \"exports/fixture.dot\" \"exports/fixture.svg\" 5000))\n"
         "  (command-context-message! context (symbol->string (command-tool-result-status result)))\n"
         "  (void))\n"
         "(define odra-package-contributions\n"
         "  (list (make-command 'fixture-command render\n"
         "                      #:requirements '(active-buffer)\n"
         "                      #:effects '(buffer))))\n"))
      (define-values (installed manifest grant)
        (make-runtime-fixture
         root source #:authorities '(external-process racket-extension)))
      (define candidate
        (prepare-package-runtime root installed manifest grant 2))
      (check-true (odra-package-runtime-candidate? candidate)
                  (format "~s" candidate))
      (define runtime (make-package-runtime))
      (check-true (void? (package-runtime-activate! runtime candidate)))
      (call-with-transaction
       1
       (lambda (_token _operation _payload) (list 'ok #t))
       (lambda (transaction)
         (call-with-command-context
          transaction 1 0 #f #f 0 0 0 '(buffer) (lambda () #f)
          (lambda (context)
            (check-true
             (void?
              (call-with-contained-package-command
               (lambda ()
                 (package-runtime-call
                  runtime "odra.fixture" 2 "fixture-command" context)))))
            (check-equal? (command-context-message context) "success"))
          #:package-data-root (path->string data-root))))
      (check-regexp-match
       #rx"<svg"
       (file->string (build-path data-root "exports/fixture.svg")))
      (package-runtime-close! runtime))
    (lambda () (delete-directory/files root))))

(test-case "activation replacement and deactivation publish complete generations"
  (define root (make-temporary-file "package-runtime-lifecycle-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define-values (installed manifest grant)
        (make-runtime-fixture root valid-module))
      (define first (prepare-package-runtime root installed manifest grant 2))
      (define runtime (make-package-runtime))
      (check-false (package-runtime-active-generation runtime "odra.fixture"))
      (check-exn
       #rx"not active"
       (lambda ()
         ((odra-command-definition-implementation
           (last
            (odra-command-catalog-definitions
             (package-runtime-candidate-catalog first))))
          #f)))
      (check-true (void? (package-runtime-activate! runtime first)))
      (check-eq? (package-runtime-candidate-state first) 'active)
      (check-equal? (package-runtime-active-generation runtime "odra.fixture") 2)
      (check-equal? (package-runtime-call
                     runtime "odra.fixture" 2 "fixture-command" #f)
                    'called)

      (define updated-module
        (string-replace valid-module "'called" "'updated"))
      (define-values (updated-installed updated-manifest updated-grant)
        (make-runtime-fixture
         root updated-module #:version "1.1.0" #:grant-generation 2))
      (define updated
        (prepare-package-runtime
         root updated-installed updated-manifest updated-grant 3))
      (check-true (void? (package-runtime-activate! runtime updated)))
      (check-eq? (package-runtime-candidate-state first) 'retired)
      (check-exn
       #rx"unavailable"
       (lambda ()
         (package-runtime-call runtime "odra.fixture" 2 "fixture-command" #f)))
      (check-equal? (package-runtime-call
                     runtime "odra.fixture" 3 "fixture-command" #f)
                    'updated)
      (check-true
       (void? (package-runtime-deactivate! runtime "odra.fixture" 3 4)))
      (check-false (package-runtime-active-generation runtime "odra.fixture"))
      (check-eq? (package-runtime-candidate-state updated) 'retired)
      (check-equal? (length
                     (odra-command-catalog-definitions
                      (package-runtime-catalog runtime)))
                    7)
      (package-runtime-close! runtime))
    (lambda () (delete-directory/files root))))

(test-case "failed and stale activation preserve the confirmed generation"
  (define root (make-temporary-file "package-runtime-rollback-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define-values (installed manifest grant)
        (make-runtime-fixture root valid-module))
      (define active (prepare-package-runtime root installed manifest grant 2))
      (define runtime (make-package-runtime))
      (check-true (void? (package-runtime-activate! runtime active)))

      (define collision-module
        (string-replace valid-module "'called" "'collision"))
      (define-values (collision-installed collision-manifest collision-grant)
        (make-runtime-fixture
         root collision-module
         #:package-id "odra.collision"
         #:grant-generation 2))
      (define collision
        (prepare-package-runtime
         root collision-installed collision-manifest collision-grant 3))
      (define rejected (package-runtime-activate! runtime collision))
      (check-true (odra-package-runtime-failure? rejected))
      (check-eq? (odra-package-runtime-failure-code rejected) 'contribution)
      (check-equal? (package-runtime-call
                     runtime "odra.fixture" 2 "fixture-command" #f)
                    'called)
      (check-eq? (package-runtime-candidate-state collision) 'prepared)
      (discard-package-runtime-candidate! collision)

      (define stale (prepare-package-runtime root installed manifest grant 2))
      (define stale-result (package-runtime-activate! runtime stale))
      (check-true (odra-package-runtime-failure? stale-result))
      (check-eq? (odra-package-runtime-failure-code stale-result) 'stale)
      (check-equal? (package-runtime-active-generation runtime "odra.fixture") 2)
      (discard-package-runtime-candidate! stale)
      (package-runtime-close! runtime))
    (lambda () (delete-directory/files root))))

(test-case "entrypoint preparation denies undeclared operating-system authority"
  (define denied-sources
    (list
     (string-append
      "#lang racket/base\n"
      "(require odra/commands racket/file)\n"
      "(provide odra-package-contributions)\n"
      "(define odra-package-contributions '())\n")
     (string-append
      "#lang racket/base\n"
      "(require odra/commands)\n"
      "(open-input-file \"/etc/passwd\")\n"
      "(provide odra-package-contributions)\n"
      "(define odra-package-contributions '())\n")
     (string-append
      "#lang racket/base\n"
      "(require odra/commands)\n"
      "(dynamic-require 'racket/tcp 'tcp-connect)\n"
      "(provide odra-package-contributions)\n"
      "(define odra-package-contributions '())\n")
     (string-append
      "#lang racket/base\n"
      "(require odra/commands)\n"
      "(subprocess #f #f #f \"/bin/true\")\n"
      "(provide odra-package-contributions)\n"
      "(define odra-package-contributions '())\n")
     (string-append
      "#lang racket/base\n"
      "(require odra/commands)\n"
      "(dynamic-require 'ffi/unsafe 'ffi-lib)\n"
      "(provide odra-package-contributions)\n"
      "(define odra-package-contributions '())\n")
     (string-append
      "#lang racket/base\n"
      "(require odra/commands)\n"
      "(dynamic-require \"../../command/catalog.rkt\" #f)\n"
      "(provide odra-package-contributions)\n"
      "(define odra-package-contributions '())\n")
     (command-module "(dynamic-require 'ffi/unsafe 'ffi-lib)")
     (command-module
      "(quasiquote (,(dynamic-require 'ffi/unsafe 'ffi-lib)))")))
  (for ([source (in-list denied-sources)])
    (define result (prepare-source-result source))
    (check-true (odra-package-runtime-failure? result) (format "~s" result))
    (check-eq? (odra-package-runtime-failure-code result) 'denied)))

(test-case "package-local modules cannot import runtime-private libraries"
  (define entrypoint
    (string-append
     "#lang racket/base\n"
     "(require odra/commands \"lib/private.rkt\")\n"
     "(provide odra-package-contributions)\n"
     "(define odra-package-contributions\n"
     "  (list (make-command 'fixture-command (lambda (_context) 'called)\n"
     "                      #:requirements '(active-buffer)\n"
     "                      #:effects '(buffer))))\n"))
  (define denied-helpers
    (append
     (for/list ([private-module (in-list '(ffi/unsafe
                                           racket/unsafe/ops
                                           racket/private/base))])
       (cons
        private-module
        (format
         "#lang racket/base\n(require ~a)\n(provide private-value)\n(define private-value #t)\n"
         private-module)))
     (list
      (cons
       'reflective-ffi
       (string-append
        "#lang racket/base\n"
        "(provide private-value)\n"
        "(define private-value (dynamic-require 'ffi/unsafe 'ffi-lib))\n")))))
  (for ([denied-helper (in-list denied-helpers)])
    (define root (make-temporary-file "package-runtime-private-~a" 'directory))
    (dynamic-wind
      void
      (lambda ()
        (define-values (installed manifest grant)
          (make-runtime-fixture
           root entrypoint
           #:modules (list (cons "lib/private.rkt" (cdr denied-helper)))))
        (define result
          (prepare-package-runtime root installed manifest grant 2))
        (check-true (odra-package-runtime-failure? result)
                    (format "module ~a produced ~s" (car denied-helper) result))
        (check-eq? (odra-package-runtime-failure-code result) 'denied))
      (lambda () (delete-directory/files root)))))

(test-case "preparation rejects undeclared contributions and stale authority"
  (define undeclared
    (prepare-source-result
     (string-replace valid-module "fixture-command" "other-command")))
  (check-true (odra-package-runtime-failure? undeclared))
  (check-eq? (odra-package-runtime-failure-code undeclared) 'contribution)

  (define root (make-temporary-file "package-runtime-authority-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define-values (installed manifest _grant)
        (make-runtime-fixture root valid-module))
      (define result
        (prepare-package-runtime
         root installed manifest
         (odra-package-authority-grant
          "odra.fixture" "1.0.0" 1 '() "missing grant")
         2))
      (check-true (odra-package-runtime-failure? result))
      (check-eq? (odra-package-runtime-failure-code result) 'authority))
    (lambda () (delete-directory/files root))))

(test-case "preparation deadline rejects nonterminating entrypoint"
  (define source
    (string-append
     "#lang racket/base\n"
     "(require odra/commands)\n"
     "(let loop () (loop))\n"
     "(provide odra-package-contributions)\n"
     "(define odra-package-contributions '())\n"))
  (define result
    (prepare-source-result
     source
     #:limits
     (odra-package-runtime-limits
      50 (* 32 1024 1024)
      default-personal-command-limits)))
  (check-true (odra-package-runtime-failure? result))
  (check-eq? (odra-package-runtime-failure-code result) 'limit))

(test-case "active commands receive an empty environment and retain no stale callback"
  (define root (make-temporary-file "package-runtime-command-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define-values (installed manifest grant)
        (make-runtime-fixture root (command-module "(getenv \"HOME\")")))
      (define candidate
        (prepare-package-runtime root installed manifest grant 2))
      (define stale-implementation
        (odra-command-definition-implementation
         (last
          (odra-command-catalog-definitions
           (package-runtime-candidate-catalog candidate)))))
      (define runtime (make-package-runtime))
      (check-true (void? (package-runtime-activate! runtime candidate)))
      (check-false
       (package-runtime-call runtime "odra.fixture" 2 "fixture-command" #f))
      (check-true
       (void? (package-runtime-deactivate! runtime "odra.fixture" 2 3)))
      (check-exn #rx"not active" (lambda () (stale-implementation #f)))
      (package-runtime-close! runtime))
    (lambda () (delete-directory/files root))))

(test-case "host-contained package commands retain the editor context thread"
  (define root (make-temporary-file "package-runtime-context-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define-values (installed manifest grant)
        (make-runtime-fixture
         root (command-module "(command-context-active-region _context)")))
      (define candidate
        (prepare-package-runtime root installed manifest grant 2))
      (define runtime (make-package-runtime))
      (check-true (void? (package-runtime-activate! runtime candidate)))
      (define implementation
        (odra-command-definition-implementation
         (last
          (odra-command-catalog-definitions
           (package-runtime-candidate-catalog candidate)))))
      (call-with-transaction
       1
       (lambda (_token _operation _payload) (list 'ok #t))
       (lambda (transaction)
         (call-with-command-context
          transaction 1 3 0 3 0 3 3 '(buffer) (lambda () #f)
          (lambda (context)
            (check-true
             (text-range?
              (call-with-contained-package-command
               (lambda () (implementation context)))))))))
      (package-runtime-close! runtime))
    (lambda () (delete-directory/files root))))

(test-case "active command turns retain the package security guard"
  (define root (make-temporary-file "package-runtime-command-denial-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define-values (installed manifest grant)
        (make-runtime-fixture
         root (command-module "(open-input-file \"/etc/passwd\")")))
      (define candidate
        (prepare-package-runtime root installed manifest grant 2))
      (define runtime (make-package-runtime))
      (check-true (void? (package-runtime-activate! runtime candidate)))
      (check-exn
       #rx"file access denied"
       (lambda ()
         (package-runtime-call
          runtime "odra.fixture" 2 "fixture-command" #f)))
      (check-eq? (package-runtime-candidate-state candidate) 'active)
      (package-runtime-close! runtime)
      (check-eq? (package-runtime-candidate-state candidate) 'retired))
    (lambda () (delete-directory/files root))))

(test-case "command turns enforce limits and remove child work"
  (define limit-root (make-temporary-file "package-runtime-limit-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define limits
        (odra-package-runtime-limits
         1000 (* 32 1024 1024)
         (make-personal-command-limits
          #:deadline-milliseconds 50
          #:custodian-memory-bytes (* 32 1024 1024))))
      (define-values (installed manifest grant)
        (make-runtime-fixture
         limit-root (command-module "(let loop () (loop))")))
      (define candidate
        (prepare-package-runtime
         limit-root installed manifest grant 2 #:limits limits))
      (define runtime (make-package-runtime))
      (check-true (void? (package-runtime-activate! runtime candidate)))
      (check-exn
       exn:fail:resource?
       (lambda ()
         (package-runtime-call
          runtime "odra.fixture" 2 "fixture-command" #f)))
      (check-equal? (package-runtime-candidate-active-turns candidate) 0)
      (package-runtime-close! runtime))
    (lambda () (delete-directory/files limit-root)))

  (define child-root (make-temporary-file "package-runtime-child-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define-values (installed manifest grant)
        (make-runtime-fixture
         child-root
         (command-module
          "(thread (lambda () (let loop () (sleep 1) (loop))))")))
      (define candidate
        (prepare-package-runtime child-root installed manifest grant 2))
      (define runtime (make-package-runtime))
      (check-true (void? (package-runtime-activate! runtime candidate)))
      (define child
        (package-runtime-call
         runtime "odra.fixture" 2 "fixture-command" #f))
      (check-true (thread? child))
      (check-not-false (sync/timeout 1 (thread-dead-evt child)))
      (package-runtime-close! runtime))
    (lambda () (delete-directory/files child-root))))

(test-case "deactivation waits for an admitted command turn before teardown"
  (define root (make-temporary-file "package-runtime-turn-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define-values (installed manifest grant)
        (make-runtime-fixture root (command-module "(begin (sleep 0.2) 'done)")))
      (define candidate
        (prepare-package-runtime root installed manifest grant 2))
      (define runtime (make-package-runtime))
      (check-true (void? (package-runtime-activate! runtime candidate)))
      (define turn
        (thread
         (lambda ()
           (package-runtime-call
            runtime "odra.fixture" 2 "fixture-command" #f))))
      (let wait-for-turn ()
        (when (zero? (package-runtime-candidate-active-turns candidate))
          (sleep 0.005)
          (wait-for-turn)))
      (check-true
       (void? (package-runtime-deactivate! runtime "odra.fixture" 2 3)))
      (check-eq? (package-runtime-candidate-state candidate) 'retiring)
      (thread-wait turn)
      (check-eq? (package-runtime-candidate-state candidate) 'retired)
      (check-equal? (package-runtime-candidate-active-turns candidate) 0)
      (package-runtime-close! runtime))
    (lambda () (delete-directory/files root))))

(test-case "package entrypoint prepares and publishes inert agent definitions"
  (define root (make-temporary-file "package-runtime-agent-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define-values (installed manifest grant)
        (make-runtime-fixture
         root agent-module #:contributions agent-contributions))
      (define candidate
        (prepare-package-runtime root installed manifest grant 2))
      (check-true (odra-package-runtime-candidate? candidate)
                  (format "~s" candidate))
      (check-equal? (package-runtime-candidate-command-names candidate) '())
      (define prepared (package-runtime-candidate-agent-catalog candidate))
      (check-equal? (length (odra-agent-catalog-agents prepared)) 1)
      (check-equal? (length (odra-agent-catalog-capabilities prepared)) 1)
      (define runtime (make-package-runtime))
      (check-true (void? (package-runtime-activate! runtime candidate)))
      (define active (package-runtime-agent-catalog runtime))
      (check-equal?
       (odra-agent-definition-projection-identity
        (car (odra-agent-catalog-agents active)))
       "fixture-agent")
      (check-equal?
       (odra-agent-capability-projection-identity
        (car (odra-agent-catalog-capabilities active)))
       "fixture.observe")
      (check-equal?
       (odra-agent-capability-projection-package-authorities
        (car (odra-agent-catalog-capabilities active)))
       '(racket-extension))
      (check-true
       (void? (package-runtime-deactivate! runtime "odra.fixture" 2 3)))
      (check-equal? (odra-agent-catalog-agents
                     (package-runtime-agent-catalog runtime))
                    '())
      (check-equal? (odra-agent-catalog-capabilities
                     (package-runtime-agent-catalog runtime))
                    '())
      (package-runtime-close! runtime))
    (lambda () (delete-directory/files root))))

(test-case "agent definition collisions preserve the active generation"
  (define first-root
    (make-temporary-file "package-runtime-agent-first-~a" 'directory))
  (define second-root
    (make-temporary-file "package-runtime-agent-second-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define-values (first-installed first-manifest first-grant)
        (make-runtime-fixture
         first-root agent-module
         #:package-id "odra.agent-first"
         #:contributions agent-contributions))
      (define-values (second-installed second-manifest second-grant)
        (make-runtime-fixture
         second-root agent-module
         #:package-id "odra.agent-second"
         #:contributions agent-contributions))
      (define first
        (prepare-package-runtime
         first-root first-installed first-manifest first-grant 2))
      (define second
        (prepare-package-runtime
         second-root second-installed second-manifest second-grant 3))
      (define runtime (make-package-runtime))
      (check-true (void? (package-runtime-activate! runtime first)))
      (check-true
       (odra-package-runtime-failure?
        (package-runtime-activate! runtime second)))
      (check-equal?
       (odra-agent-definition-projection-package-id
        (car (odra-agent-catalog-agents
              (package-runtime-agent-catalog runtime))))
       "odra.agent-first")
      (check-equal? (package-runtime-active-generation
                     runtime "odra.agent-first")
                    2)
      (check-false (package-runtime-active-generation
                    runtime "odra.agent-second"))
      (check-eq? (package-runtime-candidate-state second) 'prepared)
      (discard-package-runtime-candidate! second)
      (package-runtime-close! runtime))
    (lambda ()
      (delete-directory/files first-root)
      (delete-directory/files second-root))))

(test-case "agent definition replacement retires the prior package generation"
  (define first-root
    (make-temporary-file "package-runtime-agent-v1-~a" 'directory))
  (define second-root
    (make-temporary-file "package-runtime-agent-v2-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define-values (first-installed first-manifest first-grant)
        (make-runtime-fixture
         first-root agent-module
         #:contributions agent-contributions))
      (define-values (second-installed second-manifest second-grant)
        (make-runtime-fixture
         second-root agent-module
         #:version "1.1.0"
         #:grant-generation 2
         #:contributions agent-contributions))
      (define first
        (prepare-package-runtime
         first-root first-installed first-manifest first-grant 2))
      (define second
        (prepare-package-runtime
         second-root second-installed second-manifest second-grant 3))
      (define runtime (make-package-runtime))
      (check-true (void? (package-runtime-activate! runtime first)))
      (check-true (void? (package-runtime-activate! runtime second)))
      (check-eq? (package-runtime-candidate-state first) 'retired)
      (check-eq? (package-runtime-candidate-state second) 'active)
      (check-equal?
       (odra-agent-definition-projection-package-version
        (car (odra-agent-catalog-agents
              (package-runtime-agent-catalog runtime))))
       "1.1.0")
      (check-equal? (odra-agent-catalog-generation
                     (package-runtime-agent-catalog runtime))
                    3)
      (package-runtime-close! runtime))
    (lambda ()
      (delete-directory/files first-root)
      (delete-directory/files second-root))))
