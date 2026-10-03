#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/command/language-bundles.rkt"
         "../../src/language_bundle/activation-candidate.rkt"
         "../../src/language_bundle/activation-runtime.rkt"
         "../../src/language_bundle/state-records.rkt")

(define zero-digest (make-string 64 #\0))
(define digest-a (make-string 64 #\a))
(define digest-b (make-string 64 #\b))
(define target '((linux x86-64)))
(define no-replacements (odra-bundle-replacement-policy '() '()))

(define (bundle id source #:dependencies [dependencies '()] #:command [command-id 'shared-command])
  (language-support-bundle
   #:id id #:display-name (symbol->string id) #:version "1.0.0"
   #:api-min "1.0.0" #:api-max "2.0.0" #:description "Runtime fixture."
   #:publisher 'org.example #:source source #:targets target
   #:dependencies dependencies
   #:languages (list (language #:id 'example #:suffixes '(".example")))
   #:commands
   (list (language-command #:id command-id #:description "Fixture command."
                           #:implementation command-id))))

(define (input value source)
  (odra-bundle-preparation-input value source "" '() (hasheq) (hasheq) 0))

(define (candidate bundle-values sources [generation 1])
  (define bundles
    (for/hash ([value (in-list bundle-values)])
      (values (symbol->string (odra-language-support-bundle-id value)) "1.0.0")))
  (define contribution-generations
    (for/hash ([value (in-list bundle-values)] [index (in-naturals 10)])
      (values (symbol->string (odra-language-support-bundle-id value)) index)))
  (define lock
    (activation-lock-with-checksum
     (odra-activation-lock generation generation bundles '() digest-a digest-b
                           contribution-generations zero-digest)))
  (odra-bundle-activation-preparation-candidate
   (prepare-bundle-activation lock (map input bundle-values sources))))

(define (effective-bundle snapshot kind identity)
  (odra-bundle-runtime-entry-bundle-id
   (hash-ref (odra-bundle-runtime-snapshot-effective snapshot)
             (cons kind identity))))

(test-case "one publication swaps all registry generations atomically"
  (define runtime (make-bundle-runtime))
  (define factory (bundle 'org.example.factory 'factory))
  (define package (bundle 'org.example.package 'catalog.example))
  (define publication
    (prepare-bundle-publication
     runtime (candidate (list factory package) '(factory package)) no-replacements))
  (check-eq? (odra-bundle-publication-state publication) 'prepared)
  (check-false (bundle-runtime-inspect runtime))
  (check-true (publish-bundle-publication! runtime publication))
  (define snapshot (bundle-runtime-inspect runtime))
  (check-equal? (effective-bundle snapshot 'language 'example) "org.example.package")
  (check-equal? (effective-bundle snapshot 'command 'shared-command)
                "org.example.package")
  (define generations (odra-bundle-runtime-snapshot-registry-generations snapshot))
  (check-equal?
   (list (odra-bundle-registry-generations-language generations)
         (odra-bundle-registry-generations-syntax generations)
         (odra-bundle-registry-generations-service generations)
         (odra-bundle-registry-generations-formatter generations)
         (odra-bundle-registry-generations-command generations)
         (odra-bundle-registry-generations-keymap generations))
   '(1 1 1 1 1 1)))

(test-case "same-precedence collision rejects symmetrically until replacement is mutual"
  (define runtime (make-bundle-runtime))
  (define first (bundle 'org.example.first 'catalog.example))
  (define second (bundle 'org.example.second 'catalog.example))
  (define prepared (candidate (list first second) '(package package)))
  (define rejected (prepare-bundle-publication runtime prepared no-replacements))
  (check-eq? (odra-bundle-publication-state rejected) 'rejected)
  (check-eq? (odra-bundle-publication-diagnostic-code
              (odra-bundle-publication-failure rejected))
             'symmetric-conflict)
  (check-false (bundle-runtime-inspect runtime))
  (define language-relation
    (odra-bundle-replacement-relation
     'language 'example "org.example.second" "org.example.first"))
  (define command-relation
    (odra-bundle-replacement-relation
     'command 'shared-command "org.example.second" "org.example.first"))
  (define policy
    (odra-bundle-replacement-policy
     (list language-relation command-relation)
     (list language-relation command-relation)))
  (define accepted (prepare-bundle-publication runtime prepared policy))
  (check-true (publish-bundle-publication! runtime accepted))
  (check-equal? (effective-bundle (bundle-runtime-inspect runtime)
                                  'language 'example)
                "org.example.second"))

(test-case "removal restores factory and returns reverse dependency teardown"
  (define runtime (make-bundle-runtime))
  (define base (bundle 'org.example.base 'catalog.example))
  (define dependency
    (language-bundle-dependency
     #:id 'org.example.base #:minimum "1.0.0" #:maximum "1.0.0"))
  (define dependent
    (bundle 'org.example.dependent 'catalog.example
            #:dependencies (list dependency) #:command 'dependent-command))
  (define initial (candidate (list base dependent) '(package personal)))
  (check-true
   (publish-bundle-publication!
    runtime (prepare-bundle-publication runtime initial no-replacements)))
  (define factory (bundle 'org.example.factory 'factory))
  (define fallback (candidate (list factory) '(factory) 2))
  (define publication
    (prepare-bundle-publication runtime fallback no-replacements))
  (check-equal? (odra-bundle-publication-retired-bundles publication)
                '("org.example.dependent" "org.example.base"))
  (check-true (publish-bundle-publication! runtime publication))
  (check-equal? (effective-bundle (bundle-runtime-inspect runtime)
                                  'language 'example)
                "org.example.factory")
  (check-false (publish-bundle-publication! runtime publication)))
