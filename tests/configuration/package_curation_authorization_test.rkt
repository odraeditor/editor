#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/package_catalog/contracts.rkt"
         "../../src/package_catalog/curation-assessment-store.rkt"
         "../../src/package_catalog/curation-decisions.rkt"
         "../../src/package_catalog/curation-records.rkt"
         "../../src/package_catalog/curation-submissions.rkt")

(define (digest character) (make-string 64 character))
(define catalog-id (digest #\a))
(define governance-revision (make-string 40 #\b))
(define policy
  (odra-package-catalog-policy
   "policy-v1" 1 1 "eligible" "authority" "assessment" "decision"
   "retention"))
(define curator
  (odra-package-catalog-curator-authorization
   "primary-curator" "human.alice" 'human 10 200 '("policy-v1")))
(define-values
  (profile profile-rejection)
  (confirm-package-catalog-profile
   (odra-package-catalog-profile-proposal
    1 catalog-id "Catalog" (list (odra-package-catalog-root-key
                                  (digest #\c) 1 'ed25519 (digest #\d) 1 #f))
    (list curator) '() (list policy) '())))

(define release
  (odra-package-release-reference
   1 "org.example.package" (digest #\e) "1.0.0" "org.example.publisher"
   "https://forge.example/org/package" (make-string 40 #\f) #f (digest #\1)
   (list (odra-package-artifact-reference
          'linux 'x86-64 '("package.tar.zst") (digest #\2) 1024 #f #f
          'unverified))
   (digest #\3) (digest #\4) (digest #\5) (digest #\6)))
(define submission
  (make-curation-submission catalog-id 'add "submitter-1" release #f '()
                            governance-revision))
(define inputs (list (digest #\7)))
(define assessment
  (make-curation-assessment
   (odra-curation-submission-id submission) 1 'deterministic-tool "scanner.tool"
   "v1" "rules/v1" inputs 'findings '() '() #f 90))
(define assessed
  (record-curation-assessment (make-curation-review submission) inputs assessment))
(define review (mark-curation-reviewable assessed '(deterministic-tool)))
(define assessment-ids
  (odra-curation-submission-assessment-ids
   (odra-curation-review-submission review)))

(define (decision #:outcome [outcome 'accept]
                  #:generation [generation 1]
                  #:policy-generation [policy-generation 1]
                  #:authorization [authorization "primary-curator"]
                  #:subject [subject "human.alice"]
                  #:assessments [assessments assessment-ids]
                  #:governance [governance governance-revision]
                  #:decided-at [decided-at 100])
  (make-human-curation-decision
   (odra-curation-submission-id submission) generation "policy-v1"
   policy-generation authorization subject outcome assessments
   "The exact evidence was reviewed under policy version 1." decided-at
   governance))

(test-case "only a current authorized human decision changes review state"
  (check-false profile-rejection)
  (define result
    (authorize-human-curation-decision profile review '() (decision) 100))
  (check-true (odra-authorized-curation-decision? result))
  (check-eq?
   (odra-curation-submission-state
    (odra-curation-review-submission
     (odra-authorized-curation-decision-review result)))
   'accepted)
  (check-eq?
   (odra-package-catalog-publication-audit-event
    (odra-authorized-curation-decision-audit result))
   'decision-authorized))

(test-case "reject and request changes remain human outcomes"
  (for ([outcome '(reject request-changes)]
        [expected '(rejected changes-requested)])
    (define result
      (authorize-human-curation-decision
       profile review '() (decision #:outcome outcome) 100))
    (check-eq?
     (odra-curation-submission-state
      (odra-curation-review-submission
       (odra-authorized-curation-decision-review result)))
     expected)))

(test-case "stale submission policy and evidence reject"
  (for ([candidate
         (list (decision #:generation 2)
               (decision #:policy-generation 2)
               (decision #:assessments (list (digest #\8))))]
        [code '(stale-submission stale-policy incomplete-evidence)])
    (define result
      (authorize-human-curation-decision profile review '() candidate 100))
    (check-true (odra-curation-decision-failure? result))
    (check-eq? (odra-curation-decision-failure-code result) code)))

(test-case "inactive or mismatched curator authority rejects"
  (for ([candidate
         (list (decision #:authorization "unknown-curator")
               (decision #:subject "human.mallory")
               (decision #:decided-at 201))])
    (define result
      (authorize-human-curation-decision profile review '() candidate 201))
    (check-eq? (odra-curation-decision-failure-code result)
               'invalid-authority)))

(test-case "governance revision and reviewable state are exact"
  (check-eq?
   (odra-curation-decision-failure-code
    (authorize-human-curation-decision
     profile review '() (decision #:governance (make-string 40 #\9)) 100))
   'invalid-governance)
  (define assessing-review
    (odra-curation-review
     (struct-copy odra-curation-submission
                  (odra-curation-review-submission review)
                  [state 'assessing])
     (odra-curation-review-assessments review)))
  (check-eq?
   (odra-curation-decision-failure-code
    (authorize-human-curation-decision
     profile assessing-review '() (decision) 100))
   'invalid-state))

(test-case "one submission generation cannot acquire two decisions"
  (define accepted (decision))
  (check-eq?
   (odra-curation-decision-failure-code
    (authorize-human-curation-decision
     profile review (list accepted) accepted 100))
   'duplicate-decision)
  (check-eq?
   (odra-curation-decision-failure-code
    (authorize-human-curation-decision
     profile review (list accepted) (decision #:outcome 'reject) 100))
   'conflicting-decision))
