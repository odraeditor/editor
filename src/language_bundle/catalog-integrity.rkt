#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (prefix-in ffi: ffi/unsafe)
         (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/contract/base
         racket/list
         "../storage/record-codec.rkt"
         "catalog-contracts.rkt")

(provide
 (struct-out odra-catalog-integrity-failure)
 (contract-out
  [catalog-entries-digest (-> (listof odra-catalog-entry?) string?)]
  [catalog-snapshot-signature-message
   (-> odra-catalog-snapshot? immutable-bytes?)]
  [catalog-snapshot-content-digest (-> odra-catalog-snapshot? string?)]
  [verify-catalog-snapshot
   (-> odra-catalog-source? odra-catalog-snapshot?
       (or/c #t odra-catalog-integrity-failure?))]))

(struct odra-catalog-integrity-failure (code message) #:transparent)

(define (immutable-bytes? value)
  (and (bytes? value) (immutable? value)))

(define sodium (ffi:ffi-lib "libsodium"))
(define sodium-init
  (ffi:get-ffi-obj "sodium_init" sodium (ffi:_fun ffi:-> ffi:_int)))
(define verify-detached
  (ffi:get-ffi-obj
   "crypto_sign_verify_detached" sodium
   (ffi:_fun ffi:_bytes ffi:_bytes ffi:_uint64 ffi:_bytes ffi:-> ffi:_int)))
(define sign-detached
  (ffi:get-ffi-obj
   "crypto_sign_detached" sodium
   (ffi:_fun ffi:_bytes ffi:_pointer ffi:_bytes ffi:_uint64 ffi:_bytes
             ffi:-> ffi:_int)))
(void (sodium-init))

(define (hex->bytes value)
  (apply bytes
         (for/list ([index (in-range 0 (string-length value) 2)])
           (string->number (substring value index (+ index 2)) 16))))

(define (sha256-hex value)
  (bytes->hex-string (sha256-bytes (open-input-bytes value))))

(define (target->datum target)
  (list (odra-catalog-target-platform target)
        (odra-catalog-target-architecture target)))

(define (dependency->datum dependency)
  (list (odra-catalog-dependency-summary-id dependency)
        (odra-catalog-dependency-summary-minimum dependency)
        (odra-catalog-dependency-summary-maximum dependency)
        (odra-catalog-dependency-summary-optional? dependency)
        (odra-catalog-dependency-summary-facets dependency)))

(define (entry->datum entry)
  (list
   (odra-catalog-entry-bundle-id entry)
   (odra-catalog-entry-version entry)
   (odra-catalog-entry-api-minimum entry)
   (odra-catalog-entry-api-maximum entry)
   (map target->datum (odra-catalog-entry-targets entry))
   (odra-catalog-entry-manifest-digest entry)
   (odra-catalog-entry-manifest-locations entry)
   (odra-catalog-entry-display-name entry)
   (odra-catalog-entry-summary entry)
   (odra-catalog-entry-facets entry)
   (odra-catalog-entry-authorities entry)
   (map dependency->datum (odra-catalog-entry-dependencies entry))
   (odra-catalog-entry-artifact-count entry)
   (odra-catalog-entry-artifact-bytes entry)
   (odra-catalog-entry-deprecated? entry)
   (odra-catalog-entry-replacement entry)))

(define (entries-bytes entries)
  (record-datum->module-bytes
   (list 'language-catalog-entries 1 (map entry->datum entries))))

(define (catalog-entries-digest entries)
  (sha256-hex (entries-bytes entries)))

(define (expiry->datum expiry)
  (list (odra-catalog-expiry-generated-at expiry)
        (odra-catalog-expiry-expires-at expiry)
        (odra-catalog-expiry-confirmed-at expiry)))

(define (catalog-snapshot-signature-message snapshot)
  (record-datum->module-bytes
   (list 'odra-language-catalog-v1
         (odra-catalog-snapshot-format-version snapshot)
         (odra-catalog-snapshot-source-id snapshot)
         (odra-catalog-snapshot-sequence snapshot)
         (expiry->datum (odra-catalog-snapshot-expiry snapshot))
         (odra-catalog-snapshot-entries-digest snapshot)
         (odra-catalog-snapshot-signing-key-id snapshot)
         (map entry->datum (odra-catalog-snapshot-entries snapshot))
         (odra-catalog-snapshot-encoded-bytes snapshot))))

(define (catalog-snapshot-content-digest snapshot)
  (sha256-hex
   (bytes-append
    (catalog-snapshot-signature-message snapshot)
    (hex->bytes
     (odra-catalog-signature-value
      (odra-catalog-snapshot-signature snapshot))))))

(define (verify-catalog-snapshot source snapshot)
  (define key
    (for/first ([candidate (in-list (odra-catalog-source-trusted-keys source))]
                #:when
                (string=? (odra-catalog-signing-key-id candidate)
                          (odra-catalog-snapshot-signing-key-id snapshot)))
      candidate))
  (cond
    [(not (string=? (odra-catalog-source-id source)
                    (odra-catalog-snapshot-source-id snapshot)))
     (odra-catalog-integrity-failure 'source "snapshot source identity differs")]
    [(not key)
     (odra-catalog-integrity-failure 'untrusted-key "snapshot key is not trusted")]
    [(not (string=? (catalog-entries-digest
                     (odra-catalog-snapshot-entries snapshot))
                    (odra-catalog-snapshot-entries-digest snapshot)))
     (odra-catalog-integrity-failure 'entries-digest
                                     "catalog entry digest differs")]
    [(not (string=? (catalog-snapshot-content-digest snapshot)
                    (odra-catalog-snapshot-snapshot-digest snapshot)))
     (odra-catalog-integrity-failure 'snapshot-digest
                                     "catalog snapshot digest differs")]
    [(not (zero?
           (verify-detached
            (hex->bytes
             (odra-catalog-signature-value
              (odra-catalog-snapshot-signature snapshot)))
            (catalog-snapshot-signature-message snapshot)
            (bytes-length (catalog-snapshot-signature-message snapshot))
            (hex->bytes (odra-catalog-signing-key-public-key key)))))
     (odra-catalog-integrity-failure 'signature "catalog signature is invalid")]
    [else #t]))

(define (sign-for-test message secret-key)
  (define signature (make-bytes 64))
  (define signature-length (ffi:malloc ffi:_uint64 'atomic))
  (ffi:ptr-set! signature-length ffi:_uint64 0 0)
  (define result
    (sign-detached signature signature-length message (bytes-length message)
                   (hex->bytes secret-key)))
  (unless (and (zero? result)
               (= (ffi:ptr-ref signature-length ffi:_uint64 0) 64))
    (error 'sign-for-test "could not create fixture signature"))
  (bytes->hex-string signature))

(module+ test-support
  (provide sign-for-test))
