#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/language_bundle/catalog-contracts.rkt"
         "../../src/language_bundle/package-catalog-adapter.rkt"
         "../../src/package_catalog/curation-records.rkt"
         "../../src/package_catalog/curation-resolution.rkt")

(define (digest character) (make-string 64 character))
(define catalog-a (digest #\a))
(define catalog-b (digest #\b))
(define target (odra-catalog-target 'linux 'x86-64))
(define dependency
  (odra-catalog-dependency-summary
   "org.example.runtime" "1.0.0" "2.0.0" #f '(language)))
(define entry
  (odra-catalog-entry
   "org.example.language" "1.2.0" "1.0.0" "2.0.0"
   (list target) (digest #\c) '("manifests/language.rktd")
   "Example Language" "Curated package adapter fixture"
   '(language syntax-provider) '(native-grammar) (list dependency)
   3 4096 #f #f))
(define artifact
  (odra-package-artifact-reference
   'linux 'x86-64 '("language.tar.zst") (digest #\d) 2048
   "official-builder" "https://forge.example/builds/42" 'reproduced))

(define (adapt catalog [value entry])
  (language-bundle-catalog-entry->curation-assertion
   value catalog "org.example.publisher"
   "https://forge.example/org/language" (make-string 40 #\e) "v1.2.0"
   (list artifact) "decision-42" "policy-v1" 7))

(define assertion-a (adapt catalog-a))

(test-case "language bundle entry maps to one catalog-independent release"
  (define assertion-b (adapt catalog-b))
  (check-true (odra-package-curation-assertion? assertion-a))
  (check-true (same-package-release?
               (odra-package-curation-assertion-release assertion-a)
               (odra-package-curation-assertion-release assertion-b)))
  (check-not-equal? (odra-package-curation-assertion-id assertion-a)
                    (odra-package-curation-assertion-id assertion-b)))

(test-case "verified projection produces a lifecycle admission candidate"
  (define candidate
    (verify-language-bundle-curated-release
     entry assertion-a 'linux 'x86-64))
  (check-true (odra-language-bundle-curated-candidate? candidate))
  (check-equal?
   (odra-package-artifact-reference-digest
    (odra-language-bundle-curated-candidate-artifact candidate))
   (digest #\d)))

(test-case "manifest projection mismatch is rejected before admission"
  (define release (odra-package-curation-assertion-release assertion-a))
  (define mismatched
    (struct-copy odra-package-curation-assertion assertion-a
                 [release
                  (struct-copy odra-package-release-reference release
                               [manifest-digest (digest #\f)])]))
  (define result
    (verify-language-bundle-curated-release
     entry mismatched 'linux 'x86-64))
  (check-true (odra-language-bundle-package-projection-failure? result))
  (check-eq? (odra-language-bundle-package-projection-failure-field result)
             'manifest-digest))

(test-case "dependency projection mismatch is rejected before admission"
  (define release (odra-package-curation-assertion-release assertion-a))
  (define mismatched
    (struct-copy odra-package-curation-assertion assertion-a
                 [release
                  (struct-copy odra-package-release-reference release
                               [dependency-set-digest (digest #\f)])]))
  (define result
    (verify-language-bundle-curated-release
     entry mismatched 'linux 'x86-64))
  (check-eq? (odra-language-bundle-package-projection-failure-field result)
             'dependency-set-digest))

(test-case "artifact selectors must cover the exact legacy target set"
  (define result
    (language-bundle-catalog-entry->curation-assertion
     entry catalog-a "org.example.publisher"
     "https://forge.example/org/language" (make-string 40 #\e) #f
     (list (struct-copy odra-package-artifact-reference artifact
                        [platform 'darwin]))
     "decision-42" "policy-v1" 7))
  (check-true (odra-language-bundle-package-projection-failure? result))
  (check-eq? (odra-language-bundle-package-projection-failure-field result)
             'artifact-selectors))

(test-case "curation status must match the verified legacy entry"
  (define result
    (verify-language-bundle-curated-release
     entry
     (struct-copy odra-package-curation-assertion assertion-a
                  [status 'quarantined]
                  [status-reason "Quarantined"])
     'linux 'x86-64))
  (check-eq? (odra-language-bundle-package-projection-failure-field result)
             'status))

(test-case "generic resolution retains both curators before adaptation"
  (define assertion-b (adapt catalog-b))
  (define resolved
    (resolve-curated-package
     (list (odra-package-curated-source
            catalog-b (digest #\8) 10 (list assertion-b))
           (odra-package-curated-source
            catalog-a (digest #\9) 20 (list assertion-a)))
     (odra-package-resolution-request
      "org.example.language" "1.0.0" "2.0.0" 'linux 'x86-64 #f)))
  (check-true (odra-package-resolution? resolved))
  (check-equal? (length (odra-package-resolution-assertions resolved)) 2)
  (check-true
   (odra-language-bundle-curated-candidate?
    (verify-language-bundle-curated-release
     entry (car (odra-package-resolution-assertions resolved))
     'linux 'x86-64))))

(test-case "deprecated legacy status remains attributable"
  (define deprecated-entry (struct-copy odra-catalog-entry entry [deprecated? #t]))
  (define deprecated (adapt catalog-a deprecated-entry))
  (check-eq? (odra-package-curation-assertion-status deprecated) 'deprecated)
  (check-true
   (odra-language-bundle-curated-candidate?
    (verify-language-bundle-curated-release
     deprecated-entry deprecated 'linux 'x86-64))))
