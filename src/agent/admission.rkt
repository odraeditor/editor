#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         racket/match
         racket/port
         racket/string
         "authority.rkt"
         "continuity-store.rkt"
         (except-in "continuity.rkt"
                    odra-agent-continuity-store?
                    agent-continuity-database-name
                    open-agent-continuity-store
                    close-agent-continuity-store!)
         "definition.rkt"
         "registry.rkt")

(provide
 maximum-retained-agent-capability-requests
 maximum-agent-request-value-bytes
 maximum-agent-request-validity-milliseconds
 agent-capability-request-storage-datum
 (struct-out odra-agent-record-reference)
 (struct-out odra-agent-package-reference)
 (struct-out odra-agent-schema-reference)
 (struct-out odra-agent-capability-request)
 (struct-out odra-agent-admission-denial)
 (struct-out odra-agent-request-validation)
 (struct-out odra-agent-admission-policy)
 (struct-out odra-agent-admission-decision)
 (struct-out odra-agent-human-decision)
 (struct-out odra-agent-target-kind-definition)
 odra-agent-target-registry?
 (contract-out
  [make-agent-record-reference
   (-> symbol? (or/c symbol? string?) exact-positive-integer?
       odra-agent-record-reference?)]
  [make-agent-package-reference
   (-> (or/c symbol? string?) string? exact-positive-integer?
       odra-agent-package-reference?)]
  [make-agent-schema-reference
   (-> (or/c symbol? string?) exact-positive-integer? symbol?
       exact-positive-integer? odra-agent-schema-reference?)]
  [make-agent-capability-request
   (->* ((or/c symbol? string?)
         (or/c symbol? string?) exact-positive-integer?
         (or/c symbol? string?) exact-positive-integer?
         odra-agent-record-reference?
         (or/c symbol? string?) exact-positive-integer?
         odra-agent-package-reference? odra-agent-schema-reference?
         any/c list? odra-agent-capability-limits? list?
         exact-nonnegative-integer? exact-positive-integer?)
        (#:target-references list?
         #:human-decision-reference (or/c #f odra-agent-record-reference?)
         #:correlation-id (or/c #f symbol? string?)
         #:idempotency-id (or/c #f symbol? string?))
        odra-agent-capability-request?)]
  [record-agent-capability-request!
   (-> odra-agent-continuity-store? odra-agent-capability-request?
       (or/c odra-agent-capability-request? odra-agent-admission-denial?))]
  [inspect-agent-capability-request
   (-> odra-agent-continuity-store? (or/c symbol? string?)
       (or/c #f odra-agent-capability-request?))]
  [inspect-agent-capability-requests
   (-> odra-agent-continuity-store?
       (listof odra-agent-capability-request?))]
  [agent-schema-value?
   (-> any/c any/c boolean?)]
  [agent-schema-owner-references
   (-> any/c any/c (listof odra-agent-owner-reference?))]
  [make-agent-target-kind-definition
   (->* ((or/c symbol? string?) (or/c symbol? string?)
         exact-positive-integer? procedure? procedure?)
        (#:source string?)
        odra-agent-target-kind-definition?)]
  [make-agent-target-registry
   (-> odra-agent-target-registry?)]
  [register-agent-target-kind!
   (-> odra-agent-target-registry? odra-agent-target-kind-definition?
       (or/c odra-agent-target-kind-definition?
             odra-agent-admission-denial?))]
  [agent-target-reference-status
   (-> odra-agent-target-registry? string? (listof string?)
       odra-agent-owner-reference? odra-agent-target-scope?
       symbol?)]
  [validate-agent-capability-request
   (-> odra-agent-continuity-store? odra-agent-authority-store?
       odra-agent-catalog? odra-agent-target-registry?
       odra-agent-capability-request? exact-nonnegative-integer?
       (or/c odra-agent-request-validation?
             odra-agent-admission-denial?))]
  [make-agent-admission-policy
   (->* ((or/c symbol? string?) exact-positive-integer?)
        (#:admitted-effects list?
         #:human-decision-effects list?
         #:human-actors list?
         #:maximum-request-validity-milliseconds exact-nonnegative-integer?
         #:source string?)
        odra-agent-admission-policy?)]
  [default-agent-admission-policy odra-agent-admission-policy?]
  [decide-agent-capability-request!
   (-> odra-agent-continuity-store? odra-agent-authority-store?
       odra-agent-catalog? odra-agent-target-registry?
       (or/c symbol? string?) (or/c symbol? string?)
       odra-agent-admission-policy? exact-nonnegative-integer?
       (or/c odra-agent-admission-decision?
             odra-agent-admission-denial?))]
  [inspect-agent-admission-decision
   (-> odra-agent-continuity-store? (or/c symbol? string?)
       (or/c #f odra-agent-admission-decision?))]
  [record-agent-human-decision!
   (-> odra-agent-continuity-store? (or/c symbol? string?)
       (or/c symbol? string?) (or/c symbol? string?) symbol?
       odra-agent-admission-policy? exact-nonnegative-integer?
       exact-positive-integer?
       (or/c odra-agent-human-decision? odra-agent-admission-denial?))]
  [inspect-agent-human-decision
   (-> odra-agent-continuity-store? (or/c symbol? string?)
       (or/c #f odra-agent-human-decision?))]))

(define maximum-retained-agent-capability-requests 10000)
(define maximum-agent-request-value-bytes (* 64 1024))
(define maximum-agent-request-value-depth 8)
(define maximum-agent-request-value-items 256)
(define maximum-agent-request-references 32)
(define maximum-agent-target-kinds 256)
(define maximum-agent-request-validity-milliseconds (* 15 60 1000))

(define identity-pattern #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")
(define version-pattern
  #px"^(?:0|[1-9][0-9]*)[.](?:0|[1-9][0-9]*)[.](?:0|[1-9][0-9]*)(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?$")
(define admitted-reference-kinds
  '(agent-registration agent-turn capability-definition capability-grant
                       capability-request driver-session agent-definition
                       human-decision interaction package-generation policy
                       task))

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

(define (canonical-effects? effects)
  (and (list? effects)
       (pair? effects)
       (andmap symbol? effects)
       (equal? effects (sort (remove-duplicates effects) symbol<?))
       (andmap
        (lambda (effect) (and (memq effect admitted-agent-effect-classes) #t))
        effects)))

(define (request-value-shape? value [depth 0])
  (and
   (<= depth maximum-agent-request-value-depth)
   (cond
     [(boolean? value) #t]
     [(exact-integer? value)
      (<= (- (expt 2 63)) value (sub1 (expt 2 63)))]
     [(string? value)
      (bounded-text? value maximum-agent-request-value-bytes #:empty? #t)]
     [(bytes? value)
      (<= (bytes-length value) maximum-agent-request-value-bytes)]
     [(symbol? value) (identity? value)]
     [(null? value) #t]
     [(odra-agent-owner-reference? value) #t]
     [(list? value)
      (and (<= (length value) maximum-agent-request-value-items)
           (andmap
            (lambda (item) (request-value-shape? item (add1 depth))) value))]
     [(hash? value)
      (and (immutable? value)
           (<= (hash-count value) maximum-agent-request-value-items)
           (for/and ([(key item) (in-hash value)])
             (and (request-value-shape? key (add1 depth))
                  (request-value-shape? item (add1 depth)))))]
     [else #f])))

(define (request-value? value)
  (and (request-value-shape? value)
       (<= (bytes-length (string->bytes/utf-8 (format "~s" value)))
           maximum-agent-request-value-bytes)))

(define (immutable-copy value)
  (cond
    [(string? value) (string->immutable-string value)]
    [(bytes? value) (bytes->immutable-bytes value)]
    [(pair? value) (map immutable-copy value)]
    [(hash? value)
     (for/hash ([(key item) (in-hash value)])
       (values (immutable-copy key) (immutable-copy item)))]
    [else value]))

(define (encode-datum datum)
  (with-output-to-string (lambda () (write datum))))

(define (decode-datum text who)
  (parameterize ([read-accept-reader #f]
                 [read-accept-lang #f])
    (define input (open-input-string text))
    (define datum (read input))
    (unless (eof-object? (read input))
      (error who "persisted record contains trailing data"))
    datum))

(struct odra-agent-record-reference (kind identity generation) #:transparent)

(define (make-agent-record-reference kind identity generation)
  (unless (memq kind admitted-reference-kinds)
    (raise-arguments-error
     'make-agent-record-reference "unsupported record reference kind"
     "kind" kind))
  (odra-agent-record-reference
   kind
   (immutable-identity identity 'make-agent-record-reference "identity")
   generation))

(struct odra-agent-package-reference
  (identity version contribution-generation)
  #:transparent)

(define (make-agent-package-reference identity version generation)
  (unless (and (bounded-text? version 128)
               (regexp-match? version-pattern version))
    (raise-arguments-error
     'make-agent-package-reference "invalid package version"
     "version" version))
  (odra-agent-package-reference
   (immutable-identity identity 'make-agent-package-reference "identity")
   (string->immutable-string version) generation))

(struct odra-agent-schema-reference
  (capability-identity definition-generation kind compatibility-version)
  #:transparent)

(define (make-agent-schema-reference
         capability-identity definition-generation kind compatibility-version)
  (unless (memq kind '(input result))
    (raise-arguments-error
     'make-agent-schema-reference "unsupported schema reference kind"
     "kind" kind))
  (odra-agent-schema-reference
   (immutable-identity
    capability-identity 'make-agent-schema-reference "capability-identity")
   definition-generation kind compatibility-version))

(struct odra-agent-capability-request
  (identity task-id task-generation agent-identity agent-definition-generation
            registration-reference capability-identity
            capability-definition-generation package-reference
            target-references input-schema-reference input requested-effects
            requested-limits grant-references human-decision-reference
            correlation-id idempotency-id created-at valid-until)
  #:transparent)

(struct odra-agent-admission-denial (code subject safe-detail) #:transparent)

(struct odra-agent-target-kind-definition
  (owner-namespace kind compatibility-version validator containment source)
  #:transparent)

(struct odra-agent-target-registry ([definitions #:mutable]) #:transparent)

(struct odra-agent-request-validation
  (request task agent capability effective-grants effective-effects
           effective-limits)
  #:transparent)

(struct odra-agent-admission-policy
  (identity generation admitted-effects human-decision-effects human-actors
            maximum-request-validity-milliseconds source)
  #:transparent)

(struct odra-agent-admission-decision
  (identity request-id state effective-effects effective-limits
            effective-grants required-human-class reason-code reason-detail
            policy-references decided-at)
  #:transparent)

(struct odra-agent-human-decision
  (identity generation request-id task-id actor value scope
            captured-generations created-at valid-until consumed-by)
  #:transparent)

(define (admission-denial code subject detail)
  (odra-agent-admission-denial
   code (string->immutable-string subject) (string->immutable-string detail)))

(define (record-value-fields value)
  (and
   (list? value)
   (for/list ([entry (in-list value)])
     (and (list? entry)
          (= (length entry) 2)
          (cons (identity-text (car entry)) (cadr entry))))))

(define (map-value-entries value)
  (cond
    [(hash? value) (hash->list value)]
    [(list? value)
     (for/list ([entry (in-list value)])
       (and (list? entry)
            (= (length entry) 2)
            (cons (car entry) (cadr entry))))]
    [else #f]))

(define (schema-value-valid? schema value)
  (cond
    [(eq? schema 'boolean) (boolean? value)]
    [(not (and (list? schema) (pair? schema))) #f]
    [else
     (case (car schema)
       [(integer)
        (and (exact-integer? value)
             (<= (cadr schema) value (caddr schema)))]
       [(string)
        (and (string? value) (bounded-text? value (cadr schema) #:empty? #t))]
       [(bytes)
        (and (bytes? value) (<= (bytes-length value) (cadr schema)))]
       [(enum)
        (define normalized (identity-text value))
        (and normalized
             (for/or ([candidate (in-list (cdr schema))])
               (string=? normalized (identity-text candidate))))]
       [(optional)
        (or (not value) (schema-value-valid? (cadr schema) value))]
       [(list)
        (and (list? value)
             (<= (length value) (cadr schema))
             (andmap
              (lambda (item) (schema-value-valid? (caddr schema) item))
              value))]
       [(map)
        (define entries (map-value-entries value))
        (and entries
             (<= (length entries) (cadr schema))
             (andmap pair? entries)
             (for/and ([entry (in-list entries)])
               (and (schema-value-valid? (caddr schema) (car entry))
                    (schema-value-valid? (cadddr schema) (cdr entry)))))]
       [(record)
        (define fields (record-value-fields value))
        (and fields
             (andmap pair? fields)
             (andmap (lambda (field) (car field)) fields)
             (let ([names (map car fields)])
               (= (length names) (length (remove-duplicates names string=?))))
             (for/and ([entry (in-list fields)])
               (define declared
                 (for/first ([field (in-list (cdr schema))]
                             #:when
                             (string=? (car entry)
                                       (identity-text (car field))))
                   field))
               (and declared
                    (schema-value-valid? (caddr declared) (cdr entry))))
             (for/and ([field (in-list (cdr schema))]
                       #:when (eq? (cadr field) 'required))
               (for/or ([entry (in-list fields)])
                 (string=? (identity-text (car field)) (car entry)))))]
       [(owner-reference)
        (and (odra-agent-owner-reference? value)
             (string=?
              (identity-text (cadr schema))
              (odra-agent-owner-reference-kind value))
             (= (caddr schema)
                (odra-agent-owner-reference-compatibility-version value)))]
       [else #f])]))

(define (agent-schema-value? schema value)
  (and (agent-schema? schema)
       (request-value? value)
       (schema-value-valid? schema value)
       #t))

(define (collect-schema-owner-references schema value)
  (cond
    [(eq? schema 'boolean) '()]
    [(not (and (list? schema) (pair? schema))) '()]
    [else
     (case (car schema)
       [(optional)
        (if value
            (collect-schema-owner-references (cadr schema) value)
            '())]
       [(list)
        (append*
         (for/list ([item (in-list value)])
           (collect-schema-owner-references (caddr schema) item)))]
       [(map)
        (append*
         (for/list ([entry (in-list (map-value-entries value))])
           (append
            (collect-schema-owner-references (caddr schema) (car entry))
            (collect-schema-owner-references (cadddr schema) (cdr entry)))))]
       [(record)
        (append*
         (for/list ([entry (in-list (record-value-fields value))])
           (define declared
             (for/first ([field (in-list (cdr schema))]
                         #:when
                         (string=? (car entry) (identity-text (car field))))
               field))
           (if declared
               (collect-schema-owner-references
                (caddr declared) (cdr entry))
               '())))]
       [(owner-reference) (list value)]
       [else '()])]))

(define (agent-schema-owner-references schema value)
  (if (agent-schema-value? schema value)
      (collect-schema-owner-references schema value)
      '()))

(define (make-agent-target-kind-definition
         owner-namespace kind compatibility-version validator containment
         #:source [source "target owner registration"])
  (unless (and (procedure-arity-includes? validator 1)
               (procedure-arity-includes? containment 2)
               (bounded-text? source 512))
    (raise-arguments-error
     'make-agent-target-kind-definition
     "invalid target kind callbacks or source"))
  (odra-agent-target-kind-definition
   (immutable-identity
    owner-namespace 'make-agent-target-kind-definition "owner-namespace")
   (immutable-identity kind 'make-agent-target-kind-definition "kind")
   compatibility-version validator containment
   (string->immutable-string source)))

(define (make-agent-target-registry)
  (odra-agent-target-registry (make-hash)))

(define (target-definition-key definition)
  (list (odra-agent-target-kind-definition-owner-namespace definition)
        (odra-agent-target-kind-definition-kind definition)
        (odra-agent-target-kind-definition-compatibility-version definition)))

(define (register-agent-target-kind! registry definition)
  (define key (target-definition-key definition))
  (cond
    [(hash-has-key? (odra-agent-target-registry-definitions registry) key)
     (admission-denial
      'duplicate-target-kind
      (odra-agent-target-kind-definition-kind definition)
      "A target kind with this owner and version already exists.")]
    [(>= (hash-count (odra-agent-target-registry-definitions registry))
         maximum-agent-target-kinds)
     (admission-denial
      'target-kind-limit
      (odra-agent-target-kind-definition-kind definition)
      "The target kind registry limit has been reached.")]
    [else
     (hash-set! (odra-agent-target-registry-definitions registry)
                key definition)
     definition]))

(define (checked-target-callback callback arguments admitted)
  (with-handlers ([exn:fail? (lambda (_) 'unavailable)])
    (define result (apply callback arguments))
    (if (memq result admitted) result 'unavailable)))

(define (agent-target-reference-status
         registry owner-namespace target-kinds reference scope)
  (cond
    [(not (string=? owner-namespace
                    (odra-agent-owner-reference-owner-namespace reference)))
     'outside-scope]
    [(not (member (odra-agent-owner-reference-kind reference)
                  target-kinds string=?))
     'outside-scope]
    [else
     (define key
       (list owner-namespace
             (odra-agent-owner-reference-kind reference)
             (odra-agent-owner-reference-compatibility-version reference)))
     (define definition
       (hash-ref (odra-agent-target-registry-definitions registry) key #f))
     (cond
       [(not definition) 'unavailable]
       [else
        (define validity
          (checked-target-callback
           (odra-agent-target-kind-definition-validator definition)
           (list reference)
           '(valid stale unavailable)))
        (if (not (eq? validity 'valid))
            validity
            (checked-target-callback
             (odra-agent-target-kind-definition-containment definition)
             (list reference scope)
             '(valid outside-scope stale unavailable)))])]))

(define (subset? selected admitted)
  (andmap (lambda (value) (member value admitted)) selected))

(define (limits-within? selected maximum)
  (and
   (<= (odra-agent-capability-limits-deadline-milliseconds selected)
       (odra-agent-capability-limits-deadline-milliseconds maximum))
   (<= (odra-agent-capability-limits-input-bytes selected)
       (odra-agent-capability-limits-input-bytes maximum))
   (<= (odra-agent-capability-limits-result-bytes selected)
       (odra-agent-capability-limits-result-bytes maximum))
   (<= (odra-agent-capability-limits-target-references selected)
       (odra-agent-capability-limits-target-references maximum))))

(define (request-input-bytes request)
  (bytes-length
   (string->bytes/utf-8
    (format "~s" (request-value->datum
                  (odra-agent-capability-request-input request))))))

(define (active-task-participant? store task-id agent-identity)
  (for/or
      ([participant
        (in-list (inspect-agent-task-participants store task-id))])
    (and
     (string=? agent-identity
               (odra-agent-task-participant-agent-identity participant))
     (not (odra-agent-task-participant-left-at participant)))))

(define (request-package-matches? request capability)
  (define reference
    (odra-agent-capability-request-package-reference request))
  (and
   (string=?
    (odra-agent-package-reference-identity reference)
    (odra-agent-capability-projection-package-id capability))
   (string=?
    (odra-agent-package-reference-version reference)
    (odra-agent-capability-projection-package-version capability))
   (=
    (odra-agent-package-reference-contribution-generation reference)
    (odra-agent-capability-projection-contribution-generation capability))))

(define (request-schema-matches? request capability)
  (define reference
    (odra-agent-capability-request-input-schema-reference request))
  (and
   (eq? (odra-agent-schema-reference-kind reference) 'input)
   (string=?
    (odra-agent-schema-reference-capability-identity reference)
    (odra-agent-capability-projection-identity capability))
   (=
    (odra-agent-schema-reference-definition-generation reference)
    (odra-agent-capability-projection-definition-generation capability))
   (=
    (odra-agent-schema-reference-compatibility-version reference)
    (odra-agent-capability-projection-compatibility-version capability))))

(define (resolve-request-grants authority-store request at)
  (define visible
    (inspect-agent-grants
     authority-store
     #:agent (odra-agent-capability-request-agent-identity request)
     #:at at))
  (for/list
      ([reference
        (in-list (odra-agent-capability-request-grant-references request))])
    (for/first
        ([grant (in-list visible)]
         #:when
         (and
          (string=?
           (odra-agent-record-reference-identity reference)
           (odra-agent-grant-projection-identity grant))
          (=
           (odra-agent-record-reference-generation reference)
           (odra-agent-grant-projection-generation grant))))
      grant)))

(define (grant-admits-request?
         target-registry request capability grant)
  (and
   (odra-agent-grant-projection? grant)
   (eq? (odra-agent-grant-projection-state grant) 'active)
   (string=?
    (odra-agent-capability-request-capability-identity request)
    (odra-agent-grant-projection-capability-identity grant))
   (=
    (odra-agent-capability-request-agent-definition-generation request)
    (odra-agent-grant-projection-agent-definition-generation grant))
   (=
    (odra-agent-capability-request-capability-definition-generation request)
    (odra-agent-grant-projection-capability-definition-generation grant))
   (or (not (odra-agent-grant-projection-task-restriction grant))
       (string=?
        (odra-agent-capability-request-task-id request)
        (odra-agent-grant-projection-task-restriction grant)))
   (subset? (odra-agent-capability-request-requested-effects request)
            (odra-agent-grant-projection-effects grant))
   (limits-within?
    (odra-agent-capability-request-requested-limits request)
    (odra-agent-grant-projection-limits grant))
   (for/and
       ([reference
         (in-list
          (odra-agent-capability-request-target-references request))])
     (eq?
      (agent-target-reference-status
       target-registry
       (odra-agent-capability-projection-owner-namespace capability)
       (odra-agent-capability-projection-target-kinds capability)
       reference
       (odra-agent-grant-projection-target-scope grant))
      'valid))))

(define (request-validation-denial request code detail)
  (admission-denial
   code (odra-agent-capability-request-identity request) detail))

(define (validate-agent-capability-request
         store authority-store catalog target-registry request at)
  (define task
    (inspect-agent-task store
                        (odra-agent-capability-request-task-id request)))
  (define agent
    (agent-catalog-agent-by-identity
     catalog (odra-agent-capability-request-agent-identity request)))
  (define capability
    (agent-catalog-capability-by-identity
     catalog (odra-agent-capability-request-capability-identity request)))
  (define registration-reference
    (odra-agent-capability-request-registration-reference request))
  (cond
    [(or (< at (odra-agent-capability-request-created-at request))
         (>= at (odra-agent-capability-request-valid-until request)))
     (request-validation-denial
      request 'expired-request "The request is outside its validity window.")]
    [(not task)
     (request-validation-denial
      request 'absent-task "The request task is unavailable.")]
    [(not (= (odra-agent-capability-request-task-generation request)
             (odra-agent-task-generation task)))
     (request-validation-denial
      request 'stale-task "The request task generation is stale.")]
    [(memq (odra-agent-task-state task) '(succeeded failed cancelled))
     (request-validation-denial
      request 'terminal-task "The request task is terminal.")]
    [(not (active-task-participant?
           store
           (odra-agent-capability-request-task-id request)
           (odra-agent-capability-request-agent-identity request)))
     (request-validation-denial
      request 'absent-participant
      "The requesting agent is not an active task participant.")]
    [(not agent)
     (request-validation-denial
      request 'absent-agent "The agent definition is unavailable.")]
    [(not (= (odra-agent-capability-request-agent-definition-generation request)
             (odra-agent-definition-projection-definition-generation agent)))
     (request-validation-denial
      request 'stale-agent "The agent definition generation is stale.")]
    [(or
      (not (string=?
            (odra-agent-record-reference-identity registration-reference)
            (odra-agent-capability-request-agent-identity request)))
      (not (=
            (odra-agent-record-reference-generation registration-reference)
            (odra-agent-capability-request-agent-definition-generation
             request))))
     (request-validation-denial
      request 'stale-registration
      "The active registration reference does not match the agent definition.")]
    [(not capability)
     (request-validation-denial
      request 'absent-capability "The capability definition is unavailable.")]
    [(not (member
           (odra-agent-capability-request-capability-identity request)
           (odra-agent-definition-projection-requested-capabilities agent)
           string=?))
     (request-validation-denial
      request 'invisible-capability
      "The capability is not visible to the requesting agent.")]
    [(not (=
           (odra-agent-capability-request-capability-definition-generation
            request)
           (odra-agent-capability-projection-definition-generation capability)))
     (request-validation-denial
      request 'stale-capability
      "The capability definition generation is stale.")]
    [(not (request-package-matches? request capability))
     (request-validation-denial
      request 'stale-package "The capability package reference is stale.")]
    [(not (request-schema-matches? request capability))
     (request-validation-denial
      request 'stale-schema "The input schema reference is stale.")]
    [(not (agent-schema-value?
           (odra-agent-capability-projection-input-schema capability)
           (odra-agent-capability-request-input request)))
     (request-validation-denial
      request 'schema-mismatch "The request input does not match the schema.")]
    [(not (equal?
           (agent-schema-owner-references
            (odra-agent-capability-projection-input-schema capability)
            (odra-agent-capability-request-input request))
           (odra-agent-capability-request-target-references request)))
     (request-validation-denial
      request 'target-mismatch
      "The explicit target references do not match the schema-bound input.")]
    [(not (subset?
           (odra-agent-capability-request-requested-effects request)
           (odra-agent-capability-projection-effects capability)))
     (request-validation-denial
      request 'effect-escape
      "Requested effects exceed the capability declaration.")]
    [(not (limits-within?
           (odra-agent-capability-request-requested-limits request)
           (odra-agent-capability-projection-hard-limits capability)))
     (request-validation-denial
      request 'limit-escape
      "Requested limits exceed the capability hard limits.")]
    [(> (request-input-bytes request)
        (odra-agent-capability-limits-input-bytes
         (odra-agent-capability-request-requested-limits request)))
     (request-validation-denial
      request 'input-limit "The encoded request input exceeds its limit.")]
    [(> (length (odra-agent-capability-request-target-references request))
        (odra-agent-capability-limits-target-references
         (odra-agent-capability-request-requested-limits request)))
     (request-validation-denial
      request 'target-limit "The request has too many target references.")]
    [(and (memq
           (odra-agent-capability-projection-idempotency-class capability)
           '(deduplicated idempotent non-idempotent))
          (not (odra-agent-capability-request-idempotency-id request)))
     (request-validation-denial
      request 'missing-idempotency
      "This capability requires an idempotency identity.")]
    [else
     (define resolved-grants
       (resolve-request-grants authority-store request at))
     (cond
       [(or (null? resolved-grants) (ormap not resolved-grants))
        (request-validation-denial
         request 'stale-grant "A captured grant reference is unavailable.")]
       [else
        (define effective-grants
          (filter
           (lambda (grant)
             (grant-admits-request?
              target-registry request capability grant))
           resolved-grants))
        (if (null? effective-grants)
            (request-validation-denial
             request
             (cond
               [(not
                 (for/or ([grant (in-list resolved-grants)])
                   (eq? (odra-agent-grant-projection-state grant) 'active)))
                'inactive-grant]
               [(and
                 (pair?
                  (odra-agent-capability-request-target-references request))
                 (not
                  (for/or
                      ([grant (in-list resolved-grants)]
                       #:when
                       (eq? (odra-agent-grant-projection-state grant) 'active))
                    (for/and
                        ([reference
                          (in-list
                           (odra-agent-capability-request-target-references
                            request))])
                      (eq?
                       (agent-target-reference-status
                        target-registry
                        (odra-agent-capability-projection-owner-namespace
                         capability)
                        (odra-agent-capability-projection-target-kinds
                         capability)
                        reference
                        (odra-agent-grant-projection-target-scope grant))
                       'valid)))))
                'target-escape]
               [else 'authority-denied])
             "No current captured grant admits the complete request.")
            (odra-agent-request-validation
             request task agent capability effective-grants
             (odra-agent-capability-request-requested-effects request)
             (odra-agent-capability-request-requested-limits request)))])]))

(define (canonical-effect-set? effects #:empty? [empty? #t])
  (and (list? effects)
       (or empty? (pair? effects))
       (andmap symbol? effects)
       (equal? effects (sort (remove-duplicates effects) symbol<?))
       (andmap
        (lambda (effect) (and (memq effect admitted-agent-effect-classes) #t))
        effects)))

(define (canonical-identity-list? identities)
  (and
   (list? identities)
   (<= (length identities) 32)
   (andmap identity? identities)
   (let ([normalized (map identity-text identities)])
     (equal? normalized
             (sort (remove-duplicates normalized string=?) string<?)))))

(define (make-agent-admission-policy
         identity generation
         #:admitted-effects [admitted-effects '()]
         #:human-decision-effects [human-effects '()]
         #:human-actors [human-actors '()]
         #:maximum-request-validity-milliseconds [maximum-validity 0]
         #:source [source "local deny-by-default admission policy"])
  (unless (and
           (canonical-effect-set? admitted-effects)
           (canonical-effect-set? human-effects)
           (subset? human-effects admitted-effects)
           (canonical-identity-list? human-actors)
           (<= maximum-validity
               maximum-agent-request-validity-milliseconds)
           (bounded-text? source 512))
    (raise-arguments-error
     'make-agent-admission-policy "invalid bounded admission policy"))
  (odra-agent-admission-policy
   (immutable-identity identity 'make-agent-admission-policy "identity")
   generation (append admitted-effects '()) (append human-effects '())
   (map (lambda (actor)
          (immutable-identity actor 'make-agent-admission-policy "human-actor"))
        human-actors)
   maximum-validity (string->immutable-string source)))

(define default-agent-admission-policy
  (make-agent-admission-policy 'local.default 1))

(define (decision->datum decision)
  (list
   'admission-decision
   (odra-agent-admission-decision-identity decision)
   (odra-agent-admission-decision-request-id decision)
   (odra-agent-admission-decision-state decision)
   (odra-agent-admission-decision-effective-effects decision)
   (and (odra-agent-admission-decision-effective-limits decision)
        (limits->datum
         (odra-agent-admission-decision-effective-limits decision)))
   (map record-reference->datum
        (odra-agent-admission-decision-effective-grants decision))
   (odra-agent-admission-decision-required-human-class decision)
   (odra-agent-admission-decision-reason-code decision)
   (odra-agent-admission-decision-reason-detail decision)
   (map record-reference->datum
        (odra-agent-admission-decision-policy-references decision))
   (odra-agent-admission-decision-decided-at decision)))

(define (datum->decision datum)
  (match datum
    [(list 'admission-decision identity request-id state effects limits grants
           human-class reason-code reason-detail policies decided-at)
     (odra-agent-admission-decision
      identity request-id state effects (and limits (datum->limits limits))
      (map datum->record-reference grants) human-class reason-code reason-detail
      (map datum->record-reference policies) decided-at)]
    [_ (error 'inspect-agent-admission-decision
              "invalid persisted admission decision")]))

(define (inspect-agent-admission-decision store request-id)
  (define canonical-request-id
    (immutable-identity
     request-id 'inspect-agent-admission-decision "request-id"))
  (define row (continuity-store-admission-record store canonical-request-id))
  (and row
       (datum->decision
        (decode-datum
         (vector-ref row 2) 'inspect-agent-admission-decision))))

(define (persist-admission-decision!
         store decision #:human-decision [human-decision #f])
  (call-with-agent-continuity-transaction
   store 'decide-capability-request
   (lambda (connection)
     (continuity-transaction-insert-admission!
      connection
      (odra-agent-admission-decision-identity decision)
      (odra-agent-admission-decision-request-id decision)
      (odra-agent-admission-decision-state decision)
      (encode-datum (decision->datum decision))
      (odra-agent-admission-decision-decided-at decision))
     (when human-decision
       (unless
           (continuity-transaction-write-human-decision!
            connection
            (odra-agent-human-decision-identity human-decision)
            (odra-agent-human-decision-generation human-decision)
            (odra-agent-human-decision-request-id human-decision)
            (odra-agent-human-decision-value human-decision)
            (encode-datum (human-decision->datum human-decision))
            (odra-agent-human-decision-created-at human-decision)
            (odra-agent-human-decision-valid-until human-decision)
            (odra-agent-human-decision-consumed-by human-decision))
         (error 'persist-admission-decision!
                "human decision generation changed during publication")))
     decision)))

(define (policy-reference policy)
  (make-agent-record-reference
   'policy
   (odra-agent-admission-policy-identity policy)
   (odra-agent-admission-policy-generation policy)))

(define (validation->grant-references validation)
  (for/list
      ([grant
        (in-list (odra-agent-request-validation-effective-grants validation))])
    (make-agent-record-reference
     'capability-grant
     (odra-agent-grant-projection-identity grant)
     (odra-agent-grant-projection-generation grant))))

(define (human-class-for policy capability request)
  (define approval-class
    (odra-agent-capability-projection-approval-class capability))
  (cond
    [(eq? approval-class 'always) 'always]
    [(eq? approval-class 'ask-once) 'ask-once]
    [(for/or
         ([effect
           (in-list
            (odra-agent-capability-request-requested-effects request))])
       (memq effect
             (odra-agent-admission-policy-human-decision-effects policy)))
     'policy]
    [else #f]))

(define (request-scope-datum request)
  (list
   'request-scope
   (odra-agent-capability-request-identity request)
   (odra-agent-capability-request-task-id request)
   (odra-agent-capability-request-task-generation request)
   (odra-agent-capability-request-agent-identity request)
   (odra-agent-capability-request-agent-definition-generation request)
   (odra-agent-capability-request-capability-identity request)
   (odra-agent-capability-request-capability-definition-generation request)
   (package-reference->datum
    (odra-agent-capability-request-package-reference request))
   (map owner-reference->datum
        (odra-agent-capability-request-target-references request))
   (schema-reference->datum
    (odra-agent-capability-request-input-schema-reference request))
   (request-value->datum (odra-agent-capability-request-input request))
   (odra-agent-capability-request-requested-effects request)
   (limits->datum (odra-agent-capability-request-requested-limits request))
   (map record-reference->datum
        (odra-agent-capability-request-grant-references request))
   (odra-agent-capability-request-correlation-id request)
   (odra-agent-capability-request-idempotency-id request)
   (odra-agent-capability-request-created-at request)
   (odra-agent-capability-request-valid-until request)))

(define (request-captured-generations request policy)
  (list
   (make-agent-record-reference
    'task
    (odra-agent-capability-request-task-id request)
    (odra-agent-capability-request-task-generation request))
   (make-agent-record-reference
    'agent-definition
    (odra-agent-capability-request-agent-identity request)
    (odra-agent-capability-request-agent-definition-generation request))
   (make-agent-record-reference
    'capability-definition
    (odra-agent-capability-request-capability-identity request)
    (odra-agent-capability-request-capability-definition-generation request))
   (make-agent-record-reference
    'package-generation
    (odra-agent-package-reference-identity
     (odra-agent-capability-request-package-reference request))
    (odra-agent-package-reference-contribution-generation
     (odra-agent-capability-request-package-reference request)))
   (policy-reference policy)))

(define (human-decision->datum decision)
  (list
   'human-decision
   (odra-agent-human-decision-identity decision)
   (odra-agent-human-decision-generation decision)
   (odra-agent-human-decision-request-id decision)
   (odra-agent-human-decision-task-id decision)
   (odra-agent-human-decision-actor decision)
   (odra-agent-human-decision-value decision)
   (odra-agent-human-decision-scope decision)
   (map record-reference->datum
        (odra-agent-human-decision-captured-generations decision))
   (odra-agent-human-decision-created-at decision)
   (odra-agent-human-decision-valid-until decision)
   (odra-agent-human-decision-consumed-by decision)))

(define (datum->human-decision datum)
  (match datum
    [(list 'human-decision identity generation request-id task-id actor value
           scope generations created-at valid-until consumed-by)
     (odra-agent-human-decision
      identity generation request-id task-id actor value scope
      (map datum->record-reference generations) created-at valid-until
      consumed-by)]
    [_ (error 'inspect-agent-human-decision
              "invalid persisted human decision")]))

(define (inspect-agent-human-decision store request-id)
  (define canonical-request-id
    (immutable-identity
     request-id 'inspect-agent-human-decision "request-id"))
  (define row
    (continuity-store-human-decision-record store canonical-request-id))
  (and row
       (datum->human-decision
        (decode-datum
         (vector-ref row 3) 'inspect-agent-human-decision))))

(define (record-agent-human-decision!
         store request-id identity actor value policy created-at valid-until)
  (define canonical-request-id
    (immutable-identity
     request-id 'record-agent-human-decision! "request-id"))
  (define canonical-identity
    (immutable-identity
     identity 'record-agent-human-decision! "identity"))
  (define canonical-actor
    (immutable-identity actor 'record-agent-human-decision! "actor"))
  (unless (memq value '(approve-once reject cancel-task))
    (raise-arguments-error
     'record-agent-human-decision! "unsupported human decision value"
     "value" value))
  (define request
    (inspect-agent-capability-request store canonical-request-id))
  (cond
    [(not request)
     (admission-denial
      'absent-request canonical-request-id
      "The capability request does not exist.")]
    [(inspect-agent-human-decision store canonical-request-id)
     (admission-denial
      'duplicate-human-decision canonical-request-id
      "This request already has a human decision.")]
    [(not (member canonical-actor
                  (odra-agent-admission-policy-human-actors policy)
                  string=?))
     (admission-denial
      'inadmissible-human canonical-request-id
      "The actor is not admitted by the current human-decision policy.")]
    [(or (<= valid-until created-at)
         (> valid-until
            (odra-agent-capability-request-valid-until request)))
     (admission-denial
      'invalid-human-validity canonical-request-id
      "The human decision validity exceeds the request validity.")]
    [else
     (define decision
       (odra-agent-human-decision
        canonical-identity 1 canonical-request-id
        (odra-agent-capability-request-task-id request) canonical-actor value
        (request-scope-datum request)
        (request-captured-generations request policy)
        created-at valid-until #f))
     (call-with-agent-continuity-transaction
      store 'record-human-decision
      (lambda (connection)
        (unless
            (continuity-transaction-write-human-decision!
             connection canonical-identity 1 canonical-request-id value
             (encode-datum (human-decision->datum decision))
             created-at valid-until #f)
          (error 'record-agent-human-decision!
                 "human decision publication failed"))
        decision))]))

(define (human-decision-status request decision policy at)
  (cond
    [(not decision) 'absent]
    [(and
      (odra-agent-capability-request-human-decision-reference request)
      (let ([reference
             (odra-agent-capability-request-human-decision-reference request)])
        (or
         (not (string=?
               (odra-agent-record-reference-identity reference)
               (odra-agent-human-decision-identity decision)))
         (not (=
               (odra-agent-record-reference-generation reference)
               (odra-agent-human-decision-generation decision))))))
     'reference]
    [(odra-agent-human-decision-consumed-by decision) 'consumed]
    [(or (< at (odra-agent-human-decision-created-at decision))
         (>= at (odra-agent-human-decision-valid-until decision)))
     'expired]
    [(not (member (odra-agent-human-decision-actor decision)
                  (odra-agent-admission-policy-human-actors policy)
                  string=?))
     'actor]
    [(not (equal? (odra-agent-human-decision-scope decision)
                  (request-scope-datum request)))
     'scope]
    [(not (member
           (policy-reference policy)
           (odra-agent-human-decision-captured-generations decision)
           equal?))
     'policy]
    [else (odra-agent-human-decision-value decision)]))

(define (make-rejected-decision identity request-id denial policy at)
  (odra-agent-admission-decision
   identity request-id 'rejected '() #f '() #f
   (odra-agent-admission-denial-code denial)
   (odra-agent-admission-denial-safe-detail denial)
   (list (policy-reference policy)) at))

(define (decide-agent-capability-request!
         store authority-store catalog target-registry request-id decision-id
         policy at)
  (define canonical-request-id
    (immutable-identity
     request-id 'decide-agent-capability-request! "request-id"))
  (define canonical-decision-id
    (immutable-identity
     decision-id 'decide-agent-capability-request! "decision-id"))
  (define request
    (inspect-agent-capability-request store canonical-request-id))
  (define existing
    (and request
         (inspect-agent-admission-decision store canonical-request-id)))
  (cond
    [(not request)
     (admission-denial
      'absent-request canonical-request-id
      "The capability request does not exist.")]
    [existing
     (if (string=? canonical-decision-id
                   (odra-agent-admission-decision-identity existing))
         existing
         (admission-denial
          'duplicate-decision canonical-request-id
          "This request already has an admission decision."))]
    [else
     (define validation
       (validate-agent-capability-request
        store authority-store catalog target-registry request at))
     (cond
       [(odra-agent-admission-denial? validation)
        (persist-admission-decision!
         store
         (make-rejected-decision
          canonical-decision-id canonical-request-id validation policy at))]
       [(or
         (zero?
          (odra-agent-admission-policy-maximum-request-validity-milliseconds
           policy))
         (>
          (- (odra-agent-capability-request-valid-until request)
             (odra-agent-capability-request-created-at request))
          (odra-agent-admission-policy-maximum-request-validity-milliseconds
           policy)))
        (persist-admission-decision!
         store
         (make-rejected-decision
          canonical-decision-id canonical-request-id
          (request-validation-denial
           request 'policy-validity
           "The request validity exceeds local policy.")
          policy at))]
       [(not (subset?
              (odra-agent-capability-request-requested-effects request)
              (odra-agent-admission-policy-admitted-effects policy)))
        (persist-admission-decision!
         store
         (make-rejected-decision
          canonical-decision-id canonical-request-id
          (request-validation-denial
           request 'policy-effect
           "Local policy does not admit every requested effect.")
          policy at))]
       [else
        (define human-class
          (human-class-for
           policy (odra-agent-request-validation-capability validation)
           request))
        (define human-decision
          (and human-class
               (inspect-agent-human-decision store canonical-request-id)))
        (define human-status
          (and human-class
               (human-decision-status
                request human-decision policy at)))
        (define state
          (cond
            [(not human-class) 'admitted]
            [(eq? human-status 'approve-once) 'admitted]
            [(eq? human-status 'absent) 'needs-human-decision]
            [else 'rejected]))
        (define consumed-human-decision
          (and human-decision
               (memq human-status '(approve-once reject cancel-task))
               (struct-copy
                odra-agent-human-decision human-decision
                [generation
                 (add1 (odra-agent-human-decision-generation human-decision))]
                [consumed-by canonical-decision-id])))
        (define reason-code
          (cond
            [(eq? state 'admitted) #f]
            [(eq? state 'needs-human-decision) 'human-decision-required]
            [(memq human-status '(reject cancel-task))
             (if (eq? human-status 'reject)
                 'human-rejected
                 'human-cancelled)]
            [else
             (string->symbol
              (format "human-decision-~a" human-status))]))
        (define reason-detail
          (cond
            [(eq? state 'admitted)
             "The request is admitted for bounded execution."]
            [(eq? state 'needs-human-decision)
             "This request requires an explicit human decision."]
            [(eq? human-status 'reject)
             "The admitted human rejected this request."]
            [(eq? human-status 'cancel-task)
             "The admitted human cancelled this request and its task intent."]
            [else
             "The recorded human decision is not valid for this request."]))
        (define decision
          (odra-agent-admission-decision
           canonical-decision-id canonical-request-id state
           (if (eq? state 'admitted)
               (odra-agent-request-validation-effective-effects validation)
               '())
           (and (eq? state 'admitted)
                (odra-agent-request-validation-effective-limits validation))
           (if (eq? state 'admitted)
               (validation->grant-references validation)
               '())
           (and (eq? state 'needs-human-decision) human-class)
           reason-code reason-detail
           (list (policy-reference policy)) at))
        (persist-admission-decision!
         store decision #:human-decision consumed-human-decision)])]))

(define (make-agent-capability-request
         identity task-id task-generation agent-identity
         agent-definition-generation registration-reference
         capability-identity capability-definition-generation package-reference
         input-schema-reference input requested-effects requested-limits
         grant-references created-at valid-until
         #:target-references [target-references '()]
         #:human-decision-reference [human-decision-reference #f]
         #:correlation-id [correlation-id #f]
         #:idempotency-id [idempotency-id #f])
  (unless (and
           (eq? (odra-agent-record-reference-kind registration-reference)
                'agent-registration)
           (andmap
            (lambda (reference)
              (and (odra-agent-record-reference? reference)
                   (eq? (odra-agent-record-reference-kind reference)
                        'capability-grant)))
            grant-references)
           (<= (length grant-references) maximum-agent-request-references)
           (or (not human-decision-reference)
               (and
                (odra-agent-record-reference? human-decision-reference)
                (eq? (odra-agent-record-reference-kind
                      human-decision-reference)
                     'human-decision)))
           (<= (length target-references) maximum-agent-request-references)
           (andmap odra-agent-owner-reference? target-references)
           (request-value? input)
           (canonical-effects? requested-effects)
           (< created-at valid-until))
    (raise-arguments-error
     'make-agent-capability-request "invalid bounded capability request"))
  (odra-agent-capability-request
   (immutable-identity identity 'make-agent-capability-request "identity")
   (immutable-identity task-id 'make-agent-capability-request "task-id")
   task-generation
   (immutable-identity
    agent-identity 'make-agent-capability-request "agent-identity")
   agent-definition-generation registration-reference
   (immutable-identity
    capability-identity 'make-agent-capability-request "capability-identity")
   capability-definition-generation package-reference
   (append target-references '()) input-schema-reference
   (immutable-copy input) (append requested-effects '()) requested-limits
   (append grant-references '()) human-decision-reference
   (and correlation-id
        (immutable-identity
         correlation-id 'make-agent-capability-request "correlation-id"))
   (and idempotency-id
        (immutable-identity
         idempotency-id 'make-agent-capability-request "idempotency-id"))
   created-at valid-until))

(define (record-reference->datum reference)
  (list 'record-reference
        (odra-agent-record-reference-kind reference)
        (odra-agent-record-reference-identity reference)
        (odra-agent-record-reference-generation reference)))

(define (datum->record-reference datum)
  (match datum
    [(list 'record-reference kind identity generation)
     (odra-agent-record-reference kind identity generation)]
    [_ (error 'inspect-agent-capability-request
              "invalid persisted record reference")]))

(define (package-reference->datum reference)
  (list 'package-reference
        (odra-agent-package-reference-identity reference)
        (odra-agent-package-reference-version reference)
        (odra-agent-package-reference-contribution-generation reference)))

(define (datum->package-reference datum)
  (match datum
    [(list 'package-reference identity version generation)
     (odra-agent-package-reference identity version generation)]
    [_ (error 'inspect-agent-capability-request
              "invalid persisted package reference")]))

(define (schema-reference->datum reference)
  (list 'schema-reference
        (odra-agent-schema-reference-capability-identity reference)
        (odra-agent-schema-reference-definition-generation reference)
        (odra-agent-schema-reference-kind reference)
        (odra-agent-schema-reference-compatibility-version reference)))

(define (datum->schema-reference datum)
  (match datum
    [(list 'schema-reference identity generation kind version)
     (odra-agent-schema-reference identity generation kind version)]
    [_ (error 'inspect-agent-capability-request
              "invalid persisted schema reference")]))

(define (owner-reference->datum reference)
  (list 'owner-reference
        (odra-agent-owner-reference-owner-namespace reference)
        (odra-agent-owner-reference-kind reference)
        (odra-agent-owner-reference-compatibility-version reference)
        (odra-agent-owner-reference-identity reference)
        (odra-agent-owner-reference-generation reference)))

(define (datum->owner-reference datum)
  (match datum
    [(list 'owner-reference namespace kind version identity generation)
     (odra-agent-owner-reference namespace kind version identity generation)]
    [_ (error 'inspect-agent-capability-request
              "invalid persisted owner reference")]))

(define (request-value->datum value)
  (cond
    [(odra-agent-owner-reference? value)
     (list 'request-owner-reference (owner-reference->datum value))]
    [(list? value)
     (cons 'request-list (map request-value->datum value))]
    [(hash? value)
     (cons
      'request-map
      (for/list ([(key item) (in-hash value)])
        (list (request-value->datum key) (request-value->datum item))))]
    [else value]))

(define (datum->request-value datum)
  (match datum
    [(list 'request-owner-reference reference)
     (datum->owner-reference reference)]
    [(list 'request-list values ...)
     (map datum->request-value values)]
    [(list 'request-map entries ...)
     (for/hash ([entry (in-list entries)])
       (match entry
         [(list key item)
          (values (datum->request-value key)
                  (datum->request-value item))]
         [_ (error 'inspect-agent-capability-request
                   "invalid persisted request map")]))]
    [_ datum]))

(define (limits->datum limits)
  (list 'capability-limits
        (odra-agent-capability-limits-deadline-milliseconds limits)
        (odra-agent-capability-limits-input-bytes limits)
        (odra-agent-capability-limits-result-bytes limits)
        (odra-agent-capability-limits-target-references limits)))

(define (datum->limits datum)
  (match datum
    [(list 'capability-limits deadline input result targets)
     (make-agent-capability-limits
      #:deadline-milliseconds deadline
      #:input-bytes input
      #:result-bytes result
      #:target-references targets)]
    [_ (error 'inspect-agent-capability-request
              "invalid persisted capability limits")]))

(define (request->datum request)
  (list
   'capability-request
   (odra-agent-capability-request-identity request)
   (odra-agent-capability-request-task-id request)
   (odra-agent-capability-request-task-generation request)
   (odra-agent-capability-request-agent-identity request)
   (odra-agent-capability-request-agent-definition-generation request)
   (record-reference->datum
    (odra-agent-capability-request-registration-reference request))
   (odra-agent-capability-request-capability-identity request)
   (odra-agent-capability-request-capability-definition-generation request)
   (package-reference->datum
    (odra-agent-capability-request-package-reference request))
   (map owner-reference->datum
        (odra-agent-capability-request-target-references request))
   (schema-reference->datum
    (odra-agent-capability-request-input-schema-reference request))
   (request-value->datum (odra-agent-capability-request-input request))
   (odra-agent-capability-request-requested-effects request)
   (limits->datum (odra-agent-capability-request-requested-limits request))
   (map record-reference->datum
        (odra-agent-capability-request-grant-references request))
   (and (odra-agent-capability-request-human-decision-reference request)
        (record-reference->datum
         (odra-agent-capability-request-human-decision-reference request)))
   (odra-agent-capability-request-correlation-id request)
   (odra-agent-capability-request-idempotency-id request)
   (odra-agent-capability-request-created-at request)
   (odra-agent-capability-request-valid-until request)))

(define (agent-capability-request-storage-datum request)
  (request->datum request))

(define (datum->request datum)
  (match datum
    [(list 'capability-request identity task-id task-generation agent-identity
           agent-generation registration-reference capability-identity
           capability-generation package-reference target-references
           schema-reference input effects limits grant-references
           human-decision-reference correlation-id idempotency-id
           created-at valid-until)
     (odra-agent-capability-request
      identity task-id task-generation agent-identity agent-generation
      (datum->record-reference registration-reference) capability-identity
      capability-generation (datum->package-reference package-reference)
      (map datum->owner-reference target-references)
      (datum->schema-reference schema-reference)
      (datum->request-value input) effects
      (datum->limits limits) (map datum->record-reference grant-references)
      (and human-decision-reference
           (datum->record-reference human-decision-reference))
      correlation-id idempotency-id created-at valid-until)]
    [_ (error 'inspect-agent-capability-request
              "invalid persisted capability request")]))

(define (request-record->request row payload-index)
  (datum->request
   (decode-datum
    (vector-ref row payload-index) 'inspect-agent-capability-request)))

(define (inspect-agent-capability-request store identity)
  (define canonical-identity
    (immutable-identity
     identity 'inspect-agent-capability-request "identity"))
  (define row (continuity-store-request-record store canonical-identity))
  (and row (request-record->request row 4)))

(define (inspect-agent-capability-requests store)
  (for/list ([row (in-list (continuity-store-request-records store))])
    (request-record->request row 5)))

(define (record-agent-capability-request! store request)
  (define identity (odra-agent-capability-request-identity request))
  (cond
    [(inspect-agent-capability-request store identity)
     (admission-denial
      'duplicate-request identity
      "A capability request with this identity already exists.")]
    [(>= (continuity-store-request-count store)
         maximum-retained-agent-capability-requests)
     (admission-denial
      'request-limit identity
      "The retained capability request limit has been reached.")]
    [else
     (call-with-agent-continuity-transaction
      store 'record-capability-request
      (lambda (connection)
        (continuity-transaction-insert-request!
         connection identity
         (odra-agent-capability-request-task-id request)
         (odra-agent-capability-request-task-generation request)
         (odra-agent-capability-request-agent-identity request)
         (odra-agent-capability-request-capability-identity request)
         (encode-datum (request->datum request))
         (odra-agent-capability-request-created-at request)
         (odra-agent-capability-request-valid-until request))
        request))]))
