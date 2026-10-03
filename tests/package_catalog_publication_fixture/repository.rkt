#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require "../../src/package_catalog/contracts.rkt"
         "../../src/package_catalog/curation-assessment-store.rkt"
         "../../src/package_catalog/curation-decisions.rkt"
         "../../src/package_catalog/curation-publication.rkt"
         "../../src/package_catalog/curation-records.rkt"
         "../../src/package_catalog/curation-submissions.rkt"
         "../../src/package_catalog/integrity.rkt"
         (submod "../../src/package_catalog/integrity.rkt" test-support))

(provide profile publisher-keys previous-snapshot publication)

(define (digest character) (make-string 64 character))
(define root-public-key
  "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
(define publisher-public-key
  "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c")
;; This published test vector is fixture material, not catalog key custody.
(define publisher-test-secret-key
  (string-append
   "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
   publisher-public-key))
(define root-id (package-catalog-public-key-id root-public-key))
(define publisher-key-id (package-catalog-public-key-id publisher-public-key))
(define root
  (odra-package-catalog-root-key root-id 1 'ed25519 root-public-key 1 #f))
(define catalog-id (package-catalog-identity root))
(define publisher-key
  (odra-package-catalog-publisher-key
   publisher-key-id 'ed25519 publisher-public-key))
(define publisher-keys (list publisher-key))
(define publisher
  (odra-package-catalog-publisher-authorization
   "snapshot-publisher" (list publisher-key-id) 1 1 #f))
(define policy
  (odra-package-catalog-policy
   "policy-v1" 1 1 "eligible" "authority" "assessment" "decision"
   "retention"))
(define curator
  (odra-package-catalog-curator-authorization
   "primary-curator" "human.alice" 'human 1 #f '("policy-v1")))
(define-values
  (profile profile-rejection)
  (confirm-package-catalog-profile
   (odra-package-catalog-profile-proposal
    1 catalog-id "Fixture Catalog" (list root) (list curator) (list publisher)
    (list policy) '())))
(when profile-rejection
  (error 'package-catalog-publication-fixture "invalid fixture profile"))

(define release
  (odra-package-release-reference
   1 "org.example.package" (digest #\a) "1.0.0" "org.example.publisher"
   "https://forge.example/org/package" (make-string 40 #\b) #f (digest #\c)
   (list (odra-package-artifact-reference
          'linux 'x86-64 '("package.tar.zst") (digest #\d) 1024 #f #f
          'reproduced))
   (digest #\e) (digest #\f) (digest #\1) (digest #\2)))
(define governance-revision (make-string 40 #\3))
(define submission
  (make-curation-submission catalog-id 'add "submitter-1" release #f '()
                            governance-revision))
(define inputs (list (digest #\4)))
(define assessment
  (make-curation-assessment
   (odra-curation-submission-id submission) 1 'deterministic-tool "scanner.tool"
   "v1" "rules/v1" inputs 'pass '() '() #f 90))
(define assessed
  (record-curation-assessment (make-curation-review submission) inputs assessment))
(define review (mark-curation-reviewable assessed '(deterministic-tool)))
(define decision
  (make-human-curation-decision
   (odra-curation-submission-id submission) 1 "policy-v1" 1
   "primary-curator" "human.alice" 'accept
   (odra-curation-submission-assessment-ids
    (odra-curation-review-submission review))
   "The exact fixture release satisfies the current policy." 100
   governance-revision))
(define authorization
  (authorize-human-curation-decision profile review '() decision 100))
(define proposal
  (make-package-catalog-publication-proposal
   decision catalog-id 1 #f 110 210 "snapshot-publisher" (digest #\5) ""))

(define (fixture-signer payload _publisher-id)
  (define message
    (package-catalog-signature-message
     package-catalog-publisher-signature-domain payload))
  (list
   (odra-package-catalog-signature
    'ed25519 publisher-key-id package-catalog-publisher-signature-domain
    (sign-for-test message publisher-test-secret-key))))

(define previous-snapshot #f)
(define publication
  (build-package-catalog-publication
   profile publisher-keys previous-snapshot '() authorization proposal
   fixture-signer))
(when (odra-package-catalog-publication-failure? publication)
  (error 'package-catalog-publication-fixture "could not build fixture"))
