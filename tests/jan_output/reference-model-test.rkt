#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/list
         racket/runtime-path
         racket/set
         racket/string
         rackunit
         "model.rkt"
         "citation-model.rkt"
         (prefix-in external: "external-protocol-model.rkt")
         (prefix-in extension: "extension-model.rkt")
         "native-backend-model.rkt"
         (prefix-in publication: "publication-model.rkt")
         (prefix-in protected: "protected-sync-model.rkt")
         "tool-backend-model.rkt")

(define-runtime-path native-document-path "fixtures/native-document.rktd")
(define-runtime-path native-text-path "fixtures/native-output.txt")
(define-runtime-path native-html-path "fixtures/native-output.html")
(define-runtime-path native-markdown-path "fixtures/native-output.md")
(define-runtime-path native-org-path "fixtures/native-output.org")
(define-runtime-path native-jan-path "fixtures/native-output.jan")
(define-runtime-path tool-latex-path "fixtures/tool-output.tex")
(define-runtime-path tool-beamer-path "fixtures/tool-output-beamer.tex")
(define-runtime-path tool-texinfo-path "fixtures/tool-output.texi")
(define-runtime-path tool-man-path "fixtures/tool-output.1")
(define-runtime-path tool-events-path "fixtures/tool-events.rktd")
(define-runtime-path tool-calendar-path "fixtures/tool-output.ics")
(define-runtime-path citation-data-path "fixtures/citation-data.rktd")
(define-runtime-path citation-text-path "fixtures/citation-output.txt")
(define-runtime-path citation-html-path "fixtures/citation-output.html")
(define-runtime-path citation-latex-path "fixtures/citation-output.tex")
(define-runtime-path bibliography-markdown-path "fixtures/bibliography-output.md")
(define-runtime-path publication-data-path "fixtures/publication-data.rktd")
(define-runtime-path publication-manifest-path "fixtures/publication-manifest.rktd")
(define-runtime-path external-protocol-data-path "fixtures/external-protocol-data.rktd")
(define-runtime-path external-protocol-plan-path "fixtures/external-protocol-plan.rktd")
(define-runtime-path extension-generation-path "fixtures/extension-generation.rktd")
(define-runtime-path protected-sync-data-path "fixtures/protected-sync-data.rktd")
(define-runtime-path protected-sync-reconciliation-path "fixtures/protected-sync-reconciliation.rktd")

