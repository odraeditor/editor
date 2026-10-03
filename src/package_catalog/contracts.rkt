#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         racket/string)

(provide
 current-package-catalog-identity-format-version
 maximum-package-catalog-identity-bytes
 maximum-package-catalog-display-name-bytes
 maximum-package-catalog-uri-bytes
 maximum-package-catalog-policy-reference-bytes
 maximum-package-catalog-root-keys
 maximum-package-catalog-curator-authorizations
 maximum-package-catalog-publisher-authorizations
 maximum-package-catalog-policies
 maximum-package-catalog-endpoints
 maximum-package-catalog-signatures
 maximum-package-catalog-identity-retained-bytes
 maximum-package-catalog-identity-temporary-bytes
 (struct-out odra-package-catalog-root-key)
 (struct-out odra-package-catalog-publisher-key)
 (struct-out odra-package-catalog-curator-authorization)
 (struct-out odra-package-catalog-publisher-authorization)
 (struct-out odra-package-catalog-policy)
 (struct-out odra-package-catalog-endpoint)
 (struct-out odra-package-catalog-profile-proposal)
 (struct-out odra-package-catalog-rejection)
 odra-package-catalog-profile?
 odra-package-catalog-profile-format-version
 odra-package-catalog-profile-identity
 odra-package-catalog-profile-display-name
 odra-package-catalog-profile-roots
 odra-package-catalog-profile-curators
 odra-package-catalog-profile-publishers
 odra-package-catalog-profile-policies
 odra-package-catalog-profile-endpoints
 (contract-out
  [confirm-package-catalog-profile
   (-> odra-package-catalog-profile-proposal?
       (values (or/c #f odra-package-catalog-profile?)
               (or/c #f odra-package-catalog-rejection?)))]
  [same-package-catalog-identity?
   (-> odra-package-catalog-profile? odra-package-catalog-profile? boolean?)]
  [package-catalog-curator-authorization-active?
   (-> odra-package-catalog-curator-authorization?
       exact-nonnegative-integer? string? boolean?)]
  [package-catalog-publisher-authorization-active?
   (-> odra-package-catalog-publisher-authorization?
       exact-nonnegative-integer? (listof string?) boolean?)]))

(define current-package-catalog-identity-format-version 1)
(define maximum-package-catalog-identity-bytes 128)
(define maximum-package-catalog-display-name-bytes 256)
(define maximum-package-catalog-uri-bytes 4096)
(define maximum-package-catalog-policy-reference-bytes 4096)
(define maximum-package-catalog-root-keys 16)
(define maximum-package-catalog-curator-authorizations 64)
(define maximum-package-catalog-publisher-authorizations 64)
(define maximum-package-catalog-policies 256)
(define maximum-package-catalog-endpoints 64)
(define maximum-package-catalog-signatures 16)
(define maximum-package-catalog-identity-retained-bytes (* 16 1024 1024))
(define maximum-package-catalog-identity-temporary-bytes (* 8 1024 1024))

(define digest-pattern #px"^[0-9a-f]{64}$")
(define identity-pattern #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")

(define (copied-text value)
  (string->immutable-string value))

(define (bounded-text? value maximum)
  (and (string? value)
       (positive? (string-length value))
       (not (string-contains? value (string #\nul)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(define (identity? value)
  (and (bounded-text? value maximum-package-catalog-identity-bytes)
       (regexp-match? identity-pattern value)))

(define (digest? value)
  (and (string? value) (regexp-match? digest-pattern value)))

(define (u64? value)
  (and (exact-nonnegative-integer? value) (<= value (sub1 (expt 2 64)))))

(define (generation? value)
  (and (exact-positive-integer? value) (u64? value)))

(define (valid-interval? valid-from valid-until)
  (and (u64? valid-from)
       (or (not valid-until)
           (and (u64? valid-until) (<= valid-from valid-until)))))

(define (copied-text-list values)
  (for/list ([value (in-list values)]) (copied-text value)))

(define (ordered-unique-identities? values)
  (and (list? values)
       (andmap identity? values)
       (equal? values (sort (remove-duplicates values string=?) string<?))))

(define (bounded-list? values maximum predicate)
  (and (list? values) (<= (length values) maximum) (andmap predicate values)))

(struct odra-package-catalog-root-key
  (id generation algorithm public-key valid-from valid-until)
  #:transparent
  #:guard
  (lambda (id generation algorithm public-key valid-from valid-until _)
    (unless (and (digest? id)
                 (generation? generation)
                 (eq? algorithm 'ed25519)
                 (digest? public-key)
                 (valid-interval? valid-from valid-until))
      (raise-arguments-error 'odra-package-catalog-root-key
                             "invalid bounded catalog root key"))
    (values (copied-text id) generation algorithm (copied-text public-key)
            valid-from valid-until)))

(struct odra-package-catalog-publisher-key (id algorithm public-key)
  #:transparent
  #:guard
  (lambda (id algorithm public-key _)
    (unless (and (digest? id) (eq? algorithm 'ed25519) (digest? public-key))
      (raise-arguments-error 'odra-package-catalog-publisher-key
                             "invalid bounded catalog publisher key"))
    (values (copied-text id) algorithm (copied-text public-key))))

(struct odra-package-catalog-curator-authorization
  (id subject class valid-from valid-until policy-ids)
  #:transparent
  #:guard
  (lambda (id subject class valid-from valid-until policy-ids _)
    (unless (and (identity? id)
                 (identity? subject)
                 (eq? class 'human)
                 (valid-interval? valid-from valid-until)
                 (ordered-unique-identities? policy-ids))
      (raise-arguments-error 'odra-package-catalog-curator-authorization
                             "curator authority requires a human subject and bounded policy scope"))
    (values (copied-text id) (copied-text subject) class valid-from valid-until
            (copied-text-list policy-ids))))

(struct odra-package-catalog-publisher-authorization
  (id key-ids threshold valid-from valid-until)
  #:transparent
  #:guard
  (lambda (id key-ids threshold valid-from valid-until _)
    (unless (and (identity? id)
                 (list? key-ids)
                 (pair? key-ids)
                 (<= (length key-ids) maximum-package-catalog-root-keys)
                 (andmap digest? key-ids)
                 (equal? key-ids
                         (sort (remove-duplicates key-ids string=?) string<?))
                 (exact-positive-integer? threshold)
                 (<= threshold (length key-ids))
                 (valid-interval? valid-from valid-until))
      (raise-arguments-error 'odra-package-catalog-publisher-authorization
                             "invalid constrained publisher authorization"))
    (values (copied-text id) (copied-text-list key-ids) threshold
            valid-from valid-until)))

(struct odra-package-catalog-policy
  (id generation effective-from package-eligibility authority-policy
      assessment-policy decision-policy retention-policy)
  #:transparent
  #:guard
  (lambda (id generation effective-from package-eligibility authority-policy
              assessment-policy decision-policy retention-policy _)
    (unless (and (identity? id)
                 (generation? generation)
                 (generation? effective-from)
                 (andmap
                  (lambda (value)
                    (bounded-text? value maximum-package-catalog-policy-reference-bytes))
                  (list package-eligibility authority-policy assessment-policy
                        decision-policy retention-policy)))
      (raise-arguments-error 'odra-package-catalog-policy
                             "invalid bounded catalog policy"))
    (values (copied-text id) generation effective-from
            (copied-text package-eligibility)
            (copied-text authority-policy)
            (copied-text assessment-policy)
            (copied-text decision-policy)
            (copied-text retention-policy))))

(define (endpoint-uri? transport uri)
  (and (bounded-text? uri maximum-package-catalog-uri-bytes)
       (case transport
         [(https) (regexp-match? #px"^https://[^/@?#]+(?::[0-9]+)?/[^?#]*$" uri)]
         [(file) (regexp-match? #px"^file:///[^?#]+$" uri)]
         [else #f])))

(struct odra-package-catalog-endpoint
  (id catalog-id uri transport role priority enabled?)
  #:transparent
  #:guard
  (lambda (id catalog-id uri transport role priority enabled? _)
    (unless (and (identity? id)
                 (digest? catalog-id)
                 (endpoint-uri? transport uri)
                 (memq role '(origin mirror local))
                 (if (eq? role 'local) (eq? transport 'file) #t)
                 (exact-nonnegative-integer? priority)
                 (<= priority 65535)
                 (boolean? enabled?))
      (raise-arguments-error 'odra-package-catalog-endpoint
                             "invalid transport-independent catalog endpoint"))
    (values (copied-text id) (copied-text catalog-id) (copied-text uri)
            transport role priority enabled?)))

(struct odra-package-catalog-profile-proposal
  (format-version identity display-name roots curators publishers policies endpoints)
  #:transparent
  #:guard
  (lambda (format-version identity display-name roots curators publishers policies
                          endpoints _)
    (unless (and (exact-positive-integer? format-version)
                 (string? identity)
                 (string? display-name)
                 (list? roots)
                 (list? curators)
                 (list? publishers)
                 (list? policies)
                 (list? endpoints))
      (raise-arguments-error 'odra-package-catalog-profile-proposal
                             "profile proposal fields have invalid primitive types"))
    (values format-version (copied-text identity) (copied-text display-name)
            (for/list ([value (in-list roots)]) value)
            (for/list ([value (in-list curators)]) value)
            (for/list ([value (in-list publishers)]) value)
            (for/list ([value (in-list policies)]) value)
            (for/list ([value (in-list endpoints)]) value))))

(struct odra-package-catalog-profile
  (format-version identity display-name roots curators publishers policies endpoints)
  #:transparent)

(struct odra-package-catalog-rejection (code field limit actual identity)
  #:transparent
  #:guard
  (lambda (code field limit actual identity _)
    (unless (and (memq code '(allocation duplicate-identity invalid-authority
                                         invalid-field limit stale-generation
                                         unsupported-format))
                 (symbol? field)
                 (or (not limit) (exact-nonnegative-integer? limit))
                 (string? identity))
      (raise-arguments-error 'odra-package-catalog-rejection
                             "invalid typed catalog rejection"))
    (values code field limit actual (copied-text identity))))

(define (proposal-identity proposal)
  (odra-package-catalog-profile-proposal-identity proposal))

(define (reject proposal code field [limit #f] [actual #f])
  (odra-package-catalog-rejection
   code field limit actual
   (if (digest? (proposal-identity proposal)) (proposal-identity proposal) "")))

(define (limit-rejection proposal field values maximum)
  (and (> (length values) maximum)
       (reject proposal 'limit field maximum (length values))))

(define (duplicate-rejection proposal field values key)
  (and (not (= (length values)
               (length (remove-duplicates (map key values) equal?))))
       (reject proposal 'duplicate-identity field #f (length values))))

(define (policy-history-valid? policies)
  (define ordered (sort policies < #:key odra-package-catalog-policy-generation))
  (for/and ([current (in-list ordered)] [index (in-naturals)])
    (or (zero? index)
        (let ([previous (list-ref ordered (sub1 index))])
          (and (< (odra-package-catalog-policy-generation previous)
                  (odra-package-catalog-policy-generation current))
               (<= (odra-package-catalog-policy-effective-from previous)
                   (odra-package-catalog-policy-effective-from current)))))))

(define (proposal-rejection proposal)
  (define roots (odra-package-catalog-profile-proposal-roots proposal))
  (define curators (odra-package-catalog-profile-proposal-curators proposal))
  (define publishers (odra-package-catalog-profile-proposal-publishers proposal))
  (define policies (odra-package-catalog-profile-proposal-policies proposal))
  (define endpoints (odra-package-catalog-profile-proposal-endpoints proposal))
  (define policy-identities
    (and (andmap odra-package-catalog-policy? policies)
         (map odra-package-catalog-policy-id policies)))
  (cond
    [(not (= (odra-package-catalog-profile-proposal-format-version proposal)
             current-package-catalog-identity-format-version))
     (reject proposal 'unsupported-format 'format-version
             current-package-catalog-identity-format-version
             (odra-package-catalog-profile-proposal-format-version proposal))]
    [(not (digest? (proposal-identity proposal)))
     (reject proposal 'invalid-field 'identity 64
             (bytes-length (string->bytes/utf-8 (proposal-identity proposal))))]
    [(not (bounded-text? (odra-package-catalog-profile-proposal-display-name proposal)
                         maximum-package-catalog-display-name-bytes))
     (reject proposal 'limit 'display-name
             maximum-package-catalog-display-name-bytes
             (bytes-length
              (string->bytes/utf-8
               (odra-package-catalog-profile-proposal-display-name proposal))))]
    [(not (and (bounded-list? roots maximum-package-catalog-root-keys
                              odra-package-catalog-root-key?)
               (pair? roots)))
     (or (limit-rejection proposal 'root-keys roots maximum-package-catalog-root-keys)
         (reject proposal 'invalid-field 'root-keys))]
    [(not (bounded-list? curators maximum-package-catalog-curator-authorizations
                         odra-package-catalog-curator-authorization?))
     (or (limit-rejection proposal 'curator-authorizations curators
                          maximum-package-catalog-curator-authorizations)
         (reject proposal 'invalid-field 'curator-authorizations))]
    [(not (bounded-list? publishers maximum-package-catalog-publisher-authorizations
                         odra-package-catalog-publisher-authorization?))
     (or (limit-rejection proposal 'publisher-authorizations publishers
                          maximum-package-catalog-publisher-authorizations)
         (reject proposal 'invalid-field 'publisher-authorizations))]
    [(not (and (bounded-list? policies maximum-package-catalog-policies
                              odra-package-catalog-policy?)
               (pair? policies)))
     (or (limit-rejection proposal 'policies policies maximum-package-catalog-policies)
         (reject proposal 'invalid-field 'policies))]
    [(not (bounded-list? endpoints maximum-package-catalog-endpoints
                         odra-package-catalog-endpoint?))
     (or (limit-rejection proposal 'endpoints endpoints maximum-package-catalog-endpoints)
         (reject proposal 'invalid-field 'endpoints))]
    [(duplicate-rejection proposal 'root-keys roots odra-package-catalog-root-key-id)]
    [(duplicate-rejection proposal 'root-generations roots
                          odra-package-catalog-root-key-generation)]
    [(duplicate-rejection proposal 'curator-authorizations curators
                          odra-package-catalog-curator-authorization-id)]
    [(duplicate-rejection proposal 'publisher-authorizations publishers
                          odra-package-catalog-publisher-authorization-id)]
    [(duplicate-rejection proposal 'policies policies odra-package-catalog-policy-id)]
    [(duplicate-rejection proposal 'policy-generations policies
                          odra-package-catalog-policy-generation)]
    [(duplicate-rejection proposal 'endpoints endpoints
                          odra-package-catalog-endpoint-id)]
    [(not (policy-history-valid? policies))
     (reject proposal 'stale-generation 'policies)]
    [(not
      (for/and ([curator (in-list curators)])
        (andmap (lambda (policy-id) (member policy-id policy-identities string=?))
                (odra-package-catalog-curator-authorization-policy-ids curator))))
     (reject proposal 'invalid-authority 'curator-authorizations)]
    [(for/or ([publisher (in-list publishers)])
       (for/or ([key-id
                 (in-list
                  (odra-package-catalog-publisher-authorization-key-ids publisher))])
         (for/or ([root (in-list roots)])
           (string=? key-id (odra-package-catalog-root-key-id root)))))
     (reject proposal 'invalid-authority 'publisher-authorizations)]
    [(not
      (for/and ([endpoint (in-list endpoints)])
        (string=? (odra-package-catalog-endpoint-catalog-id endpoint)
                  (proposal-identity proposal))))
     (reject proposal 'invalid-field 'endpoints)]
    [else #f]))

(define (normalize-profile proposal)
  (odra-package-catalog-profile
   (odra-package-catalog-profile-proposal-format-version proposal)
   (proposal-identity proposal)
   (odra-package-catalog-profile-proposal-display-name proposal)
   (sort (odra-package-catalog-profile-proposal-roots proposal)
         string<? #:key odra-package-catalog-root-key-id)
   (sort (odra-package-catalog-profile-proposal-curators proposal)
         string<? #:key odra-package-catalog-curator-authorization-id)
   (sort (odra-package-catalog-profile-proposal-publishers proposal)
         string<? #:key odra-package-catalog-publisher-authorization-id)
   (sort (odra-package-catalog-profile-proposal-policies proposal)
         < #:key odra-package-catalog-policy-generation)
   (sort (odra-package-catalog-profile-proposal-endpoints proposal)
         string<? #:key odra-package-catalog-endpoint-id)))

(define (confirm-package-catalog-profile/normalizer proposal normalizer)
  (define rejection (proposal-rejection proposal))
  (if rejection
      (values #f rejection)
      (with-handlers ([exn:fail:out-of-memory?
                       (lambda (_failure)
                         (values #f (reject proposal 'allocation 'profile)))])
        (values (normalizer proposal) #f))))

(define (confirm-package-catalog-profile proposal)
  (confirm-package-catalog-profile/normalizer proposal normalize-profile))

(define (same-package-catalog-identity? left right)
  (string=? (odra-package-catalog-profile-identity left)
            (odra-package-catalog-profile-identity right)))

(define (within-interval? now valid-from valid-until)
  (and (<= valid-from now) (or (not valid-until) (<= now valid-until))))

(define (package-catalog-curator-authorization-active? authorization now policy-id)
  (and (within-interval?
        now
        (odra-package-catalog-curator-authorization-valid-from authorization)
        (odra-package-catalog-curator-authorization-valid-until authorization))
       (member policy-id
               (odra-package-catalog-curator-authorization-policy-ids authorization)
               string=?)
       #t))

(define (package-catalog-publisher-authorization-active?
         authorization now supplied-key-ids)
  (and (within-interval?
        now
        (odra-package-catalog-publisher-authorization-valid-from authorization)
        (odra-package-catalog-publisher-authorization-valid-until authorization))
       (>= (length
            (remove-duplicates
             (filter
              (lambda (key-id)
                (member key-id
                        (odra-package-catalog-publisher-authorization-key-ids
                         authorization)
                        string=?))
              supplied-key-ids)
             string=?))
           (odra-package-catalog-publisher-authorization-threshold authorization))))

(module+ test-support
  (provide confirm-package-catalog-profile-with-normalizer-for-test)

  (define (confirm-package-catalog-profile-with-normalizer-for-test
           proposal normalizer)
    (confirm-package-catalog-profile/normalizer proposal normalizer)))
