#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         racket/string
         "../package_catalog/curation-records.rkt"
         "../package_catalog/curation-resolution.rkt"
         "../package_catalog/manual-resolution.rkt"
         "manifest-contracts.rkt"
         "state-records.rkt")

(provide
 (struct-out odra-package-installation-candidate)
 (struct-out odra-package-resolution-rejection)
 (contract-out
  [prepare-curated-package-installation
   (-> odra-package-manifest? odra-package-resolution? symbol? symbol?
       (or/c odra-package-installation-candidate?
             odra-package-resolution-rejection?))]
  [prepare-manual-package-installation
   (-> odra-package-manifest? odra-manual-package-resolved-source?
       odra-package-release-reference? (listof odra-package-curated-source?)
       symbol? symbol?
       (or/c odra-package-installation-candidate?
             odra-package-resolution-rejection?))]
  [prepare-bundled-package-installation
   (-> odra-package-manifest? odra-package-release-reference?
       symbol? symbol? string?
       (or/c odra-package-installation-candidate?
             odra-package-resolution-rejection?))]))

(struct odra-package-installation-candidate
  (manifest manifest-digest release artifact provenance curation-status)
  #:transparent)

(struct odra-package-resolution-rejection (code field expected actual)
  #:transparent
  #:guard
  (lambda (code field expected actual _)
    (unless (and (memq code '(artifact-mismatch manifest-mismatch
                                                package-mismatch
                                                publisher-mismatch
                                                source-mismatch target-mismatch
                                                version-mismatch))
                 (symbol? field))
      (raise-arguments-error 'odra-package-resolution-rejection
                             "invalid generic package resolution rejection"))
    (values code field expected actual)))

(define (reject code field expected actual)
  (odra-package-resolution-rejection code field expected actual))

(define (manifest-target? manifest platform architecture)
  (for/or ([target (in-list (odra-package-manifest-targets manifest))])
    (and (eq? platform (odra-package-target-platform target))
         (eq? architecture (odra-package-target-architecture target)))))

