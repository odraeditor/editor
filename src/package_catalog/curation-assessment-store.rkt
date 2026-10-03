#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/contract/base
         racket/file
         racket/list
         racket/match
         "../storage/durable-file.rkt"
         "../storage/record-codec.rkt"
         "curation-records.rkt"
         "curation-submissions.rkt")

(provide
 (struct-out odra-curation-review)
 (struct-out odra-curation-assessment-ingestion-failure)
 (contract-out
  [make-curation-review (-> odra-curation-submission? odra-curation-review?)]
  [record-curation-assessment
   (-> odra-curation-review? (listof string?) odra-curation-assessment?
       (or/c odra-curation-review?
             odra-curation-assessment-ingestion-failure?))]
  [mark-curation-reviewable
   (-> odra-curation-review? (listof symbol?)
       (or/c odra-curation-review?
             odra-curation-assessment-ingestion-failure?))]
  [curation-review->module-bytes
   (-> odra-curation-review? immutable-bytes?)]
  [curation-review-module-load
   (-> path-string? (or/c odra-curation-review? odra-record-diagnostic?))]
  [curation-review-persist
   (-> path-string? odra-curation-review?
       (or/c path? odra-curation-assessment-ingestion-failure?))]))

(define admitted-assessor-classes
  '(ai-assisted deterministic-tool human-review isolated-runtime))

(define (immutable-bytes? value)
  (and (bytes? value) (immutable? value)))

(struct odra-curation-review (submission assessments)
  #:transparent
  #:guard
  (lambda (submission assessments _)
    (define ids
      (and (list? assessments)
           (sort (map odra-curation-assessment-id assessments) string<?)))
    (unless
        (and (odra-curation-submission? submission)
             (list? assessments)
             (<= (length assessments) maximum-submission-assessments)
             (andmap odra-curation-assessment? assessments)
             (equal? assessments
                     (sort assessments string<? #:key odra-curation-assessment-id))
             (equal? ids (odra-curation-submission-assessment-ids submission))
             (for/and ([assessment (in-list assessments)])
               (and (string=?
                     (odra-curation-submission-id submission)
                     (odra-curation-assessment-submission-id assessment))
                    (= (odra-curation-submission-generation submission)
                       (odra-curation-assessment-submission-generation
                        assessment)))))
      (raise-arguments-error 'odra-curation-review
                             "review evidence must match the exact submission generation"))
    (values submission assessments)))

(struct odra-curation-assessment-ingestion-failure
  (code field expected actual)
  #:transparent)

(define (failure code field expected actual)
  (odra-curation-assessment-ingestion-failure code field expected actual))

(define (make-curation-review submission)
  (unless (null? (odra-curation-submission-assessment-ids submission))
    (raise-arguments-error 'make-curation-review
                           "new review requires a submission without attached evidence"))
  (odra-curation-review submission '()))

(define (record-curation-assessment review expected-inputs assessment)
  (define submission (odra-curation-review-submission review))
  (define assessments (odra-curation-review-assessments review))
  (cond
    [(not (string=? (odra-curation-assessment-submission-id assessment)
                    (odra-curation-submission-id submission)))
     (failure 'wrong-submission 'submission-id
              (odra-curation-submission-id submission)
              (odra-curation-assessment-submission-id assessment))]
    [(not (= (odra-curation-assessment-submission-generation assessment)
             (odra-curation-submission-generation submission)))
     (failure 'stale-input 'submission-generation
              (odra-curation-submission-generation submission)
              (odra-curation-assessment-submission-generation assessment))]
    [(not (equal? expected-inputs
                  (odra-curation-assessment-input-digests assessment)))
     (failure 'stale-input 'input-digests expected-inputs
              (odra-curation-assessment-input-digests assessment))]
    [(findf (lambda (existing)
              (string=? (odra-curation-assessment-id existing)
                        (odra-curation-assessment-id assessment)))
            assessments)
     (failure 'duplicate-assessment 'assessment-id #f
              (odra-curation-assessment-id assessment))]
    [(>= (length assessments) maximum-submission-assessments)
     (failure 'retention-limit 'assessments maximum-submission-assessments
              (add1 (length assessments)))]
    [(memq (odra-curation-submission-state submission)
           '(accepted closed rejected))
     (failure 'closed-submission 'state 'open
              (odra-curation-submission-state submission))]
    [else
     (define updated-assessments
       (sort (cons assessment assessments) string<?
             #:key odra-curation-assessment-id))
     (define updated-submission
       (struct-copy odra-curation-submission submission
                    [assessment-ids
                     (map odra-curation-assessment-id updated-assessments)]
                    [state 'assessing]))
     (odra-curation-review updated-submission updated-assessments)]))

(define (mark-curation-reviewable review required-classes)
  (define submission (odra-curation-review-submission review))
  (define assessments (odra-curation-review-assessments review))
  (cond
    [(or (not (list? required-classes))
         (not (andmap (lambda (value)
                        (and (memq value admitted-assessor-classes) #t))
                      required-classes))
         (not (= (length required-classes)
                 (length (remove-duplicates required-classes eq?)))))
     (failure 'invalid-requirement 'assessor-classes
              admitted-assessor-classes required-classes)]
    [else
     (define missing
       (filter
        (lambda (required)
          (not (for/or ([assessment (in-list assessments)])
                 (eq? required
                      (odra-curation-assessment-assessor-class assessment)))))
        required-classes))
     (if (pair? missing)
         (failure 'incomplete-assessment 'assessor-classes required-classes missing)
         (odra-curation-review
          (struct-copy odra-curation-submission submission [state 'reviewable])
          assessments))]))

(define (artifact->datum value)
  (list (odra-package-artifact-reference-platform value)
        (odra-package-artifact-reference-architecture value)
        (odra-package-artifact-reference-uri-set value)
        (odra-package-artifact-reference-digest value)
        (odra-package-artifact-reference-size value)
        (odra-package-artifact-reference-builder-id value)
        (odra-package-artifact-reference-provenance-ref value)
        (odra-package-artifact-reference-reproducibility-state value)))

(define (release->datum value)
  (list (odra-package-release-reference-format-version value)
        (odra-package-release-reference-package-id value)
        (odra-package-release-reference-release-id value)
        (odra-package-release-reference-version value)
        (odra-package-release-reference-publisher-id value)
        (odra-package-release-reference-source-uri value)
        (odra-package-release-reference-source-revision value)
        (odra-package-release-reference-source-label value)
        (odra-package-release-reference-manifest-digest value)
        (map artifact->datum (odra-package-release-reference-artifact-set value))
        (odra-package-release-reference-dependency-set-digest value)
        (odra-package-release-reference-compatibility-digest value)
        (odra-package-release-reference-capability-set-digest value)
        (odra-package-release-reference-contribution-set-digest value)))

(define (change->datum value)
  (list (odra-package-change-summary-class value)
        (odra-package-change-summary-direction value)
        (odra-package-change-summary-risk value)
        (odra-package-change-summary-previous value)
        (odra-package-change-summary-current value)))

(define (submission->datum value)
  (list (odra-curation-submission-format-version value)
        (odra-curation-submission-id value)
        (odra-curation-submission-generation value)
        (odra-curation-submission-catalog-id value)
        (odra-curation-submission-kind value)
        (odra-curation-submission-submitter-id value)
        (and (odra-curation-submission-release value)
             (release->datum (odra-curation-submission-release value)))
        (odra-curation-submission-prior-assertion-id value)
        (map change->datum (odra-curation-submission-changes value))
        (odra-curation-submission-assessment-ids value)
        (odra-curation-submission-state value)
        (odra-curation-submission-governance-revision value)))

(define (finding->datum value)
  (list (odra-assessment-finding-kind value)
        (odra-assessment-finding-severity value)
        (odra-assessment-finding-location value)
        (odra-assessment-finding-evidence-summary value)
        (odra-assessment-finding-confidence value)))

(define (assessment->datum value)
  (list (odra-curation-assessment-format-version value)
        (odra-curation-assessment-id value)
        (odra-curation-assessment-submission-id value)
        (odra-curation-assessment-submission-generation value)
        (odra-curation-assessment-assessor-class value)
        (odra-curation-assessment-assessor-identity value)
        (odra-curation-assessment-assessor-version value)
        (odra-curation-assessment-rule-set-ref value)
        (odra-curation-assessment-input-digests value)
        (odra-curation-assessment-outcome value)
        (map finding->datum (odra-curation-assessment-findings value))
        (odra-curation-assessment-limitations value)
        (odra-curation-assessment-evidence-ref value)
        (odra-curation-assessment-completed-at value)))

(define (curation-review->module-bytes review)
  (record-datum->module-bytes
   (list 'package-curation-review 1
         (submission->datum (odra-curation-review-submission review))
         (map assessment->datum (odra-curation-review-assessments review)))))

(define (decode-artifact value)
  (apply odra-package-artifact-reference value))

(define (decode-release value)
  (match value
    [(list format package-id release-id version publisher source revision label
           manifest artifacts dependency compatibility capability contribution)
     (odra-package-release-reference
      format package-id release-id version publisher source revision label manifest
      (map decode-artifact artifacts) dependency compatibility capability
      contribution)]))

(define (decode-submission value)
  (match value
    [(list format id generation catalog kind submitter release prior changes
           assessment-ids state governance)
     (odra-curation-submission
      format id generation catalog kind submitter
      (and release (decode-release release)) prior
      (map (lambda (change) (apply odra-package-change-summary change)) changes)
      assessment-ids state governance)]))

(define (decode-assessment value)
  (match value
    [(list format id submission generation class identity version rules inputs
           outcome findings limitations evidence completed-at)
     (odra-curation-assessment
      format id submission generation class identity version rules inputs outcome
      (map (lambda (finding) (apply odra-assessment-finding finding)) findings)
      limitations evidence completed-at)]))

(define (decode-review value)
  (match value
    [(list 'package-curation-review 1 submission assessments)
     (odra-curation-review (decode-submission submission)
                           (map decode-assessment assessments))]))

(define (curation-review-module-load path)
  (record-module-load path decode-review))

(define (curation-review-persist root review)
  (define bytes (curation-review->module-bytes review))
  (define digest
    (bytes->hex-string (sha256-bytes (open-input-bytes bytes))))
  (define submission (odra-curation-review-submission review))
  (define complete-root (path->complete-path root))
  (define directory
    (build-path complete-root "package-curation" "reviews"
                (odra-curation-submission-id submission)
                (number->string (odra-curation-submission-generation submission))))
  (define target (build-path directory (string-append digest ".rktd")))
  (cond
    [(file-exists? target)
     (if (bytes=? bytes (file->bytes target))
         target
         (failure 'identity-conflict 'review digest target))]
    [else
     (define publication
       (durable-file-publish
        target bytes
        #:private-directories
        (list complete-root (build-path complete-root "package-curation")
              (build-path complete-root "package-curation" "reviews")
              (build-path complete-root "package-curation" "reviews"
                          (odra-curation-submission-id submission))
              directory)
        #:validate-stage
        (lambda (stage)
          (define loaded (curation-review-module-load stage))
          (and (odra-curation-review? loaded) (equal? loaded review)))))
     (if (odra-durable-file-publication? publication)
         target
         (failure 'publication 'review #f
                  (odra-durable-file-failure-code publication))) ]))
