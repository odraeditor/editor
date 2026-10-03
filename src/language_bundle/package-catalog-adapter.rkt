#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/contract/base
         racket/list
         "../package_catalog/curation-records.rkt"
         "../storage/record-codec.rkt"
         "catalog-contracts.rkt")

(provide
 (struct-out odra-language-bundle-package-projection)
 (struct-out odra-language-bundle-package-projection-failure)
 odra-language-bundle-curated-candidate?
 odra-language-bundle-curated-candidate-entry
 odra-language-bundle-curated-candidate-release
 odra-language-bundle-curated-candidate-assertion
 odra-language-bundle-curated-candidate-artifact
 (contract-out
  [language-bundle-catalog-entry-projection
   (-> odra-catalog-entry? odra-language-bundle-package-projection?)]
  [language-bundle-catalog-entry->curation-assertion
   (-> odra-catalog-entry? string? string? string? string? (or/c #f string?)
       (listof odra-package-artifact-reference?) string? string?
       exact-positive-integer?
       (or/c odra-package-curation-assertion?
             odra-language-bundle-package-projection-failure?))]
  [verify-language-bundle-curated-release
   (-> odra-catalog-entry? odra-package-curation-assertion? symbol? symbol?
       (or/c odra-language-bundle-curated-candidate?
             odra-language-bundle-package-projection-failure?))]))

(struct odra-language-bundle-package-projection
  (package-id version manifest-digest dependency-set-digest compatibility-digest
              capability-set-digest contribution-set-digest)
  #:transparent)

(struct odra-language-bundle-package-projection-failure
  (code field expected actual)
  #:transparent)

;; The constructor stays private so downstream lifecycle code can receive only
;; a candidate produced by the complete projection verifier below.
(struct odra-language-bundle-curated-candidate
  (entry release assertion artifact)
  #:transparent)

(define (sha256-datum datum)
  (bytes->hex-string
   (sha256-bytes
    (open-input-bytes (record-datum->module-bytes datum)))))

(define (target->datum target)
  (list (odra-catalog-target-platform target)
        (odra-catalog-target-architecture target)))

(define (dependency->datum dependency)
  (list (odra-catalog-dependency-summary-id dependency)
        (odra-catalog-dependency-summary-minimum dependency)
        (odra-catalog-dependency-summary-maximum dependency)
        (odra-catalog-dependency-summary-optional? dependency)
        (odra-catalog-dependency-summary-facets dependency)))

(define (artifact->datum artifact)
  (list (odra-package-artifact-reference-platform artifact)
        (odra-package-artifact-reference-architecture artifact)
        (odra-package-artifact-reference-uri-set artifact)
        (odra-package-artifact-reference-digest artifact)
        (odra-package-artifact-reference-size artifact)
        (odra-package-artifact-reference-builder-id artifact)
        (odra-package-artifact-reference-provenance-ref artifact)
        (odra-package-artifact-reference-reproducibility-state artifact)))

(define (artifact-selector artifact)
  (list (odra-package-artifact-reference-platform artifact)
        (odra-package-artifact-reference-architecture artifact)))

(define (entry-selectors entry)
  (map target->datum (odra-catalog-entry-targets entry)))

(define (release-selectors release)
  (map artifact-selector
       (odra-package-release-reference-artifact-set release)))

(define (projection-digest domain payload)
  (sha256-datum (list domain current-package-curation-format-version payload)))

(define (language-bundle-catalog-entry-projection entry)
  (odra-language-bundle-package-projection
   (odra-catalog-entry-bundle-id entry)
   (odra-catalog-entry-version entry)
   (odra-catalog-entry-manifest-digest entry)
   (projection-digest
    'language-bundle-dependencies
    (map dependency->datum (odra-catalog-entry-dependencies entry)))
   (projection-digest
    'language-bundle-compatibility
    (list (odra-catalog-entry-api-minimum entry)
          (odra-catalog-entry-api-maximum entry)
          (entry-selectors entry)))
   (projection-digest
    'language-bundle-capabilities
    (odra-catalog-entry-authorities entry))
   (projection-digest
    'language-bundle-contributions
    (odra-catalog-entry-facets entry))))

(define (release-content-digest release)
  (sha256-datum
   (list 'package-release
         (odra-package-release-reference-format-version release)
         (odra-package-release-reference-package-id release)
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
         (odra-package-release-reference-contribution-set-digest release))))

(define (assertion-identity catalog-id release-id)
  (sha256-datum (list 'package-curation-assertion catalog-id release-id)))

(define (failure code field expected actual)
  (odra-language-bundle-package-projection-failure
   code field expected actual))

(define (language-bundle-catalog-entry->curation-assertion
         entry catalog-id publisher-id source-uri source-revision source-label
         artifact-set decision-id policy-id snapshot-sequence)
  (define expected-selectors (entry-selectors entry))
  (define actual-selectors (map artifact-selector artifact-set))
  (cond
    [(not (equal? expected-selectors actual-selectors))
     (failure 'projection-mismatch 'artifact-selectors
              expected-selectors actual-selectors)]
    [else
     (define projection (language-bundle-catalog-entry-projection entry))
     (define provisional
       (odra-package-release-reference
        current-package-curation-format-version
        (odra-language-bundle-package-projection-package-id projection)
        (make-string 64 #\0)
        (odra-language-bundle-package-projection-version projection)
        publisher-id source-uri source-revision source-label
        (odra-language-bundle-package-projection-manifest-digest projection)
        artifact-set
        (odra-language-bundle-package-projection-dependency-set-digest projection)
        (odra-language-bundle-package-projection-compatibility-digest projection)
        (odra-language-bundle-package-projection-capability-set-digest projection)
        (odra-language-bundle-package-projection-contribution-set-digest projection)))
     (define release
       (struct-copy odra-package-release-reference provisional
                    [release-id (release-content-digest provisional)]))
     (odra-package-curation-assertion
      current-package-curation-format-version
      (assertion-identity catalog-id
                          (odra-package-release-reference-release-id release))
      catalog-id 1 release decision-id policy-id
      (if (odra-catalog-entry-deprecated? entry) 'deprecated 'admitted)
      (if (odra-catalog-entry-deprecated? entry)
          "Deprecated by the source language-bundle catalog"
          "")
      '() snapshot-sequence snapshot-sequence)]))

(define (mismatch field expected actual)
  (and (not (equal? expected actual))
       (failure 'projection-mismatch field expected actual)))

(define (verify-language-bundle-curated-release
         entry assertion platform architecture)
  (define release (odra-package-curation-assertion-release assertion))
  (define projection (language-bundle-catalog-entry-projection entry))
  (define expected-status
    (if (odra-catalog-entry-deprecated? entry) 'deprecated 'admitted))
  (define artifact (package-release-artifact release platform architecture))
  (or
   (mismatch 'status expected-status
             (odra-package-curation-assertion-status assertion))
   (mismatch 'package-id
             (odra-language-bundle-package-projection-package-id projection)
             (odra-package-release-reference-package-id release))
   (mismatch 'version
             (odra-language-bundle-package-projection-version projection)
             (odra-package-release-reference-version release))
   (mismatch 'manifest-digest
             (odra-language-bundle-package-projection-manifest-digest projection)
             (odra-package-release-reference-manifest-digest release))
   (mismatch 'dependency-set-digest
             (odra-language-bundle-package-projection-dependency-set-digest projection)
             (odra-package-release-reference-dependency-set-digest release))
   (mismatch 'compatibility-digest
             (odra-language-bundle-package-projection-compatibility-digest projection)
             (odra-package-release-reference-compatibility-digest release))
   (mismatch 'capability-set-digest
             (odra-language-bundle-package-projection-capability-set-digest projection)
             (odra-package-release-reference-capability-set-digest release))
   (mismatch 'contribution-set-digest
             (odra-language-bundle-package-projection-contribution-set-digest projection)
             (odra-package-release-reference-contribution-set-digest release))
   (mismatch 'artifact-selectors (entry-selectors entry)
             (release-selectors release))
   (and (not artifact)
        (failure 'unsupported-target 'artifact
                 (list platform architecture) #f))
   (mismatch 'release-id (release-content-digest release)
             (odra-package-release-reference-release-id release))
   (mismatch 'assertion-id
             (assertion-identity
              (odra-package-curation-assertion-catalog-id assertion)
              (odra-package-release-reference-release-id release))
             (odra-package-curation-assertion-id assertion))
   (odra-language-bundle-curated-candidate
    entry release assertion artifact)))
