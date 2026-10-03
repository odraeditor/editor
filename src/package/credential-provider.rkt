#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         racket/string)

(provide
 odra-package-credential?
 odra-package-credential-provider?
 odra-package-credential-resolution?
 (struct-out odra-package-credential-failure)
 (struct-out odra-package-credential-projection)
 (struct-out odra-package-artifact-credential-binding)
 current-package-credential-provider
 (contract-out
  [make-package-credential
   (->* (#:headers hash?)
        (#:expires-at (or/c #f exact-nonnegative-integer?))
        odra-package-credential?)]
  [make-package-credential-provider
   (->* (#:id string? #:generation exact-positive-integer?
         #:lookup procedure?)
        (#:refresh procedure?)
        odra-package-credential-provider?)]
  [odra-package-credential-provider-id
   (-> odra-package-credential-provider? string?)]
  [odra-package-credential-provider-generation
   (-> odra-package-credential-provider? exact-positive-integer?)]
  [make-environment-package-credential-provider
   (->* ()
        (#:id string? #:generation exact-positive-integer?
         #:environment procedure?)
        odra-package-credential-provider?)]
  [resolve-package-credential
   (->* (odra-package-credential-provider? string?)
        (#:now exact-nonnegative-integer?)
        (or/c odra-package-credential-resolution?
              odra-package-credential-failure?))]
  [package-credential-resolution-headers
   (-> odra-package-credential-resolution? hash?)]
  [package-credential-resolution->projection
   (-> odra-package-credential-resolution?
       odra-package-credential-projection?)]
  [package-credential-failure->projection
   (-> odra-package-credential-failure?
       odra-package-credential-projection?)]
  [package-credential-resolver
   (-> odra-package-credential-provider? procedure?)]
  [package-artifact-credential-binding
   (->* (#:endpoint-id string? #:origin string? #:credential-reference string?
         #:provider-id string? #:provider-generation exact-positive-integer?)
        (#:header-policy (listof string?) #:enabled? boolean?)
        odra-package-artifact-credential-binding?)]))

(define maximum-identity-bytes 128)
(define maximum-reference-bytes 512)
(define maximum-header-bytes 4096)
(define maximum-headers 8)
(define identity-pattern #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")
(define environment-reference-pattern #px"^[A-Z][A-Z0-9_]{0,127}$")
(define https-origin-pattern #px"^https://[^/@?#]+(?::[0-9]+)?$")
(define admitted-header-names '("authorization"))

(define (bounded-text? value maximum)
  (and (string? value)
       (positive? (string-length value))
       (not (string-contains? value (string #\nul)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(define (identity? value)
  (and (bounded-text? value maximum-identity-bytes)
       (regexp-match? identity-pattern value)))

(define (credential-reference? value)
  (bounded-text? value maximum-reference-bytes))

(define (header-name? value)
  (and (string? value)
       (member (string-downcase value) admitted-header-names string=?)))

(define (header-value? value)
  (and (bounded-text? value maximum-header-bytes)
       (not (string-contains? value "\r"))
       (not (string-contains? value "\n"))))

(define (normalized-headers value)
  (and
   (hash? value)
   (<= 1 (hash-count value) maximum-headers)
   (for/and ([(name content) (in-hash value)])
     (and (header-name? name) (header-value? content)))
   (for/hash ([(name content) (in-hash value)])
     (values (string->immutable-string (string-downcase name))
             (string->immutable-string content)))))

(struct odra-package-credential (headers expires-at)
  #:constructor-name make-credential-record
  #:guard
  (lambda (headers expires-at _)
    (define normalized (normalized-headers headers))
    (unless (and normalized
                 (or (not expires-at)
                     (exact-nonnegative-integer? expires-at)))
      (raise-arguments-error 'make-package-credential
                             "invalid bounded credential material"))
    (values normalized expires-at)))

(struct odra-package-credential-provider (id generation lookup refresh)
  #:constructor-name make-provider-record
  #:guard
  (lambda (id generation lookup refresh _)
    (unless (and (identity? id) (exact-positive-integer? generation)
                 (procedure? lookup) (procedure-arity-includes? lookup 1)
                 (procedure? refresh) (procedure-arity-includes? refresh 1))
      (raise-arguments-error 'make-package-credential-provider
                             "invalid credential provider"))
    (values (string->immutable-string id) generation lookup refresh)))

(struct odra-package-credential-resolution
  (provider-id provider-generation reference credential refreshed?))

(define failure-codes '(expired provider rejected unavailable))

(struct odra-package-credential-failure
  (code provider-id provider-generation reference detail)
  #:transparent
  #:guard
  (lambda (code provider-id provider-generation reference detail _)
    (unless (and (memq code failure-codes)
                 (identity? provider-id)
                 (exact-positive-integer? provider-generation)
                 (credential-reference? reference)
                 (bounded-text? detail maximum-header-bytes))
      (raise-arguments-error 'odra-package-credential-failure
                             "invalid redacted credential failure"))
    (values code (string->immutable-string provider-id) provider-generation
            (string->immutable-string reference)
            (string->immutable-string detail))))

(struct odra-package-credential-projection
  (provider-id provider-generation reference status expires-at refreshed?)
  #:transparent
  #:guard
  (lambda (provider-id provider-generation reference status expires-at
                       refreshed? _)
    (unless (and (identity? provider-id)
                 (exact-positive-integer? provider-generation)
                 (credential-reference? reference)
                 (memq status '(available expired provider rejected unavailable))
                 (or (not expires-at)
                     (exact-nonnegative-integer? expires-at))
                 (boolean? refreshed?))
      (raise-arguments-error 'odra-package-credential-projection
                             "invalid redacted credential projection"))
    (values (string->immutable-string provider-id) provider-generation
            (string->immutable-string reference) status expires-at refreshed?)))

(struct odra-package-artifact-credential-binding
  (endpoint-id origin credential-reference provider-id provider-generation
               header-policy enabled?)
  #:transparent
  #:guard
  (lambda (endpoint-id origin credential-reference provider-id
                       provider-generation header-policy enabled? _)
    (define normalized-policy
      (and (list? header-policy)
           (map string-downcase header-policy)))
    (unless (and (identity? endpoint-id)
                 (string? origin) (regexp-match? https-origin-pattern origin)
                 (credential-reference? credential-reference)
                 (identity? provider-id)
                 (exact-positive-integer? provider-generation)
                 normalized-policy
                 (pair? normalized-policy)
                 (<= (length normalized-policy) maximum-headers)
                 (andmap header-name? normalized-policy)
                 (equal? normalized-policy
                         (sort (remove-duplicates normalized-policy string=?)
                               string<?))
                 (boolean? enabled?))
      (raise-arguments-error 'odra-package-artifact-credential-binding
                             "invalid credential-free artifact binding"))
    (values (string->immutable-string endpoint-id)
            (string->immutable-string origin)
            (string->immutable-string credential-reference)
            (string->immutable-string provider-id) provider-generation
            (map string->immutable-string normalized-policy) enabled?)))

(define (make-package-credential #:headers headers #:expires-at [expires-at #f])
  (make-credential-record headers expires-at))

(define (make-package-credential-provider
         #:id id #:generation generation #:lookup lookup
         #:refresh [refresh lookup])
  (make-provider-record id generation lookup refresh))

(define (environment-credential environment reference)
  (and (regexp-match? environment-reference-pattern reference)
       (let ([value (environment reference)])
         (and (header-value? value)
              (make-package-credential
               #:headers (hash "authorization" value))))))

(define (make-environment-package-credential-provider
         #:id [id "environment"] #:generation [generation 1]
         #:environment [environment getenv])
  (make-package-credential-provider
   #:id id
   #:generation generation
   #:lookup (lambda (reference) (environment-credential environment reference))
   #:refresh (lambda (reference) (environment-credential environment reference))))

(define current-package-credential-provider
  (make-parameter (make-environment-package-credential-provider)))

(define (expired? credential now)
  (define expires-at (odra-package-credential-expires-at credential))
  (and expires-at (<= expires-at now)))

(define (provider-result provider reference operation)
  (with-handlers ([exn:fail?
                   (lambda (_)
                     (odra-package-credential-failure
                      'provider
                      (odra-package-credential-provider-id provider)
                      (odra-package-credential-provider-generation provider)
                      reference "credential provider failed"))])
    (define result (operation reference))
    (cond
      [(or (not result) (odra-package-credential? result)) result]
      [else
       (odra-package-credential-failure
        'rejected
        (odra-package-credential-provider-id provider)
        (odra-package-credential-provider-generation provider)
        reference "credential provider returned an invalid result")])))

(define (resolved provider reference credential refreshed?)
  (odra-package-credential-resolution
   (odra-package-credential-provider-id provider)
   (odra-package-credential-provider-generation provider)
   (string->immutable-string reference) credential refreshed?))

(define (failure provider reference code detail)
  (odra-package-credential-failure
   code
   (odra-package-credential-provider-id provider)
   (odra-package-credential-provider-generation provider)
   reference detail))

(define (resolve-package-credential provider reference #:now [now (current-seconds)])
  (unless (credential-reference? reference)
    (raise-argument-error 'resolve-package-credential
                          "bounded nonempty credential reference" reference))
  (define initial
    (provider-result provider reference
                     (odra-package-credential-provider-lookup provider)))
  (cond
    [(odra-package-credential-failure? initial) initial]
    [(and initial (not (expired? initial now)))
     (resolved provider reference initial #f)]
    [else
     (define refreshed
       (provider-result provider reference
                        (odra-package-credential-provider-refresh provider)))
     (cond
       [(odra-package-credential-failure? refreshed) refreshed]
       [(not refreshed)
        (failure provider reference 'unavailable
                 "credential reference is unavailable")]
       [(expired? refreshed now)
        (failure provider reference 'expired "credential reference is expired")]
       [else (resolved provider reference refreshed #t)])]))

(define (package-credential-resolution-headers resolution)
  (odra-package-credential-headers
   (odra-package-credential-resolution-credential resolution)))

(define (package-credential-resolution->projection resolution)
  (define credential
    (odra-package-credential-resolution-credential resolution))
  (odra-package-credential-projection
   (odra-package-credential-resolution-provider-id resolution)
   (odra-package-credential-resolution-provider-generation resolution)
   (odra-package-credential-resolution-reference resolution)
   'available
   (odra-package-credential-expires-at credential)
   (odra-package-credential-resolution-refreshed? resolution)))

(define (package-credential-failure->projection failure)
  (odra-package-credential-projection
   (odra-package-credential-failure-provider-id failure)
   (odra-package-credential-failure-provider-generation failure)
   (odra-package-credential-failure-reference failure)
   (odra-package-credential-failure-code failure)
   #f #f))

(define (package-credential-resolver provider)
  (lambda (reference)
    (define result (resolve-package-credential provider reference))
    (and (odra-package-credential-resolution? result)
         (package-credential-resolution-headers result))))

(define (package-artifact-credential-binding
         #:endpoint-id endpoint-id #:origin origin
         #:credential-reference credential-reference
         #:provider-id provider-id #:provider-generation provider-generation
         #:header-policy [header-policy '("authorization")]
         #:enabled? [enabled? #t])
  (odra-package-artifact-credential-binding
   endpoint-id origin credential-reference provider-id provider-generation
   header-policy enabled?))
