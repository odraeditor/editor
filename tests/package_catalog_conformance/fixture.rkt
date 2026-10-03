#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (prefix-in kit:
                    "../../assets/package-catalog/curator-kit/template/catalog.rkt")
         (prefix-in published: "../package_catalog_publication_fixture/repository.rkt")
         "../../scripts/package-catalog-curator-support.rkt"
         "../../src/package_catalog/contracts.rkt"
         "../../src/package_catalog/curation-publication.rkt"
         "../../src/package_catalog/curation-records.rkt"
         "../../src/package_catalog/integrity.rkt"
         "../../src/package_catalog/manual-records.rkt"
         "../../src/package_catalog/official-bootstrap.rkt"
         "../../src/package_catalog/security-advisories.rkt")

(provide official-bootstrap independent-profile fork-profile mirror-profile
         mirror-publisher-keys mirror-snapshot external-language-release
         external-language-assertion external-language-manual-acquisition
         advisory root-rotation-request)

(define (digest character) (make-string 64 character))

(define official-bootstrap official-package-catalog-bootstrap)
(define independent-profile kit:profile)

;; A copied name, publisher key, and endpoint host still produce a separate
;; catalog because the fork has distinct root material.
(define fork-root-public-key (digest #\4))
(define fork-root-key-id
  (package-catalog-public-key-id fork-root-public-key))
(define fork-root
  (odra-package-catalog-root-key
   fork-root-key-id 1 'ed25519 fork-root-public-key 1 #f))
(define fork-id (package-catalog-identity fork-root))
(define fork-publisher-key (car kit:publisher-keys))
(define fork-publisher
  (odra-package-catalog-publisher-authorization
   "snapshot-publisher"
   (list (odra-package-catalog-publisher-key-id fork-publisher-key)) 1 1 #f))
(define fork-policy
  (odra-package-catalog-policy
   "catalog-policy" 1 1 "policy/package-eligibility.md"
   "policy/authority.md" "policy/assessment.md" "policy/decision.md"
   "policy/retention.md"))
(define fork-curator
  (odra-package-catalog-curator-authorization
   "primary-curator" "human.curator" 'human 1 #f '("catalog-policy")))
(define fork-origin
  (odra-package-catalog-endpoint
   "origin" fork-id "https://catalog.example/snapshots/current.rktd"
   'https 'origin 0 #t))
(define-values (fork-profile fork-rejection)
  (confirm-package-catalog-profile
   (odra-package-catalog-profile-proposal
    current-package-catalog-identity-format-version fork-id
    (odra-package-catalog-profile-display-name independent-profile)
    (list fork-root) (list fork-curator) (list fork-publisher)
    (list fork-policy) (list fork-origin))))
(when fork-rejection
  (error 'package-catalog-conformance-fixture "invalid fork profile"))

(define mirror-profile published:profile)
(define mirror-publisher-keys published:publisher-keys)
(define mirror-snapshot
  (odra-package-catalog-publication-snapshot published:publication))

(define external-language-release
  (odra-package-release-reference
   current-package-curation-format-version "org.example.language" (digest #\5)
   "1.0.0" "org.example.publisher"
   "https://forge.example/org/language-bundle" (make-string 40 #\6) #f
   (digest #\7)
   (list
    (odra-package-artifact-reference
     'linux 'x86-64 '("language-bundle.tar.zst") (digest #\8) 2048
     "builder.example" "provenance/language-bundle.json" 'reproduced))
   (digest #\9) (digest #\a) (digest #\b) (digest #\c)))
(define external-language-assertion
  (odra-package-curation-assertion
   current-package-curation-format-version (digest #\d)
   (odra-package-catalog-profile-identity independent-profile) 1
   external-language-release (digest #\e) "catalog-policy" 'admitted ""
   (list (digest #\f)) 1 1))
(define external-language-manual-acquisition
  (make-manual-package-acquisition
   1 'local-artifact "/tmp/language-bundle.tar.zst" #f #f
   (digest #\8) (digest #\7) external-language-release))

(define advisory
  (odra-security-advisory
   current-security-advisory-format-version "language-bundle-advisory"
   "independent-advisory-authority"
   (odra-package-catalog-profile-identity independent-profile)
   1 'draft 'vulnerability 'high 'suspected '("org.example.language") '() '()
   '(block-activation warn)
   "Deterministic fixture advisory pending external signature." 100 #f '()))

(define root-rotation-request
  (prepare-package-catalog-root-rotation
   (odra-package-catalog-profile-identity independent-profile)
   (odra-package-catalog-root-key-id
    (car (odra-package-catalog-profile-roots independent-profile)))
   (digest #\3) 2))
