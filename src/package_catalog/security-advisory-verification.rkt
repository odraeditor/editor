#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         "integrity.rkt"
         "security-advisories.rkt")

(provide
 (struct-out odra-security-advisory-key)
 (contract-out
  [verify-security-advisory
   (-> odra-security-advisory-issuer?
       (listof odra-security-advisory-key?)
       (or/c #f odra-security-advisory?)
       exact-nonnegative-integer?
       odra-security-advisory?
       (or/c #t odra-package-catalog-integrity-failure?))]
  [verify-security-advisory-history
   (-> (listof odra-security-advisory-issuer?)
       (listof odra-security-advisory-key?)
       (listof odra-security-advisory?)
       exact-nonnegative-integer?
       (or/c (listof odra-security-advisory?)
             odra-package-catalog-integrity-failure?))]
  [security-advisory-matches-release?
   (-> odra-security-advisory? string? (or/c #f string?) (listof string?)
       boolean?)]))

(define digest-pattern #px"^[0-9a-f]{64}$")
(define identity-pattern #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")

(define (immutable-copy value)
  (if (immutable? value) value (string->immutable-string value)))

(struct odra-security-advisory-key (id issuer-id algorithm public-key)
  #:transparent
  #:guard
  (lambda (id issuer-id algorithm public-key _)
    (unless (and (string? id) (regexp-match? digest-pattern id)
                 (string? issuer-id) (regexp-match? identity-pattern issuer-id)
                 (eq? algorithm 'ed25519)
                 (string? public-key) (regexp-match? digest-pattern public-key))
      (raise-arguments-error 'odra-security-advisory-key
                             "invalid issuer-specific Ed25519 key"))
    (values (immutable-copy id) (immutable-copy issuer-id) algorithm
            (immutable-copy public-key))))

(define (failure code message)
  (odra-package-catalog-integrity-failure code message))

(define (issuer-valid-for-advisory? issuer advisory now)
  (define issued-at (odra-security-advisory-issued-at advisory))
  (and (eq? (odra-security-advisory-issuer-status issuer) 'trusted)
       (<= issued-at now)
       (<= (odra-security-advisory-issuer-valid-from issuer) issued-at)
       (or (not (odra-security-advisory-issuer-valid-until issuer))
           (<= issued-at (odra-security-advisory-issuer-valid-until issuer)))))

(define (key-map keys)
  (for/hash ([key (in-list keys)])
    (values (cons (odra-security-advisory-key-issuer-id key)
                  (odra-security-advisory-key-id key))
            key)))

(define (verify-advisory-chain previous advisory)
  (define generation (odra-security-advisory-generation advisory))
  (define reference (odra-security-advisory-supersedes advisory))
  (cond
    [(= generation 1)
     (if previous
         (failure 'advisory-generation
                  "generation one cannot replace retained advisory history")
         #t)]
    [(not previous)
     (failure 'advisory-history
              "advisory correction has no retained predecessor")]
    [(or (not (string=? (odra-security-advisory-id advisory)
                        (odra-security-advisory-id previous)))
         (not (string=? (odra-security-advisory-issuer-id advisory)
                        (odra-security-advisory-issuer-id previous)))
         (not (string=? (odra-security-advisory-issuer-catalog-id advisory)
                        (odra-security-advisory-issuer-catalog-id previous)))
         (not (= generation
                 (add1 (odra-security-advisory-generation previous))))
         (< (odra-security-advisory-issued-at advisory)
            (odra-security-advisory-issued-at previous))
         (not reference)
         (not (string=?
               (odra-security-advisory-generation-reference-advisory-id reference)
               (odra-security-advisory-id previous)))
         (not (=
               (odra-security-advisory-generation-reference-generation reference)
               (odra-security-advisory-generation previous)))
         (not (string=?
               (odra-security-advisory-generation-reference-digest reference)
               (security-advisory-content-digest previous))))
     (failure 'advisory-history
              "advisory correction does not exactly extend its predecessor")]
    [else #t]))

(define (verify-security-advisory issuer keys previous now advisory)
  (define signatures (odra-security-advisory-signatures advisory))
  (define admitted-key-ids (odra-security-advisory-issuer-key-ids issuer))
  (define keys-by-id (key-map keys))
  (cond
    [(or (not (string=? (odra-security-advisory-issuer-identity issuer)
                        (odra-security-advisory-issuer-id advisory)))
         (not (string=?
               (odra-security-advisory-issuer-catalog-identity issuer)
               (odra-security-advisory-issuer-catalog-id advisory))))
     (failure 'advisory-issuer
              "advisory identity differs from its issuer-specific trust record")]
    [(not (issuer-valid-for-advisory? issuer advisory now))
     (failure 'advisory-issuer
              "advisory issuer is untrusted or invalid at issuance time")]
    [(eq? (odra-security-advisory-state advisory) 'draft)
     (failure 'advisory-state "draft advisories are not verifiable inputs")]
    [(< (length signatures) (odra-security-advisory-issuer-threshold issuer))
     (failure 'advisory-threshold
              "advisory signature threshold is not satisfied")]
    [else
     (define key-failure
       (for/first ([signature (in-list signatures)]
                   #:do
                   [(define signature-key-id
                      (odra-package-catalog-signature-key-id signature))
                    (define key
                      (hash-ref
                       keys-by-id
                       (cons (odra-security-advisory-issuer-id advisory)
                             signature-key-id)
                       #f))]
                   #:when
                   (or (not (member signature-key-id admitted-key-ids string=?))
                       (not key)
                       (not (string=?
                             (odra-security-advisory-key-issuer-id key)
                             (odra-security-advisory-issuer-id advisory)))))
         (failure 'advisory-key
                  "advisory signature key is absent or belongs to another issuer")))
     (or
      key-failure
      (for/first ([signature (in-list signatures)]
                  #:do
                  [(define key
                     (hash-ref
                      keys-by-id
                      (cons
                       (odra-security-advisory-issuer-id advisory)
                       (odra-package-catalog-signature-key-id signature))))
                   (define result
                     (verify-package-catalog-signature
                      (odra-security-advisory-key-public-key key)
                      signature package-catalog-advisory-signature-domain
                      (security-advisory-signing-payload advisory)))]
                  #:when (odra-package-catalog-integrity-failure? result))
        result)
      (verify-advisory-chain previous advisory))]))

(define (advisory-history-key advisory)
  (cons (odra-security-advisory-issuer-id advisory)
        (odra-security-advisory-id advisory)))

(define (find-issuer issuers advisory)
  (for/first ([issuer (in-list issuers)]
              #:when
              (string=? (odra-security-advisory-issuer-identity issuer)
                        (odra-security-advisory-issuer-id advisory)))
    issuer))

(define (verify-security-advisory-history issuers keys advisories now)
  (let loop ([remaining advisories] [latest (hash)])
    (cond
      [(null? remaining)
       (sort (hash-values latest)
             (lambda (left right)
               (or (string<? (odra-security-advisory-issuer-id left)
                             (odra-security-advisory-issuer-id right))
                   (and
                    (string=? (odra-security-advisory-issuer-id left)
                              (odra-security-advisory-issuer-id right))
                    (string<? (odra-security-advisory-id left)
                              (odra-security-advisory-id right))))))]
      [else
       (define advisory (car remaining))
       (define issuer (find-issuer issuers advisory))
       (define history-key (advisory-history-key advisory))
       (define previous (hash-ref latest history-key #f))
       (define result
         (if issuer
             (verify-security-advisory issuer keys previous now advisory)
             (failure 'advisory-issuer
                      "advisory has no issuer-specific trust record")))
       (if (odra-package-catalog-integrity-failure? result)
           result
           (loop (cdr remaining) (hash-set latest history-key advisory)))])))

(define (security-advisory-matches-release? advisory package-id release-id
                                            artifact-digests)
  (or (and (member package-id
                   (odra-security-advisory-affected-package-ids advisory)
                   string=?)
           #t)
      (and release-id
           (member release-id
                   (odra-security-advisory-affected-release-ids advisory)
                   string=?)
           #t)
      (for/or ([artifact-digest (in-list artifact-digests)])
        (and (member artifact-digest
                     (odra-security-advisory-affected-artifact-digests advisory)
                     string=?)
             #t))))
