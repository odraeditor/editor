#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         racket/match
         racket/string)

(provide catalog-identity-limits
         catalog-identity-resource-profiles
         (struct-out catalog-root-key)
         (struct-out curator-authorization)
         (struct-out publisher-authorization)
         (struct-out catalog-policy)
         (struct-out catalog-endpoint)
         (struct-out catalog-profile)
         (struct-out catalog-identity-rejection)
         confirm-catalog-profile
         same-catalog-identity?
         curator-authorization-active?
         publisher-authorization-active?
         validate-catalog-identity-resource-profile
         estimate-catalog-identity-retained-bytes
         estimate-catalog-identity-temporary-bytes)

(define catalog-identity-limits
  '#hasheq((identity-bytes . 128)
           (display-name-bytes . 256)
           (uri-bytes . 4096)
           (policy-reference-bytes . 4096)
           (root-keys . 16)
           (curator-authorizations . 64)
           (publisher-authorizations . 64)
           (policies . 256)
           (endpoints . 64)
           (signatures . 16)
           (retained-bytes . 16777216)
           (temporary-bytes . 8388608)))

(define catalog-identity-resource-profiles
  (list
   '#hasheq((name . ordinary)
            (root-keys . 2)
            (curator-authorizations . 2)
            (publisher-authorizations . 2)
            (policies . 4)
            (endpoints . 4)
            (signatures . 2))
   '#hasheq((name . demanding)
            (root-keys . 8)
            (curator-authorizations . 32)
            (publisher-authorizations . 16)
            (policies . 96)
            (endpoints . 32)
            (signatures . 8))
   '#hasheq((name . boundary)
            (root-keys . 16)
            (curator-authorizations . 64)
            (publisher-authorizations . 64)
            (policies . 256)
            (endpoints . 64)
            (signatures . 16))))

