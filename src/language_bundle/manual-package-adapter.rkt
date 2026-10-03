#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/contract/base
         racket/list
         (prefix-in bundle: "../command/language-bundles.rkt")
         "../package_catalog/curation-records.rkt"
         "../package_catalog/curation-resolution.rkt"
         "../package_catalog/manual-persistence.rkt"
         "../package_catalog/manual-records.rkt"
         "../package_catalog/manual-resolution.rkt"
         "activation-candidate.rkt"
         "lifecycle.rkt")

(provide
 (struct-out odra-manual-language-bundle-failure)
 odra-manual-language-bundle-candidate?
 odra-manual-language-bundle-candidate-acquisition
 odra-manual-language-bundle-candidate-install-request
 odra-manual-language-bundle-candidate-matching-assertions
 (contract-out
  [prepare-manual-language-bundle-installation
   (-> odra-manual-package-resolved-source?
       odra-package-release-reference?
       (listof odra-package-curated-source?)
       odra-bundle-preparation-input?
       bytes? symbol? symbol? string?
       (or/c odra-manual-language-bundle-candidate?
             odra-manual-language-bundle-failure?))]
  [install-manual-language-bundle!
   (-> path-string? bundle-lifecycle-manager?
       odra-manual-language-bundle-candidate?
       (or/c odra-bundle-lifecycle-result?
             odra-manual-package-persistence-failure?))]))

(struct odra-manual-language-bundle-failure (code field expected actual)
  #:transparent
  #:guard
  (lambda (code field expected actual _)
    (unless (and (memq code '(artifact-mismatch manifest-mismatch
                                                package-mismatch
                                                publisher-mismatch
                                                source-mismatch target-mismatch
                                                version-mismatch))
                 (symbol? field))
      (raise-arguments-error 'odra-manual-language-bundle-failure
                             "invalid manual bundle preparation failure"))
    (values code field expected actual)))

;; The constructor is private: installation accepts only a candidate that has
;; crossed every manual-content, manifest, release, and bundle identity check.
(struct odra-manual-language-bundle-candidate
  (acquisition install-request matching-assertions)
  #:transparent)

(define (sha256-bytes-hex value)
  (bytes->hex-string (sha256-bytes (open-input-bytes value))))

(define (failure code field expected actual)
  (odra-manual-language-bundle-failure code field expected actual))

(define (expected-input-source kind)
  (if (eq? kind 'development-directory) 'project 'personal))

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

(define (prepare-manual-language-bundle-installation
         resolved release curated-sources input manifest-bytes
         platform architecture authority-provenance)
  (define artifact (package-release-artifact release platform architecture))
  (define value (odra-bundle-preparation-input-bundle input))
  (define source-kind
    (odra-manual-package-resolved-source-source-kind resolved))
  (define expected-source (expected-input-source source-kind))
  (define manifest-digest (sha256-bytes-hex manifest-bytes))
  (define resolved-manifest
    (odra-manual-package-resolved-source-manifest-digest resolved))
  (cond
    [(not artifact)
     (failure 'target-mismatch 'artifact (list platform architecture) #f)]
    [(not (member (list platform architecture)
                  (bundle:odra-language-support-bundle-targets value) equal?))
     (failure 'target-mismatch 'bundle-targets
              (list platform architecture)
              (bundle:odra-language-support-bundle-targets value))]
    [(not (eq? expected-source
               (odra-bundle-preparation-input-source input)))
     (failure 'source-mismatch 'preparation-source expected-source
              (odra-bundle-preparation-input-source input))]
    [(not (string=? (resolved-source-uri resolved)
                    (odra-package-release-reference-source-uri release)))
     (failure 'source-mismatch 'source-uri (resolved-source-uri resolved)
              (odra-package-release-reference-source-uri release))]
    [(and (eq? source-kind 'git)
          (not (string=?
                (odra-manual-package-resolved-source-resolved-source-revision
                 resolved)
                (odra-package-release-reference-source-revision release))))
     (failure
      'source-mismatch 'source-revision
      (odra-manual-package-resolved-source-resolved-source-revision resolved)
      (odra-package-release-reference-source-revision release))]
    [(not (string=?
           (odra-package-release-reference-package-id release)
           (symbol->string (bundle:odra-language-support-bundle-id value))))
     (failure 'package-mismatch 'package-id
              (odra-package-release-reference-package-id release)
              (symbol->string (bundle:odra-language-support-bundle-id value)))]
    [(not (string=?
           (odra-package-release-reference-version release)
           (bundle:odra-language-support-bundle-version value)))
     (failure 'version-mismatch 'version
              (odra-package-release-reference-version release)
              (bundle:odra-language-support-bundle-version value))]
    [(not (string=?
           (odra-package-release-reference-publisher-id release)
           (symbol->string (bundle:odra-language-support-bundle-publisher value))))
     (failure 'publisher-mismatch 'publisher-id
              (odra-package-release-reference-publisher-id release)
              (symbol->string (bundle:odra-language-support-bundle-publisher value)))]
    [(not (string=? manifest-digest
                    (odra-package-release-reference-manifest-digest release)))
     (failure 'manifest-mismatch 'manifest-digest
              (odra-package-release-reference-manifest-digest release)
              manifest-digest)]
    [(and resolved-manifest
          (not (string=? resolved-manifest manifest-digest)))
     (failure 'manifest-mismatch 'resolved-manifest-digest
              resolved-manifest manifest-digest)]
    [(not (string=?
           (odra-manual-package-resolved-source-artifact-digest resolved)
           (odra-package-artifact-reference-digest artifact)))
     (failure 'artifact-mismatch 'artifact-digest
              (odra-manual-package-resolved-source-artifact-digest resolved)
              (odra-package-artifact-reference-digest artifact))]
    [(not (= (odra-manual-package-resolved-source-content-bytes resolved)
             (odra-package-artifact-reference-size artifact)))
     (failure 'artifact-mismatch 'artifact-size
              (odra-manual-package-resolved-source-content-bytes resolved)
              (odra-package-artifact-reference-size artifact))]
    [else
     (define matches (matching-assertions curated-sources release))
     (define assertion-ids
       (map odra-package-curation-assertion-id matches))
     (define acquisition
       (make-manual-package-acquisition
        (odra-manual-package-resolved-source-generation resolved)
        source-kind
        (odra-manual-package-resolved-source-source-ref resolved)
        (odra-manual-package-resolved-source-source-label resolved)
        (odra-manual-package-resolved-source-resolved-source-revision resolved)
        (odra-manual-package-resolved-source-artifact-digest resolved)
        manifest-digest release
        #:curation-state
        (if (null? matches) 'manual-uncurated 'matches-curated-release)
        #:matching-assertion-ids assertion-ids))
     (define request
       (odra-bundle-install-request
        input manifest-digest platform architecture authority-provenance
        (bytes-length manifest-bytes)
        (odra-manual-package-resolved-source-content-bytes resolved)))
     (odra-manual-language-bundle-candidate acquisition request matches)]))

(define (install-manual-language-bundle! root manager candidate)
  (define persisted
    (manual-package-acquisition-persist
     root (odra-manual-language-bundle-candidate-acquisition candidate)))
  (if (odra-manual-package-persistence-failure? persisted)
      persisted
      (bundle-lifecycle-install!
       manager (odra-manual-language-bundle-candidate-install-request candidate))))
