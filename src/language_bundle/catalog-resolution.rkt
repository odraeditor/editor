#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         racket/match
         racket/set
         racket/string
         "../package/authority-contract.rkt"
         "catalog-contracts.rkt"
         "catalog-integrity.rkt")

(provide
 (struct-out odra-catalog-resolution-request)
 (struct-out odra-catalog-resolved-bundle)
 (struct-out odra-catalog-replacement)
 (struct-out odra-catalog-resolution)
 (struct-out odra-catalog-resolution-failure)
 (contract-out
  [resolve-catalog-candidates
   (->* ((listof odra-catalog-source?)
         (listof odra-catalog-snapshot?)
         (listof odra-catalog-resolution-request?)
         symbol? symbol? string? exact-nonnegative-integer?)
        (#:granted-authorities (listof symbol?)
         #:replacement-policy hash?)
        (or/c odra-catalog-resolution? odra-catalog-resolution-failure?))]))

(define admitted-facets '(command formatter keymap language service syntax-provider))
(define identity-pattern #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")
(define version-pattern
  #px"^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z.-]+))?$")
(define maximum-message-bytes 4096)

(define (identity? value)
  (and (string? value)
       (<= 1 (bytes-length (string->bytes/utf-8 value)) 128)
       (regexp-match? identity-pattern value)))

(define (symbol<? left right)
  (string<? (symbol->string left) (symbol->string right)))

(define (symbol-set? values admitted)
  (and (list? values)
       (equal? values (sort (remove-duplicates values) symbol<?))
       (andmap (lambda (value) (and (memq value admitted) #t)) values)))

(define (copied value)
  (if (string? value) (string->immutable-string value) value))

(define (bounded-message value)
  (define bytes (string->bytes/utf-8 value))
  (copied
   (if (<= (bytes-length bytes) maximum-message-bytes)
       value
       (bytes->string/utf-8 (subbytes bytes 0 maximum-message-bytes) #\uFFFD))))

(define (parse-version value)
  (match (regexp-match version-pattern value)
    [(list _ major minor patch pre-release)
     (list (string->number major) (string->number minor) (string->number patch)
           (and pre-release (string-split pre-release ".")))]
    [_ #f]))

(define (compare-number left right)
  (cond [(< left right) -1] [(> left right) 1] [else 0]))

(define (numeric-identifier? value)
  (regexp-match? #px"^(?:0|[1-9][0-9]*)$" value))

(define (compare-pre-release left right)
  (cond
    [(and (not left) (not right)) 0]
    [(not left) 1]
    [(not right) -1]
    [else
     (let loop ([left left] [right right])
       (cond
         [(and (null? left) (null? right)) 0]
         [(null? left) -1]
         [(null? right) 1]
         [else
          (define left-id (car left))
          (define right-id (car right))
          (define compared
            (cond
              [(and (numeric-identifier? left-id) (numeric-identifier? right-id))
               (compare-number (string->number left-id) (string->number right-id))]
              [(numeric-identifier? left-id) -1]
              [(numeric-identifier? right-id) 1]
              [(string<? left-id right-id) -1]
              [(string>? left-id right-id) 1]
              [else 0]))
          (if (zero? compared)
              (loop (cdr left) (cdr right))
              compared)]))]))

(define (version-compare left right)
  (define parsed-left (parse-version left))
  (define parsed-right (parse-version right))
  (and parsed-left parsed-right
       (or (for/or ([left-part (in-list (take parsed-left 3))]
                    [right-part (in-list (take parsed-right 3))])
             (define compared (compare-number left-part right-part))
             (and (not (zero? compared)) compared))
           (compare-pre-release (last parsed-left) (last parsed-right)))))

(define (version<=? left right)
  (define compared (version-compare left right))
  (and compared (<= compared 0)))

(struct odra-catalog-resolution-request (bundle-id minimum maximum facets)
  #:transparent
  #:guard
  (lambda (bundle-id minimum maximum facets _)
    (unless (and (identity? bundle-id)
                 (parse-version minimum)
                 (parse-version maximum)
                 (version<=? minimum maximum)
                 (symbol-set? facets admitted-facets))
      (raise-arguments-error 'odra-catalog-resolution-request
                             "invalid bundle resolution request"))
    (values (copied bundle-id) (copied minimum) (copied maximum) facets)))

(struct odra-catalog-resolved-bundle
  (bundle-id version source-id snapshot-digest manifest-digest authorities dependencies)
  #:transparent
  #:guard
  (lambda (bundle-id version source-id snapshot-digest manifest-digest
                     authorities dependencies _)
    (unless (and (identity? bundle-id) (parse-version version)
                 (identity? source-id)
                 (regexp-match? #px"^[0-9a-f]{64}$" snapshot-digest)
                 (regexp-match? #px"^[0-9a-f]{64}$" manifest-digest)
                 (package-authority-set? authorities)
                 (list? dependencies)
                 (equal? dependencies (sort (remove-duplicates dependencies) string<?))
                 (andmap
                  (lambda (dependency)
                    (match (string-split dependency "@")
                      [(list id dependency-version)
                       (and (identity? id) (parse-version dependency-version))]
                      [_ #f]))
                  dependencies))
      (raise-arguments-error 'odra-catalog-resolved-bundle
                             "invalid exact resolved bundle"))
    (values (copied bundle-id) (copied version) (copied source-id)
            (copied snapshot-digest) (copied manifest-digest)
            authorities (map copied dependencies))))

(struct odra-catalog-replacement (replacer replaced)
  #:transparent
  #:guard
  (lambda (replacer replaced _)
    (unless (and (identity? replacer) (identity? replaced)
                 (not (string=? replacer replaced)))
      (raise-arguments-error 'odra-catalog-replacement
                             "invalid exact replacement relation"))
    (values (copied replacer) (copied replaced))))

(struct odra-catalog-resolution
  (snapshot-digests bundles activation-order authority-delta replacements)
  #:transparent
  #:guard
  (lambda (snapshot-digests bundles activation-order authority-delta replacements _)
    (define bundle-identities
      (and (list? bundles) (map odra-catalog-resolved-bundle-bundle-id bundles)))
    (define exact-snapshot-digests
      (and (list? bundles)
           (sort
            (remove-duplicates
             (map odra-catalog-resolved-bundle-snapshot-digest bundles)
             string=?)
            string<?)))
    (unless (and (list? snapshot-digests)
                 (equal? snapshot-digests exact-snapshot-digests)
                 (list? bundles) (pair? bundles)
                 (andmap odra-catalog-resolved-bundle? bundles)
                 (equal? activation-order bundle-identities)
                 (package-authority-set? authority-delta)
                 (list? replacements)
                 (andmap odra-catalog-replacement? replacements)
                 (equal? replacements
                         (sort (remove-duplicates replacements equal?) string<?
                               #:key odra-catalog-replacement-replacer)))
      (raise-arguments-error 'odra-catalog-resolution
                             "invalid deterministic catalog resolution"))
    (values (map copied snapshot-digests) bundles (map copied activation-order)
            authority-delta replacements)))

(define failure-codes
  '(catalog-conflict cycle dependency-conflict invalid-input no-candidate
                     invalid-snapshot replacement-conflict replacement-denied snapshot-conflict
                     untrusted-snapshot unknown-source))

(struct odra-catalog-resolution-failure (code identity candidates message)
  #:transparent
  #:guard
  (lambda (code identity candidates message _)
    (unless (and (memq code failure-codes)
                 (or (string=? identity "") (identity? identity))
                 (list? candidates)
                 (andmap string? candidates)
                 (string? message))
      (raise-arguments-error 'odra-catalog-resolution-failure
                             "invalid catalog resolution failure"))
    (values code (copied identity) (map copied candidates)
            (bounded-message message))))

(struct candidate (source snapshot entry) #:transparent)

(define (failure code identity message [candidates '()])
  (odra-catalog-resolution-failure code identity candidates message))

(define (source-map sources)
  (for/fold ([result (hash)]) ([source (in-list sources)])
    (define id (odra-catalog-source-id source))
    (and result
         (not (hash-has-key? result id))
         (hash-set result id source))))

(define (snapshot-groups snapshots)
  (for/fold ([groups (hash)]) ([snapshot (in-list snapshots)])
    (hash-update groups (odra-catalog-snapshot-source-id snapshot)
                 (lambda (values) (cons snapshot values)) '())))

(define (select-source-snapshots sources snapshots now)
  (define sources-by-id (source-map sources))
  (cond
    [(not sources-by-id)
     (values #f (failure 'invalid-input "" "catalog source identities must be unique"))]
    [else
     (let loop ([groups (sort (hash->list (snapshot-groups snapshots))
                              string<? #:key car)]
                [selected '()])
       (cond
         [(null? groups) (values (reverse selected) #f)]
         [else
          (define source-id (caar groups))
          (define source (hash-ref sources-by-id source-id #f))
          (define group (cdar groups))
          (cond
            [(not source)
             (values #f (failure 'unknown-source source-id
                                 "snapshot source is not configured"))]
            [else
             (define fresh
               (filter
                (lambda (snapshot)
                  (eq? (catalog-expiry-status
                        (odra-catalog-snapshot-expiry snapshot) now)
                       'fresh))
                group))
             (cond
               [(null? fresh) (loop (cdr groups) selected)]
               [else
                (define maximum-sequence
                  (apply max (map odra-catalog-snapshot-sequence fresh)))
                (define latest
                  (filter (lambda (snapshot)
                            (= (odra-catalog-snapshot-sequence snapshot)
                               maximum-sequence))
                          fresh))
                (cond
                  [(> (length latest) 1)
                   (values
                    #f
                    (failure
                     'snapshot-conflict source-id
                     "one source sequence resolves to multiple snapshot digests"
                     (sort (map odra-catalog-snapshot-snapshot-digest latest)
                           string<?)))]
                  [(not (member (odra-catalog-snapshot-signing-key-id (car latest))
                                (map odra-catalog-signing-key-id
                                     (odra-catalog-source-trusted-keys source))
                                string=?))
                   (values #f (failure 'untrusted-snapshot source-id
                                       "snapshot signing key is not configured"))]
                  [(odra-catalog-integrity-failure?
                    (verify-catalog-snapshot source (car latest)))
                   (values #f (failure 'invalid-snapshot source-id
                                       "snapshot integrity verification failed"))]
                  [else (loop (cdr groups) (cons (car latest) selected))])])])]))]))

(define (candidate-better? left right)
  (define left-source (candidate-source left))
  (define right-source (candidate-source right))
  (define left-entry (candidate-entry left))
  (define right-entry (candidate-entry right))
  (cond
    [(not (= (odra-catalog-source-precedence left-source)
             (odra-catalog-source-precedence right-source)))
     (> (odra-catalog-source-precedence left-source)
        (odra-catalog-source-precedence right-source))]
    [(not (zero? (version-compare (odra-catalog-entry-version left-entry)
                                  (odra-catalog-entry-version right-entry))))
     (> (version-compare (odra-catalog-entry-version left-entry)
                         (odra-catalog-entry-version right-entry))
        0)]
    [(not (= (odra-catalog-snapshot-sequence (candidate-snapshot left))
             (odra-catalog-snapshot-sequence (candidate-snapshot right))))
     (> (odra-catalog-snapshot-sequence (candidate-snapshot left))
        (odra-catalog-snapshot-sequence (candidate-snapshot right)))]
    [(not (string=? (odra-catalog-source-id left-source)
                    (odra-catalog-source-id right-source)))
     (string<? (odra-catalog-source-id left-source)
               (odra-catalog-source-id right-source))]
    [else
     (string<? (odra-catalog-snapshot-snapshot-digest (candidate-snapshot left))
               (odra-catalog-snapshot-snapshot-digest (candidate-snapshot right)))]))

(define (target-compatible? entry platform architecture)
  (for/or ([target (in-list (odra-catalog-entry-targets entry))])
    (and (eq? platform (odra-catalog-target-platform target))
         (eq? architecture (odra-catalog-target-architecture target)))))

(define (facets-satisfy? available requested)
  (for/and ([facet (in-list requested)]) (memq facet available)))

(define (entry-satisfies? entry constraints platform architecture api-version)
  (and (target-compatible? entry platform architecture)
       (version<=? (odra-catalog-entry-api-minimum entry) api-version)
       (version<=? api-version (odra-catalog-entry-api-maximum entry))
       (for/and ([constraint (in-list constraints)])
         (and (version<=? (odra-catalog-resolution-request-minimum constraint)
                          (odra-catalog-entry-version entry))
              (version<=? (odra-catalog-entry-version entry)
                          (odra-catalog-resolution-request-maximum constraint))
              (facets-satisfy? (odra-catalog-entry-facets entry)
                               (odra-catalog-resolution-request-facets constraint))))))

(define (candidate-options inventory identity constraints platform architecture api-version)
  (define compatible
    (sort
     (filter
      (lambda (value)
        (define entry (candidate-entry value))
        (and (string=? identity (odra-catalog-entry-bundle-id entry))
             (entry-satisfies? entry constraints platform architecture api-version)))
      inventory)
     candidate-better?))
  (cond
    [(null? compatible)
     (values '() (failure 'no-candidate identity
                          "no catalog entry satisfies all exact constraints"))]
    [else
     (define top (car compatible))
     (define top-entry (candidate-entry top))
     (define peers
       (filter
        (lambda (value)
          (and (= (odra-catalog-source-precedence (candidate-source value))
                  (odra-catalog-source-precedence (candidate-source top)))
               (string=? (odra-catalog-entry-version (candidate-entry value))
                         (odra-catalog-entry-version top-entry))))
        compatible))
     (define manifests
       (remove-duplicates
        (map (lambda (value)
               (odra-catalog-entry-manifest-digest (candidate-entry value)))
             peers)
        string=?))
     (if (> (length manifests) 1)
         (values
          '()
          (failure 'catalog-conflict identity
                   "equal-precedence entries disagree on the exact manifest"
                   (sort manifests string<?)))
         (values compatible #f))]))

(define (required-dependencies entry)
  (filter (lambda (dependency)
            (not (odra-catalog-dependency-summary-optional? dependency)))
          (odra-catalog-entry-dependencies entry)))

(define (dependency->request dependency)
  (odra-catalog-resolution-request
   (odra-catalog-dependency-summary-id dependency)
   (odra-catalog-dependency-summary-minimum dependency)
   (odra-catalog-dependency-summary-maximum dependency)
   (odra-catalog-dependency-summary-facets dependency)))

(define (add-constraint constraints request)
  (hash-update constraints (odra-catalog-resolution-request-bundle-id request)
               (lambda (values) (cons request values)) '()))

(define (solve-required inventory constraints selected edges pending
                        platform architecture api-version)
  (cond
    ((null? pending) (values selected edges #f))
    (else
     (define identity (car (sort (remove-duplicates pending string=?) string<?)))
     (define remaining (remove identity pending string=?))
     (define identity-constraints (hash-ref constraints identity '()))
     (define existing (hash-ref selected identity #f))
     (cond
       (existing
        (if (entry-satisfies? (candidate-entry existing) identity-constraints
                              platform architecture api-version)
            (solve-required inventory constraints selected edges remaining
                            platform architecture api-version)
            (values #f #f
                    (failure 'dependency-conflict identity
                             "selected version violates a later dependency constraint"))))
       (else
        (define-values (options option-failure)
          (candidate-options inventory identity identity-constraints
                             platform architecture api-version))
        (if option-failure
            (values #f #f option-failure)
            (let try ([remaining-options options] [latest-failure #f])
              (cond
                ((null? remaining-options)
                 (values #f #f
                         (or latest-failure
                             (failure 'dependency-conflict identity
                                      "no deterministic dependency graph exists"))))
                (else
                 (define chosen (car remaining-options))
                 (define dependencies
                   (required-dependencies (candidate-entry chosen)))
                 (define next-constraints
                   (for/fold ([result constraints])
                             ([dependency (in-list dependencies)])
                     (add-constraint result (dependency->request dependency))))
                 (define dependency-ids
                   (map odra-catalog-dependency-summary-id dependencies))
                 (define-values (solved solved-edges solve-failure)
                   (solve-required
                    inventory next-constraints
                    (hash-set selected identity chosen)
                    (hash-set edges identity dependency-ids)
                    (append remaining dependency-ids)
                    platform architecture api-version))
                 (if solved
                     (values solved solved-edges #f)
                     (try (cdr remaining-options) solve-failure)))))))))))

(define (activation-order selected edges)
  (let loop ([remaining (sort (hash-keys selected) string<?)] [ordered '()])
    (cond
      ((null? remaining) (values ordered #f))
      (else
       (define ready
         (filter
          (lambda (identity)
            (for/and ([dependency (in-list (hash-ref edges identity '()))])
              (member dependency ordered string=?)))
          remaining))
       (if (null? ready)
           (values #f (failure 'cycle (car remaining)
                               "required bundle dependencies contain a cycle"
                               remaining))
           (loop (filter (lambda (identity)
                           (not (member identity ready string=?)))
                         remaining)
                 (append ordered (sort ready string<?))))))))

(define (replacement-policy? policy)
  (and (hash? policy) (immutable? policy)
       (for/and ([(replacer replaced) (in-hash policy)])
         (and (identity? replacer)
              (list? replaced)
              (equal? replaced (sort (remove-duplicates replaced) string<?))
              (andmap identity? replaced)))))

(define (apply-replacements selected edges order policy)
  (define pairs
    (for/list ([(identity value) (in-hash selected)]
               #:do [(define replaced
                       (odra-catalog-entry-replacement (candidate-entry value)))]
               #:when (and replaced (hash-has-key? selected replaced)))
      (odra-catalog-replacement identity replaced)))
  (define targets (map odra-catalog-replacement-replaced pairs))
  (cond
    [(not (= (length targets) (length (remove-duplicates targets string=?))))
     (values #f #f #f
             (failure 'replacement-conflict ""
                      "multiple selected bundles replace the same identity" targets))]
    [(for/or ([pair (in-list pairs)])
       (member (odra-catalog-replacement-replacer pair) targets string=?))
     (values #f #f #f
             (failure 'replacement-conflict ""
                      "selected replacement relations are cyclic" targets))]
    [else
     (define denied
       (for/first ([pair (in-list pairs)]
                   #:unless
                   (member (odra-catalog-replacement-replaced pair)
                           (hash-ref policy
                                     (odra-catalog-replacement-replacer pair) '())
                           string=?))
         pair))
     (define depended
       (for/first ([target (in-list targets)]
                   #:when
                   (for/or ([(owner dependencies) (in-hash edges)])
                     (and (not (string=? owner target))
                          (member target dependencies string=?))))
         target))
     (cond
       [denied
        (values #f #f #f
                (failure 'replacement-denied
                         (odra-catalog-replacement-replacer denied)
                         "replacement requires matching explicit user policy"
                         (list (odra-catalog-replacement-replaced denied))))]
       [depended
        (values #f #f #f
                (failure 'replacement-conflict depended
                         "a required dependency cannot be removed by replacement"))]
       [else
        (define retained
          (for/fold ([result selected]) ([target (in-list targets)])
            (hash-remove result target)))
        (values retained
                (filter (lambda (identity) (not (member identity targets string=?))) order)
                (sort pairs string<? #:key odra-catalog-replacement-replacer)
                #f)])]))

(define (resolved-bundle identity value selected edges)
  (define entry (candidate-entry value))
  (define snapshot (candidate-snapshot value))
  (define source (candidate-source value))
  (odra-catalog-resolved-bundle
   identity
   (odra-catalog-entry-version entry)
   (odra-catalog-source-id source)
   (odra-catalog-snapshot-snapshot-digest snapshot)
   (odra-catalog-entry-manifest-digest entry)
   (odra-catalog-entry-authorities entry)
   (for/list ([dependency (in-list (sort (hash-ref edges identity '()) string<?))])
     (format "~a@~a" dependency
             (odra-catalog-entry-version
              (candidate-entry (hash-ref selected dependency)))))))

(define (resolve-catalog-candidates sources snapshots requests platform architecture api-version now
                                    #:granted-authorities [granted-authorities '()]
                                    #:replacement-policy [replacement-policy (hash)])
  (cond
    [(or (null? requests)
         (not (member platform '(darwin linux windows)))
         (not (member architecture '(aarch64 x86-64)))
         (not (parse-version api-version))
         (not (package-authority-set? granted-authorities))
         (not (replacement-policy? replacement-policy)))
     (failure 'invalid-input "" "invalid catalog resolution policy or request")]
    [else
     (define-values (selected-snapshots snapshot-failure)
       (select-source-snapshots sources snapshots now))
     (cond
       [snapshot-failure snapshot-failure]
       [else
        (define sources-by-id (source-map sources))
        (define inventory
          (append-map
           (lambda (snapshot)
             (define source
               (hash-ref sources-by-id (odra-catalog-snapshot-source-id snapshot)))
             (map (lambda (entry) (candidate source snapshot entry))
                  (odra-catalog-snapshot-entries snapshot)))
           selected-snapshots))
        (define constraints
          (for/fold ([result (hash)]) ([request (in-list requests)])
            (add-constraint result request)))
        (define pending
          (map odra-catalog-resolution-request-bundle-id requests))
        (define-values (selected edges solve-failure)
          (solve-required inventory constraints (hash) (hash) pending
                          platform architecture api-version))
        (cond
          [solve-failure solve-failure]
          [else
           (define-values (order order-failure) (activation-order selected edges))
           (cond
             [order-failure order-failure]
             [else
              (define-values
                (retained retained-order replacements replacement-failure)
                (apply-replacements selected edges order replacement-policy))
              (cond
                [replacement-failure replacement-failure]
                [else
                 (define bundles
                   (for/list ([identity (in-list retained-order)])
                     (resolved-bundle identity (hash-ref retained identity)
                                      retained edges)))
                 (define authority-delta
                   (sort
                    (set->list
                     (set-subtract
                      (for/fold ([authorities (set)])
                                ([bundle (in-list bundles)])
                        (set-union authorities
                                   (list->set
                                    (odra-catalog-resolved-bundle-authorities bundle))))
                      (list->set granted-authorities)))
                    symbol<?))
                 (odra-catalog-resolution
                  (sort
                   (remove-duplicates
                    (map odra-catalog-resolved-bundle-snapshot-digest bundles)
                    string=?)
                   string<?)
                  bundles retained-order authority-delta replacements)])])])])]))
