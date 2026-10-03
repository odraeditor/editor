#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require "../../../../src/package_catalog/contracts.rkt"
         "../../../../src/package_catalog/curation-decisions.rkt"
         "../../../../src/package_catalog/curation-records.rkt"
         "../../../../src/package_catalog/curation-submissions.rkt"
         "../../../../src/package_catalog/integrity.rkt"
         "../../../../src/package_catalog/security-advisories.rkt"
         "../../../../src/package_catalog/snapshot-records.rkt")

(provide profile publisher-keys previous-snapshot origin-endpoint mirror-endpoint release
         submission assessment decision assertion advisory snapshot)

(define (digest character) (make-string 64 character))

;; Replace both placeholder public keys and recalculate their identifiers.
(define root-public-key (digest #\1))
(define publisher-public-key (digest #\2))
(define root-key-id (package-catalog-public-key-id root-public-key))
(define publisher-key-id
  (package-catalog-public-key-id publisher-public-key))
(define root
  (odra-package-catalog-root-key
   root-key-id 1 'ed25519 root-public-key 1 #f))
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
   "catalog-policy" 1 1
   "policy/package-eligibility.md"
   "policy/authority.md"
   "policy/assessment.md"
   "policy/decision.md"
   "policy/retention.md"))
(define curator
  (odra-package-catalog-curator-authorization
   "primary-curator" "human.curator" 'human 1 #f '("catalog-policy")))
(define origin-endpoint
  (odra-package-catalog-endpoint
   "origin" catalog-id "https://catalog.example/snapshots/current.rktd"
   'https 'origin 0 #t))
(define mirror-endpoint
  (odra-package-catalog-endpoint
   "mirror" catalog-id "https://mirror.example/catalog/current.rktd"
   'https 'mirror 10 #t))

(define-values (profile profile-rejection)
  (confirm-package-catalog-profile
   (odra-package-catalog-profile-proposal
    current-package-catalog-identity-format-version catalog-id
    "Independent Example Catalog" (list root) (list curator)
    (list publisher) (list policy) (list origin-endpoint mirror-endpoint))))
(when profile-rejection
  (error 'package-catalog-curator-template "invalid profile: ~s"
         profile-rejection))

(define release
  (odra-package-release-reference
   current-package-curation-format-version
   "org.example.package" (digest #\3) "1.0.0" "org.example.publisher"
   "https://forge.example/org/package" (make-string 40 #\4) #f
   (digest #\5)
   (list
    (odra-package-artifact-reference
     'linux 'x86-64 '("package-linux-x86-64.tar.zst") (digest #\6)
     1024 "builder.example" "provenance/build.json" 'unverified))
   (digest #\7) (digest #\8) (digest #\9) (digest #\a)))
(define governance-revision (make-string 40 #\b))
(define submission
  (make-curation-submission
   catalog-id 'add "submitter.example" release #f '() governance-revision))
(define assessment
  (make-curation-assessment
   (odra-curation-submission-id submission) 1 'deterministic-tool
   "scanner.example" "1.0.0" "policy/assessment.md" (list (digest #\c))
   'pass '() '() "evidence/assessment.json" 100))
(define decision
  (make-human-curation-decision
   (odra-curation-submission-id submission) 1 "catalog-policy" 1
   "primary-curator" "human.curator" 'accept
   (list (odra-curation-assessment-id assessment))
   "The exact release satisfies the current catalog policy." 110
   governance-revision))
(define assertion
  (odra-package-curation-assertion
   current-package-curation-format-version (digest #\d) catalog-id 1 release
   (odra-human-curation-decision-id decision) "catalog-policy" 'admitted ""
   (list (odra-curation-assessment-id assessment)) 1 1))
(define advisory
  (odra-security-advisory
   current-security-advisory-format-version "example-advisory"
   "catalog-advisory-authority" catalog-id 1 'draft 'vulnerability 'medium
   'suspected '("org.example.package") '() '() '(block-activation warn)
   "Draft advisory awaiting evidence review and external signing." 120 #f '()))
(define unsigned-snapshot
  (odra-package-catalog-snapshot
   current-package-catalog-snapshot-format-version (digest #\e) catalog-id 1 #f
   "catalog-policy" 130 3130 (digest #\f) (digest #\0) 2048
   "snapshot-publisher" '()))
(define snapshot
  (struct-copy odra-package-catalog-snapshot unsigned-snapshot
               [id (package-catalog-snapshot-content-digest unsigned-snapshot)]))
(define previous-snapshot #f)
