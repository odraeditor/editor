#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/contract/base
         racket/list
         racket/match
         "../storage/record-codec.rkt"
         "integrity.rkt")

(provide
 current-package-catalog-snapshot-format-version
 maximum-package-catalog-snapshot-metadata-bytes
 maximum-package-catalog-snapshot-signatures
 maximum-package-catalog-snapshot-observations
 maximum-package-catalog-retained-snapshots
 (struct-out odra-package-catalog-snapshot)
 package-catalog-snapshot-signing-payload
 package-catalog-snapshot-content-digest
 package-catalog-snapshot-module-digest
 package-catalog-snapshot->module-bytes
 (contract-out
  [package-catalog-snapshot-module-parse
   (-> bytes? path-string?
       (or/c odra-package-catalog-snapshot? odra-record-diagnostic?))]
  [package-catalog-snapshot-module-load
   (-> path-string? (or/c odra-package-catalog-snapshot? odra-record-diagnostic?))]))

(define current-package-catalog-snapshot-format-version 1)
(define maximum-package-catalog-snapshot-metadata-bytes (* 4 1024 1024))
(define maximum-package-catalog-snapshot-signatures 16)
(define maximum-package-catalog-snapshot-observations 64)
(define maximum-package-catalog-retained-snapshots 1024)

(define digest-pattern #px"^[0-9a-f]{64}$")
(define identity-pattern #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")

(define (digest? value)
  (and (string? value) (regexp-match? digest-pattern value)))

(define (identity? value)
  (and (string? value)
       (positive? (string-length value))
       (<= (bytes-length (string->bytes/utf-8 value)) 128)
       (regexp-match? identity-pattern value)))

(define (u64? value)
  (and (exact-nonnegative-integer? value) (<= value (sub1 (expt 2 64)))))

(define (generation? value)
  (and (exact-positive-integer? value) (u64? value)))

(define (copied value)
  (if (string? value) (record-copied-text value) value))

(struct odra-package-catalog-snapshot
  (format-version id catalog-id sequence previous-snapshot-digest policy-id
      issued-at expires-at assertion-set-digest advisory-set-digest metadata-size
      publisher-authorization-id signatures)
  #:transparent
  #:guard
  (lambda (format-version id catalog-id sequence previous-snapshot-digest
                          policy-id issued-at expires-at assertion-set-digest
                          advisory-set-digest metadata-size
                          publisher-authorization-id signatures _)
    (unless
        (and (= format-version current-package-catalog-snapshot-format-version)
             (digest? id)
             (digest? catalog-id)
             (generation? sequence)
             (if (= sequence 1)
                 (not previous-snapshot-digest)
                 (digest? previous-snapshot-digest))
             (identity? policy-id)
             (u64? issued-at)
             (u64? expires-at)
             (< issued-at expires-at)
             (digest? assertion-set-digest)
             (digest? advisory-set-digest)
             (exact-positive-integer? metadata-size)
             (<= metadata-size maximum-package-catalog-snapshot-metadata-bytes)
             (identity? publisher-authorization-id)
             (list? signatures)
             (<= (length signatures) maximum-package-catalog-snapshot-signatures)
             (andmap odra-package-catalog-signature? signatures)
             (equal?
              signatures
              (sort
               (remove-duplicates
                signatures string=?
                #:key odra-package-catalog-signature-key-id)
               string<? #:key odra-package-catalog-signature-key-id)))
      (raise-arguments-error 'odra-package-catalog-snapshot
                             "invalid bounded package catalog snapshot"))
    (values format-version (copied id) (copied catalog-id) sequence
            (and previous-snapshot-digest (copied previous-snapshot-digest))
            (copied policy-id) issued-at expires-at
            (copied assertion-set-digest) (copied advisory-set-digest)
            metadata-size (copied publisher-authorization-id)
            (for/list ([signature (in-list signatures)]) signature))))

(define (signature->datum signature)
  (list (odra-package-catalog-signature-algorithm signature)
        (odra-package-catalog-signature-key-id signature)
        (odra-package-catalog-signature-domain signature)
        (odra-package-catalog-signature-value signature)))

(define (package-catalog-snapshot-signing-payload snapshot)
  (list 'package-catalog-snapshot
        '#:format-version
        (odra-package-catalog-snapshot-format-version snapshot)
        '#:catalog-id (odra-package-catalog-snapshot-catalog-id snapshot)
        '#:sequence (odra-package-catalog-snapshot-sequence snapshot)
        '#:previous-snapshot-digest
        (odra-package-catalog-snapshot-previous-snapshot-digest snapshot)
        '#:policy-id (odra-package-catalog-snapshot-policy-id snapshot)
        '#:issued-at (odra-package-catalog-snapshot-issued-at snapshot)
        '#:expires-at (odra-package-catalog-snapshot-expires-at snapshot)
        '#:assertion-set-digest
        (odra-package-catalog-snapshot-assertion-set-digest snapshot)
        '#:advisory-set-digest
        (odra-package-catalog-snapshot-advisory-set-digest snapshot)
        '#:metadata-size (odra-package-catalog-snapshot-metadata-size snapshot)
        '#:publisher-authorization-id
        (odra-package-catalog-snapshot-publisher-authorization-id snapshot)))

(define (package-catalog-snapshot-content-digest snapshot)
  (bytes->hex-string
   (sha256-bytes
    (open-input-bytes
     (record-datum->module-bytes
      (package-catalog-snapshot-signing-payload snapshot))))))

(define (package-catalog-snapshot->module-bytes snapshot)
  (record-datum->module-bytes
   (append
    (package-catalog-snapshot-signing-payload snapshot)
    (list '#:id (odra-package-catalog-snapshot-id snapshot)
          '#:signatures
          (map signature->datum
               (odra-package-catalog-snapshot-signatures snapshot))))))

(define (package-catalog-snapshot-module-digest snapshot)
  (bytes->hex-string
   (sha256-bytes
    (open-input-bytes (package-catalog-snapshot->module-bytes snapshot)))))

(define (decode-signature datum)
  (apply odra-package-catalog-signature datum))

(define (decode-snapshot datum)
  (match datum
    [(list 'package-catalog-snapshot
           '#:format-version format-version
           '#:catalog-id catalog-id
           '#:sequence sequence
           '#:previous-snapshot-digest previous
           '#:policy-id policy-id
           '#:issued-at issued-at
           '#:expires-at expires-at
           '#:assertion-set-digest assertion-digest
           '#:advisory-set-digest advisory-digest
           '#:metadata-size metadata-size
           '#:publisher-authorization-id publisher-id
           '#:id id
           '#:signatures signatures)
     (odra-package-catalog-snapshot
      format-version id catalog-id sequence previous policy-id issued-at
      expires-at assertion-digest advisory-digest metadata-size publisher-id
      (map decode-signature signatures))]
    [_
     (raise-arguments-error 'package-catalog-snapshot
                            "unsupported package catalog snapshot schema")]))

(define (package-catalog-snapshot-module-load path)
  (record-module-load path decode-snapshot))

(define (package-catalog-snapshot-module-parse bytes source)
  (record-module-parse bytes source decode-snapshot))
