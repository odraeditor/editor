#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/contract/base
         racket/list
         racket/path
         racket/string
         "../storage/record-codec.rkt"
         "curation-records.rkt")

(provide
 current-manual-package-acquisition-format-version
 maximum-manual-matching-assertions
 (struct-out odra-manual-package-acquisition)
 (contract-out
  [make-manual-package-acquisition
   (->* (exact-positive-integer? symbol? string? (or/c #f string?)
         (or/c #f string?) string? string? odra-package-release-reference?)
        (#:curation-state symbol?
         #:matching-assertion-ids (listof string?)
         #:prepared-generation-ref (or/c #f exact-positive-integer?))
        odra-manual-package-acquisition?)]
  [manual-package-acquisition-redacted-source-ref
   (-> odra-manual-package-acquisition? string?)]
  [manual-package-acquisition-with-curation
   (-> odra-manual-package-acquisition? symbol? (listof string?)
       odra-manual-package-acquisition?)]))

(define current-manual-package-acquisition-format-version 1)
(define maximum-manual-matching-assertions 64)
(define maximum-source-reference-bytes 4096)
(define maximum-source-label-bytes 1024)
(define digest-pattern #px"^[0-9a-f]{64}$")
(define revision-pattern #px"^[0-9a-f]{40}(?:[0-9a-f]{24})?$")
(define source-kinds '(development-directory git local-artifact))
(define curation-states '(manual-uncurated matches-curated-release))

(define (digest? value)
  (and (string? value) (regexp-match? digest-pattern value)))

(define (bounded-text? value maximum)
  (and (string? value)
       (positive? (string-length value))
       (not (string-contains? value (string #\nul)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(define (local-source-ref? value)
  (and (bounded-text? value maximum-source-reference-bytes)
       (absolute-path? (string->path value))))

(define (remote-git-source-ref? value)
  (and (bounded-text? value maximum-source-reference-bytes)
       (or (regexp-match? #px"^https://[^/@?#]+(?::[0-9]+)?/[^?#]+$" value)
           (regexp-match?
            #px"^ssh://(?:[A-Za-z0-9._-]+@)?[^/@:#]+(?::[0-9]+)?/[^?#]+$"
            value))))

(define (source-ref? kind value)
  (case kind
    [(development-directory local-artifact) (local-source-ref? value)]
    [(git) (or (local-source-ref? value) (remote-git-source-ref? value))]
    [else #f]))

(define (copied value)
  (if (string? value) (record-copied-text value) value))

(define (artifact-digests release)
  (map odra-package-artifact-reference-digest
       (odra-package-release-reference-artifact-set release)))

(define (manual-identity generation source-kind source-ref source-label
                         resolved-source-revision artifact-digest manifest-digest
                         release)
  (bytes->hex-string
   (sha256-bytes
    (open-input-bytes
     (record-datum->module-bytes
      (list 'manual-package-acquisition
            current-manual-package-acquisition-format-version
            generation source-kind source-ref source-label
            resolved-source-revision artifact-digest manifest-digest
            (odra-package-release-reference-release-id release)))))))

(struct odra-manual-package-acquisition
  (format-version id generation source-kind source-ref source-label
                  resolved-source-revision artifact-digest manifest-digest release
                  curation-state matching-assertion-ids update-policy
                  prepared-generation-ref)
  #:transparent
  #:guard
  (lambda (format-version id generation source-kind source-ref source-label
                          resolved-source-revision artifact-digest manifest-digest
                          release curation-state matching-assertion-ids update-policy
                          prepared-generation-ref _)
    (unless
        (and (= format-version current-manual-package-acquisition-format-version)
             (digest? id)
             (exact-positive-integer? generation)
             (memq source-kind source-kinds)
             (source-ref? source-kind source-ref)
             (or (not source-label)
                 (bounded-text? source-label maximum-source-label-bytes))
             (if (eq? source-kind 'git)
                 (and (string? resolved-source-revision)
                      (regexp-match? revision-pattern resolved-source-revision))
                 (not resolved-source-revision))
             (digest? artifact-digest)
             (digest? manifest-digest)
             (odra-package-release-reference? release)
             (string=? manifest-digest
                       (odra-package-release-reference-manifest-digest release))
             (member artifact-digest (artifact-digests release) string=?)
             (memq curation-state curation-states)
             (list? matching-assertion-ids)
             (<= (length matching-assertion-ids)
                 maximum-manual-matching-assertions)
             (andmap digest? matching-assertion-ids)
             (equal? matching-assertion-ids
                     (sort (remove-duplicates matching-assertion-ids string=?)
                           string<?))
             (if (eq? curation-state 'manual-uncurated)
                 (null? matching-assertion-ids)
                 (pair? matching-assertion-ids))
             (eq? update-policy 'explicit-only)
             (or (not prepared-generation-ref)
                 (exact-positive-integer? prepared-generation-ref))
             (string=?
              id
              (manual-identity generation source-kind source-ref source-label
                               resolved-source-revision artifact-digest
                               manifest-digest release)))
      (raise-arguments-error 'odra-manual-package-acquisition
                             "invalid exact manual acquisition provenance"))
    (values format-version (copied id) generation source-kind (copied source-ref)
            (and source-label (copied source-label))
            (and resolved-source-revision (copied resolved-source-revision))
            (copied artifact-digest) (copied manifest-digest) release
            curation-state (map copied matching-assertion-ids) update-policy
            prepared-generation-ref)))

(define (make-manual-package-acquisition
         generation source-kind source-ref source-label resolved-source-revision
         artifact-digest manifest-digest release
         #:curation-state [curation-state 'manual-uncurated]
         #:matching-assertion-ids [matching-assertion-ids '()]
         #:prepared-generation-ref [prepared-generation-ref #f])
  (odra-manual-package-acquisition
   current-manual-package-acquisition-format-version
   (manual-identity generation source-kind source-ref source-label
                    resolved-source-revision artifact-digest manifest-digest release)
   generation source-kind source-ref source-label resolved-source-revision
   artifact-digest manifest-digest release curation-state matching-assertion-ids
   'explicit-only prepared-generation-ref))

(define (manual-package-acquisition-redacted-source-ref acquisition)
  (case (odra-manual-package-acquisition-source-kind acquisition)
    [(development-directory) "<local-development-directory>"]
    [(local-artifact) "<local-package-artifact>"]
    [(git)
     (if (absolute-path?
          (string->path (odra-manual-package-acquisition-source-ref acquisition)))
         "<local-git-repository>"
         "<remote-git-repository>")]))

(define (manual-package-acquisition-with-curation acquisition state assertion-ids)
  (struct-copy odra-manual-package-acquisition acquisition
               [curation-state state]
               [matching-assertion-ids assertion-ids]))