(struct catalog-root-key
  (id generation algorithm public-key valid-from valid-until)
  #:transparent)
(struct curator-authorization
  (id subject class valid-from valid-until policy-ids)
  #:transparent)
(struct publisher-authorization
  (id key-ids threshold valid-from valid-until)
  #:transparent)
(struct catalog-policy
  (id generation effective-from package-eligibility authority-policy
      assessment-policy decision-policy retention-policy)
  #:transparent)
(struct catalog-endpoint
  (id catalog-id uri transport role priority enabled?)
  #:transparent)
(struct catalog-profile
  (format-version identity display-name roots curators publishers policies endpoints)
  #:transparent)
(struct catalog-identity-rejection (code field limit actual identity) #:transparent)

(define digest-pattern #px"^[0-9a-f]{64}$")
(define identity-pattern #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")

(define (utf8-length value)
  (if (string? value) (bytes-length (string->bytes/utf-8 value)) +inf.0))

(define (bounded-text? value maximum)
  (and (string? value)
       (positive? (string-length value))
       (not (string-contains? value (string #\nul)))
       (<= (utf8-length value) maximum)))

(define (identity? value)
  (and (bounded-text? value (hash-ref catalog-identity-limits 'identity-bytes))
       (regexp-match? identity-pattern value)))

(define (digest? value)
  (and (string? value) (regexp-match? digest-pattern value)))

(define (generation? value)
  (and (exact-positive-integer? value) (<= value (sub1 (expt 2 64)))))

(define (time? value)
  (and (exact-nonnegative-integer? value) (<= value (sub1 (expt 2 64)))))

(define (interval? start end)
  (and (time? start) (or (not end) (and (time? end) (<= start end)))))

(define (unique-by? values key same?)
  (= (length values) (length (remove-duplicates (map key values) same?))))

(define (ordered-unique-text? values)
  (and (list? values)
       (andmap identity? values)
       (equal? values (sort (remove-duplicates values string=?) string<?))))

(define (root-valid? value)
  (and (catalog-root-key? value)
       (digest? (catalog-root-key-id value))
       (generation? (catalog-root-key-generation value))
       (eq? (catalog-root-key-algorithm value) 'ed25519)
       (digest? (catalog-root-key-public-key value))
       (interval? (catalog-root-key-valid-from value)
                  (catalog-root-key-valid-until value))))

(define (curator-valid? value policy-identities)
  (and (curator-authorization? value)
       (identity? (curator-authorization-id value))
       (identity? (curator-authorization-subject value))
       (eq? (curator-authorization-class value) 'human)
       (interval? (curator-authorization-valid-from value)
                  (curator-authorization-valid-until value))
       (ordered-unique-text? (curator-authorization-policy-ids value))
       (andmap (lambda (identity) (member identity policy-identities string=?))
               (curator-authorization-policy-ids value))))

(define (publisher-valid? value root-identities)
  (and (publisher-authorization? value)
       (identity? (publisher-authorization-id value))
       (ordered-unique-text? (publisher-authorization-key-ids value))
       (pair? (publisher-authorization-key-ids value))
       (andmap (lambda (identity) (member identity root-identities string=?))
               (publisher-authorization-key-ids value))
       (exact-positive-integer? (publisher-authorization-threshold value))
       (<= (publisher-authorization-threshold value)
           (length (publisher-authorization-key-ids value)))
       (interval? (publisher-authorization-valid-from value)
                  (publisher-authorization-valid-until value))))

(define (policy-reference? value)
  (bounded-text? value (hash-ref catalog-identity-limits 'policy-reference-bytes)))

(define (policy-valid? value)
  (and (catalog-policy? value)
       (identity? (catalog-policy-id value))
       (generation? (catalog-policy-generation value))
       (generation? (catalog-policy-effective-from value))
       (andmap policy-reference?
               (list (catalog-policy-package-eligibility value)
                     (catalog-policy-authority-policy value)
                     (catalog-policy-assessment-policy value)
                     (catalog-policy-decision-policy value)
                     (catalog-policy-retention-policy value)))))

(define (endpoint-uri? transport uri)
  (and (bounded-text? uri (hash-ref catalog-identity-limits 'uri-bytes))
       (case transport
         [(https) (regexp-match? #px"^https://[^/@?#]+(?::[0-9]+)?/[^?#]*$" uri)]
         [(file) (regexp-match? #px"^file:///[^?#]+$" uri)]
         [else #f])))

(define (endpoint-valid? value catalog-identity)
  (and (catalog-endpoint? value)
       (identity? (catalog-endpoint-id value))
       (string=? (catalog-endpoint-catalog-id value) catalog-identity)
       (memq (catalog-endpoint-role value) '(origin mirror local))
       (memq (catalog-endpoint-transport value) '(https file))
       (endpoint-uri? (catalog-endpoint-transport value)
                      (catalog-endpoint-uri value))
       (if (eq? (catalog-endpoint-role value) 'local)
           (eq? (catalog-endpoint-transport value) 'file)
           #t)
       (exact-nonnegative-integer? (catalog-endpoint-priority value))
       (<= (catalog-endpoint-priority value) 65535)
       (boolean? (catalog-endpoint-enabled? value))))

(define (record-limit-rejection profile field values)
  (define limit (hash-ref catalog-identity-limits field))
  (and (> (length values) limit)
       (catalog-identity-rejection
        'limit field limit (length values) (catalog-profile-identity profile))))

(define (duplicate-rejection profile field values key same?)
  (and (not (unique-by? values key same?))
       (catalog-identity-rejection
        'duplicate-identity field #f (length values) (catalog-profile-identity profile))))

(define (policy-history-valid? policies)
  (define ordered (sort policies < #:key catalog-policy-generation))
  (for/and ([current (in-list ordered)] [index (in-naturals)])
    (or (zero? index)
        (let ([previous (list-ref ordered (sub1 index))])
          (and (< (catalog-policy-generation previous)
                  (catalog-policy-generation current))
               (<= (catalog-policy-effective-from previous)
                   (catalog-policy-effective-from current)))))))

(define (profile-rejection profile)
  (cond
    [(not (catalog-profile? profile))
     (catalog-identity-rejection 'invalid-field 'profile #f profile "")]
    [(not (= (catalog-profile-format-version profile) 1))
     (catalog-identity-rejection 'unsupported-format 'format-version 1
                                 (catalog-profile-format-version profile) "")]
    [(not (digest? (catalog-profile-identity profile)))
     (catalog-identity-rejection 'invalid-field 'identity 64
                                 (catalog-profile-identity profile) "")]
    [(not (bounded-text? (catalog-profile-display-name profile)
                         (hash-ref catalog-identity-limits 'display-name-bytes)))
     (catalog-identity-rejection
      'limit 'display-name
      (hash-ref catalog-identity-limits 'display-name-bytes)
      (utf8-length (catalog-profile-display-name profile))
      (catalog-profile-identity profile))]
    [else
     (define roots (catalog-profile-roots profile))
     (define curators (catalog-profile-curators profile))
     (define publishers (catalog-profile-publishers profile))
     (define policies (catalog-profile-policies profile))
     (define endpoints (catalog-profile-endpoints profile))
     (define policy-identities (map catalog-policy-id policies))
     (define root-identities (map catalog-root-key-id roots))
     (or
      (record-limit-rejection profile 'root-keys roots)
      (record-limit-rejection profile 'curator-authorizations curators)
      (record-limit-rejection profile 'publisher-authorizations publishers)
      (record-limit-rejection profile 'policies policies)
      (record-limit-rejection profile 'endpoints endpoints)
      (duplicate-rejection profile 'root-keys roots catalog-root-key-id string=?)
      (duplicate-rejection profile 'root-generations roots
                           catalog-root-key-generation =)
      (duplicate-rejection profile 'curator-authorizations curators
                           curator-authorization-id string=?)
      (duplicate-rejection profile 'publisher-authorizations publishers
                           publisher-authorization-id string=?)
      (duplicate-rejection profile 'policies policies catalog-policy-id string=?)
      (duplicate-rejection profile 'policy-generations policies
                           catalog-policy-generation =)
      (duplicate-rejection profile 'endpoints endpoints catalog-endpoint-id string=?)
      (and (not (andmap root-valid? roots))
           (catalog-identity-rejection 'invalid-field 'root-keys #f #f
                                       (catalog-profile-identity profile)))
      (and (not (andmap policy-valid? policies))
           (catalog-identity-rejection 'invalid-field 'policies #f #f
                                       (catalog-profile-identity profile)))
      (and (not (policy-history-valid? policies))
           (catalog-identity-rejection 'stale-generation 'policies #f #f
                                       (catalog-profile-identity profile)))
      (and (not (andmap (lambda (value)
                          (curator-valid? value policy-identities))
                        curators))
           (catalog-identity-rejection 'invalid-authority 'curators #f #f
                                       (catalog-profile-identity profile)))
      (and (not (andmap (lambda (value)
                          (publisher-valid? value root-identities))
                        publishers))
           (catalog-identity-rejection 'invalid-authority 'publishers #f #f
                                       (catalog-profile-identity profile)))
      (and (not (andmap (lambda (value)
                          (endpoint-valid? value (catalog-profile-identity profile)))
                        endpoints))
           (catalog-identity-rejection 'invalid-field 'endpoints #f #f
                                       (catalog-profile-identity profile))))]))

(define (normalize-profile profile)
  (struct-copy
   catalog-profile profile
   [roots (sort (catalog-profile-roots profile) string<? #:key catalog-root-key-id)]
   [curators (sort (catalog-profile-curators profile)
                    string<? #:key curator-authorization-id)]
   [publishers (sort (catalog-profile-publishers profile)
                      string<? #:key publisher-authorization-id)]
   [policies (sort (catalog-profile-policies profile)
                   < #:key catalog-policy-generation)]
   [endpoints (sort (catalog-profile-endpoints profile)
                    string<? #:key catalog-endpoint-id)]))

(define (confirm-catalog-profile profile)
  (define rejection (profile-rejection profile))
  (if rejection
      (values #f rejection)
      (values (normalize-profile profile) #f)))

(define (same-catalog-identity? left right)
  (and (catalog-profile? left)
       (catalog-profile? right)
       (string=? (catalog-profile-identity left)
                 (catalog-profile-identity right))))

(define (within-interval? now start end)
  (and (<= start now) (or (not end) (<= now end))))

(define (curator-authorization-active? authorization now policy-id)
  (and (curator-authorization? authorization)
       (within-interval? now
                         (curator-authorization-valid-from authorization)
                         (curator-authorization-valid-until authorization))
       (member policy-id (curator-authorization-policy-ids authorization) string=?)
       #t))

(define (publisher-authorization-active? authorization now supplied-key-ids)
  (and (publisher-authorization? authorization)
       (within-interval? now
                         (publisher-authorization-valid-from authorization)
                         (publisher-authorization-valid-until authorization))
       (>= (length
            (remove-duplicates
             (filter (lambda (identity)
                       (member identity
                               (publisher-authorization-key-ids authorization)
                               string=?))
                     supplied-key-ids)
             string=?))
           (publisher-authorization-threshold authorization))))

(define (estimate-catalog-identity-retained-bytes profile)
  (+ 4096
     (* 512 (hash-ref profile 'root-keys))
     (* 768 (hash-ref profile 'curator-authorizations))
     (* 1024 (hash-ref profile 'publisher-authorizations))
     (* 8192 (hash-ref profile 'policies))
     (* 4608 (hash-ref profile 'endpoints))))

(define (estimate-catalog-identity-temporary-bytes profile)
  (+ 8192
     (* 1024 (hash-ref profile 'root-keys))
     (* 2048 (hash-ref profile 'endpoints))
     (* 131072 (hash-ref profile 'signatures))))

(define (validate-catalog-identity-resource-profile profile)
  (and
   (for/and ([field (in-list '(root-keys curator-authorizations
                                         publisher-authorizations policies
                                         endpoints signatures))])
     (define value (hash-ref profile field #f))
     (and (exact-nonnegative-integer? value)
          (<= value (hash-ref catalog-identity-limits field))))
   (<= (estimate-catalog-identity-retained-bytes profile)
       (hash-ref catalog-identity-limits 'retained-bytes))
   (<= (estimate-catalog-identity-temporary-bytes profile)
       (hash-ref catalog-identity-limits 'temporary-bytes))))
