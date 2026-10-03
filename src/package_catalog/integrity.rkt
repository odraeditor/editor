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
         "contracts.rkt")

(provide
 package-catalog-root-signature-domain
 package-catalog-publisher-signature-domain
 package-catalog-advisory-signature-domain
 package-catalog-profile->datum
 (struct-out odra-package-catalog-signature)
 (struct-out odra-package-catalog-integrity-failure)
 (contract-out
  [package-catalog-public-key-id (-> string? string?)]
  [package-catalog-identity (-> odra-package-catalog-root-key? string?)]
  [package-catalog-profile->canonical-bytes
   (-> odra-package-catalog-profile? immutable-bytes?)]
  [package-catalog-signature-message
   (-> (or/c package-catalog-root-signature-domain
             package-catalog-publisher-signature-domain
             package-catalog-advisory-signature-domain)
       list? immutable-bytes?)]
  [verify-package-catalog-signature
   (-> string? odra-package-catalog-signature?
       (or/c package-catalog-root-signature-domain
             package-catalog-publisher-signature-domain
             package-catalog-advisory-signature-domain)
       list? (or/c #t odra-package-catalog-integrity-failure?))]
  [verify-package-catalog-profile-identity
   (-> odra-package-catalog-profile?
       (or/c #t odra-package-catalog-integrity-failure?))]
  [verify-package-catalog-root-signature
   (-> odra-package-catalog-profile? odra-package-catalog-signature?
       (or/c #t odra-package-catalog-integrity-failure?))]
  [verify-package-catalog-publisher-signatures
   (-> odra-package-catalog-publisher-authorization?
       (listof odra-package-catalog-publisher-key?)
       (listof odra-package-catalog-signature?)
       exact-nonnegative-integer?
       list?
       (or/c #t odra-package-catalog-integrity-failure?))]))

(define package-catalog-root-signature-domain
  "odra-package-catalog-root-v1")
(define package-catalog-publisher-signature-domain
  "odra-package-catalog-publisher-v1")
(define package-catalog-advisory-signature-domain
  "odra-package-security-advisory-v1")

(define digest-pattern #px"^[0-9a-f]{64}$")
(define signature-pattern #px"^[0-9a-f]{128}$")

(define (immutable-bytes? value)
  (and (bytes? value) (immutable? value)))

(define (digest? value)
  (and (string? value) (regexp-match? digest-pattern value)))

(struct odra-package-catalog-signature (algorithm key-id domain value)
  #:transparent
  #:guard
  (lambda (algorithm key-id domain value _)
    (unless (and (eq? algorithm 'ed25519)
                 (digest? key-id)
                 (member domain
                         (list package-catalog-root-signature-domain
                               package-catalog-publisher-signature-domain
                               package-catalog-advisory-signature-domain)
                         string=?)
                 (string? value)
                 (regexp-match? signature-pattern value))
      (raise-arguments-error 'odra-package-catalog-signature
                             "invalid domain-separated Ed25519 signature"))
    (values algorithm
            (string->immutable-string key-id)
            (string->immutable-string domain)
            (string->immutable-string value))))

(struct odra-package-catalog-integrity-failure (code message) #:transparent)

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

(define (package-catalog-public-key-id public-key)
  (unless (and (string? public-key) (regexp-match? digest-pattern public-key))
    (raise-arguments-error 'package-catalog-public-key-id
                           "public key must be 32 lowercase hexadecimal bytes"))
  (sha256-hex (hex->bytes public-key)))

(define (package-catalog-identity root-key)
  (sha256-hex
   (record-datum->module-bytes
    (list package-catalog-root-signature-domain
          'catalog-identity
          (odra-package-catalog-root-key-algorithm root-key)
          (odra-package-catalog-root-key-public-key root-key)))))

(define (root-key->datum key)
  (list (odra-package-catalog-root-key-id key)
        (odra-package-catalog-root-key-generation key)
        (odra-package-catalog-root-key-algorithm key)
        (odra-package-catalog-root-key-public-key key)
        (odra-package-catalog-root-key-valid-from key)
        (odra-package-catalog-root-key-valid-until key)))

(define (curator->datum authorization)
  (list (odra-package-catalog-curator-authorization-id authorization)
        (odra-package-catalog-curator-authorization-subject authorization)
        (odra-package-catalog-curator-authorization-class authorization)
        (odra-package-catalog-curator-authorization-valid-from authorization)
        (odra-package-catalog-curator-authorization-valid-until authorization)
        (odra-package-catalog-curator-authorization-policy-ids authorization)))

(define (publisher->datum authorization)
  (list (odra-package-catalog-publisher-authorization-id authorization)
        (odra-package-catalog-publisher-authorization-key-ids authorization)
        (odra-package-catalog-publisher-authorization-threshold authorization)
        (odra-package-catalog-publisher-authorization-valid-from authorization)
        (odra-package-catalog-publisher-authorization-valid-until authorization)))

(define (policy->datum policy)
  (list (odra-package-catalog-policy-id policy)
        (odra-package-catalog-policy-generation policy)
        (odra-package-catalog-policy-effective-from policy)
        (odra-package-catalog-policy-package-eligibility policy)
        (odra-package-catalog-policy-authority-policy policy)
        (odra-package-catalog-policy-assessment-policy policy)
        (odra-package-catalog-policy-decision-policy policy)
        (odra-package-catalog-policy-retention-policy policy)))

(define (endpoint->datum endpoint)
  (list (odra-package-catalog-endpoint-id endpoint)
        (odra-package-catalog-endpoint-catalog-id endpoint)
        (odra-package-catalog-endpoint-uri endpoint)
        (odra-package-catalog-endpoint-transport endpoint)
        (odra-package-catalog-endpoint-role endpoint)
        (odra-package-catalog-endpoint-priority endpoint)
        (odra-package-catalog-endpoint-enabled? endpoint)))

(define (package-catalog-profile->datum profile)
  (list 'package-catalog-profile
        (odra-package-catalog-profile-format-version profile)
        (odra-package-catalog-profile-identity profile)
        (odra-package-catalog-profile-display-name profile)
        (map root-key->datum (odra-package-catalog-profile-roots profile))
        (map curator->datum (odra-package-catalog-profile-curators profile))
        (map publisher->datum (odra-package-catalog-profile-publishers profile))
        (map policy->datum (odra-package-catalog-profile-policies profile))
        (map endpoint->datum (odra-package-catalog-profile-endpoints profile))))

(define (package-catalog-profile->canonical-bytes profile)
  (record-datum->module-bytes (package-catalog-profile->datum profile)))

(define (package-catalog-signature-message domain payload)
  (record-datum->module-bytes (list domain payload)))

(define (initial-root profile)
  (for/first ([root (in-list (odra-package-catalog-profile-roots profile))]
              #:when (= (odra-package-catalog-root-key-generation root) 1))
    root))

(define (valid-key-identity? key-id public-key)
  (string=? key-id (package-catalog-public-key-id public-key)))

(define (verify-package-catalog-profile-identity profile)
  (define bootstrap-root (initial-root profile))
  (cond
    [(not bootstrap-root)
     (odra-package-catalog-integrity-failure
      'root-generation "catalog has no generation-one trust root")]
    [(not
      (for/and ([root (in-list (odra-package-catalog-profile-roots profile))])
        (valid-key-identity?
         (odra-package-catalog-root-key-id root)
         (odra-package-catalog-root-key-public-key root))))
     (odra-package-catalog-integrity-failure
      'root-key-identity "catalog root key identity differs from its public key")]
    [(not (string=? (odra-package-catalog-profile-identity profile)
                    (package-catalog-identity bootstrap-root)))
     (odra-package-catalog-integrity-failure
      'catalog-identity "catalog identity differs from initial trust material")]
    [else #t]))

(define (verify-signature public-key signature expected-domain message)
  (cond
    [(not (string=? (odra-package-catalog-signature-domain signature)
                    expected-domain))
     (odra-package-catalog-integrity-failure
      'signature-domain "signature uses the wrong catalog authority domain")]
    [(not (zero?
           (verify-detached
            (hex->bytes (odra-package-catalog-signature-value signature))
            message
            (bytes-length message)
            (hex->bytes public-key))))
     (odra-package-catalog-integrity-failure
      'signature "catalog signature is invalid")]
    [else #t]))

(define (verify-package-catalog-signature public-key signature expected-domain
                                          payload)
  (cond
    [(not (regexp-match? digest-pattern public-key))
     (odra-package-catalog-integrity-failure
      'public-key "public key is not 32 lowercase hexadecimal bytes")]
    [(not (string=? (package-catalog-public-key-id public-key)
                    (odra-package-catalog-signature-key-id signature)))
     (odra-package-catalog-integrity-failure
      'signature-key "signature key identity differs from its public key")]
    [else
     (verify-signature
      public-key signature expected-domain
      (package-catalog-signature-message expected-domain payload))]))

(define (verify-package-catalog-root-signature profile signature)
  (define identity-result (verify-package-catalog-profile-identity profile))
  (define key
    (for/first ([candidate
                 (in-list (odra-package-catalog-profile-roots profile))]
                #:when
                (string=? (odra-package-catalog-root-key-id candidate)
                          (odra-package-catalog-signature-key-id signature)))
      candidate))
  (cond
    [(odra-package-catalog-integrity-failure? identity-result) identity-result]
    [(not key)
     (odra-package-catalog-integrity-failure
      'untrusted-root-key "signature key is not an admitted catalog root")]
    [else
     (verify-signature
      (odra-package-catalog-root-key-public-key key)
      signature
      package-catalog-root-signature-domain
      (package-catalog-signature-message
       package-catalog-root-signature-domain
       (package-catalog-profile->datum profile)))]))

(define (publisher-key-map keys)
  (for/hash ([key (in-list keys)])
    (values (odra-package-catalog-publisher-key-id key) key)))

(define (verify-package-catalog-publisher-signatures
         authorization keys signatures now payload)
  (define admitted-key-ids
    (odra-package-catalog-publisher-authorization-key-ids authorization))
  (define keys-by-id (publisher-key-map keys))
  (define unique-signatures
    (remove-duplicates signatures string=?
                       #:key odra-package-catalog-signature-key-id))
  (define message
    (package-catalog-signature-message
     package-catalog-publisher-signature-domain payload))
  (cond
    [(not (package-catalog-publisher-authorization-active?
           authorization now
           (map odra-package-catalog-signature-key-id unique-signatures)))
     (odra-package-catalog-integrity-failure
      'publisher-authorization "publisher threshold or validity interval is not satisfied")]
    [else
     (or
      (for/first ([signature (in-list unique-signatures)]
                  #:do
                  [(define key-id
                     (odra-package-catalog-signature-key-id signature))
                   (define key (hash-ref keys-by-id key-id #f))]
                  #:when
                  (or (not (member key-id admitted-key-ids string=?))
                      (not key)
                      (not
                       (valid-key-identity?
                        (odra-package-catalog-publisher-key-id key)
                        (odra-package-catalog-publisher-key-public-key key)))))
        (odra-package-catalog-integrity-failure
         'publisher-key "signature publisher key is absent or malformed"))
      (for/first ([signature (in-list unique-signatures)]
                  #:do
                  [(define key
                     (hash-ref keys-by-id
                               (odra-package-catalog-signature-key-id signature)))
                   (define result
                     (verify-signature
                      (odra-package-catalog-publisher-key-public-key key)
                      signature
                      package-catalog-publisher-signature-domain
                      message))]
                  #:when (odra-package-catalog-integrity-failure? result))
        result)
      #t)]))

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