(define (release-consistency-rejection manifest release artifact platform architecture)
  (cond
    [(not artifact)
     (reject 'target-mismatch 'artifact (list platform architecture) #f)]
    [(not (manifest-target? manifest platform architecture))
     (reject 'target-mismatch 'manifest-targets
             (list platform architecture)
             (map (lambda (target)
                    (list (odra-package-target-platform target)
                          (odra-package-target-architecture target)))
                  (odra-package-manifest-targets manifest)))]
    [(not (string=? (odra-package-manifest-package-id manifest)
                    (odra-package-release-reference-package-id release)))
     (reject 'package-mismatch 'package-id
             (odra-package-release-reference-package-id release)
             (odra-package-manifest-package-id manifest))]
    [(not (string=? (odra-package-manifest-version manifest)
                    (odra-package-release-reference-version release)))
     (reject 'version-mismatch 'version
             (odra-package-release-reference-version release)
             (odra-package-manifest-version manifest))]
    [(not (string=? (odra-package-manifest-publisher-id manifest)
                    (odra-package-release-reference-publisher-id release)))
     (reject 'publisher-mismatch 'publisher-id
             (odra-package-release-reference-publisher-id release)
             (odra-package-manifest-publisher-id manifest))]
    [(not (string=? (odra-package-manifest-source-revision manifest)
                    (odra-package-release-reference-source-revision release)))
     (reject 'source-mismatch 'source-revision
             (odra-package-release-reference-source-revision release)
             (odra-package-manifest-source-revision manifest))]
    [(not (string=? (package-manifest-digest manifest)
                    (odra-package-release-reference-manifest-digest release)))
     (reject 'manifest-mismatch 'manifest-digest
             (odra-package-release-reference-manifest-digest release)
             (package-manifest-digest manifest))]
    [else #f]))

(define (prepare-curated-package-installation manifest resolution platform architecture)
  (define release (odra-package-resolution-release resolution))
  (define artifact (odra-package-resolution-artifact resolution))
  (define rejection
    (release-consistency-rejection manifest release artifact platform architecture))
  (if rejection
      rejection
      (let ([catalog-id
             (odra-package-resolution-selected-catalog-id resolution)]
            [snapshot-id
             (odra-package-resolution-selected-snapshot-id resolution)]
            [assertion
             (odra-package-resolution-selected-assertion resolution)])
        (odra-package-installation-candidate
         manifest (package-manifest-digest manifest) release artifact
         (odra-package-provenance
          'catalog catalog-id snapshot-id
          (odra-package-curation-assertion-id assertion)
          (odra-package-release-reference-publisher-id release)
          (odra-package-release-reference-source-revision release))
         (odra-package-resolution-curation-status resolution)))))

(define (resolved-source-uri resolved)
  (define source-ref
    (odra-manual-package-resolved-source-source-ref resolved))
  (if (absolute-path? (string->path source-ref))
      (string-append "file://" source-ref)
      source-ref))

(define (matching-assertions sources release)
  (sort
   (for*/list ([source (in-list sources)]
               [assertion
                (in-list (odra-package-curated-source-assertions source))]
               #:when
               (and (memq (odra-package-curation-assertion-status assertion)
                          '(admitted deprecated))
                    (same-package-release?
                     release (odra-package-curation-assertion-release assertion))))
     assertion)
   string<? #:key odra-package-curation-assertion-id))

(define (prepare-manual-package-installation
         manifest resolved release curated-sources platform architecture)
  (define artifact (package-release-artifact release platform architecture))
  (define rejection
    (release-consistency-rejection manifest release artifact platform architecture))
  (cond
    [rejection rejection]
    [(not (string=? (resolved-source-uri resolved)
                    (odra-package-release-reference-source-uri release)))
     (reject 'source-mismatch 'source-uri
             (odra-package-release-reference-source-uri release)
             (resolved-source-uri resolved))]
    [(and (odra-manual-package-resolved-source-manifest-digest resolved)
          (not (string=?
                (odra-manual-package-resolved-source-manifest-digest resolved)
                (package-manifest-digest manifest))))
     (reject 'manifest-mismatch 'resolved-manifest-digest
             (odra-manual-package-resolved-source-manifest-digest resolved)
             (package-manifest-digest manifest))]
    [(not (string=?
           (odra-manual-package-resolved-source-artifact-digest resolved)
           (odra-package-artifact-reference-digest artifact)))
     (reject 'artifact-mismatch 'artifact-digest
             (odra-package-artifact-reference-digest artifact)
             (odra-manual-package-resolved-source-artifact-digest resolved))]
    [(not (= (odra-manual-package-resolved-source-content-bytes resolved)
             (odra-package-artifact-reference-size artifact)))
     (reject 'artifact-mismatch 'artifact-size
             (odra-package-artifact-reference-size artifact)
             (odra-manual-package-resolved-source-content-bytes resolved))]
    [else
     (define matches (matching-assertions curated-sources release))
     (odra-package-installation-candidate
      manifest (package-manifest-digest manifest) release artifact
      (odra-package-provenance
       'manual #f
       (odra-manual-package-resolved-source-artifact-digest resolved)
       (odra-manual-package-resolved-source-id resolved)
       (odra-package-release-reference-publisher-id release)
       (odra-manual-package-resolved-source-resolved-source-revision resolved))
      (if (null? matches) 'manual-uncurated 'matches-curated-release))]))

(define (prepare-bundled-package-installation
         manifest release platform architecture distribution-id)
  (define artifact (package-release-artifact release platform architecture))
  (define rejection
    (release-consistency-rejection
     manifest release artifact platform architecture))
  (if rejection
      rejection
      (odra-package-installation-candidate
       manifest (package-manifest-digest manifest) release artifact
       (odra-package-provenance
        'bundled distribution-id #f #f
        (odra-package-release-reference-publisher-id release)
        (odra-package-release-reference-source-revision release))
       'bundled-official)))
