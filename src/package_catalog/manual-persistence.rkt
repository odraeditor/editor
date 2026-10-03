#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/file
         racket/match
         "../storage/durable-file.rkt"
         "../storage/record-codec.rkt"
         "curation-records.rkt"
         "manual-records.rkt")

(provide
 (struct-out odra-manual-package-persistence-failure)
 (contract-out
  [manual-package-acquisition-path
   (-> path-string? string? path?)]
  [manual-package-acquisition->module-bytes
   (-> odra-manual-package-acquisition? immutable-bytes?)]
  [manual-package-acquisition-module-load
   (-> path-string?
       (or/c odra-manual-package-acquisition? odra-record-diagnostic?))]
  [manual-package-acquisition-persist
   (-> path-string? odra-manual-package-acquisition?
       (or/c #t odra-manual-package-persistence-failure?))]))

(struct odra-manual-package-persistence-failure (code detail path)
  #:transparent)

(define (immutable-bytes? value)
  (and (bytes? value) (immutable? value)))

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

(define (manual-package-acquisition->module-bytes acquisition)
  (record-datum->module-bytes
   (list 'manual-package-acquisition
         '#:format-version
         (odra-manual-package-acquisition-format-version acquisition)
         '#:id (odra-manual-package-acquisition-id acquisition)
         '#:generation (odra-manual-package-acquisition-generation acquisition)
         '#:source-kind
         (odra-manual-package-acquisition-source-kind acquisition)
         '#:source-ref (odra-manual-package-acquisition-source-ref acquisition)
         '#:source-label
         (odra-manual-package-acquisition-source-label acquisition)
         '#:resolved-source-revision
         (odra-manual-package-acquisition-resolved-source-revision acquisition)
         '#:artifact-digest
         (odra-manual-package-acquisition-artifact-digest acquisition)
         '#:manifest-digest
         (odra-manual-package-acquisition-manifest-digest acquisition)
         '#:release (release->datum
                     (odra-manual-package-acquisition-release acquisition))
         '#:curation-state
         (odra-manual-package-acquisition-curation-state acquisition)
         '#:matching-assertion-ids
         (odra-manual-package-acquisition-matching-assertion-ids acquisition)
         '#:update-policy
         (odra-manual-package-acquisition-update-policy acquisition)
         '#:prepared-generation-ref
         (odra-manual-package-acquisition-prepared-generation-ref acquisition))))

(define (decode-artifact datum)
  (apply odra-package-artifact-reference datum))

(define (decode-release datum)
  (match datum
    [(list format-version package-id release-id version publisher-id source-uri
           source-revision source-label manifest-digest artifact-set
           dependency-set-digest compatibility-digest capability-set-digest
           contribution-set-digest)
     (odra-package-release-reference
      format-version package-id release-id version publisher-id source-uri
      source-revision source-label manifest-digest (map decode-artifact artifact-set)
      dependency-set-digest compatibility-digest capability-set-digest
      contribution-set-digest)]))

(define (decode-acquisition datum)
  (match datum
    [(list 'manual-package-acquisition
           '#:format-version format-version
           '#:id id
           '#:generation generation
           '#:source-kind source-kind
           '#:source-ref source-ref
           '#:source-label source-label
           '#:resolved-source-revision revision
           '#:artifact-digest artifact-digest
           '#:manifest-digest manifest-digest
           '#:release release
           '#:curation-state curation-state
           '#:matching-assertion-ids assertion-ids
           '#:update-policy update-policy
           '#:prepared-generation-ref prepared-generation-ref)
     (odra-manual-package-acquisition
      format-version id generation source-kind source-ref source-label revision
      artifact-digest manifest-digest (decode-release release) curation-state
      assertion-ids update-policy prepared-generation-ref)]))

(define (manual-package-acquisition-module-load path)
  (record-module-load path decode-acquisition))

(define (manual-package-acquisition-path root acquisition-id)
  (build-path (path->complete-path root) "package-manual" "acquisitions"
              (string-append acquisition-id ".rktd")))

(define (manual-package-acquisition-persist root acquisition)
  (define target
    (manual-package-acquisition-path
     root (odra-manual-package-acquisition-id acquisition)))
  (define bytes (manual-package-acquisition->module-bytes acquisition))
  (cond
    [(or (file-exists? target) (link-exists? target))
     (define loaded (manual-package-acquisition-module-load target))
     (if (and (odra-manual-package-acquisition? loaded)
              (equal? loaded acquisition)
              (bytes=? (file->bytes target) bytes))
         #t
         (odra-manual-package-persistence-failure
          'identity-conflict "Immutable acquisition record differs" target))]
    [else
     (define complete-root (path->complete-path root))
     (define publication
       (durable-file-publish
        target bytes
        #:private-directories
        (list complete-root (build-path complete-root "package-manual")
              (build-path complete-root "package-manual" "acquisitions"))
        #:validate-stage
        (lambda (stage)
          (define loaded (manual-package-acquisition-module-load stage))
          (and (odra-manual-package-acquisition? loaded)
               (equal? loaded acquisition)))))
     (if (odra-durable-file-publication? publication)
         #t
         (odra-manual-package-persistence-failure
          (odra-durable-file-failure-code publication)
          (odra-durable-file-failure-message publication)
          target))]))
