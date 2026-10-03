#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         racket/match
         racket/string
         "../package_catalog/curation-records.rkt"
         "../storage/record-codec.rkt")

(provide
 current-package-distribution-format-version
 maximum-bundled-packages
 (struct-out odra-bundled-package)
 (struct-out odra-package-distribution)
 (contract-out
  [package-distribution->module-bytes
   (-> odra-package-distribution? immutable-bytes?)]
  [package-distribution-module-parse
   (-> bytes? path-string?
       (or/c odra-package-distribution? odra-record-diagnostic?))]
  [package-distribution-module-load
   (-> path-string?
       (or/c odra-package-distribution? odra-record-diagnostic?))]))

(define current-package-distribution-format-version 1)
(define maximum-bundled-packages 256)
(define identity-pattern #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")
(define version-pattern
  #px"^(?:0|[1-9][0-9]*)[.](?:0|[1-9][0-9]*)[.](?:0|[1-9][0-9]*)(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?$")

(define (immutable-bytes? value)
  (and (bytes? value) (immutable? value)))

(define (bounded-text? value maximum)
  (and (string? value)
       (positive? (string-length value))
       (not (string-contains? value (string #\nul)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(define (identity? value)
  (and (bounded-text? value maximum-record-identity-bytes)
       (regexp-match? identity-pattern value)))

(define (version? value)
  (and (bounded-text? value maximum-record-identity-bytes)
       (regexp-match? version-pattern value)))

(define (relative-path? value)
  (and (bounded-text? value maximum-record-path-bytes)
       (not (absolute-path? (string->path value)))
       (for/and ([part (in-list (string-split value "/"))])
         (not (member part '("" "." ".."))))))

(define (copied value)
  (if (string? value) (record-copied-text value) value))

(struct odra-bundled-package
  (release manifest-path archive-path enabled?)
  #:transparent
  #:guard
  (lambda (release manifest-path archive-path enabled? _)
    (unless (and (odra-package-release-reference? release)
                 (relative-path? manifest-path)
                 (relative-path? archive-path)
                 (boolean? enabled?))
      (raise-arguments-error 'odra-bundled-package
                             "invalid bundled package declaration"))
    (values release (copied manifest-path) (copied archive-path) enabled?)))

(define (bundled-package-key package)
  (odra-package-release-reference-package-id
   (odra-bundled-package-release package)))

(struct odra-package-distribution
  (format-version id runtime-api-version packages)
  #:transparent
  #:guard
  (lambda (format-version id runtime-api-version packages _)
    (define package-ids
      (and (list? packages)
           (andmap odra-bundled-package? packages)
           (map bundled-package-key packages)))
    (unless (and (= format-version current-package-distribution-format-version)
                 (identity? id)
                 (version? runtime-api-version)
                 (list? packages)
                 (<= (length packages) maximum-bundled-packages)
                 (andmap odra-bundled-package? packages)
                 (= (length package-ids)
                    (length (remove-duplicates package-ids string=?))))
      (raise-arguments-error 'odra-package-distribution
                             "invalid canonical package distribution"))
    (values format-version (copied id) (copied runtime-api-version) packages)))

(define (artifact->datum artifact)
  (list (odra-package-artifact-reference-platform artifact)
        (odra-package-artifact-reference-architecture artifact)
        (odra-package-artifact-reference-uri-set artifact)
        (odra-package-artifact-reference-digest artifact)
        (odra-package-artifact-reference-size artifact)
        (odra-package-artifact-reference-builder-id artifact)
        (odra-package-artifact-reference-provenance-ref artifact)
        (odra-package-artifact-reference-reproducibility-state artifact)))

(define (release->datum release)
  (list (odra-package-release-reference-format-version release)
        (odra-package-release-reference-package-id release)
        (odra-package-release-reference-release-id release)
        (odra-package-release-reference-version release)
        (odra-package-release-reference-publisher-id release)
        (odra-package-release-reference-source-uri release)
        (odra-package-release-reference-source-revision release)
        (odra-package-release-reference-source-label release)
        (odra-package-release-reference-manifest-digest release)
        (map artifact->datum
             (odra-package-release-reference-artifact-set release))
        (odra-package-release-reference-dependency-set-digest release)
        (odra-package-release-reference-compatibility-digest release)
        (odra-package-release-reference-capability-set-digest release)
        (odra-package-release-reference-contribution-set-digest release)))

(define (package->datum package)
  (list (release->datum (odra-bundled-package-release package))
        (odra-bundled-package-manifest-path package)
        (odra-bundled-package-archive-path package)
        (odra-bundled-package-enabled? package)))

(define (package-distribution->module-bytes distribution)
  (record-datum->module-bytes
   (list 'odra-package-distribution
         '#:format-version
         (odra-package-distribution-format-version distribution)
         '#:id (odra-package-distribution-id distribution)
         '#:runtime-api-version
         (odra-package-distribution-runtime-api-version distribution)
         '#:packages
         (map package->datum (odra-package-distribution-packages distribution)))))

(define (datum->artifact datum)
  (match datum
    [(list platform architecture uri-set digest size builder-id provenance-ref
           reproducibility-state)
     (odra-package-artifact-reference
      platform architecture uri-set digest size builder-id provenance-ref
      reproducibility-state)]
    [_ (raise-arguments-error 'odra-package-distribution
                              "invalid artifact reference")]))

(define (datum->release datum)
  (match datum
    [(list format-version package-id release-id version publisher-id source-uri
           source-revision source-label manifest-digest artifact-set
           dependency-set-digest compatibility-digest capability-set-digest
           contribution-set-digest)
     (odra-package-release-reference
      format-version package-id release-id version publisher-id source-uri
      source-revision source-label manifest-digest
      (map datum->artifact artifact-set)
      dependency-set-digest compatibility-digest capability-set-digest
      contribution-set-digest)]
    [_ (raise-arguments-error 'odra-package-distribution
                              "invalid package release")]))

(define (datum->package datum)
  (match datum
    [(list release manifest-path archive-path enabled?)
     (odra-bundled-package
      (datum->release release) manifest-path archive-path enabled?)]
    [_ (raise-arguments-error 'odra-package-distribution
                              "invalid bundled package")]))

(define (decode-distribution datum)
  (match datum
    [(list 'odra-package-distribution
           '#:format-version format-version
           '#:id id
           '#:runtime-api-version runtime-api-version
           '#:packages packages)
     (odra-package-distribution
      format-version id runtime-api-version (map datum->package packages))]
    [_ (raise-arguments-error 'odra-package-distribution
                              "unsupported package distribution schema")]))

(define (package-distribution-module-parse bytes source)
  (record-module-parse bytes source decode-distribution))

(define (package-distribution-module-load path)
  (record-module-load path decode-distribution))