(test-case "settings resolve scalar precedence and additive order"
  (define candidates
    (list '#hasheq((key . title) (value . factory) (precedence . 1) (order . 1))
          '#hasheq((key . title) (value . project) (precedence . 4) (order . 2))
          '#hasheq((key . title) (value . generic) (precedence . 8) (order . 3))
          '#hasheq((key . title) (value . html) (backend . html) (precedence . 8) (order . 3))))
  (check-equal? (hash-ref (resolve-export-setting 'title 'html candidates) 'value) 'html)
  (define additive
    (list '#hasheq((key . header) (value . b) (precedence . 5) (order . 2) (additive? . #t))
          '#hasheq((key . header) (value . a) (precedence . 1) (order . 1) (additive? . #t))))
  (check-equal? (map (lambda (candidate) (hash-ref candidate 'value))
                     (resolve-export-setting 'header 'html additive))
                '(a b)))

(test-case "include graphs require exact acyclic resources"
  (check-true
   (list? (validate-include-graph
           (list '#hasheq((resource . 1) (revision . 3) (depth . 1))
                 '#hasheq((resource . 2) (revision . 4) (depth . 2) (parent . 1))))))
  (check-false
   (validate-include-graph
    (list '#hasheq((resource . 1) (revision . 3) (depth . 1) (parent . 2))
          '#hasheq((resource . 2) (revision . 4) (depth . 2) (parent . 1))))))

(test-case "macros are inert and bounded"
  (define result
    (expand-macros (list '#hasheq((identity . author)))
                   '#hasheq((author . #hasheq((expansion . #"Ada"))))))
  (check-equal? (hash-ref result 'fragments) '(#"Ada"))
  (check-false (expand-macros (list '#hasheq((identity . missing))) '#hasheq())))

(test-case "normalization applies comments archive and tag policy"
  (define nodes
    (list '#hasheq((kind . heading) (start . 0) (end . 4))
          '#hasheq((kind . comment) (start . 4) (end . 8))
          '#hasheq((kind . heading) (start . 8) (end . 12) (archived? . #t))
          '#hasheq((kind . paragraph) (start . 12) (end . 16) (tag . private))))
  (define tree
    (normalize-output-tree #"0123456789abcdef" nodes
                           (hasheq 'comments? #f 'archived? #f
                                   'excluded-tags (set 'private))))
  (check-equal? (hash-ref tree 'node-count) 1))

(test-case "publication manifests require complete resource candidates"
  (define manifest
    (construct-publication-manifest
     9 '#hasheq((source . 7) (backend . 3))
     (list '#hasheq((resource . 11) (digest . #"digest")))))
  (check-equal? (hash-ref manifest 'state) 'candidate)
  (check-false
   (construct-publication-manifest 9 '#hasheq()
                                   (list '#hasheq((resource . 11) (digest . #""))))))

(test-case "incremental reuse rejects every semantic mismatch"
  (define key '#hasheq((source . a) (dependencies . b) (backend . c)
                        (filters . d) (settings . e) (tools . f)))
  (check-true (incremental-output-current? key key))
  (check-false (incremental-output-current? key (hash-set key 'tools 'changed))))

(test-case "protocol admission is explicit and pre-decode bounded"
  (define request '#hasheq((explicit? . #t) (provider-generation . 4) (payload . #"value")))
  (check-equal? (hash-ref (admit-protocol-request request) 'payload) #"value")
  (check-false (admit-protocol-request (hash-set request 'explicit? #f))))

(test-case "synchronization preserves divergent entries as conflicts"
  (define result
    (reconcile-synchronization
     (list '#hasheq((base . a) (local . b) (remote . c))
           '#hasheq((base . a) (local . a) (remote . b)))))
  (check-equal? (hash-ref result 'conflicts) 1)
  (check-equal? (hash-ref result 'state) 'conflicted))

(test-case "extension order is deterministic and rejects duplicates"
  (define ordered
    (order-extensions
     (list '#hasheq((identity . z) (priority . 2) (generation . 1))
           '#hasheq((identity . b) (priority . 1) (generation . 1))
           '#hasheq((identity . a) (priority . 1) (generation . 1)))))
  (check-equal? (map (lambda (extension) (hash-ref extension 'identity)) ordered) '(a b z))
  (check-false (order-extensions (list (car ordered) (car ordered)))))

(test-case "resource plans copy bytes and perform no write"
  (define source (bytes-copy #"output"))
  (define plan (plan-output-resource 7 source 11 #f))
  (bytes-set! source 0 88)
  (check-equal? (hash-ref plan 'bytes) #"output")
  (check-true (hash-ref plan 'complete?)))

(test-case "output lifecycle cannot skip confirmation"
  (check-equal? (transition-output-lifecycle 'prepared 'confirmed) 'confirmed)
  (check-equal? (transition-output-lifecycle 'confirmed 'active) 'active)
  (check-equal? (transition-output-lifecycle 'active 'reconciliation-required)
                'reconciliation-required)
  (check-equal? (transition-output-lifecycle 'reconciliation-required 'closed) 'closed)
  (check-false (transition-output-lifecycle 'prepared 'completed)))

(test-case "resource profiles remain within every stable ceiling"
  (for ([profile (in-list output-resource-profiles)])
    (check-true (validate-output-resource-profile profile))
    (check-true (positive? (estimate-output-retained-bytes profile)))
    (check-true (positive? (estimate-output-temporary-bytes profile)))))

(test-case "factory-native backends match deterministic offline goldens"
  (define document (call-with-input-file native-document-path read))
  (for ([case (in-list (list (list 'plain-text native-text-path)
                                  (list 'html native-html-path)
                                  (list 'markdown native-markdown-path)
                                  (list 'normalized-org native-org-path)
                                  (list 'normalized-jan native-jan-path)))])
    (check-equal? (render-native-document (car case) document)
                  (file->string (cadr case))
                  (symbol->string (car case))))
  (check-equal? (file->string native-org-path) (file->string native-jan-path)))

(test-case "adapter source backends match deterministic offline goldens"
  (define document (call-with-input-file native-document-path read))
  (for ([case (in-list (list (list 'latex tool-latex-path)
                                  (list 'beamer tool-beamer-path)
                                  (list 'texinfo tool-texinfo-path)
                                  (list 'man-page tool-man-path)))])
    (check-equal? (render-tool-document (car case) document)
                  (file->string (cadr case))
                  (symbol->string (car case)))))

(test-case "tool plans require exact trusted available adapters"
  (define tools
    '#hasheq((pdflatex . #hasheq((generation . 9) (available? . #t) (trusted? . #t)))
             (odra-odt-packager . #hasheq((generation . 9) (available? . #t) (trusted? . #t)))
             (makeinfo . #hasheq((generation . 9) (available? . #t) (trusted? . #t)))))
  (check-equal? (hash-ref (plan-tool-backend 'pdf tools 9 #t) 'steps) 3)
  (check-equal? (hash-ref (plan-tool-backend 'odt tools 9 #t) 'cleanup) 3)
  (check-equal? (hash-ref (plan-tool-backend 'info tools 9 #f) 'steps) 1)
  (check-false (plan-tool-backend 'pdf tools 8 #t)))

(test-case "iCalendar output matches deterministic escaped golden"
  (define events (call-with-input-file tool-events-path read))
  (define fixture
    (string-replace (file->string tool-calendar-path) "\n" "\r\n"))
  (check-equal? (render-calendar events) fixture))

(test-case "citation resolution and completion require exact admitted sources"
  (define data (call-with-input-file citation-data-path read))
  (define resolutions
    (resolve-citations (hash-ref data 'processor) (hash-ref data 'sources)
                       (hash-ref data 'entries) (hash-ref data 'references)))
  (check-equal? (length resolutions) 2)
  (check-equal? (map (lambda (value) (hash-ref value 'entry)) resolutions) '(0 1))
  (check-equal? (map (lambda (value) (hash-ref value 'key))
                     (complete-citation-keys "b" (hash-ref data 'sources) (hash-ref data 'entries)))
                '(beta-2020))
  (check-false
   (resolve-citations (hash-set (hash-ref data 'processor) 'available? #f)
                      (hash-ref data 'sources) (hash-ref data 'entries) (hash-ref data 'references))))

(test-case "CSL and LaTeX citation adapters match offline goldens"
  (define data (call-with-input-file citation-data-path read))
  (define entries (hash-ref data 'entries))
  (define references (hash-ref data 'references))
  (define resolutions
    (resolve-citations (hash-ref data 'processor) (hash-ref data 'sources) entries references))
  (check-equal? (string-append (render-citations 'plain-text 'csl entries references resolutions) "\n")
                (file->string citation-text-path))
  (check-equal? (string-append (render-citations 'html 'csl entries references resolutions) "\n")
                (file->string citation-html-path))
  (check-equal? (string-append (render-citations 'latex 'latex entries references resolutions) "\n")
                (file->string citation-latex-path)))

(test-case "bibliography filtering and sorting are deterministic"
  (define data (call-with-input-file citation-data-path read))
  (check-equal? (render-bibliography 'markdown (hash-ref data 'entries))
                (file->string bibliography-markdown-path))
  (check-equal? (length (string-split (string-trim
                                       (render-bibliography 'markdown (hash-ref data 'entries)
                                                            #:minimum-year 2021))
                                      "\n"))
                1))

(test-case "publishing projects compose and discover deterministically"
  (define data (call-with-input-file publication-data-path read))
  (define projects (hash-ref data 'projects))
  (check-equal? (map (lambda (project) (hash-ref project 'identity))
                     (publication:order-publishing-projects projects))
                '(core theme site))
  (check-equal? (map (lambda (candidate) (hash-ref candidate 'path))
                     (publication:discover-publication-sources (car projects) (hash-ref data 'candidates)))
                '("assets/site.css" "docs/a.org" "docs/z.org")))

(test-case "publication manifests match complete offline golden"
  (define data (call-with-input-file publication-data-path read))
  (define manifest
    (publication:construct-publication-manifest (car (hash-ref data 'projects)) (hash-ref data 'candidates)
                                                (hash-ref data 'cache) (hash-ref data 'existing)))
  (check-equal? manifest (call-with-input-file publication-manifest-path read))
  (define changed-cache
    (hash-set (hash-ref data 'cache) 203
              (hash-set (hash-ref (hash-ref data 'cache) 203) 'tools 'changed)))
  (check-false (hash-ref (second (hash-ref (publication:construct-publication-manifest
                                           (car (hash-ref data 'projects)) (hash-ref data 'candidates)
                                           changed-cache (hash-ref data 'existing))
                                          'entries))
                         'reuse?)))

(test-case "local publication and remote deployment remain separate"
  (define local '#hasheq((state . prepared) (entries . 3) (remote? . #f)))
  (define local-active (publication:advance-publication local 'start-local))
  (define local-complete (publication:advance-publication local-active 'local-succeeded 3))
  (check-equal? (hash-ref local-complete 'state) 'local-complete)
  (check-false (publication:advance-publication local-complete 'remote-succeeded 3))
  (define remote '#hasheq((state . prepared) (entries . 3) (remote? . #t)))
  (define remote-active
    (publication:advance-publication
     (publication:advance-publication (publication:advance-publication remote 'start-local)
                                      'local-succeeded 3)
     'start-remote))
  (define partial
    (publication:advance-publication
     (publication:advance-publication remote-active 'remote-progress 2)
     'remote-failed 1))
  (check-equal? (hash-ref partial 'state) 'remote-partial)
  (define retried (publication:advance-publication partial 'retry))
  (check-equal? (hash-ref (publication:advance-publication retried 'remote-succeeded 3) 'state) 'published))

(test-case "external link and media operations require exact admitted providers"
  (define data (call-with-input-file external-protocol-data-path read))
  (define providers (hash-ref data 'providers))
  (define plans
    (map (lambda (request) (external:plan-link-operation request providers))
         (hash-ref data 'link-requests)))
  (check-true (andmap hash? plans))
  (check-true (hash-ref (first plans) 'navigation?))
  (check-true (hash-ref (second plans) 'resource-write?))
  (define stale (hash-set (first (hash-ref data 'link-requests)) 'provider-generation 18))
  (check-false (external:plan-link-operation stale providers)))

(test-case "external protocol admission is versioned authenticated and replay safe"
  (define data (call-with-input-file external-protocol-data-path read))
  (define admitted
    (external:admit-external-protocol (hash-ref data 'external) (hash-ref data 'providers) '()))
  (check-equal? admitted (call-with-input-file external-protocol-plan-path read))
  (check-false
   (external:admit-external-protocol
    (hash-ref data 'external) (hash-ref data 'providers) (list (hash-ref admitted 'replay))))
  (check-false
   (external:admit-external-protocol
    (hash-set (hash-ref data 'external) 'authenticated? #f) (hash-ref data 'providers) '())))

(test-case "external protocol failures cannot report editor effects"
  (define data (call-with-input-file external-protocol-data-path read))
  (define admitted
    (external:admit-external-protocol (hash-ref data 'external) (hash-ref data 'providers) '()))
  (define plan (hash-ref admitted 'plan))
  (define failed
    (hasheq 'operation 301 'provider 'resource-provider 'provider-generation 17
            'state 'failed 'complete? #f
            'link-state-changed? #f 'document-changed? #f 'navigation-changed? #f))
  (check-true (external:dispatch-result-valid? plan failed))
  (check-false (external:dispatch-result-valid? plan (hash-set failed 'document-changed? #t))))

(test-case "protected subtree plans retain handles but no secret material"
  (define data (call-with-input-file protected-sync-data-path read))
  (define plan
    (protected:plan-protection (hash-ref data 'protection-request)
                               (hash-ref data 'protection-providers)))
  (check-equal? (hash-ref plan 'configuration-generation) 13)
  (check-equal? (hash-ref plan 'credential-handle) 501)
  (check-false (hash-has-key? plan 'key))
  (check-false
   (protected:plan-protection
    (hash-set (hash-ref data 'protection-request) 'trigger 'search)
    (hash-ref data 'protection-providers))))

(test-case "protected content and plaintext save policy remain explicit"
  (check-false (protected:protected-consumer-visible? 'encrypted-opaque 'search))
  (check-false (protected:protected-consumer-visible? 'decrypted-transient 'background-index))
  (check-true (protected:protected-consumer-visible? 'decrypted-transient 'interactive-view))
  (check-false (protected:plaintext-save-allowed? 'decrypted-transient 'confirm #f #t))
  (check-true (protected:plaintext-save-allowed? 'decrypted-transient 'confirm #t #t)))

(test-case "protected synchronization is transport neutral and attachment bounded"
  (define data (call-with-input-file protected-sync-data-path read))
  (define local
    (protected:stage-synchronization (hash-ref data 'sync-request)
                                     (hash-ref data 'sync-providers)
                                     (hash-ref data 'sync-candidates)))
  (define hosted-request
    (hash-set* (hash-ref data 'sync-request)
               'provider 'hosted-sync 'provider-generation 29))
  (define hosted
    (protected:stage-synchronization hosted-request (hash-ref data 'sync-providers)
                                     (hash-ref data 'sync-candidates)))
  (check-equal? (hash-ref local 'entries) (hash-ref hosted 'entries))
  (check-equal? (map (lambda (entry) (hash-ref entry 'resource)) (hash-ref local 'entries))
                '(101 103 105 201)))

(test-case "protected synchronization requires explicit divergence resolution"
  (define data (call-with-input-file protected-sync-data-path read))
  (define staged
    (protected:stage-synchronization (hash-ref data 'sync-request)
                                     (hash-ref data 'sync-providers)
                                     (hash-ref data 'sync-candidates)))
  (define unresolved
    (protected:reconcile-protected-synchronization staged (hash-ref data 'remote) '()))
  (check-equal? (hash-ref unresolved 'state) 'conflicted)
  (check-false (protected:plan-synchronization-apply unresolved))
  (define resolved
    (protected:reconcile-protected-synchronization
     staged (hash-ref data 'remote) (hash-ref data 'resolutions)))
  (check-equal? resolved (call-with-input-file protected-sync-reconciliation-path read))
  (check-equal? (protected:plan-synchronization-apply resolved) '(101 105)))

(test-case "extension generations admit every family in deterministic order"
  (define data (call-with-input-file extension-generation-path read))
  (define admitted (extension:admit-extension-generation data 40))
  (check-equal? (hash-ref admitted 'generation) 41)
  (check-equal? (length (hash-ref admitted 'providers))
                (length extension:extension-families))
  (check-equal? (map (lambda (provider) (hash-ref provider 'family))
                     (hash-ref admitted 'providers))
                extension:extension-families)
  (define reordered
    (extension:admit-extension-generation
     (hash-set data 'providers (reverse (hash-ref data 'providers))) 40))
  (check-equal? (extension:inspect-extension-catalog admitted)
                (extension:inspect-extension-catalog reordered))
  (check-false (extension:admit-extension-generation data 41)))

(test-case "derived backends require an exact acyclic admitted parent"
  (define data (call-with-input-file extension-generation-path read))
  (define providers (hash-ref data 'providers))
  (define broken
    (for/list ([provider (in-list providers)])
      (if (eq? (hash-ref provider 'identity) 'html-notes)
          (hash-set provider 'parent 'missing)
          provider)))
  (check-false
   (extension:admit-extension-generation (hash-set data 'providers broken) 40)))

(test-case "extension invocation constrains authority and returns candidates only"
  (define data (call-with-input-file extension-generation-path read))
  (define catalog (extension:admit-extension-generation data 40))
  (define plan (extension:plan-extension-invocation (hash-ref data 'invocation) catalog))
  (check-equal? (hash-ref plan 'boundary) 'document-candidate)
  (check-true (extension:extension-result-valid? plan (hash-ref data 'result)))
  (check-false
   (extension:extension-result-valid?
    plan (hash-set (hash-ref data 'result) 'mutated-directly? #t)))
  (check-false
   (extension:plan-extension-invocation
    (hash-update (hash-ref data 'invocation) 'authorities
                 (lambda (authorities) (cons 'network authorities)))
    catalog)))

(test-case "extension inspection and conformance expose complete provider truth"
  (define data (call-with-input-file extension-generation-path read))
  (define catalog (extension:admit-extension-generation data 40))
  (define inspection (extension:inspect-extension-catalog catalog))
  (check-equal? (length inspection) (length extension:extension-families))
  (check-true (andmap (lambda (record) (hash-ref record 'active?)) inspection))
  (check-true
   (extension:extension-conformance-complete? catalog (hash-ref data 'conformance)))
  (check-false
   (extension:extension-conformance-complete?
    catalog (hash-set (hash-ref data 'conformance) 'cleanup-complete? #f))))
