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
         "contracts.rkt"
         "curation-assessment-store.rkt"
         "curation-decisions.rkt"
         "curation-history.rkt"
         "curation-records.rkt"
         "curation-submissions.rkt"
         "integrity.rkt"
         "publication-metadata.rkt"
         "snapshot-records.rkt"
         "snapshot-verification.rkt")

(provide
 (struct-out odra-package-catalog-publication-diff)
 (struct-out odra-package-catalog-publication)
 (struct-out odra-package-catalog-publication-output)
 (struct-out odra-package-catalog-publication-failure)
 package-curation-assertion-set-digest
 (contract-out
  [package-curation-assertion-set->module-bytes
   (-> (listof odra-package-curation-assertion?) immutable-bytes?)]
  [package-curation-assertion-set-module-parse
   (-> bytes? string?
       (or/c (listof odra-package-curation-assertion?)
             odra-record-diagnostic?))]
  [package-curation-assertion-set-module-load
   (-> path-string?
       (or/c (listof odra-package-curation-assertion?)
             odra-record-diagnostic?))]
  [build-package-catalog-publication
   (-> odra-package-catalog-profile?
       (listof odra-package-catalog-publisher-key?)
       (or/c #f odra-package-catalog-snapshot?)
       (listof odra-package-curation-assertion?)
       odra-authorized-curation-decision?
       odra-package-catalog-publication-proposal?
       procedure?
       (or/c odra-package-catalog-publication?
             odra-package-catalog-publication-failure?))]
  [verify-package-catalog-publication
   (-> odra-package-catalog-profile?
       (listof odra-package-catalog-publisher-key?)
       (or/c #f odra-package-catalog-snapshot?)
       odra-package-catalog-publication?
       (or/c #t odra-package-catalog-publication-failure?))]
  [package-catalog-publication-persist
   (-> path-string? odra-package-catalog-profile?
       (listof odra-package-catalog-publisher-key?)
       (or/c #f odra-package-catalog-snapshot?)
       odra-package-catalog-publication?
       (or/c odra-package-catalog-publication-output?
             odra-package-catalog-publication-failure?))]))

(define digest-pattern #px"^[0-9a-f]{64}$")
(define maximum-publication-assertions 4096)

(define (immutable-bytes? value)
  (and (bytes? value) (immutable? value)))

(define (digest? value)
  (and (string? value) (regexp-match? digest-pattern value)))

(define (canonical-digests? values)
  (and (list? values)
       (<= (length values) maximum-publication-assertions)
       (andmap digest? values)
       (equal? values (sort (remove-duplicates values string=?) string<?))))

(define (sha256-bytes->hex bytes)
  (bytes->hex-string (sha256-bytes (open-input-bytes bytes))))

(define (sha256-datum datum)
  (sha256-bytes->hex (record-datum->module-bytes datum)))

(struct odra-package-catalog-publication-diff
  (added changed removed unchanged)
  #:transparent
  #:guard
  (lambda (added changed removed unchanged _)
    (unless (andmap canonical-digests? (list added changed removed unchanged))
      (raise-arguments-error 'odra-package-catalog-publication-diff
                             "invalid bounded semantic publication diff"))
    (values added changed removed unchanged)))

(struct odra-package-catalog-publication
  (publication-proposal authorization assertion-history assertions assertion-set-bytes
      snapshot snapshot-bytes dry-run-diff publication-audit)
  #:transparent
  #:guard
  (lambda (proposal authorization assertion-history assertions assertion-bytes
                    snapshot snapshot-bytes dry-run-diff audit _)
    (unless
        (and (odra-package-catalog-publication-proposal? proposal)
             (odra-authorized-curation-decision? authorization)
             (list? assertion-history)
             (<= (length assertion-history)
                 maximum-package-curation-history-records)
             (andmap odra-package-curation-assertion? assertion-history)
             (list? assertions)
             (<= (length assertions) maximum-publication-assertions)
             (andmap odra-package-curation-assertion? assertions)
             (immutable-bytes? assertion-bytes)
             (odra-package-catalog-snapshot? snapshot)
             (immutable-bytes? snapshot-bytes)
             (odra-package-catalog-publication-diff? dry-run-diff)
             (odra-package-catalog-publication-audit? audit))
      (raise-arguments-error 'odra-package-catalog-publication
                             "invalid deterministic package catalog publication"))
    (values proposal authorization assertion-history assertions assertion-bytes
            snapshot snapshot-bytes dry-run-diff audit)))

(struct odra-package-catalog-publication-output
  (metadata-path assertion-set-path snapshot-path audit-path)
  #:transparent)

(struct odra-package-catalog-publication-failure (code field expected actual)
  #:transparent
  #:guard
  (lambda (code field expected actual _)
    (unless
        (and (memq code '(assertion-history decision history identity-conflict
                                            invalid-proposal metadata-size
                                            persistence policy publication
                                            signer signature snapshot))
             (symbol? field))
      (raise-arguments-error 'odra-package-catalog-publication-failure
                             "invalid catalog publication failure"))
    (values code field expected actual)))

(define (failure code field [expected #f] [actual #f])
  (odra-package-catalog-publication-failure code field expected actual))

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
        (map artifact->datum
             (odra-package-release-reference-artifact-set value))
        (odra-package-release-reference-dependency-set-digest value)
        (odra-package-release-reference-compatibility-digest value)
        (odra-package-release-reference-capability-set-digest value)
        (odra-package-release-reference-contribution-set-digest value)))

(define (assertion->datum value)
  (list (odra-package-curation-assertion-format-version value)
        (odra-package-curation-assertion-id value)
        (odra-package-curation-assertion-catalog-id value)
        (odra-package-curation-assertion-sequence value)
        (release->datum (odra-package-curation-assertion-release value))
        (odra-package-curation-assertion-decision-id value)
        (odra-package-curation-assertion-policy-id value)
        (odra-package-curation-assertion-status value)
        (odra-package-curation-assertion-status-reason value)
        (odra-package-curation-assertion-assessment-summary value)
        (odra-package-curation-assertion-first-snapshot-sequence value)
        (odra-package-curation-assertion-last-status-snapshot-sequence value)))

(define (assertion-order-key assertion)
  (define sequence
    (number->string
     (odra-package-curation-assertion-sequence assertion)))
  (string-append
   (odra-package-curation-assertion-id assertion)
   "/"
   (make-string (max 0 (- 20 (string-length sequence))) #\0)
   sequence))

(define (canonical-assertions assertions)
  (sort assertions string<? #:key assertion-order-key))

(define (package-curation-assertion-set->module-bytes assertions)
  (record-datum->module-bytes
   (list 'package-curation-assertion-set 1
         (map assertion->datum (canonical-assertions assertions)))))

(define (package-curation-assertion-set-digest assertions)
  (sha256-bytes->hex
   (package-curation-assertion-set->module-bytes assertions)))

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

(define (decode-assertion value)
  (match value
    [(list format id catalog sequence release decision policy status reason
           assessments first-snapshot last-snapshot)
     (odra-package-curation-assertion
      format id catalog sequence (decode-release release) decision policy status
      reason assessments first-snapshot last-snapshot)]))

(define (decode-assertion-set value)
  (match value
    [(list 'package-curation-assertion-set 1 assertions)
     (define decoded (map decode-assertion assertions))
     (unless (equal? decoded (canonical-assertions decoded))
       (raise-arguments-error 'package-curation-assertion-set
                              "assertions are not in canonical order"))
     decoded]
    [_
     (raise-arguments-error 'package-curation-assertion-set
                            "unsupported assertion set schema")]))

(define (package-curation-assertion-set-module-load path)
  (record-module-load path decode-assertion-set))

(define (package-curation-assertion-set-module-parse bytes source)
  (record-module-parse bytes source decode-assertion-set))

(define (latest-assertion history assertion-id)
  (for/fold ([latest #f]) ([candidate (in-list history)]
                           #:when
                           (string=? assertion-id
                                     (odra-package-curation-assertion-id candidate)))
    (if (or (not latest)
            (> (odra-package-curation-assertion-sequence candidate)
               (odra-package-curation-assertion-sequence latest)))
        candidate
        latest)))

(define (submission-status kind)
  (case kind
    [(add restore transfer update) 'admitted]
    [(deprecate) 'deprecated]
    [(withdraw) 'withdrawn]
    [(quarantine) 'quarantined]))

(define (new-assertion-id catalog-id release)
  (sha256-datum
   (list 'package-curation-assertion catalog-id
         (odra-package-release-reference-release-id release))))

(define (derive-assertion history submission decision proposal)
  (define kind (odra-curation-submission-kind submission))
  (define status (submission-status kind))
  (define snapshot-sequence
    (odra-package-catalog-publication-proposal-target-snapshot-sequence proposal))
  (define prior-id (odra-curation-submission-prior-assertion-id submission))
  (define previous (and prior-id (latest-assertion history prior-id)))
  (cond
    [(and prior-id (not previous))
     (failure 'assertion-history 'prior-assertion-id prior-id #f)]
    [(and (eq? status 'admitted)
          (not (string=?
                (odra-package-catalog-publication-proposal-status-reason proposal)
                "")))
     (failure 'invalid-proposal 'status-reason ""
              (odra-package-catalog-publication-proposal-status-reason proposal))]
    [(and (not (eq? status 'admitted))
          (string=?
           (odra-package-catalog-publication-proposal-status-reason proposal)
           ""))
     (failure 'invalid-proposal 'status-reason 'non-empty "")]
    [else
     (define release
       (or (odra-curation-submission-release submission)
           (and previous (odra-package-curation-assertion-release previous))))
     (define assertion-id
       (if (and previous (memq kind '(deprecate quarantine restore withdraw)))
           (odra-package-curation-assertion-id previous)
           (new-assertion-id
            (odra-curation-submission-catalog-id submission) release)))
     (define assertion-sequence
       (if (and previous (memq kind '(deprecate quarantine restore withdraw)))
           (add1 (odra-package-curation-assertion-sequence previous))
           1))
     (define first-snapshot
       (if (and previous (memq kind '(deprecate quarantine restore withdraw)))
           (odra-package-curation-assertion-first-snapshot-sequence previous)
           snapshot-sequence))
     (odra-package-curation-assertion
      1 assertion-id (odra-curation-submission-catalog-id submission)
      assertion-sequence release (odra-human-curation-decision-id decision)
      (odra-human-curation-decision-policy-id decision) status
      (if (eq? status 'admitted)
          ""
          (odra-package-catalog-publication-proposal-status-reason proposal))
      (odra-human-curation-decision-assessment-ids decision) first-snapshot
      snapshot-sequence)]))

(define (assertion-map assertions)
  (for/hash ([assertion (in-list assertions)])
    (values (odra-package-curation-assertion-id assertion) assertion)))

(define (publication-diff previous current)
  (define previous-map (assertion-map previous))
  (define current-map (assertion-map current))
  (define previous-ids (sort (hash-keys previous-map) string<?))
  (define current-ids (sort (hash-keys current-map) string<?))
  (odra-package-catalog-publication-diff
   (filter (lambda (id) (not (hash-has-key? previous-map id))) current-ids)
   (filter (lambda (id)
             (and (hash-has-key? previous-map id)
                  (not (equal? (hash-ref previous-map id)
                               (hash-ref current-map id)))))
           current-ids)
   (filter (lambda (id) (not (hash-has-key? current-map id))) previous-ids)
   (filter (lambda (id)
             (and (hash-has-key? previous-map id)
                  (equal? (hash-ref previous-map id)
                          (hash-ref current-map id))))
           current-ids)))

(define (proposal-history-valid? proposal previous)
  (and
   (= (odra-package-catalog-publication-proposal-target-snapshot-sequence proposal)
      (if previous
          (add1 (odra-package-catalog-snapshot-sequence previous))
          1))
   (equal?
    (odra-package-catalog-publication-proposal-previous-snapshot-id proposal)
    (and previous (odra-package-catalog-snapshot-id previous)))))

(define (proposal-decision-valid? proposal decision submission)
  (and
   (eq? (odra-human-curation-decision-outcome decision) 'accept)
   (string=?
    (odra-package-catalog-publication-proposal-decision-id proposal)
    (odra-human-curation-decision-id decision))
   (string=?
    (odra-package-catalog-publication-proposal-catalog-id proposal)
    (odra-curation-submission-catalog-id submission))
   (string=?
    (odra-package-catalog-publication-proposal-submission-id proposal)
    (odra-curation-submission-id submission))
   (=
    (odra-package-catalog-publication-proposal-submission-generation proposal)
    (odra-curation-submission-generation submission))
   (eq? (odra-curation-submission-state submission) 'accepted)))

(define (build-signed-snapshot profile publisher-keys previous proposal decision
                               assertion-bytes signer)
  (let loop ([metadata-size 1] [remaining-attempts 8])
    (define unsigned
      (odra-package-catalog-snapshot
       1 (make-string 64 #\0)
       (odra-package-catalog-publication-proposal-catalog-id proposal)
       (odra-package-catalog-publication-proposal-target-snapshot-sequence proposal)
       (odra-package-catalog-publication-proposal-previous-snapshot-id proposal)
       (odra-human-curation-decision-policy-id decision)
       (odra-package-catalog-publication-proposal-issued-at proposal)
       (odra-package-catalog-publication-proposal-expires-at proposal)
       (sha256-bytes->hex assertion-bytes)
       (odra-package-catalog-publication-proposal-advisory-set-digest proposal)
       metadata-size
       (odra-package-catalog-publication-proposal-publisher-authorization-id
        proposal)
       '()))
    (define identified
      (struct-copy odra-package-catalog-snapshot unsigned
                   [id (package-catalog-snapshot-content-digest unsigned)]))
    (define signatures
      (with-handlers ([exn:fail?
                       (lambda (exception)
                         (failure 'signer 'callback #f
                                  (exn-message exception)))])
        (signer
         (package-catalog-snapshot-signing-payload identified)
         (odra-package-catalog-publication-proposal-publisher-authorization-id
          proposal))))
    (cond
      [(odra-package-catalog-publication-failure? signatures) signatures]
      [else
       (with-handlers ([exn:fail?
                        (lambda (exception)
                          (failure 'signature 'signatures #f
                                   (exn-message exception)))])
         (define snapshot
           (struct-copy odra-package-catalog-snapshot identified
                        [signatures signatures]))
         (define observed-size
           (bytes-length (package-catalog-snapshot->module-bytes snapshot)))
         (cond
           [(> observed-size maximum-package-catalog-snapshot-metadata-bytes)
            (failure 'metadata-size 'snapshot
                     maximum-package-catalog-snapshot-metadata-bytes
                     observed-size)]
           [(not (= observed-size metadata-size))
            (if (positive? remaining-attempts)
                (loop observed-size (sub1 remaining-attempts))
                (failure 'metadata-size 'snapshot metadata-size observed-size))]
           [else
            (define verification
              (verify-package-catalog-snapshot
               profile publisher-keys previous
               (odra-package-catalog-publication-proposal-issued-at proposal)
               observed-size snapshot))
            (if (odra-package-catalog-snapshot-failure? verification)
                (failure
                 'signature 'snapshot #t
                 (odra-package-catalog-snapshot-failure-code verification))
                snapshot)]))])))

(define (assemble-publication profile publisher-keys previous history
                              authorization proposal signer assertion)
  (define decision (odra-authorized-curation-decision-decision authorization))
  (let-values ([(updated-history history-rejection)
                (reconcile-package-curation-assertion history assertion)])
    (cond
      [history-rejection
       (failure 'assertion-history 'assertion #f
                (odra-package-curation-history-failure-code history-rejection))]
      [else
       (define previous-assertions
         (package-curation-latest-assertions history))
       (define assertions
         (package-curation-latest-assertions updated-history))
       (define assertion-bytes
         (package-curation-assertion-set->module-bytes assertions))
       (cond
         [(> (bytes-length assertion-bytes)
             maximum-package-catalog-snapshot-metadata-bytes)
          (failure 'metadata-size 'assertion-set
                   maximum-package-catalog-snapshot-metadata-bytes
                   (bytes-length assertion-bytes))]
         [else
          (define snapshot
            (build-signed-snapshot profile publisher-keys previous proposal
                                   decision assertion-bytes signer))
          (if (odra-package-catalog-publication-failure? snapshot)
              snapshot
              (odra-package-catalog-publication
               proposal authorization updated-history assertions assertion-bytes
               snapshot (package-catalog-snapshot->module-bytes snapshot)
               (publication-diff previous-assertions assertions)
               (make-package-catalog-publication-audit
                'snapshot-built 'publication-service
                (odra-package-catalog-publication-proposal-publisher-authorization-id
                 proposal)
                (odra-human-curation-decision-id decision)
                (odra-package-catalog-publication-proposal-id proposal)
                (odra-package-catalog-snapshot-id snapshot)
                (odra-package-catalog-publication-proposal-issued-at
                 proposal))))])])))

(define (build-package-catalog-publication
         profile publisher-keys previous history authorization proposal signer)
  (define decision (odra-authorized-curation-decision-decision authorization))
  (define review (odra-authorized-curation-decision-review authorization))
  (define submission (odra-curation-review-submission review))
  (cond
    [(not (proposal-decision-valid? proposal decision submission))
     (failure 'decision 'proposal
              (odra-human-curation-decision-id decision)
              (odra-package-catalog-publication-proposal-decision-id proposal))]
    [(not (string=?
           (odra-package-catalog-profile-identity profile)
           (odra-package-catalog-publication-proposal-catalog-id proposal)))
     (failure 'invalid-proposal 'catalog-id
              (odra-package-catalog-profile-identity profile)
              (odra-package-catalog-publication-proposal-catalog-id proposal))]
    [(not (proposal-history-valid? proposal previous))
     (failure 'history 'snapshot
              (and previous (odra-package-catalog-snapshot-id previous))
              (odra-package-catalog-publication-proposal-previous-snapshot-id
               proposal))]
    [else
     (define assertion (derive-assertion history submission decision proposal))
     (if (odra-package-catalog-publication-failure? assertion)
         assertion
         (assemble-publication profile publisher-keys previous history
                               authorization proposal signer assertion))]))

(define (snapshot-matches-proposal? snapshot proposal decision)
  (and
   (string=?
    (odra-package-catalog-snapshot-catalog-id snapshot)
    (odra-package-catalog-publication-proposal-catalog-id proposal))
   (=
    (odra-package-catalog-snapshot-sequence snapshot)
    (odra-package-catalog-publication-proposal-target-snapshot-sequence proposal))
   (equal?
    (odra-package-catalog-snapshot-previous-snapshot-digest snapshot)
    (odra-package-catalog-publication-proposal-previous-snapshot-id proposal))
   (string=? (odra-package-catalog-snapshot-policy-id snapshot)
             (odra-human-curation-decision-policy-id decision))
   (= (odra-package-catalog-snapshot-issued-at snapshot)
      (odra-package-catalog-publication-proposal-issued-at proposal))
   (= (odra-package-catalog-snapshot-expires-at snapshot)
      (odra-package-catalog-publication-proposal-expires-at proposal))
   (string=?
    (odra-package-catalog-snapshot-advisory-set-digest snapshot)
    (odra-package-catalog-publication-proposal-advisory-set-digest proposal))
   (string=?
    (odra-package-catalog-snapshot-publisher-authorization-id snapshot)
    (odra-package-catalog-publication-proposal-publisher-authorization-id
     proposal))))

(define (audit-matches-publication? audit proposal decision snapshot)
  (and
   (eq? (odra-package-catalog-publication-audit-event audit) 'snapshot-built)
   (eq? (odra-package-catalog-publication-audit-actor-class audit)
        'publication-service)
   (string=?
    (odra-package-catalog-publication-audit-actor-id audit)
    (odra-package-catalog-publication-proposal-publisher-authorization-id
     proposal))
   (string=?
    (odra-package-catalog-publication-audit-decision-id audit)
    (odra-human-curation-decision-id decision))
   (string=?
    (odra-package-catalog-publication-audit-input-digest audit)
    (odra-package-catalog-publication-proposal-id proposal))
   (string=?
    (odra-package-catalog-publication-audit-output-digest audit)
    (odra-package-catalog-snapshot-id snapshot))))

(define (verify-package-catalog-publication profile publisher-keys previous
                                            publication)
  (define proposal
    (odra-package-catalog-publication-publication-proposal publication))
  (define authorization
    (odra-package-catalog-publication-authorization publication))
  (define decision (odra-authorized-curation-decision-decision authorization))
  (define snapshot (odra-package-catalog-publication-snapshot publication))
  (define assertions (odra-package-catalog-publication-assertions publication))
  (define assertion-bytes
    (odra-package-catalog-publication-assertion-set-bytes publication))
  (define audit
    (odra-package-catalog-publication-publication-audit publication))
  (cond
    [(not (snapshot-matches-proposal? snapshot proposal decision))
     (failure 'invalid-proposal 'snapshot #t #f)]
    [(not (audit-matches-publication? audit proposal decision snapshot))
     (failure 'publication 'audit #t #f)]
    [(not (equal? assertion-bytes
                  (package-curation-assertion-set->module-bytes assertions)))
     (failure 'snapshot 'assertion-set-bytes #f #f)]
    [(not (string=?
           (odra-package-catalog-snapshot-assertion-set-digest snapshot)
           (sha256-bytes->hex assertion-bytes)))
     (failure 'snapshot 'assertion-set-digest
              (sha256-bytes->hex assertion-bytes)
              (odra-package-catalog-snapshot-assertion-set-digest snapshot))]
    [(not (= (odra-package-catalog-snapshot-metadata-size snapshot)
             (bytes-length
              (odra-package-catalog-publication-snapshot-bytes publication))))
     (failure 'metadata-size 'snapshot
              (bytes-length
               (odra-package-catalog-publication-snapshot-bytes publication))
              (odra-package-catalog-snapshot-metadata-size snapshot))]
    [(not (equal?
           (odra-package-catalog-publication-snapshot-bytes publication)
           (package-catalog-snapshot->module-bytes snapshot)))
     (failure 'snapshot 'snapshot-bytes #f #f)]
    [(not (and
           (proposal-history-valid? proposal previous)
           (string=?
            (odra-package-catalog-publication-proposal-decision-id proposal)
            (odra-human-curation-decision-id decision))))
     (failure 'invalid-proposal 'history-or-decision #t #f)]
    [(not
      (for/or ([assertion (in-list assertions)])
        (string=? (odra-package-curation-assertion-decision-id assertion)
                  (odra-human-curation-decision-id decision))))
     (failure 'decision 'assertion #t #f)]
    [else
     (define verified
       (verify-package-catalog-snapshot
        profile publisher-keys previous
        (odra-package-catalog-publication-proposal-issued-at proposal)
        (bytes-length
         (odra-package-catalog-publication-snapshot-bytes publication))
        snapshot))
     (if (odra-package-catalog-snapshot-failure? verified)
         (failure 'signature 'snapshot #t
                  (odra-package-catalog-snapshot-failure-code verified))
         #t)]))

(define (audit->module-bytes audit)
  (record-datum->module-bytes
   (list 'package-catalog-publication-audit
         (odra-package-catalog-publication-audit-format-version audit)
         (odra-package-catalog-publication-audit-id audit)
         (odra-package-catalog-publication-audit-event audit)
         (odra-package-catalog-publication-audit-actor-class audit)
         (odra-package-catalog-publication-audit-actor-id audit)
         (odra-package-catalog-publication-audit-decision-id audit)
         (odra-package-catalog-publication-audit-input-digest audit)
         (odra-package-catalog-publication-audit-output-digest audit)
         (odra-package-catalog-publication-audit-recorded-at audit))))

(define (publish-immutable target bytes private-directories)
  (cond
    [(file-exists? target)
     (if (bytes=? bytes (file->bytes target))
         target
         (failure 'identity-conflict 'path target #f))]
    [else
     (define result
       (durable-file-publish target bytes
                             #:private-directories private-directories))
     (if (odra-durable-file-publication? result)
         target
         (failure 'persistence 'path target
                  (odra-durable-file-failure-code result)))]))

(define (package-catalog-publication-persist
         root profile publisher-keys previous publication)
  (define verification
    (verify-package-catalog-publication profile publisher-keys previous
                                        publication))
  (if (odra-package-catalog-publication-failure? verification)
      verification
      (let* ([snapshot (odra-package-catalog-publication-snapshot publication)]
             [complete-root (path->complete-path root)]
             [catalog-root (build-path complete-root "package-catalog")]
             [publication-root (build-path catalog-root "publications")]
             [identity-root
              (build-path publication-root
                          (odra-package-catalog-snapshot-catalog-id snapshot))]
             [sequence-root
              (build-path identity-root
                          (number->string
                           (odra-package-catalog-snapshot-sequence snapshot)))]
             [snapshot-root
              (build-path sequence-root
                          (odra-package-catalog-snapshot-id snapshot))]
             [private-directories
              (list complete-root catalog-root publication-root identity-root
                    sequence-root snapshot-root)]
             [assertion-path (build-path snapshot-root "assertions.rktd")]
             [metadata-path (build-path snapshot-root "catalog.rktd")]
             [snapshot-path (build-path snapshot-root "snapshot.rktd")]
             [audit-path (build-path snapshot-root "audit.rktd")]
             [metadata-result
              (publish-immutable
               metadata-path
               (package-catalog-publication-metadata->module-bytes
                (odra-package-catalog-publication-metadata
                 current-package-catalog-publication-metadata-format-version
                 profile publisher-keys))
               private-directories)]
             [assertion-result
              (publish-immutable
               assertion-path
               (odra-package-catalog-publication-assertion-set-bytes publication)
               private-directories)])
        (if (odra-package-catalog-publication-failure? metadata-result)
            metadata-result
            (if (odra-package-catalog-publication-failure? assertion-result)
                assertion-result
            (let ([snapshot-result
                   (publish-immutable
                    snapshot-path
                    (odra-package-catalog-publication-snapshot-bytes publication)
                    private-directories)])
              (if (odra-package-catalog-publication-failure? snapshot-result)
                  snapshot-result
                  (let ([audit-result
                         (publish-immutable
                          audit-path
                          (audit->module-bytes
                           (odra-package-catalog-publication-publication-audit
                            publication))
                          private-directories)])
                    (if (odra-package-catalog-publication-failure? audit-result)
                        audit-result
                        (odra-package-catalog-publication-output
                         metadata-result assertion-result snapshot-result
                         audit-result))))))))))
