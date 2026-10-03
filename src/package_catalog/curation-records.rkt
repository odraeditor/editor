#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         racket/string
         "../storage/record-codec.rkt")

(provide
 current-package-curation-format-version
 maximum-package-release-artifacts
 maximum-package-artifact-locations
 maximum-package-assessment-summary
 (struct-out odra-package-artifact-reference)
 (struct-out odra-package-release-reference)
 (struct-out odra-package-curation-assertion)
 (contract-out
  [same-package-release?
   (-> odra-package-release-reference? odra-package-release-reference? boolean?)]
  [package-release-artifact
   (-> odra-package-release-reference? symbol? symbol?
       (or/c #f odra-package-artifact-reference?))]))

(define current-package-curation-format-version 1)
(define maximum-package-release-artifacts 16)
(define maximum-package-artifact-locations 16)
(define maximum-package-assessment-summary 64)
(define maximum-text-bytes 4096)

(define digest-pattern #px"^[0-9a-f]{64}$")
(define identity-pattern #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")
(define version-pattern
  #px"^(?:0|[1-9][0-9]*)\\.(?:0|[1-9][0-9]*)\\.(?:0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?$")
(define revision-pattern #px"^[0-9a-f]{40}(?:[0-9a-f]{24})?$")
(define admitted-platforms '(darwin linux windows))
(define admitted-architectures '(aarch64 x86-64))
(define reproducibility-states '(mismatch not-required reproduced unverified))
(define assertion-statuses '(admitted deprecated quarantined withdrawn))

(define (bounded-text? value #:empty? [empty? #f])
  (and (string? value)
       (or empty? (positive? (string-length value)))
       (not (string-contains? value (string #\nul)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum-text-bytes)))

(define (identity? value)
  (and (bounded-text? value)
       (<= (bytes-length (string->bytes/utf-8 value)) 128)
       (regexp-match? identity-pattern value)))

(define (digest? value)
  (and (string? value) (regexp-match? digest-pattern value)))

(define (version? value)
  (and (string? value) (regexp-match? version-pattern value)))

(define (source-uri? value)
  (and (bounded-text? value)
       (or (regexp-match? #px"^https://[^/@?#]+(?::[0-9]+)?/[^?#]*$" value)
           (regexp-match? #px"^ssh://[^/@?#]+@?[^/?#]+(?::[0-9]+)?/[^?#]+$" value)
           (regexp-match? #px"^file:///[^?#]+$" value))))

(define (artifact-uri? value)
  (and (bounded-text? value)
       (or (regexp-match? #px"^https://[^/@?#]+(?::[0-9]+)?/[^?#]*$" value)
           (regexp-match? #px"^[a-zA-Z0-9][a-zA-Z0-9._/-]*$" value))))

(define (copied value)
  (if (string? value) (record-copied-text value) value))

(struct odra-package-artifact-reference
  (platform architecture uri-set digest size builder-id provenance-ref
            reproducibility-state)
  #:transparent
  #:guard
  (lambda (platform architecture uri-set digest size builder-id provenance-ref
                    reproducibility-state _)
    (unless
        (and (memq platform admitted-platforms)
             (memq architecture admitted-architectures)
             (list? uri-set)
             (pair? uri-set)
             (<= (length uri-set) maximum-package-artifact-locations)
             (andmap artifact-uri? uri-set)
             (equal? uri-set (sort (remove-duplicates uri-set string=?) string<?))
             (digest? digest)
             (exact-positive-integer? size)
             (<= size (expt 2 40))
             (or (not builder-id) (identity? builder-id))
             (or (not provenance-ref) (bounded-text? provenance-ref))
             (memq reproducibility-state reproducibility-states))
      (raise-arguments-error 'odra-package-artifact-reference
                             "invalid immutable package artifact reference"))
    (values platform architecture (map copied uri-set) (copied digest) size
            (and builder-id (copied builder-id))
            (and provenance-ref (copied provenance-ref))
            reproducibility-state)))

(define (artifact-key artifact)
  (format "~a/~a"
          (odra-package-artifact-reference-platform artifact)
          (odra-package-artifact-reference-architecture artifact)))

(struct odra-package-release-reference
  (format-version package-id release-id version publisher-id source-uri
      source-revision source-label manifest-digest artifact-set
      dependency-set-digest compatibility-digest capability-set-digest
      contribution-set-digest)
  #:transparent
  #:guard
  (lambda (format-version package-id release-id version publisher-id source-uri
                          source-revision source-label manifest-digest artifact-set
                          dependency-set-digest compatibility-digest
                          capability-set-digest contribution-set-digest _)
    (define artifact-keys
      (and (list? artifact-set) (map artifact-key artifact-set)))
    (unless
        (and (= format-version current-package-curation-format-version)
             (identity? package-id)
             (digest? release-id)
             (version? version)
             (identity? publisher-id)
             (source-uri? source-uri)
             (string? source-revision)
             (regexp-match? revision-pattern source-revision)
             (or (not source-label) (bounded-text? source-label))
             (digest? manifest-digest)
             (list? artifact-set)
             (pair? artifact-set)
             (<= (length artifact-set) maximum-package-release-artifacts)
             (andmap odra-package-artifact-reference? artifact-set)
             (equal? artifact-keys
                     (sort (remove-duplicates artifact-keys string=?) string<?))
             (andmap digest?
                     (list dependency-set-digest compatibility-digest
                           capability-set-digest contribution-set-digest)))
      (raise-arguments-error 'odra-package-release-reference
                             "invalid exact package release projection"))
    (values format-version (copied package-id) (copied release-id)
            (copied version) (copied publisher-id) (copied source-uri)
            (copied source-revision) (and source-label (copied source-label))
            (copied manifest-digest)
            (for/list ([artifact (in-list artifact-set)]) artifact)
            (copied dependency-set-digest) (copied compatibility-digest)
            (copied capability-set-digest) (copied contribution-set-digest))))

(struct odra-package-curation-assertion
  (format-version id catalog-id sequence release decision-id policy-id status
      status-reason assessment-summary first-snapshot-sequence
      last-status-snapshot-sequence)
  #:transparent
  #:guard
  (lambda (format-version id catalog-id sequence release decision-id policy-id
                          status status-reason assessment-summary
                          first-snapshot-sequence last-status-snapshot-sequence _)
    (unless
        (and (= format-version current-package-curation-format-version)
             (digest? id)
             (digest? catalog-id)
             (exact-positive-integer? sequence)
             (odra-package-release-reference? release)
             (identity? decision-id)
             (identity? policy-id)
             (memq status assertion-statuses)
             (bounded-text? status-reason #:empty? #t)
             (if (eq? status 'admitted)
                 #t
                 (positive? (string-length status-reason)))
             (list? assessment-summary)
             (<= (length assessment-summary) maximum-package-assessment-summary)
             (andmap identity? assessment-summary)
             (equal? assessment-summary
                     (sort (remove-duplicates assessment-summary string=?) string<?))
             (exact-positive-integer? first-snapshot-sequence)
             (exact-positive-integer? last-status-snapshot-sequence)
             (<= first-snapshot-sequence last-status-snapshot-sequence))
      (raise-arguments-error 'odra-package-curation-assertion
                             "invalid attributable curation assertion"))
    (values format-version (copied id) (copied catalog-id) sequence release
            (copied decision-id) (copied policy-id) status
            (copied status-reason) (map copied assessment-summary)
            first-snapshot-sequence last-status-snapshot-sequence)))

(define (same-package-release? left right)
  (equal? left right))

(define (package-release-artifact release platform architecture)
  (for/first
      ([artifact (in-list (odra-package-release-reference-artifact-set release))]
       #:when
       (and (eq? platform (odra-package-artifact-reference-platform artifact))
            (eq? architecture
                 (odra-package-artifact-reference-architecture artifact))))
    artifact))
