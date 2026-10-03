#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/list
         rackunit
         "../../src/command/language-bundles.rkt"
         "../../src/language_bundle/activation-candidate.rkt"
         "../../src/language_bundle/activation-runtime.rkt"
         "../../src/language_bundle/lifecycle.rkt"
         "../../src/language_bundle/state-persistence.rkt"
         "../../src/language_bundle/state-records.rkt")

(define zero-digest (make-string 64 #\0))
(define digest-a (make-string 64 #\a))
(define digest-b (make-string 64 #\b))
(define digest-c (make-string 64 #\c))
(define digest-d (make-string 64 #\d))
(define target '((linux x86-64)))
(define no-replacements (odra-bundle-replacement-policy '() '()))

(define (simple-bundle id language-id suffix source
                       #:version [version "1.0.0"]
                       #:dependencies [dependencies '()]
                       #:authorities [authorities '()]
                       #:services [services '()]
                       #:formatters [formatters '()])
  (language-support-bundle
   #:id id #:display-name (symbol->string id) #:version version
   #:api-min "1.0.0" #:api-max "2.0.0" #:description "Failure matrix fixture."
   #:publisher 'org.example #:source source #:targets target
   #:dependencies dependencies
   #:authorities (map language-bundle-authority authorities)
   #:languages (list (language #:id language-id #:suffixes (list suffix)))
   #:services services #:formatters formatters))

(define (preparation-input value source
                           #:availability [availability (hasheq)]
                           #:granted [granted '()])
  (odra-bundle-preparation-input value source "" granted (hasheq) availability 0))

(define (activation-candidate bundle-values sources
                              #:generation [generation 1]
                              #:availability [availability (hasheq)]
                              #:grants [grants '()])
  (define bundle-table
    (for/hash ([value (in-list bundle-values)])
      (values (symbol->string (odra-language-support-bundle-id value))
              (odra-language-support-bundle-version value))))
  (define generations
    (for/hash ([value (in-list bundle-values)] [index (in-naturals 10)])
      (values (symbol->string (odra-language-support-bundle-id value)) index)))
  (define lock
    (activation-lock-with-checksum
     (odra-activation-lock generation generation bundle-table '()
                           digest-c digest-d generations zero-digest)))
  (prepare-bundle-activation
   lock
   (for/list ([value (in-list bundle-values)] [source (in-list sources)])
     (preparation-input value source #:availability availability #:granted grants))))

(define (effective-bundle snapshot kind identity)
  (odra-bundle-runtime-entry-bundle-id
   (hash-ref (odra-bundle-runtime-snapshot-effective snapshot)
             (cons kind identity))))

(test-case "permutations publish the same effective generation and preserve old observations"
  (define factory
    (simple-bundle 'org.example.factory 'example ".example" 'factory))
  (define package
    (simple-bundle 'org.example.package 'example ".example" 'catalog.example))
  (define (publish-order bundle-values sources)
    (define runtime (make-bundle-runtime))
    (define prepared (activation-candidate bundle-values sources))
    (define publication
      (prepare-bundle-publication
       runtime (odra-bundle-activation-preparation-candidate prepared) no-replacements))
    (check-true (publish-bundle-publication! runtime publication))
    (values runtime (bundle-runtime-inspect runtime)))
  (define-values (runtime first)
    (publish-order (list factory package) '(factory package)))
  (define-values (_ second)
    (publish-order (list package factory) '(package factory)))
  (check-equal? (effective-bundle first 'language 'example)
                (effective-bundle second 'language 'example))
  (define next-preparation
    (activation-candidate (list factory) '(factory) #:generation 2))
  (define next-publication
    (prepare-bundle-publication
     runtime (odra-bundle-activation-preparation-candidate next-preparation)
     no-replacements))
  (check-true (publish-bundle-publication! runtime next-publication))
  (check-equal? (odra-bundle-runtime-snapshot-runtime-generation first) 1)
  (check-equal? (effective-bundle first 'language 'example) "org.example.package")
  (check-equal? (effective-bundle (bundle-runtime-inspect runtime) 'language 'example)
                "org.example.factory"))

(test-case "one formatter conflict rejects every registry before publication"
  (define formatter
    (language-formatter #:id 'shared-formatter #:languages '(first)
                        #:kind 'command #:command '("fixture-format")))
  (define first
    (simple-bundle 'org.example.first 'first ".first" 'catalog.example
                   #:authorities '(external-process) #:formatters (list formatter)))
  (define second-formatter
    (language-formatter #:id 'shared-formatter #:languages '(second)
                        #:kind 'command #:command '("fixture-format")))
  (define second
    (simple-bundle 'org.example.second 'second ".second" 'catalog.example
                   #:authorities '(external-process)
                   #:formatters (list second-formatter)))
  (define prepared
    (activation-candidate (list first second) '(package package)
                          #:grants '(external-process)))
  (check-eq? (odra-bundle-activation-preparation-state prepared) 'prepared)
  (define runtime (make-bundle-runtime))
  (define publication
    (prepare-bundle-publication
     runtime (odra-bundle-activation-preparation-candidate prepared) no-replacements))
  (check-eq? (odra-bundle-publication-state publication) 'rejected)
  (check-eq? (odra-bundle-publication-diagnostic-kind
              (odra-bundle-publication-failure publication))
             'formatter)
  (check-false (bundle-runtime-inspect runtime)))

(test-case "dependency and authority deltas reject before registry preparation"
  (define dependency
    (language-bundle-dependency
     #:id 'org.example.base #:minimum "1.0.0" #:maximum "1.0.0"))
  (define dependent
    (simple-bundle 'org.example.dependent 'dependent ".dependent" 'catalog.example
                   #:dependencies (list dependency)))
  (define missing (activation-candidate (list dependent) '(package)))
  (check-eq? (odra-bundle-activation-failure-code
              (odra-bundle-activation-preparation-failure missing))
             'dependency-mismatch)
  (define ordinary
    (simple-bundle 'org.example.ordinary 'ordinary ".ordinary" 'catalog.example))
  (define escalated
    (activation-candidate (list ordinary) '(package)
                          #:grants '(external-process)))
  (check-eq? (odra-bundle-activation-failure-code
              (odra-bundle-activation-preparation-failure escalated))
             'authority-escalation))

(test-case "an unavailable service remains explicit inside one confirmed bundle"
  (define service
    (language-service #:id 'fixture-service #:languages '(example)
                      #:command '("missing-fixture-server")
                      #:features '(diagnostics completion) #:default? #t))
  (define value
    (simple-bundle 'org.example.service 'example ".example" 'catalog.example
                   #:authorities '(external-process) #:services (list service)))
  (define prepared
    (activation-candidate
     (list value) '(package) #:grants '(external-process)
     #:availability (hasheq 'fixture-service 'unavailable)))
  (define runtime (make-bundle-runtime))
  (define publication
    (prepare-bundle-publication
     runtime (odra-bundle-activation-preparation-candidate prepared) no-replacements))
  (check-true (publish-bundle-publication! runtime publication))
  (define snapshot (bundle-runtime-inspect runtime))
  (check-eq?
   (odra-bundle-runtime-entry-status
    (hash-ref (odra-bundle-runtime-snapshot-effective snapshot)
              (cons 'service 'fixture-service)))
   'unavailable)
  (check-eq?
   (odra-bundle-runtime-entry-status
    (hash-ref (odra-bundle-runtime-snapshot-effective snapshot)
              (cons 'language 'example)))
   'available))

(define (install-request version digest)
  (define value
    (simple-bundle 'org.example.lifecycle 'lifecycle ".life" 'catalog.example
                   #:version version))
  (odra-bundle-install-request
   (preparation-input value 'package)
   digest 'linux 'x86-64 "user grant" 512 0))

(define (request-for value digest)
  (odra-bundle-install-request
   (preparation-input value 'package)
   digest 'linux 'x86-64 "user grant" 512 0))

(define (with-private-root action)
  (define root (make-temporary-file "odra-bundle-failure-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind void (lambda () (action root))
                (lambda () (delete-directory/files root))))

(test-case "interrupted final publication recovers the previous lock on restart"
  (with-private-root
   (lambda (root)
     (define first (install-request "1.0.0" digest-a))
     (define second (install-request "1.1.0" digest-b))
     (define initial (make-bundle-lifecycle-manager root))
     (bundle-lifecycle-install! initial first)
     (bundle-lifecycle-enable! initial "org.example.lifecycle" "1.0.0")
     (define calls 0)
     (define (fail-final root state)
       (set! calls (add1 calls))
       (if (= calls 4) #f (language-bundle-state-persist root state)))
     (define updating
       (make-bundle-lifecycle-manager
        root #:inputs (list first second) #:persistence fail-final))
     (define update-result (bundle-lifecycle-update! updating second))
     (check-eq? (odra-bundle-lifecycle-result-state update-result) 'interrupted)
     (define startup (language-bundle-state-startup root))
     (check-eq? (odra-language-bundle-startup-mode startup) 'rollback-previous)
     (define recovered
       (make-bundle-lifecycle-manager root #:inputs (list first second)))
     (check-equal?
      (hash-ref
       (odra-bundle-runtime-snapshot-bundles
        (bundle-lifecycle-runtime-snapshot recovered))
       "org.example.lifecycle")
      "1.0.0")
     (define safe
       (make-bundle-lifecycle-manager
        root #:inputs (list first second) #:safe-mode? #t))
     (check-false (bundle-lifecycle-runtime-snapshot safe))
     (check-true (pair? (odra-language-bundle-state-bundles
                         (bundle-lifecycle-state safe)))))))

(test-case "required dependents block removal and runtime close retains no snapshot"
  (define base
    (simple-bundle 'org.example.base 'base ".base" 'catalog.example))
  (define dependency
    (language-bundle-dependency
     #:id 'org.example.base #:minimum "1.0.0" #:maximum "1.0.0"))
  (define dependent
    (simple-bundle 'org.example.dependent 'dependent ".dependent" 'catalog.example
                   #:dependencies (list dependency)))
  (with-private-root
   (lambda (root)
     (define manager (make-bundle-lifecycle-manager root))
     (bundle-lifecycle-install! manager (request-for base digest-a))
     (bundle-lifecycle-install! manager (request-for dependent digest-b))
     (check-eq?
      (odra-bundle-lifecycle-result-state
       (bundle-lifecycle-enable! manager "org.example.dependent" "1.0.0"))
      'enable)
     (define blocked
       (bundle-lifecycle-remove! manager "org.example.base" "1.0.0"))
     (check-eq? (odra-bundle-lifecycle-result-state blocked) 'rejected)
     (check-equal? (odra-bundle-lifecycle-result-detail blocked)
                   "Required dependents prevent removal")))
  (define runtime (make-bundle-runtime))
  (define prepared
    (activation-candidate (list base dependent) '(package personal)))
  (define publication
    (prepare-bundle-publication
     runtime (odra-bundle-activation-preparation-candidate prepared) no-replacements))
  (check-true (publish-bundle-publication! runtime publication))
  (check-equal? (bundle-runtime-close! runtime)
                '("org.example.dependent" "org.example.base"))
  (check-false (bundle-runtime-inspect runtime))
  (check-equal? (bundle-runtime-close! runtime) '()))
