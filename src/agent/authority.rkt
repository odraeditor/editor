#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         racket/string
         "../package/authority-contract.rkt"
         "definition.rkt"
         "registry.rkt")

(provide
 maximum-retained-nonexpired-agent-grants
 (struct-out odra-agent-target-scope)
 (struct-out odra-agent-authority-origin)
 (struct-out odra-agent-authority-policy)
 (struct-out odra-agent-grant-request)
 (struct-out odra-agent-capability-grant)
 (struct-out odra-agent-authority-denial)
 (struct-out odra-agent-capability-discovery)
 (struct-out odra-agent-grant-projection)
 odra-agent-authority-store?
 (contract-out
  [make-agent-target-scope
   (-> (or/c symbol? string?) (or/c symbol? string?) any/c
       odra-agent-target-scope?)]
  [make-agent-authority-origin
   (->* (symbol? (or/c symbol? string?))
        (#:decision-reference (or/c #f symbol? string?))
        odra-agent-authority-origin?)]
  [make-agent-authority-policy
   (->* ()
        (#:effects list?
         #:authorities list?
         #:limit-ceiling odra-agent-capability-limits?
         #:maximum-validity-milliseconds exact-nonnegative-integer?
         #:maximum-delegation-depth exact-nonnegative-integer?
         #:source string?)
        odra-agent-authority-policy?)]
  [default-agent-authority-policy odra-agent-authority-policy?]
  [make-agent-grant-request
   (->* ((or/c symbol? string?)
         (or/c symbol? string?) exact-positive-integer?
         string? exact-positive-integer?
         odra-agent-target-scope?
         odra-agent-authority-origin?
         exact-nonnegative-integer?)
        (#:effects list?
         #:limits odra-agent-capability-limits?
         #:task-restriction (or/c #f symbol? string?)
         #:delegation-depth exact-nonnegative-integer?
         #:valid-until (or/c #f exact-positive-integer?))
        odra-agent-grant-request?)]
  [make-agent-authority-store
   (->* () (#:publisher procedure?) odra-agent-authority-store?)]
  [discover-agent-capabilities
   (->* (odra-agent-catalog? odra-agent-authority-store? string?)
        (#:at exact-nonnegative-integer?)
        (listof odra-agent-capability-discovery?))]
  [grant-agent-capability!
   (-> odra-agent-authority-store? odra-agent-catalog?
       odra-agent-grant-request? odra-agent-authority-policy?
       exact-nonnegative-integer?
       (or/c odra-agent-capability-grant? odra-agent-authority-denial?))]
  [revoke-agent-capability-grant!
   (-> odra-agent-authority-store? string? exact-positive-integer? string?
       exact-nonnegative-integer?
       (or/c odra-agent-capability-grant? odra-agent-authority-denial?))]
  [inspect-agent-grants
   (->* (odra-agent-authority-store?)
        (#:agent (or/c #f string?) #:at exact-nonnegative-integer?)
        (listof odra-agent-grant-projection?))]
  [agent-capability-grant-effective?
   (-> odra-agent-catalog? odra-agent-capability-grant?
       exact-nonnegative-integer? boolean?)]
  [agent-capability-authority-effective?
   (->* (odra-agent-authority-store? odra-agent-catalog? string? string?
         exact-nonnegative-integer?)
        (#:task-id (or/c #f string?) #:delegation? boolean?)
        boolean?)]))

(define maximum-retained-nonexpired-agent-grants 1024)
(define maximum-scope-selector-bytes 4096)
(define maximum-scope-selector-depth 4)
(define maximum-scope-selector-items 32)
(define maximum-authority-source-bytes 512)
(define maximum-revocation-reason-bytes 4096)
(define maximum-delegation-depth 8)

(define identity-pattern #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")
(define capability-pattern-pattern
  #px"^(?:[a-z0-9]+(?:[.-][a-z0-9]+)*|[a-z0-9]+(?:[.-][a-z0-9]+)*[.]\\*)$")
(define admitted-origin-kinds
  '(administrator human-decision local-policy local-user))

(define (bounded-text? value maximum #:empty? [empty? #f])
  (and (string? value)
       (or empty? (positive? (string-length value)))
       (not (string-contains? value (string #\nul)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(define (identity-text value)
  (cond
    [(symbol? value) (symbol->string value)]
    [(string? value) value]
    [else #f]))

(define (identity? value)
  (define text (identity-text value))
  (and text
       (bounded-text? text 128)
       (regexp-match? identity-pattern text)))

(define (immutable-identity value who field)
  (unless (identity? value)
    (raise-arguments-error who "invalid semantic identity" field value))
  (string->immutable-string (identity-text value)))

(define (symbol<? left right)
  (string<? (symbol->string left) (symbol->string right)))

(define (canonical-effects? effects #:empty? [empty? #f])
  (and (list? effects)
       (or empty? (pair? effects))
       (andmap symbol? effects)
       (equal? effects (sort (remove-duplicates effects) symbol<?))
       (andmap
        (lambda (effect)
          (and (memq effect admitted-agent-effect-classes) #t))
        effects)))

(define (immutable-copy value)
  (cond
    [(string? value) (string->immutable-string value)]
    [(bytes? value) (bytes->immutable-bytes value)]
    [(pair? value) (map immutable-copy value)]
    [else value]))

(define (scope-selector-shape? value [depth 0])
  (and
   (<= depth maximum-scope-selector-depth)
   (cond
     [(string? value) (bounded-text? value maximum-scope-selector-bytes)]
     [(bytes? value)
      (and (positive? (bytes-length value))
           (<= (bytes-length value) maximum-scope-selector-bytes))]
     [(symbol? value) (identity? value)]
     [(exact-integer? value)
      (<= (- (expt 2 63)) value (sub1 (expt 2 63)))]
     [(list? value)
      (and (pair? value)
           (<= (length value) maximum-scope-selector-items)
           (andmap
            (lambda (item) (scope-selector-shape? item (add1 depth))) value))]
     [else #f])))

(define (scope-selector? value)
  (and (scope-selector-shape? value)
       (<= (bytes-length (string->bytes/utf-8 (format "~s" value)))
           maximum-scope-selector-bytes)))

(struct odra-agent-target-scope
  (owner-namespace kind compatibility-version selector)
  #:transparent)

(define (make-agent-target-scope owner-namespace kind selector)
  (unless (scope-selector? selector)
    (raise-arguments-error
     'make-agent-target-scope "invalid bounded inert scope selector"
     "selector" selector))
  (odra-agent-target-scope
   (immutable-identity
    owner-namespace 'make-agent-target-scope "owner-namespace")
   (immutable-identity kind 'make-agent-target-scope "kind")
   agent-substrate-api-version
   (immutable-copy selector)))

(struct odra-agent-authority-origin
  (kind actor-identity decision-reference)
  #:transparent)

(define (make-agent-authority-origin
         kind actor-identity #:decision-reference [decision-reference #f])
  (unless (memq kind admitted-origin-kinds)
    (raise-arguments-error
     'make-agent-authority-origin "unsupported authority origin kind"
     "kind" kind))
  (odra-agent-authority-origin
   kind
   (immutable-identity
    actor-identity 'make-agent-authority-origin "actor-identity")
   (and decision-reference
        (immutable-identity
         decision-reference 'make-agent-authority-origin
         "decision-reference"))))

(struct odra-agent-authority-policy
  (effects authorities limit-ceiling maximum-validity-milliseconds
           maximum-delegation-depth source)
  #:transparent)

(define (make-agent-authority-policy
         #:effects [effects '()]
         #:authorities [authorities '()]
         #:limit-ceiling [limit-ceiling default-agent-capability-limits]
         #:maximum-validity-milliseconds [maximum-validity 0]
         #:maximum-delegation-depth [delegation-depth 0]
         #:source [source "local deny-by-default policy"])
  (unless (and (canonical-effects? effects #:empty? #t)
               (list? authorities)
               (andmap symbol? authorities)
               (equal? authorities
                       (sort (remove-duplicates authorities) symbol<?))
               (odra-agent-capability-limits? limit-ceiling)
               (exact-nonnegative-integer? maximum-validity)
               (exact-nonnegative-integer? delegation-depth)
               (<= delegation-depth maximum-delegation-depth)
               (bounded-text? source maximum-authority-source-bytes))
    (raise-arguments-error
     'make-agent-authority-policy "invalid bounded authority policy"))
  (odra-agent-authority-policy
   (append effects '()) (append authorities '()) limit-ceiling
   maximum-validity delegation-depth
   (string->immutable-string source)))

(define default-agent-authority-policy (make-agent-authority-policy))

(struct odra-agent-grant-request
  (identity agent-identity agent-definition-generation capability-pattern
            capability-definition-generation target-scope effects limits
            task-restriction delegation-depth origin valid-from valid-until)
  #:transparent)

(define (capability-pattern? value)
  (and (bounded-text? value 128)
       (regexp-match? capability-pattern-pattern value)))

(define (make-agent-grant-request
         identity agent-identity agent-generation capability-pattern
         capability-generation target-scope origin valid-from
         #:effects [effects '(observe)]
         #:limits [limits default-agent-capability-limits]
         #:task-restriction [task-restriction #f]
         #:delegation-depth [delegation-depth 0]
         #:valid-until [valid-until #f])
  (unless (and (exact-positive-integer? agent-generation)
               (capability-pattern? capability-pattern)
               (exact-positive-integer? capability-generation)
               (odra-agent-target-scope? target-scope)
               (canonical-effects? effects)
               (odra-agent-capability-limits? limits)
               (or (not task-restriction) (identity? task-restriction))
               (exact-nonnegative-integer? delegation-depth)
               (<= delegation-depth maximum-delegation-depth)
               (odra-agent-authority-origin? origin)
               (exact-nonnegative-integer? valid-from)
               (or (not valid-until)
                   (and (exact-positive-integer? valid-until)
                        (> valid-until valid-from))))
    (raise-arguments-error
     'make-agent-grant-request "invalid bounded grant request"))
  (odra-agent-grant-request
   (immutable-identity identity 'make-agent-grant-request "identity")
   (immutable-identity
    agent-identity 'make-agent-grant-request "agent-identity")
   agent-generation (string->immutable-string capability-pattern)
   capability-generation target-scope (append effects '()) limits
   (and task-restriction
        (immutable-identity
         task-restriction 'make-agent-grant-request "task-restriction"))
   delegation-depth origin valid-from valid-until))

(struct odra-agent-capability-grant
  (identity generation agent-identity agent-definition-generation
            capability-pattern capability-identity
            capability-definition-generation target-scope effects limits
            task-restriction delegation-depth origin valid-from valid-until
            state revocation-reason revoked-at)
  #:transparent)

(struct odra-agent-authority-denial
  (code subject agent-identity capability-pattern detail)
  #:transparent)

(struct odra-agent-capability-discovery
  (identity definition-generation owner-namespace purpose input-schema
            result-schema target-kinds effects required-authorities
            default-limits hard-limits approval-class availability grant-state
            active-grants)
  #:transparent)

(struct odra-agent-grant-projection
  (identity generation agent-identity agent-definition-generation
            capability-pattern capability-identity
            capability-definition-generation target-scope effects limits
            task-restriction delegation-depth origin valid-from valid-until
            state revocation-reason revoked-at)
  #:transparent)

(struct odra-agent-authority-store ([grants #:mutable] publisher)
  #:transparent)

(define (make-agent-authority-store #:publisher [publisher (lambda (_) #t)])
  (unless (procedure-arity-includes? publisher 1)
    (raise-arguments-error
     'make-agent-authority-store "publisher must accept one candidate state"))
  (odra-agent-authority-store (make-hash) publisher))

(define (denial code subject agent capability detail)
  (odra-agent-authority-denial
   code
   (string->immutable-string subject)
   (and agent (string->immutable-string agent))
   (and capability (string->immutable-string capability))
   (string->immutable-string detail)))

(define (request-denial request code detail)
  (denial code
          (odra-agent-grant-request-identity request)
          (odra-agent-grant-request-agent-identity request)
          (odra-agent-grant-request-capability-pattern request)
          detail))

(define (pattern-matches? pattern identity)
  (cond
    [(string-suffix? pattern ".*")
     (string-prefix? identity (substring pattern 0 (sub1 (string-length pattern))))]
    [else (string=? pattern identity)]))

(define (resolve-capability catalog agent pattern)
  (define visible
    (for/list
        ([identity
          (in-list
           (odra-agent-definition-projection-requested-capabilities agent))]
         #:when (pattern-matches? pattern identity)
         #:do
         [(define capability
            (agent-catalog-capability-by-identity catalog identity))]
         #:when capability)
      capability))
  (cond
    [(null? visible) 'absent]
    [(pair? (cdr visible)) 'ambiguous]
    [else (car visible)]))

(define (subset? selected admitted)
  (andmap (lambda (value) (member value admitted)) selected))

(define (effect-intersection . sets)
  (sort
   (remove-duplicates
    (filter
     (lambda (effect)
       (for/and ([set (in-list (cdr sets))]) (member effect set)))
     (car sets)))
   symbol<?))

(define (limit-intersection . limits)
  (make-agent-capability-limits
   #:deadline-milliseconds
   (apply min
          (map odra-agent-capability-limits-deadline-milliseconds limits))
   #:input-bytes
   (apply min (map odra-agent-capability-limits-input-bytes limits))
   #:result-bytes
   (apply min (map odra-agent-capability-limits-result-bytes limits))
   #:target-references
   (apply min
          (map odra-agent-capability-limits-target-references limits))))

(define (grant-state-at grant at)
  (cond
    [(memq (odra-agent-capability-grant-state grant) '(invalid revoked))
     (odra-agent-capability-grant-state grant)]
    [(< at (odra-agent-capability-grant-valid-from grant)) 'pending]
    [(and (odra-agent-capability-grant-valid-until grant)
          (>= at (odra-agent-capability-grant-valid-until grant)))
     'expired]
    [else 'active]))

(define (grant->projection grant at)
  (odra-agent-grant-projection
   (odra-agent-capability-grant-identity grant)
   (odra-agent-capability-grant-generation grant)
   (odra-agent-capability-grant-agent-identity grant)
   (odra-agent-capability-grant-agent-definition-generation grant)
   (odra-agent-capability-grant-capability-pattern grant)
   (odra-agent-capability-grant-capability-identity grant)
   (odra-agent-capability-grant-capability-definition-generation grant)
   (odra-agent-capability-grant-target-scope grant)
   (odra-agent-capability-grant-effects grant)
   (odra-agent-capability-grant-limits grant)
   (odra-agent-capability-grant-task-restriction grant)
   (odra-agent-capability-grant-delegation-depth grant)
   (odra-agent-capability-grant-origin grant)
   (odra-agent-capability-grant-valid-from grant)
   (odra-agent-capability-grant-valid-until grant)
   (grant-state-at grant at)
   (odra-agent-capability-grant-revocation-reason grant)
   (odra-agent-capability-grant-revoked-at grant)))

(define (grant-state-for store agent-identity capability-identity at)
  (define states
    (for/list
        ([grant (in-hash-values (odra-agent-authority-store-grants store))]
         #:when
         (and
          (string=? agent-identity
                    (odra-agent-capability-grant-agent-identity grant))
          (string=? capability-identity
                    (odra-agent-capability-grant-capability-identity grant))))
      (grant-state-at grant at)))
  (values
   (cond
     [(member 'active states) 'granted]
     [(member 'pending states) 'pending]
     [(member 'revoked states) 'revoked]
     [(member 'expired states) 'expired]
     [else 'ungranted])
   (count (lambda (state) (eq? state 'active)) states)))

(define (discover-agent-capabilities catalog store agent-identity #:at [at 0])
  (define agent (agent-catalog-agent-by-identity catalog agent-identity))
  (if
   (not agent)
   '()
   (for/list
       ([identity
         (in-list
          (odra-agent-definition-projection-requested-capabilities agent))]
        #:do
        [(define capability
           (agent-catalog-capability-by-identity catalog identity))]
        #:when capability)
     (define-values (grant-state active-grants)
       (grant-state-for store agent-identity identity at))
     (odra-agent-capability-discovery
      identity
      (odra-agent-capability-projection-definition-generation capability)
      (odra-agent-capability-projection-owner-namespace capability)
      (odra-agent-capability-projection-purpose capability)
      (odra-agent-capability-projection-input-schema capability)
      (odra-agent-capability-projection-result-schema capability)
      (odra-agent-capability-projection-target-kinds capability)
      (odra-agent-capability-projection-effects capability)
      (odra-agent-capability-projection-required-authorities capability)
      (odra-agent-capability-projection-default-limits capability)
      (odra-agent-capability-projection-hard-limits capability)
      (odra-agent-capability-projection-approval-class capability)
      'available grant-state active-grants))))

(define (publish-grants! store candidate)
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (define published-view
      (make-immutable-hash (hash->list candidate)))
    (and ((odra-agent-authority-store-publisher store) published-view)
         (begin
           (set-odra-agent-authority-store-grants! store candidate)
           #t))))

(define (nonexpired-grant-count store at)
  (count
   (lambda (grant)
     (memq (grant-state-at grant at) '(active pending)))
   (hash-values (odra-agent-authority-store-grants store))))

(define (effective-valid-until request policy)
  (define policy-until
    (and (positive?
          (odra-agent-authority-policy-maximum-validity-milliseconds policy))
         (+ (odra-agent-grant-request-valid-from request)
            (odra-agent-authority-policy-maximum-validity-milliseconds
             policy))))
  (cond
    [(and policy-until (odra-agent-grant-request-valid-until request))
     (min policy-until (odra-agent-grant-request-valid-until request))]
    [policy-until policy-until]
    [else (odra-agent-grant-request-valid-until request)]))

(define (grant-agent-capability! store catalog request policy at)
  (define agent
    (agent-catalog-agent-by-identity
     catalog (odra-agent-grant-request-agent-identity request)))
  (cond
    [(not agent)
     (request-denial request 'absent-agent "agent definition is unavailable")]
    [(not (= (odra-agent-grant-request-agent-definition-generation request)
             (odra-agent-definition-projection-definition-generation agent)))
     (request-denial request 'stale-agent "agent definition generation is stale")]
    [(hash-has-key? (odra-agent-authority-store-grants store)
                    (odra-agent-grant-request-identity request))
     (request-denial request 'duplicate-grant "grant identity already exists")]
    [else
     (define capability
       (resolve-capability
        catalog agent (odra-agent-grant-request-capability-pattern request)))
     (cond
       [(eq? capability 'absent)
        (request-denial
         request 'absent-capability "capability is not visible to the agent")]
       [(eq? capability 'ambiguous)
        (request-denial
         request 'ambiguous-capability
         "capability pattern resolves to more than one visible definition")]
       [(not (= (odra-agent-grant-request-capability-definition-generation request)
                (odra-agent-capability-projection-definition-generation
                 capability)))
        (request-denial
         request 'stale-capability "capability definition generation is stale")]
       [(or
         (not
          (string=?
           (odra-agent-target-scope-owner-namespace
            (odra-agent-grant-request-target-scope request))
           (odra-agent-capability-projection-owner-namespace capability)))
         (not
          (member
           (odra-agent-target-scope-kind
            (odra-agent-grant-request-target-scope request))
           (odra-agent-capability-projection-target-kinds capability))))
        (request-denial
         request 'invalid-scope "target scope is not owned by the capability")]
       [(not
         (subset?
          (filter
           package-authority?
           (map string->symbol
                (odra-agent-capability-projection-required-authorities
                 capability)))
          (odra-agent-capability-projection-package-authorities capability)))
        (request-denial
         request 'package-authority
         "active package authority does not satisfy the capability")]
       [(not
         (subset?
          (map string->symbol
               (odra-agent-capability-projection-required-authorities
                capability))
          (odra-agent-authority-policy-authorities policy)))
        (request-denial
         request 'policy-authority
         "local policy does not admit the capability authority")]
       [(>= (nonexpired-grant-count store at)
            maximum-retained-nonexpired-agent-grants)
        (request-denial request 'grant-limit "active grant limit is reached")]
       [else
        (define effects
          (effect-intersection
           (odra-agent-grant-request-effects request)
           (odra-agent-capability-projection-effects capability)
           (odra-agent-authority-policy-effects policy)))
        (define valid-until (effective-valid-until request policy))
        (cond
          [(null? effects)
           (request-denial
            request 'denied "effective effect authority is empty")]
          [(and valid-until (<= valid-until at))
           (request-denial request 'expired "effective validity has expired")]
          [else
           (define grant
             (odra-agent-capability-grant
              (odra-agent-grant-request-identity request) 1
              (odra-agent-grant-request-agent-identity request)
              (odra-agent-grant-request-agent-definition-generation request)
              (odra-agent-grant-request-capability-pattern request)
              (odra-agent-capability-projection-identity capability)
              (odra-agent-grant-request-capability-definition-generation request)
              (odra-agent-grant-request-target-scope request)
              effects
              (limit-intersection
               (odra-agent-grant-request-limits request)
               (odra-agent-capability-projection-hard-limits capability)
               (odra-agent-authority-policy-limit-ceiling policy))
              (odra-agent-grant-request-task-restriction request)
              (min
               (odra-agent-grant-request-delegation-depth request)
               (odra-agent-authority-policy-maximum-delegation-depth policy))
              (odra-agent-grant-request-origin request)
              (odra-agent-grant-request-valid-from request)
              valid-until
              (if (< at (odra-agent-grant-request-valid-from request))
                  'pending 'active)
              #f #f))
           (define candidate
             (hash-copy (odra-agent-authority-store-grants store)))
           (hash-set! candidate
                      (odra-agent-capability-grant-identity grant) grant)
           (if (publish-grants! store candidate)
               grant
               (request-denial
                request 'publication-failure
                "grant publication failed without changing active authority"))])])]))

(define (revoke-agent-capability-grant!
         store identity expected-generation reason at)
  (define grant
    (hash-ref (odra-agent-authority-store-grants store) identity #f))
  (cond
    [(not grant)
     (denial 'absent-grant identity #f #f "grant is unavailable")]
    [(not (= expected-generation
             (odra-agent-capability-grant-generation grant)))
     (denial 'stale-grant identity
             (odra-agent-capability-grant-agent-identity grant)
             (odra-agent-capability-grant-capability-pattern grant)
             "grant generation is stale")]
    [(eq? (grant-state-at grant at) 'revoked)
     (denial 'revoked identity
             (odra-agent-capability-grant-agent-identity grant)
             (odra-agent-capability-grant-capability-pattern grant)
             "grant is already revoked")]
    [(not (bounded-text? reason maximum-revocation-reason-bytes))
     (denial 'invalid-reason identity
             (odra-agent-capability-grant-agent-identity grant)
             (odra-agent-capability-grant-capability-pattern grant)
             "revocation reason is invalid")]
    [else
     (define revoked
       (struct-copy
        odra-agent-capability-grant grant
        [generation (add1 (odra-agent-capability-grant-generation grant))]
        [state 'revoked]
        [revocation-reason (string->immutable-string reason)]
        [revoked-at at]))
     (define candidate
       (hash-copy (odra-agent-authority-store-grants store)))
     (hash-set! candidate identity revoked)
     (if (publish-grants! store candidate)
         revoked
         (denial 'publication-failure identity
                 (odra-agent-capability-grant-agent-identity grant)
                 (odra-agent-capability-grant-capability-pattern grant)
                 "revocation publication failed without changing authority"))]))

(define (inspect-agent-grants store #:agent [agent #f] #:at [at 0])
  (for/list
      ([grant
        (in-list
         (sort (hash-values (odra-agent-authority-store-grants store))
               string<? #:key odra-agent-capability-grant-identity))]
       #:when
       (or (not agent)
           (string=? agent
                     (odra-agent-capability-grant-agent-identity grant))))
    (grant->projection grant at)))

(define (agent-capability-grant-effective? catalog grant at)
  (define agent
    (agent-catalog-agent-by-identity
     catalog (odra-agent-capability-grant-agent-identity grant)))
  (define capability
    (agent-catalog-capability-by-identity
     catalog (odra-agent-capability-grant-capability-identity grant)))
  (and
   (eq? (grant-state-at grant at) 'active)
   agent capability
   (= (odra-agent-capability-grant-agent-definition-generation grant)
      (odra-agent-definition-projection-definition-generation agent))
   (= (odra-agent-capability-grant-capability-definition-generation grant)
      (odra-agent-capability-projection-definition-generation capability))
   (string=?
    (odra-agent-target-scope-owner-namespace
     (odra-agent-capability-grant-target-scope grant))
    (odra-agent-capability-projection-owner-namespace capability))
   #t))

(define (agent-capability-authority-effective?
         store catalog agent-identity capability-identity at
         #:task-id [task-id #f]
         #:delegation? [delegation? #f])
  (for/or
      ([grant
        (in-hash-values (odra-agent-authority-store-grants store))])
    (and
     (string=? agent-identity
               (odra-agent-capability-grant-agent-identity grant))
     (string=? capability-identity
               (odra-agent-capability-grant-capability-identity grant))
     (or (not (odra-agent-capability-grant-task-restriction grant))
         (and task-id
              (string=?
               task-id
               (odra-agent-capability-grant-task-restriction grant))))
     (or (not delegation?)
         (positive? (odra-agent-capability-grant-delegation-depth grant)))
     (agent-capability-grant-effective? catalog grant at))))
