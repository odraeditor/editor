#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/contract/base
         racket/list
         racket/string
         "../storage/record-codec.rkt"
         "contracts.rkt"
         "curation-assessment-store.rkt"
         "curation-submissions.rkt")

(provide
 current-curation-decision-format-version
 maximum-curation-decision-assessments
 maximum-curation-decision-rationale-bytes
 (struct-out odra-human-curation-decision)
 (struct-out odra-authorized-curation-decision)
 (struct-out odra-curation-decision-failure)
 (struct-out odra-package-catalog-publication-proposal)
 (struct-out odra-package-catalog-publication-audit)
 (contract-out
  [make-human-curation-decision
   (-> string? exact-positive-integer? string? exact-positive-integer?
       string? string? symbol? (listof string?) string?
       exact-nonnegative-integer? string? odra-human-curation-decision?)]
  [make-package-catalog-publication-proposal
   (-> odra-human-curation-decision? string? exact-positive-integer?
       (or/c #f string?) exact-nonnegative-integer? exact-nonnegative-integer?
       string? string? string? odra-package-catalog-publication-proposal?)]
  [make-package-catalog-publication-audit
   (-> symbol? symbol? string? string? string? (or/c #f string?)
       exact-nonnegative-integer? odra-package-catalog-publication-audit?)]
  [authorize-human-curation-decision
   (-> odra-package-catalog-profile? odra-curation-review?
       (listof odra-human-curation-decision?) odra-human-curation-decision?
       exact-nonnegative-integer?
       (or/c odra-authorized-curation-decision?
             odra-curation-decision-failure?))]))

(define current-curation-decision-format-version 1)
(define maximum-curation-decision-assessments 128)
(define maximum-curation-decision-rationale-bytes 4096)
(define maximum-text-bytes 4096)

(define digest-pattern #px"^[0-9a-f]{64}$")
(define revision-pattern #px"^[0-9a-f]{40}(?:[0-9a-f]{24})?$")
(define identity-pattern #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")
(define decision-outcomes '(accept reject request-changes))
(define publication-events
  '(decision-authorized publication-validated snapshot-built snapshot-published))
(define audit-actor-classes '(human publication-service validator))

(define (digest? value)
  (and (string? value) (regexp-match? digest-pattern value)))

(define (identity? value)
  (and (string? value)
       (positive? (string-length value))
       (<= (bytes-length (string->bytes/utf-8 value)) 128)
       (regexp-match? identity-pattern value)))

(define (bounded-text? value maximum)
  (and (string? value)
       (positive? (string-length value))
       (not (string-contains? value (string #\nul)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(define (canonical-digests? values maximum)
  (and (list? values)
       (pair? values)
       (<= (length values) maximum)
       (andmap digest? values)
       (equal? values (sort (remove-duplicates values string=?) string<?))))

(define (copied value)
  (if (string? value) (record-copied-text value) value))

(define (sha256-datum datum)
  (bytes->hex-string
   (sha256-bytes (open-input-bytes (record-datum->module-bytes datum)))))

(define (decision-content submission-id submission-generation policy-id
                          policy-generation curator-authorization-id
                          curator-subject-id outcome assessment-ids rationale
                          decided-at governance-revision)
  (list 'human-curation-decision submission-id submission-generation policy-id
        policy-generation curator-authorization-id curator-subject-id outcome
        assessment-ids rationale decided-at governance-revision))

(struct odra-human-curation-decision
  (format-version id submission-id submission-generation policy-id
      policy-generation curator-authorization-id curator-subject-id outcome
      assessment-ids rationale decided-at governance-revision)
  #:transparent
  #:guard
  (lambda (format-version id submission-id submission-generation policy-id
                          policy-generation curator-authorization-id
                          curator-subject-id outcome assessment-ids rationale
                          decided-at governance-revision _)
    (define expected-id
      (sha256-datum
       (decision-content submission-id submission-generation policy-id
                         policy-generation curator-authorization-id
                         curator-subject-id outcome assessment-ids rationale
                         decided-at governance-revision)))
    (unless
        (and (= format-version current-curation-decision-format-version)
             (digest? id)
             (digest? submission-id)
             (exact-positive-integer? submission-generation)
             (identity? policy-id)
             (exact-positive-integer? policy-generation)
             (identity? curator-authorization-id)
             (identity? curator-subject-id)
             (memq outcome decision-outcomes)
             (canonical-digests? assessment-ids
                                 maximum-curation-decision-assessments)
             (bounded-text? rationale maximum-curation-decision-rationale-bytes)
             (exact-nonnegative-integer? decided-at)
             (string? governance-revision)
             (regexp-match? revision-pattern governance-revision)
             (string=? id expected-id))
      (raise-arguments-error 'odra-human-curation-decision
                             "invalid immutable human curation decision"))
    (values format-version (copied id) (copied submission-id)
            submission-generation (copied policy-id) policy-generation
            (copied curator-authorization-id) (copied curator-subject-id)
            outcome (map copied assessment-ids) (copied rationale) decided-at
            (copied governance-revision))))

(define (make-human-curation-decision
         submission-id submission-generation policy-id policy-generation
         curator-authorization-id curator-subject-id outcome assessment-ids
         rationale decided-at governance-revision)
  (define id
    (sha256-datum
     (decision-content submission-id submission-generation policy-id
                       policy-generation curator-authorization-id
                       curator-subject-id outcome assessment-ids rationale
                       decided-at governance-revision)))
  (odra-human-curation-decision
   1 id submission-id submission-generation policy-id policy-generation
   curator-authorization-id curator-subject-id outcome assessment-ids rationale
   decided-at governance-revision))

(define (proposal-content decision-id catalog-id target-sequence previous-id
                          issued-at expires-at publisher-id advisory-digest
                          status-reason)
  (list 'package-catalog-publication-proposal decision-id catalog-id
        target-sequence previous-id issued-at expires-at publisher-id
        advisory-digest status-reason))

(struct odra-package-catalog-publication-proposal
  (format-version id decision-id catalog-id submission-id submission-generation
      target-snapshot-sequence previous-snapshot-id issued-at expires-at
      publisher-authorization-id advisory-set-digest status-reason)
  #:transparent
  #:guard
  (lambda (format-version id decision-id catalog-id submission-id
                          submission-generation target-sequence previous-id
                          issued-at expires-at publisher-id advisory-digest
                          status-reason _)
    (define expected-id
      (sha256-datum
       (proposal-content decision-id catalog-id target-sequence previous-id
                         issued-at expires-at publisher-id advisory-digest
                         status-reason)))
    (unless
        (and (= format-version current-curation-decision-format-version)
             (digest? id)
             (digest? decision-id)
             (digest? catalog-id)
             (digest? submission-id)
             (exact-positive-integer? submission-generation)
             (exact-positive-integer? target-sequence)
             (if (= target-sequence 1)
                 (not previous-id)
                 (digest? previous-id))
             (exact-nonnegative-integer? issued-at)
             (exact-nonnegative-integer? expires-at)
             (< issued-at expires-at)
             (identity? publisher-id)
             (digest? advisory-digest)
             (or (string=? status-reason "")
                 (bounded-text? status-reason maximum-text-bytes))
             (string=? id expected-id))
      (raise-arguments-error 'odra-package-catalog-publication-proposal
                             "invalid bounded publication proposal"))
    (values format-version (copied id) (copied decision-id) (copied catalog-id)
            (copied submission-id) submission-generation target-sequence
            (and previous-id (copied previous-id)) issued-at expires-at
            (copied publisher-id) (copied advisory-digest)
            (copied status-reason))))

(define (make-package-catalog-publication-proposal
         decision catalog-id target-sequence previous-id issued-at expires-at
         publisher-id advisory-digest status-reason)
  (define decision-id (odra-human-curation-decision-id decision))
  (define id
    (sha256-datum
     (proposal-content decision-id catalog-id target-sequence previous-id
                       issued-at expires-at publisher-id advisory-digest
                       status-reason)))
  (odra-package-catalog-publication-proposal
   1 id decision-id catalog-id
   (odra-human-curation-decision-submission-id decision)
   (odra-human-curation-decision-submission-generation decision)
   target-sequence previous-id issued-at expires-at publisher-id advisory-digest
   status-reason))

(define (audit-content event actor-class actor-id decision-id input-digest
                       output-digest recorded-at)
  (list 'package-catalog-publication-audit event actor-class actor-id decision-id
        input-digest output-digest recorded-at))

(struct odra-package-catalog-publication-audit
  (format-version id event actor-class actor-id decision-id input-digest
      output-digest recorded-at)
  #:transparent
  #:guard
  (lambda (format-version id event actor-class actor-id decision-id input-digest
                          output-digest recorded-at _)
    (define expected-id
      (sha256-datum
       (audit-content event actor-class actor-id decision-id input-digest
                      output-digest recorded-at)))
    (unless
        (and (= format-version current-curation-decision-format-version)
             (digest? id)
             (memq event publication-events)
             (memq actor-class audit-actor-classes)
             (identity? actor-id)
             (digest? decision-id)
             (digest? input-digest)
             (or (not output-digest) (digest? output-digest))
             (exact-nonnegative-integer? recorded-at)
             (string=? id expected-id))
      (raise-arguments-error 'odra-package-catalog-publication-audit
                             "invalid immutable publication audit record"))
    (values format-version (copied id) event actor-class (copied actor-id)
            (copied decision-id) (copied input-digest)
            (and output-digest (copied output-digest)) recorded-at)))

(define (make-package-catalog-publication-audit
         event actor-class actor-id decision-id input-digest output-digest
         recorded-at)
  (define id
    (sha256-datum
     (audit-content event actor-class actor-id decision-id input-digest
                    output-digest recorded-at)))
  (odra-package-catalog-publication-audit
   1 id event actor-class actor-id decision-id input-digest output-digest
   recorded-at))

(struct odra-authorized-curation-decision (decision review audit)
  #:transparent
  #:guard
  (lambda (decision review audit _)
    (unless (and (odra-human-curation-decision? decision)
                 (odra-curation-review? review)
                 (odra-package-catalog-publication-audit? audit)
                 (string=?
                  (odra-human-curation-decision-id decision)
                  (odra-package-catalog-publication-audit-decision-id audit)))
      (raise-arguments-error 'odra-authorized-curation-decision
                             "invalid authorized human decision"))
    (values decision review audit)))

(struct odra-curation-decision-failure (code field expected actual)
  #:transparent
  #:guard
  (lambda (code field expected actual _)
    (unless
        (and (memq code '(catalog-identity conflicting-decision
                                           duplicate-decision future-decision
                                           incomplete-evidence invalid-authority
                                           invalid-governance invalid-state
                                           stale-policy stale-submission))
             (symbol? field))
      (raise-arguments-error 'odra-curation-decision-failure
                             "invalid curation decision failure"))
    (values code field expected actual)))

(define (decision-failure code field expected actual)
  (odra-curation-decision-failure code field expected actual))

(define (find-policy profile decision)
  (for/first ([policy (in-list (odra-package-catalog-profile-policies profile))]
              #:when
              (and (string=?
                    (odra-package-catalog-policy-id policy)
                    (odra-human-curation-decision-policy-id decision))
                   (=
                    (odra-package-catalog-policy-generation policy)
                    (odra-human-curation-decision-policy-generation decision))))
    policy))

(define (find-curator profile decision)
  (for/first
      ([authorization
        (in-list (odra-package-catalog-profile-curators profile))]
       #:when
       (string=?
        (odra-package-catalog-curator-authorization-id authorization)
        (odra-human-curation-decision-curator-authorization-id decision)))
    authorization))

(define (decision-for-submission-generation? candidate decision)
  (and (string=?
        (odra-human-curation-decision-submission-id candidate)
        (odra-human-curation-decision-submission-id decision))
       (=
        (odra-human-curation-decision-submission-generation candidate)
        (odra-human-curation-decision-submission-generation decision))))

(define (decision-state outcome)
  (case outcome
    [(accept) 'accepted]
    [(reject) 'rejected]
    [(request-changes) 'changes-requested]))

(define (authorize-human-curation-decision
         profile review existing-decisions decision now)
  (define submission (odra-curation-review-submission review))
  (define policy (find-policy profile decision))
  (define curator (find-curator profile decision))
  (define previous
    (findf (lambda (candidate)
             (decision-for-submission-generation? candidate decision))
           existing-decisions))
  (cond
    [(not (string=?
           (odra-package-catalog-profile-identity profile)
           (odra-curation-submission-catalog-id submission)))
     (decision-failure
      'catalog-identity 'catalog-id
      (odra-package-catalog-profile-identity profile)
      (odra-curation-submission-catalog-id submission))]
    [(not (string=?
           (odra-human-curation-decision-submission-id decision)
           (odra-curation-submission-id submission)))
     (decision-failure
      'stale-submission 'submission-id
      (odra-curation-submission-id submission)
      (odra-human-curation-decision-submission-id decision))]
    [(not (=
           (odra-human-curation-decision-submission-generation decision)
           (odra-curation-submission-generation submission)))
     (decision-failure
      'stale-submission 'submission-generation
      (odra-curation-submission-generation submission)
      (odra-human-curation-decision-submission-generation decision))]
    [(not (eq? (odra-curation-submission-state submission) 'reviewable))
     (decision-failure 'invalid-state 'state 'reviewable
                       (odra-curation-submission-state submission))]
    [(> (odra-human-curation-decision-decided-at decision) now)
     (decision-failure 'future-decision 'decided-at now
                       (odra-human-curation-decision-decided-at decision))]
    [(not policy)
     (decision-failure
      'stale-policy 'policy
      (cons (odra-human-curation-decision-policy-id decision)
            (odra-human-curation-decision-policy-generation decision))
      #f)]
    [(not curator)
     (decision-failure
      'invalid-authority 'curator-authorization-id #f
      (odra-human-curation-decision-curator-authorization-id decision))]
    [(not (string=?
           (odra-package-catalog-curator-authorization-subject curator)
           (odra-human-curation-decision-curator-subject-id decision)))
     (decision-failure
      'invalid-authority 'curator-subject-id
      (odra-package-catalog-curator-authorization-subject curator)
      (odra-human-curation-decision-curator-subject-id decision))]
    [(not
      (and
       (package-catalog-curator-authorization-active?
        curator (odra-human-curation-decision-decided-at decision)
        (odra-human-curation-decision-policy-id decision))
       (package-catalog-curator-authorization-active?
        curator now (odra-human-curation-decision-policy-id decision))))
     (decision-failure 'invalid-authority 'validity 'active now)]
    [(not (equal?
           (odra-human-curation-decision-assessment-ids decision)
           (odra-curation-submission-assessment-ids submission)))
     (decision-failure
      'incomplete-evidence 'assessment-ids
      (odra-curation-submission-assessment-ids submission)
      (odra-human-curation-decision-assessment-ids decision))]
    [(not
      (and (odra-curation-submission-governance-revision submission)
           (string=?
            (odra-human-curation-decision-governance-revision decision)
            (odra-curation-submission-governance-revision submission))))
     (decision-failure
      'invalid-governance 'governance-revision
      (odra-curation-submission-governance-revision submission)
      (odra-human-curation-decision-governance-revision decision))]
    [previous
     (decision-failure
      (if (equal? previous decision)
          'duplicate-decision
          'conflicting-decision)
      'submission-generation previous decision)]
    [else
     (define updated-submission
       (struct-copy
        odra-curation-submission submission
        [state (decision-state
                (odra-human-curation-decision-outcome decision))]))
     (define updated-review
       (odra-curation-review updated-submission
                             (odra-curation-review-assessments review)))
     (define review-digest
       (bytes->hex-string
        (sha256-bytes
         (open-input-bytes (curation-review->module-bytes review)))))
     (odra-authorized-curation-decision
      decision updated-review
      (make-package-catalog-publication-audit
       'decision-authorized 'human
       (odra-human-curation-decision-curator-subject-id decision)
       (odra-human-curation-decision-id decision) review-digest
       (odra-human-curation-decision-id decision) now))]))
