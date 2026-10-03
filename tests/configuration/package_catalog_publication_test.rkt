#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         rackunit
         "../../src/package_catalog/contracts.rkt"
         "../../src/package_catalog/curation-assessment-store.rkt"
         "../../src/package_catalog/curation-decisions.rkt"
         "../../src/package_catalog/curation-publication.rkt"
         "../../src/package_catalog/curation-records.rkt"
         "../../src/package_catalog/curation-submissions.rkt"
         "../../src/package_catalog/integrity.rkt"
         "../../src/package_catalog/snapshot-records.rkt"
         (submod "../../src/package_catalog/integrity.rkt" test-support))

(define (digest character) (make-string 64 character))
(define root-public-key
  "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
(define publisher-public-key
  "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c")
(define publisher-secret-key
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
    1 catalog-id "Catalog" (list root) (list curator) (list publisher)
    (list policy) '())))

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
   "v1" "rules/v1" inputs 'findings '() '() #f 90))
(define assessed
  (record-curation-assessment (make-curation-review submission) inputs assessment))
(define review (mark-curation-reviewable assessed '(deterministic-tool)))
(define decision
  (make-human-curation-decision
   (odra-curation-submission-id submission) 1 "policy-v1" 1
   "primary-curator" "human.alice" 'accept
   (odra-curation-submission-assessment-ids
    (odra-curation-review-submission review))
   "The exact package release satisfies the current policy." 100
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
    (sign-for-test message publisher-secret-key))))

(define (build [selected-proposal proposal] [signer fixture-signer])
  (build-package-catalog-publication
   profile (list publisher-key) #f '() authorization selected-proposal signer))

(test-case "accepted human decision builds a verifiable signed snapshot"
  (check-false profile-rejection)
  (define publication (build))
  (check-true (odra-package-catalog-publication? publication))
  (check-true
   (verify-package-catalog-publication
    profile (list publisher-key) #f publication))
  (check-equal?
   (length (odra-package-catalog-publication-assertions publication)) 1)
  (check-equal?
   (odra-package-catalog-snapshot-metadata-size
    (odra-package-catalog-publication-snapshot publication))
   (bytes-length
    (odra-package-catalog-publication-snapshot-bytes publication)))
  (check-equal?
   (odra-package-catalog-publication-diff-added
    (odra-package-catalog-publication-dry-run-diff publication))
   (list
    (odra-package-curation-assertion-id
     (car (odra-package-catalog-publication-assertions publication))))))

(test-case "publication derivation is reproducible for exact inputs"
  (define first (build))
  (define second (build))
  (check-equal? first second)
  (check-equal?
   (odra-package-catalog-publication-snapshot-bytes first)
   (odra-package-catalog-publication-snapshot-bytes second)))

(test-case "multiple assertions use stable canonical ordering"
  (define first
    (odra-package-curation-assertion
     1 (digest #\6) catalog-id 10 release (digest #\7) "policy-v1"
     'admitted "" (list (digest #\8)) 1 10))
  (define second
    (odra-package-curation-assertion
     1 (digest #\9) catalog-id 2 release (digest #\a) "policy-v1"
     'admitted "" (list (digest #\b)) 2 2))
  (define encoded
    (package-curation-assertion-set->module-bytes (list second first)))
  (check-equal?
   encoded
   (package-curation-assertion-set->module-bytes (list first second)))
  (check-equal?
   (package-curation-assertion-set-module-parse encoded "fixture")
   (list first second)))

(test-case "stale history and unverified signatures reject explicitly"
  (define stale
    (make-package-catalog-publication-proposal
     decision catalog-id 2 (digest #\6) 110 210 "snapshot-publisher"
     (digest #\5) ""))
  (check-eq?
   (odra-package-catalog-publication-failure-code (build stale))
   'history)
  (check-eq?
   (odra-package-catalog-publication-failure-code
    (build proposal (lambda (_payload _publisher-id) '())))
   'signature))

(test-case "immutable publication output reloads without private key state"
  (define publication (build))
  (define root-path
    (make-temporary-file "odra-package-catalog-publication-~a" 'directory))
  (file-or-directory-permissions root-path #o700)
  (dynamic-wind
    void
    (lambda ()
      (define output
        (package-catalog-publication-persist
         root-path profile (list publisher-key) #f publication))
      (check-true (odra-package-catalog-publication-output? output))
      (check-equal?
       (package-curation-assertion-set-module-load
        (odra-package-catalog-publication-output-assertion-set-path output))
       (odra-package-catalog-publication-assertions publication))
      (check-equal?
       (package-catalog-snapshot-module-load
        (odra-package-catalog-publication-output-snapshot-path output))
       (odra-package-catalog-publication-snapshot publication))
      (define emitted
        (bytes-append
         (file->bytes
          (odra-package-catalog-publication-output-assertion-set-path output))
         (file->bytes
          (odra-package-catalog-publication-output-snapshot-path output))))
      (check-false (regexp-match? (regexp-quote publisher-secret-key) emitted)))
    (lambda () (delete-directory/files root-path))))

(test-case "tampered assertion projection fails publication verification"
  (define publication (build))
  (define tampered
    (struct-copy
     odra-package-catalog-publication publication
     [assertion-set-bytes #"#lang odra/config\n(package-curation-assertion-set 1 ())\n"]))
  (check-eq?
   (odra-package-catalog-publication-failure-code
   (verify-package-catalog-publication
     profile (list publisher-key) #f tampered))
   'snapshot))

(test-case "snapshot and audit records remain bound to one proposal"
  (define publication (build))
  (define original-audit
    (odra-package-catalog-publication-publication-audit publication))
  (define tampered-audit
    (make-package-catalog-publication-audit
     'snapshot-built 'publication-service "snapshot-publisher"
     (odra-package-catalog-publication-audit-decision-id original-audit)
     (digest #\9)
     (odra-package-catalog-publication-audit-output-digest original-audit)
     (odra-package-catalog-publication-audit-recorded-at original-audit)))
  (define tampered
    (struct-copy odra-package-catalog-publication publication
                 [publication-audit tampered-audit]))
  (check-eq?
   (odra-package-catalog-publication-failure-code
    (verify-package-catalog-publication
     profile (list publisher-key) #f tampered))
   'publication))
