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
         "curation-records.rkt")

(provide
 current-curation-submission-format-version
 maximum-submission-changes
 maximum-submission-assessments
 maximum-assessment-inputs
 maximum-assessment-findings
 (struct-out odra-package-change-summary)
 (struct-out odra-curation-submission)
 (struct-out odra-assessment-finding)
 (struct-out odra-curation-assessment)
 (struct-out odra-curation-submission-failure)
 make-curation-submission
 make-curation-assessment
 (contract-out
  [transition-curation-submission
   (-> odra-curation-submission? symbol?
       (or/c odra-curation-submission? odra-curation-submission-failure?))]
  [replace-curation-submission-candidate
   (-> odra-curation-submission? (or/c #f odra-package-release-reference?)
       (listof odra-package-change-summary?) (or/c #f string?)
       odra-curation-submission?)]
  [curation-assessment-redacted
   (-> odra-curation-assessment? odra-curation-assessment?)]))

(define current-curation-submission-format-version 1)
(define maximum-submission-changes 64)
(define maximum-submission-assessments 128)
(define maximum-assessment-inputs 128)
(define maximum-assessment-findings 256)
(define maximum-text-bytes 4096)
(define digest-pattern #px"^[0-9a-f]{64}$")
(define revision-pattern #px"^[0-9a-f]{40}(?:[0-9a-f]{24})?$")
(define identity-pattern #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")
(define submission-kinds '(add deprecate quarantine restore transfer update withdraw))
(define submission-states
  '(accepted assessing changes-requested closed proposed rejected reviewable))
(define change-classes
  '(artifact-content build capability compatibility contribution dependency
                     filesystem foreign native network package-identity
                     process publisher source))
(define change-directions '(added changed removed unchanged))
(define change-risks '(critical high low medium none))
(define assessor-classes
  '(ai-assisted deterministic-tool human-review isolated-runtime))
(define assessment-outcomes
  '(fail findings inconclusive pass timeout unavailable))
(define finding-severities '(critical high informational low medium))

(define (digest? value)
  (and (string? value) (regexp-match? digest-pattern value)))

(define (identity? value)
  (and (string? value) (regexp-match? identity-pattern value)
       (<= (bytes-length (string->bytes/utf-8 value)) 128)))

(define (bounded-text? value #:empty? [empty? #f])
  (and (string? value) (or empty? (positive? (string-length value)))
       (not (string-contains? value (string #\nul)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum-text-bytes)))

(define (hidden-reasoning? value)
  (define normalized (string-downcase value))
  (or (string-contains? normalized "<think>")
      (string-contains? normalized "chain-of-thought")
      (string-contains? normalized "hidden reasoning")))

(define (canonical-digests? values maximum)
  (and (list? values) (<= (length values) maximum) (andmap digest? values)
       (equal? values (sort (remove-duplicates values string=?) string<?))))

(define (copied value)
  (if (string? value) (record-copied-text value) value))

(define (sha256-datum datum)
  (bytes->hex-string
   (sha256-bytes (open-input-bytes (record-datum->module-bytes datum)))))

(struct odra-package-change-summary (class direction risk previous current)
  #:transparent
  #:guard
  (lambda (class direction risk previous current _)
    (unless (and (memq class change-classes) (memq direction change-directions)
                 (memq risk change-risks)
                 (bounded-text? previous #:empty? #t)
                 (bounded-text? current #:empty? #t))
      (raise-arguments-error 'odra-package-change-summary
                             "invalid bounded semantic change"))
    (values class direction risk (copied previous) (copied current))))

(define (submission-identity catalog-id kind submitter-id release prior)
  (sha256-datum
   (list 'curation-submission catalog-id kind submitter-id
         (and release (odra-package-release-reference-package-id release)) prior)))

(struct odra-curation-submission
  (format-version id generation catalog-id kind submitter-id release
                  prior-assertion-id changes assessment-ids state
                  governance-revision)
  #:transparent
  #:guard
  (lambda (format-version id generation catalog-id kind submitter-id release prior
                          changes assessment-ids state governance-revision _)
    (unless
        (and (= format-version current-curation-submission-format-version)
             (digest? id) (exact-positive-integer? generation) (digest? catalog-id)
             (memq kind submission-kinds) (identity? submitter-id)
             (or (not release) (odra-package-release-reference? release))
             (or (not prior) (digest? prior))
             (case kind
               [(add) (and release (not prior))]
               [(update transfer) (and release prior)]
               [else (and (not release) prior)])
             (list? changes) (<= (length changes) maximum-submission-changes)
             (andmap odra-package-change-summary? changes)
             (canonical-digests? assessment-ids maximum-submission-assessments)
             (memq state submission-states)
             (or (not governance-revision)
                 (and (string? governance-revision)
                      (regexp-match? revision-pattern governance-revision)))
             (string=? id (submission-identity catalog-id kind submitter-id
                                                release prior)))
      (raise-arguments-error 'odra-curation-submission
                             "invalid exact curation submission generation"))
    (values format-version (copied id) generation (copied catalog-id) kind
            (copied submitter-id) release (and prior (copied prior)) changes
            (map copied assessment-ids) state
            (and governance-revision (copied governance-revision)))))

(struct odra-assessment-finding
  (kind severity location evidence-summary confidence)
  #:transparent
  #:guard
  (lambda (kind severity location evidence-summary confidence _)
    (unless (and (identity? kind) (memq severity finding-severities)
                 (bounded-text? location #:empty? #t)
                 (bounded-text? evidence-summary)
                 (not (hidden-reasoning? evidence-summary))
                 (exact-nonnegative-integer? confidence) (<= confidence 100))
      (raise-arguments-error 'odra-assessment-finding
                             "invalid bounded public assessment finding"))
    (values (copied kind) severity (copied location)
            (copied evidence-summary) confidence)))

(define (assessment-identity submission-id generation assessor-class
                             assessor-identity assessor-version rule-set-ref inputs)
  (sha256-datum
   (list 'curation-assessment submission-id generation assessor-class
         assessor-identity assessor-version rule-set-ref inputs)))

(struct odra-curation-assessment
  (format-version id submission-id submission-generation assessor-class
                  assessor-identity assessor-version rule-set-ref input-digests
                  outcome findings limitations evidence-ref completed-at)
  #:transparent
  #:guard
  (lambda (format-version id submission-id submission-generation assessor-class
                          assessor-identity assessor-version rule-set-ref inputs
                          outcome findings limitations evidence-ref completed-at _)
    (unless
        (and (= format-version current-curation-submission-format-version)
             (digest? id) (digest? submission-id)
             (exact-positive-integer? submission-generation)
             (memq assessor-class assessor-classes) (identity? assessor-identity)
             (or (not assessor-version) (bounded-text? assessor-version))
             (bounded-text? rule-set-ref)
             (canonical-digests? inputs maximum-assessment-inputs)
             (pair? inputs) (memq outcome assessment-outcomes)
             (list? findings) (<= (length findings) maximum-assessment-findings)
             (andmap odra-assessment-finding? findings)
             (list? limitations) (<= (length limitations) 64)
             (andmap identity? limitations)
             (equal? limitations
                     (sort (remove-duplicates limitations string=?) string<?))
             (or (not evidence-ref) (bounded-text? evidence-ref))
             (exact-nonnegative-integer? completed-at)
             (string=? id
                       (assessment-identity submission-id submission-generation
                                            assessor-class assessor-identity
                                            assessor-version rule-set-ref inputs)))
      (raise-arguments-error 'odra-curation-assessment
                             "invalid attributable bounded assessment"))
    (values format-version (copied id) (copied submission-id)
            submission-generation assessor-class (copied assessor-identity)
            (and assessor-version (copied assessor-version)) (copied rule-set-ref)
            (map copied inputs) outcome findings (map copied limitations)
            (and evidence-ref (copied evidence-ref)) completed-at)))

(struct odra-curation-submission-failure (code field expected actual)
  #:transparent)

(define (make-curation-submission catalog-id kind submitter-id release prior
                                  changes governance-revision)
  (odra-curation-submission
   1 (submission-identity catalog-id kind submitter-id release prior) 1
   catalog-id kind submitter-id release prior changes '() 'proposed
   governance-revision))

(define (make-curation-assessment submission-id generation assessor-class
                                  assessor-identity assessor-version rule-set-ref
                                  inputs outcome findings limitations evidence-ref
                                  completed-at)
  (odra-curation-assessment
   1 (assessment-identity submission-id generation assessor-class
                          assessor-identity assessor-version rule-set-ref inputs)
   submission-id generation assessor-class assessor-identity assessor-version
   rule-set-ref inputs outcome findings limitations evidence-ref completed-at))

(define transitions
  (hash 'proposed '(assessing closed)
        'assessing '(reviewable changes-requested rejected closed)
        'reviewable '(changes-requested rejected closed)
        'changes-requested '(proposed closed)
        'rejected '(closed)
        'accepted '(closed)
        'closed '()))

(define (transition-curation-submission submission state)
  (define current (odra-curation-submission-state submission))
  (if (memq state (hash-ref transitions current '()))
      (struct-copy odra-curation-submission submission [state state])
      (odra-curation-submission-failure
       (if (eq? state 'accepted) 'human-decision-required 'invalid-transition)
       'state current state)))

(define (replace-curation-submission-candidate submission release changes governance)
  (struct-copy odra-curation-submission submission
               [generation (add1 (odra-curation-submission-generation submission))]
               [release release]
               [changes changes]
               [assessment-ids '()]
               [state 'proposed]
               [governance-revision governance]))

(define (local-path-text? value)
  (and (string? value)
       (regexp-match? #px"^(?:/|\\\\|[A-Za-z]:)" value)))

(define (curation-assessment-redacted assessment)
  (struct-copy
   odra-curation-assessment assessment
   [findings
    (for/list ([finding (in-list (odra-curation-assessment-findings assessment))])
      (if (local-path-text? (odra-assessment-finding-location finding))
          (struct-copy odra-assessment-finding finding [location "<local-path>"])
          finding))]
   [evidence-ref
    (let ([reference (odra-curation-assessment-evidence-ref assessment)])
      (if (local-path-text? reference) "<local-evidence>" reference))]))
