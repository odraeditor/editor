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
         "admission.rkt"
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
 agent-driver-compatibility-version
 maximum-agent-driver-definitions
 maximum-agent-driver-sessions
 maximum-agent-turns-per-task
 maximum-agent-turn-context-references
 maximum-agent-turn-input-interactions
 maximum-agent-turn-output-items
 maximum-agent-turn-token-usage
 maximum-agent-turn-cost-micros
 admitted-agent-driver-features
 (struct-out odra-agent-driver-failure)
 (struct-out odra-agent-driver-definition)
 (struct-out odra-agent-driver-projection)
 (struct-out odra-agent-driver-open-context)
 (struct-out odra-agent-driver-open-result)
 (struct-out odra-agent-driver-session)
 (struct-out odra-agent-turn-usage)
 (struct-out odra-agent-turn-context)
 (struct-out odra-agent-request-draft)
 (struct-out odra-agent-turn-output-item)
 (struct-out odra-agent-turn-output)
 (struct-out odra-agent-turn)
 (struct-out odra-agent-turn-invocation)
 (struct-out odra-agent-driver-denial)
 odra-agent-driver-registry?
 (contract-out
  [make-agent-driver
   (->* ((or/c symbol? string?) exact-positive-integer?
         procedure? procedure? procedure? procedure?)
        (#:role (or/c symbol? string?)
         #:features list?
         #:source string?)
        odra-agent-driver-definition?)]
  [make-agent-turn-usage
   (->* ()
        (#:input-tokens exact-nonnegative-integer?
         #:output-tokens exact-nonnegative-integer?
         #:cost-micros exact-nonnegative-integer?
         #:provider-events exact-nonnegative-integer?
         #:input-bytes exact-nonnegative-integer?
         #:output-bytes exact-nonnegative-integer?)
        odra-agent-turn-usage?)]
  [make-agent-turn-output-item
   (-> symbol? any/c odra-agent-turn-output-item?)]
  [make-agent-request-draft
   (->* ((or/c symbol? string?) (or/c symbol? string?) any/c list?
         odra-agent-capability-limits? list? exact-positive-integer?)
        (#:target-references list?
         #:correlation-id (or/c #f symbol? string?)
         #:idempotency-id (or/c #f symbol? string?))
        odra-agent-request-draft?)]
  [make-agent-turn-output
   (->* (list?)
        (#:continuation-reference (or/c #f symbol? string?)
         #:usage odra-agent-turn-usage?)
        odra-agent-turn-output?)]
  [make-agent-driver-registry (-> odra-agent-driver-registry?)]
  [register-agent-driver!
   (-> odra-agent-driver-registry? odra-agent-driver-definition?
       (or/c odra-agent-driver-projection? odra-agent-driver-denial?))]
  [inspect-agent-drivers
   (-> odra-agent-driver-registry? (listof odra-agent-driver-projection?))]
  [open-agent-driver-session!
   (-> odra-agent-continuity-store? odra-agent-driver-registry?
       odra-agent-catalog? (or/c symbol? string?)
       odra-agent-record-reference? (or/c symbol? string?)
       exact-positive-integer? (or/c symbol? string?)
       (or/c symbol? string?) exact-nonnegative-integer?
       (or/c odra-agent-driver-session? odra-agent-driver-denial?))]
  [close-agent-driver-session!
   (-> odra-agent-continuity-store? odra-agent-driver-registry?
       (or/c symbol? string?) exact-positive-integer?
       exact-nonnegative-integer?
       (or/c odra-agent-driver-session? odra-agent-driver-denial?))]
  [replace-agent-driver-session!
   (-> odra-agent-continuity-store? odra-agent-driver-registry?
       odra-agent-catalog? (or/c symbol? string?) exact-positive-integer?
       (or/c symbol? string?) exact-nonnegative-integer?
       (or/c odra-agent-driver-session? odra-agent-driver-denial?))]
  [inspect-agent-driver-session
   (-> odra-agent-continuity-store? (or/c symbol? string?)
       (or/c #f odra-agent-driver-session?))]
  [inspect-agent-task-driver-sessions
   (-> odra-agent-continuity-store? (or/c symbol? string?)
       (listof odra-agent-driver-session?))]
  [prepare-agent-turn!
   (->* (odra-agent-continuity-store? odra-agent-driver-registry?
         odra-agent-authority-store? odra-agent-catalog?
         (or/c symbol? string?) (or/c symbol? string?)
         exact-positive-integer? exact-positive-integer?
         exact-nonnegative-integer?)
        (#:input-interactions list? #:context-references list?)
        (or/c odra-agent-turn? odra-agent-driver-denial?))]
  [invoke-agent-turn!
   (-> odra-agent-continuity-store? odra-agent-driver-registry?
       odra-agent-authority-store? odra-agent-catalog?
       (or/c symbol? string?) exact-positive-integer?
       exact-nonnegative-integer?
       (or/c odra-agent-turn-invocation? odra-agent-driver-denial?))]
  [inspect-agent-turn
   (-> odra-agent-continuity-store? (or/c symbol? string?)
       (or/c #f odra-agent-turn?))]
  [inspect-agent-task-turns
   (-> odra-agent-continuity-store? (or/c symbol? string?)
       (listof odra-agent-turn?))]
  [finalize-agent-turn!
   (-> odra-agent-continuity-store? odra-agent-catalog?
       odra-agent-turn-invocation? (or/c symbol? string?)
       exact-nonnegative-integer?
       (or/c odra-agent-turn? odra-agent-driver-denial?))]
  [cancel-agent-turn!
   (-> odra-agent-continuity-store? odra-agent-driver-registry?
       (or/c symbol? string?) exact-positive-integer?
       exact-nonnegative-integer?
       (or/c odra-agent-turn? odra-agent-driver-denial?))]
  [reconcile-agent-driver-session!
   (-> odra-agent-continuity-store? (or/c symbol? string?)
       exact-positive-integer? exact-nonnegative-integer?
       (or/c odra-agent-driver-session? odra-agent-driver-denial?))]
  [reconcile-agent-turn!
   (-> odra-agent-continuity-store? (or/c symbol? string?)
       exact-positive-integer? exact-nonnegative-integer?
       (or/c odra-agent-turn? odra-agent-driver-denial?))]))

(define agent-driver-compatibility-version 1)
(define maximum-agent-driver-definitions 32)
(define maximum-agent-driver-sessions 128)
(define maximum-agent-turns-per-task 8)
(define maximum-agent-turn-context-references 32)
(define maximum-agent-turn-input-interactions 32)
(define maximum-agent-turn-output-items 64)
(define maximum-agent-turn-token-usage 1000000)
(define maximum-agent-turn-cost-micros 100000000)

(define admitted-agent-driver-features
  '(cancel close continuation interaction-output request-proposal-output
           safe-failure session-open turn usage))
(define admitted-agent-turn-output-kinds
  '(failure progress proposal question request terminal))
(define identity-pattern #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")

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
  (and text (bounded-text? text 128) (regexp-match? identity-pattern text)))

(define (immutable-identity value who field)
  (unless (identity? value)
    (raise-arguments-error who "invalid semantic identity" field value))
  (string->immutable-string (identity-text value)))

(define (symbol<? left right)
  (string<? (symbol->string left) (symbol->string right)))

(define (canonical-features? features)
  (and (list? features)
       (equal? features (sort (remove-duplicates features) symbol<?))
       (andmap
        (lambda (feature)
          (and (memq feature admitted-agent-driver-features) #t))
        features)))

(define required-agent-driver-features admitted-agent-driver-features)

(struct odra-agent-driver-failure (code safe-detail retryable?) #:transparent)

(struct odra-agent-driver-definition
  (role identity generation compatibility-version features source
        open-procedure turn-procedure cancel-procedure close-procedure)
  #:transparent)

(define (make-agent-driver
         identity generation open-procedure turn-procedure cancel-procedure
         close-procedure
         #:role [role 'odra.agent-driver]
         #:features [features required-agent-driver-features]
         #:source [source "trusted driver registration"])
  (unless (and (canonical-features? features)
               (andmap (lambda (feature) (memq feature features))
                       required-agent-driver-features)
               (andmap (lambda (procedure) (procedure-arity-includes? procedure 1))
                       (list open-procedure turn-procedure cancel-procedure
                             close-procedure))
               (bounded-text? source 512))
    (raise-arguments-error
     'make-agent-driver "invalid provider-neutral driver contract"))
  (odra-agent-driver-definition
   (immutable-identity role 'make-agent-driver "role")
   (immutable-identity identity 'make-agent-driver "identity")
   generation agent-driver-compatibility-version features
   (string->immutable-string source)
   open-procedure turn-procedure cancel-procedure close-procedure))

(struct odra-agent-driver-projection
  (role identity generation compatibility-version features source)
  #:transparent)

(struct odra-agent-driver-open-context
  (session-id session-generation task-id task-generation agent-identity
              agent-definition-generation effective-limits)
  #:transparent)

(struct odra-agent-driver-open-result
  (provider-session-reference continuation-reference)
  #:transparent)

(struct odra-agent-driver-session
  (identity generation agent-registration-reference task-id task-generation
            agent-identity agent-definition-generation driver-projection
            provider-session-reference continuation-reference state
            effective-limits opened-at last-observed-at closed-at failure)
  #:transparent)

(struct odra-agent-turn-usage
  (input-tokens output-tokens cost-micros provider-events input-bytes
                output-bytes)
  #:transparent)

(define (make-agent-turn-usage
         #:input-tokens [input-tokens 0]
         #:output-tokens [output-tokens 0]
         #:cost-micros [cost-micros 0]
         #:provider-events [provider-events 0]
         #:input-bytes [input-bytes 0]
         #:output-bytes [output-bytes 0])
  (unless (and (<= input-tokens maximum-agent-turn-token-usage)
               (<= output-tokens maximum-agent-turn-token-usage)
               (<= cost-micros maximum-agent-turn-cost-micros))
    (raise-arguments-error
     'make-agent-turn-usage "agent turn usage exceeds hard limits"))
  (odra-agent-turn-usage
   input-tokens output-tokens cost-micros provider-events input-bytes
   output-bytes))

(struct odra-agent-turn-context
  (turn-id task agent driver-session-reference input-interactions
           context-references visible-capabilities effective-limits deadline
           continuation-reference)
  #:transparent)

(struct odra-agent-request-draft
  (identity capability-identity input requested-effects requested-limits
            grant-references target-references correlation-id idempotency-id
            valid-until)
  #:transparent)

(define (make-agent-request-draft
         identity capability-identity input requested-effects requested-limits
         grant-references valid-until
         #:target-references [target-references '()]
         #:correlation-id [correlation-id #f]
         #:idempotency-id [idempotency-id #f])
  (odra-agent-request-draft
   (immutable-identity identity 'make-agent-request-draft "identity")
   (immutable-identity capability-identity
                       'make-agent-request-draft "capability-identity")
   input (append requested-effects '()) requested-limits
   (append grant-references '()) (append target-references '())
   (and correlation-id
        (immutable-identity correlation-id
                            'make-agent-request-draft "correlation-id"))
   (and idempotency-id
        (immutable-identity idempotency-id
                            'make-agent-request-draft "idempotency-id"))
   valid-until))

(struct odra-agent-turn-output-item (kind payload) #:transparent)

(define (make-agent-turn-output-item kind payload)
  (unless (memq kind admitted-agent-turn-output-kinds)
    (raise-arguments-error
     'make-agent-turn-output-item "unsupported driver output kind" "kind" kind))
  (odra-agent-turn-output-item kind payload))

(struct odra-agent-turn-output (items continuation-reference usage)
  #:transparent)

(define (make-agent-turn-output
         items #:continuation-reference [continuation-reference #f]
         #:usage [usage (make-agent-turn-usage)])
  (unless (and (<= (length items) maximum-agent-turn-output-items)
               (andmap odra-agent-turn-output-item? items)
               (or (not continuation-reference)
                   (identity? continuation-reference)))
    (raise-arguments-error
     'make-agent-turn-output "invalid bounded driver turn output"))
  (odra-agent-turn-output
   (append items '())
   (and continuation-reference
        (immutable-identity continuation-reference
                            'make-agent-turn-output
                            "continuation-reference"))
   usage))

(struct odra-agent-turn
  (identity generation task-id task-generation agent-identity
            agent-definition-generation driver-session-reference state
            input-interaction-references context-references
            visible-capability-generation effective-limits deadline
            output-interaction-references proposed-request-references
            usage-record
            started-at ended-at failure)
  #:transparent)

(struct odra-agent-turn-invocation (turn output) #:transparent)

(struct odra-agent-driver-denial (code safe-detail) #:transparent)

(struct odra-agent-driver-registry (definitions retained-definitions)
  #:transparent)

(define (make-agent-driver-registry)
  (odra-agent-driver-registry (make-hash) (make-hash)))

(define (driver-denial code detail)
  (odra-agent-driver-denial code (string->immutable-string detail)))

(define (driver-projection definition)
  (odra-agent-driver-projection
   (odra-agent-driver-definition-role definition)
   (odra-agent-driver-definition-identity definition)
   (odra-agent-driver-definition-generation definition)
   (odra-agent-driver-definition-compatibility-version definition)
   (append (odra-agent-driver-definition-features definition) '())
   (odra-agent-driver-definition-source definition)))

(define (register-agent-driver! registry definition)
  (define identity (odra-agent-driver-definition-identity definition))
  (define current
    (hash-ref (odra-agent-driver-registry-definitions registry) identity #f))
  (cond
    [(and current
          (<= (odra-agent-driver-definition-generation definition)
              (odra-agent-driver-definition-generation current)))
     (driver-denial
      'stale-driver "Driver replacement requires a newer generation.")]
    [(and (not current)
          (>= (hash-count (odra-agent-driver-registry-definitions registry))
              maximum-agent-driver-definitions))
     (driver-denial
      'driver-limit "The active driver definition limit has been reached.")]
    [else
     (when current
       (hash-set!
        (odra-agent-driver-registry-retained-definitions registry)
        (cons identity (odra-agent-driver-definition-generation current))
        current))
     (hash-set! (odra-agent-driver-registry-definitions registry)
                identity definition)
     (driver-projection definition)]))

(define (inspect-agent-drivers registry)
  (for/list
      ([identity
        (in-list
         (sort (hash-keys (odra-agent-driver-registry-definitions registry))
               string<?))])
    (driver-projection
     (hash-ref (odra-agent-driver-registry-definitions registry) identity))))

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

(define (resource-profile->datum profile)
  (list 'agent-resource-profile
        (odra-agent-resource-profile-turn-deadline-milliseconds profile)
        (odra-agent-resource-profile-context-bytes profile)
        (odra-agent-resource-profile-output-bytes profile)
        (odra-agent-resource-profile-provider-events profile)))

(define (datum->resource-profile datum)
  (match datum
    [(list 'agent-resource-profile deadline context output events)
     (make-agent-resource-profile
      #:turn-deadline-milliseconds deadline
      #:context-bytes context
      #:output-bytes output
      #:provider-events events)]
    [_ (error 'inspect-agent-driver-session
              "invalid persisted driver limits")]))

(define (record-reference->datum reference)
  (list 'record-reference
        (odra-agent-record-reference-kind reference)
        (odra-agent-record-reference-identity reference)
        (odra-agent-record-reference-generation reference)))

(define (datum->record-reference datum)
  (match datum
    [(list 'record-reference kind identity generation)
     (make-agent-record-reference kind identity generation)]
    [_ (error 'inspect-agent-driver-session
              "invalid persisted registration reference")]))

(define (driver-projection->datum projection)
  (list 'driver-projection
        (odra-agent-driver-projection-role projection)
        (odra-agent-driver-projection-identity projection)
        (odra-agent-driver-projection-generation projection)
        (odra-agent-driver-projection-compatibility-version projection)
        (odra-agent-driver-projection-features projection)
        (odra-agent-driver-projection-source projection)))

(define (datum->driver-projection datum)
  (match datum
    [(list 'driver-projection role identity generation compatibility features
           source)
     (odra-agent-driver-projection
      role identity generation compatibility features source)]
    [_ (error 'inspect-agent-driver-session
              "invalid persisted driver projection")]))

(define (failure->datum failure)
  (and failure
       (list 'driver-failure
             (odra-agent-driver-failure-code failure)
             (odra-agent-driver-failure-safe-detail failure)
             (odra-agent-driver-failure-retryable? failure))))

(define (datum->failure datum)
  (match datum
    [#f #f]
    [(list 'driver-failure code detail retryable?)
     (odra-agent-driver-failure code detail retryable?)]
    [_ (error 'inspect-agent-driver-session
              "invalid persisted driver failure")]))

(define (driver-session->datum session)
  (list 'agent-driver-session
        (odra-agent-driver-session-identity session)
        (odra-agent-driver-session-generation session)
        (record-reference->datum
         (odra-agent-driver-session-agent-registration-reference session))
        (odra-agent-driver-session-task-id session)
        (odra-agent-driver-session-task-generation session)
        (odra-agent-driver-session-agent-identity session)
        (odra-agent-driver-session-agent-definition-generation session)
        (driver-projection->datum
         (odra-agent-driver-session-driver-projection session))
        (odra-agent-driver-session-provider-session-reference session)
        (odra-agent-driver-session-continuation-reference session)
        (odra-agent-driver-session-state session)
        (resource-profile->datum
         (odra-agent-driver-session-effective-limits session))
        (odra-agent-driver-session-opened-at session)
        (odra-agent-driver-session-last-observed-at session)
        (odra-agent-driver-session-closed-at session)
        (failure->datum (odra-agent-driver-session-failure session))))

(define (datum->driver-session datum)
  (match datum
    [(list 'agent-driver-session identity generation registration task-id
           task-generation agent-identity agent-generation driver
           provider-reference continuation-reference state limits opened-at
           observed-at closed-at failure)
     (odra-agent-driver-session
      identity generation (datum->record-reference registration) task-id
      task-generation agent-identity agent-generation
      (datum->driver-projection driver) provider-reference
      continuation-reference state (datum->resource-profile limits) opened-at
      observed-at closed-at (datum->failure failure))]
    [_ (error 'inspect-agent-driver-session
              "invalid persisted driver session")]))

(define (inspect-agent-driver-session store identity)
  (define normalized
    (immutable-identity identity 'inspect-agent-driver-session "identity"))
  (define row (continuity-store-driver-session-record store normalized))
  (and row
       (datum->driver-session
        (decode-datum (vector-ref row 7) 'inspect-agent-driver-session))))

(define (inspect-agent-task-driver-sessions store task-id)
  (define normalized
    (immutable-identity task-id 'inspect-agent-task-driver-sessions "task-id"))
  (for/list ([row (in-list
                   (continuity-store-driver-session-records store normalized))])
    (datum->driver-session
     (decode-datum (vector-ref row 7)
                   'inspect-agent-task-driver-sessions))))

(define (write-session! connection session updated-at)
  (define projection (odra-agent-driver-session-driver-projection session))
  (continuity-transaction-write-driver-session!
   connection
   (odra-agent-driver-session-identity session)
   (odra-agent-driver-session-generation session)
   (odra-agent-driver-session-task-id session)
   (odra-agent-driver-session-task-generation session)
   (odra-agent-driver-session-agent-identity session)
   (odra-agent-driver-projection-identity projection)
   (odra-agent-driver-projection-generation projection)
   (odra-agent-driver-session-state session)
   (encode-datum (driver-session->datum session))
   (odra-agent-driver-session-opened-at session)
   updated-at
   (odra-agent-driver-session-closed-at session)))

(define (active-participant? store task-id agent-identity)
  (for/or ([participant
            (in-list (inspect-agent-task-participants store task-id))])
    (and (string=? agent-identity
                   (odra-agent-task-participant-agent-identity participant))
         (not (odra-agent-task-participant-left-at participant)))))

(define (checked-driver-call procedure argument)
  (with-handlers ([exn:fail?
                   (lambda (_)
                     (odra-agent-driver-failure
                      'provider-failure
                      "The driver failed without exposing provider details."
                      #t))])
    (procedure argument)))

(define (valid-open-result? result)
  (and (odra-agent-driver-open-result? result)
       (or (not (odra-agent-driver-open-result-provider-session-reference result))
           (identity?
            (odra-agent-driver-open-result-provider-session-reference result)))
       (or (not (odra-agent-driver-open-result-continuation-reference result))
           (identity?
            (odra-agent-driver-open-result-continuation-reference result)))))

(define (resolve-open-input store registry catalog task-id task-generation
                            agent-identity driver-identity)
  (define task (inspect-agent-task store task-id))
  (define agent (agent-catalog-agent-by-identity catalog agent-identity))
  (define driver
    (hash-ref (odra-agent-driver-registry-definitions registry)
              driver-identity #f))
  (cond
    [(not task) (driver-denial 'unknown-task "The task does not exist.")]
    [(not (= task-generation (odra-agent-task-generation task)))
     (driver-denial 'stale-task "The task generation is stale.")]
    [(memq (odra-agent-task-state task) '(succeeded failed cancelled))
     (driver-denial 'terminal-task "The task is terminal.")]
    [(not agent)
     (driver-denial 'unknown-agent "The agent definition is unavailable.")]
    [(not (active-participant? store task-id agent-identity))
     (driver-denial
      'inactive-agent "The agent is not an active task participant.")]
    [(not driver)
     (driver-denial 'unknown-driver "The driver is unavailable.")]
    [(and (pair? (odra-agent-definition-projection-provider-requirements agent))
          (not (member
                (odra-agent-driver-definition-role driver)
                (odra-agent-definition-projection-provider-requirements agent)
                string=?)))
     (driver-denial
      'incompatible-driver "The driver does not satisfy the agent role.")]
    [else (list task agent driver)]))

(define (opening-session identity generation registration task agent driver now)
  (odra-agent-driver-session
   identity generation registration
   (odra-agent-task-identity task) (odra-agent-task-generation task)
   (odra-agent-definition-projection-identity agent)
   (odra-agent-definition-projection-definition-generation agent)
   (driver-projection driver) #f #f 'opening
   (odra-agent-definition-projection-resource-profile agent)
   now #f #f #f))

(define (complete-session-open store opening driver now)
  (define context
    (odra-agent-driver-open-context
     (odra-agent-driver-session-identity opening)
     (odra-agent-driver-session-generation opening)
     (odra-agent-driver-session-task-id opening)
     (odra-agent-driver-session-task-generation opening)
     (odra-agent-driver-session-agent-identity opening)
     (odra-agent-driver-session-agent-definition-generation opening)
     (odra-agent-driver-session-effective-limits opening)))
  (define result
    (checked-driver-call
     (odra-agent-driver-definition-open-procedure driver) context))
  (define completed
    (cond
      [(odra-agent-driver-failure? result)
       (struct-copy odra-agent-driver-session opening
                    [generation (add1
                                 (odra-agent-driver-session-generation opening))]
                    [state 'failed]
                    [closed-at now]
                    [failure result])]
      [(valid-open-result? result)
       (struct-copy odra-agent-driver-session opening
                    [generation (add1
                                 (odra-agent-driver-session-generation opening))]
                    [provider-session-reference
                     (odra-agent-driver-open-result-provider-session-reference
                      result)]
                    [continuation-reference
                     (odra-agent-driver-open-result-continuation-reference
                      result)]
                    [state 'available]
                    [last-observed-at now])]
      [else
       (struct-copy odra-agent-driver-session opening
                    [generation (add1
                                 (odra-agent-driver-session-generation opening))]
                    [state 'failed]
                    [closed-at now]
                    [failure
                     (odra-agent-driver-failure
                      'malformed-provider-output
                      "The driver returned an invalid session result."
                      #f)])]))
  (call-with-agent-continuity-transaction
   store 'complete-driver-session-open
   (lambda (connection)
     (unless (write-session! connection completed now)
       (error 'open-agent-driver-session! "stale driver session"))
     completed)))

(define (open-agent-driver-session!
         store registry catalog identity registration task-id task-generation
         agent-identity driver-identity now)
  (define normalized-identity
    (immutable-identity identity 'open-agent-driver-session! "identity"))
  (define normalized-task
    (immutable-identity task-id 'open-agent-driver-session! "task-id"))
  (define normalized-agent
    (immutable-identity agent-identity
                        'open-agent-driver-session! "agent-identity"))
  (define normalized-driver
    (immutable-identity driver-identity
                        'open-agent-driver-session! "driver-identity"))
  (cond
    [(not (eq? (odra-agent-record-reference-kind registration)
               'agent-registration))
     (driver-denial
      'invalid-registration "The registration reference kind is invalid.")]
    [(inspect-agent-driver-session store normalized-identity)
     (driver-denial 'duplicate-session "The driver session already exists.")]
    [(>= (continuity-store-driver-session-count store)
         maximum-agent-driver-sessions)
     (driver-denial
      'session-limit "The retained driver session limit has been reached.")]
    [else
     (define resolved
       (resolve-open-input store registry catalog normalized-task
                           task-generation normalized-agent normalized-driver))
     (if (odra-agent-driver-denial? resolved)
         resolved
         (match-let ([(list task agent driver) resolved])
           (define opening
             (opening-session normalized-identity 1 registration task agent
                              driver now))
           (call-with-agent-continuity-transaction
            store 'open-driver-session
            (lambda (connection)
              (unless (write-session! connection opening now)
                (error 'open-agent-driver-session!
                       "driver session publication failed"))
              opening))
           (complete-session-open store opening driver now)))]))

(define (usage->datum usage)
  (list 'agent-turn-usage
        (odra-agent-turn-usage-input-tokens usage)
        (odra-agent-turn-usage-output-tokens usage)
        (odra-agent-turn-usage-cost-micros usage)
        (odra-agent-turn-usage-provider-events usage)
        (odra-agent-turn-usage-input-bytes usage)
        (odra-agent-turn-usage-output-bytes usage)))

(define (datum->usage datum)
  (match datum
    [(list 'agent-turn-usage input-tokens output-tokens cost events
           input-bytes output-bytes)
     (make-agent-turn-usage
      #:input-tokens input-tokens #:output-tokens output-tokens
      #:cost-micros cost #:provider-events events
      #:input-bytes input-bytes #:output-bytes output-bytes)]
    [_ (error 'inspect-agent-turn "invalid persisted turn usage")]))

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
     (make-agent-owner-reference
      namespace kind version identity #:generation generation)]
    [_ (error 'inspect-agent-turn "invalid persisted context reference")]))

(define (turn->datum turn)
  (list 'agent-turn
        (odra-agent-turn-identity turn)
        (odra-agent-turn-generation turn)
        (odra-agent-turn-task-id turn)
        (odra-agent-turn-task-generation turn)
        (odra-agent-turn-agent-identity turn)
        (odra-agent-turn-agent-definition-generation turn)
        (record-reference->datum
         (odra-agent-turn-driver-session-reference turn))
        (odra-agent-turn-state turn)
        (map record-reference->datum
             (odra-agent-turn-input-interaction-references turn))
        (map owner-reference->datum
             (odra-agent-turn-context-references turn))
        (odra-agent-turn-visible-capability-generation turn)
        (resource-profile->datum (odra-agent-turn-effective-limits turn))
        (odra-agent-turn-deadline turn)
        (map record-reference->datum
             (odra-agent-turn-output-interaction-references turn))
        (map record-reference->datum
             (odra-agent-turn-proposed-request-references turn))
        (usage->datum (odra-agent-turn-usage-record turn))
        (odra-agent-turn-started-at turn)
        (odra-agent-turn-ended-at turn)
        (failure->datum (odra-agent-turn-failure turn))))

(define (datum->turn datum)
  (match datum
    [(list 'agent-turn identity generation task-id task-generation
           agent-identity agent-generation session-reference state
           input-references context-references capability-generation limits
           deadline output-references request-references usage started-at
           ended-at failure)
     (odra-agent-turn
      identity generation task-id task-generation agent-identity
      agent-generation (datum->record-reference session-reference) state
      (map datum->record-reference input-references)
      (map datum->owner-reference context-references)
      capability-generation (datum->resource-profile limits) deadline
      (map datum->record-reference output-references)
      (map datum->record-reference request-references)
      (datum->usage usage) started-at ended-at (datum->failure failure))]
    [_ (error 'inspect-agent-turn "invalid persisted agent turn")]))

(define (inspect-agent-turn store identity)
  (define normalized
    (immutable-identity identity 'inspect-agent-turn "identity"))
  (define row (continuity-store-turn-record store normalized))
  (and row
       (datum->turn
        (decode-datum (vector-ref row 8) 'inspect-agent-turn))))

(define (inspect-agent-task-turns store task-id)
  (define normalized
    (immutable-identity task-id 'inspect-agent-task-turns "task-id"))
  (for/list ([row (in-list (continuity-store-turn-records store normalized))])
    (datum->turn
     (decode-datum (vector-ref row 8) 'inspect-agent-task-turns))))

(define (write-turn! connection turn updated-at)
  (define session-reference
    (odra-agent-turn-driver-session-reference turn))
  (continuity-transaction-write-turn!
   connection
   (odra-agent-turn-identity turn)
   (odra-agent-turn-generation turn)
   (odra-agent-turn-task-id turn)
   (odra-agent-turn-task-generation turn)
   (odra-agent-turn-agent-identity turn)
   (odra-agent-record-reference-identity session-reference)
   (odra-agent-record-reference-generation session-reference)
   (odra-agent-turn-state turn)
   (odra-agent-turn-deadline turn)
   (encode-datum (turn->datum turn))
   (odra-agent-turn-started-at turn) updated-at
   (odra-agent-turn-ended-at turn)))

(define (interaction-reference interaction)
  (make-agent-record-reference
   'interaction (odra-agent-interaction-identity interaction)
   (odra-agent-interaction-generation interaction)))

(define (resolve-turn-interactions store task-id identities)
  (for/list ([identity (in-list identities)])
    (define interaction (inspect-agent-interaction store identity))
    (and interaction
         (string=? task-id (odra-agent-interaction-task-id interaction))
         interaction)))

(define (context-size interactions references capabilities)
  (bytes-length
   (string->bytes/utf-8
    (format "~s" (list interactions references capabilities)))))

(define (prepare-agent-turn!
         store registry authority-store catalog identity session-id
         session-generation task-generation now
         #:input-interactions [input-identities '()]
         #:context-references [context-references '()])
  (define normalized-identity
    (immutable-identity identity 'prepare-agent-turn! "identity"))
  (define normalized-session
    (immutable-identity session-id 'prepare-agent-turn! "session-id"))
  (define session (inspect-agent-driver-session store normalized-session))
  (cond
    [(inspect-agent-turn store normalized-identity)
     (driver-denial 'duplicate-turn "The turn already exists.")]
    [(not session)
     (driver-denial 'unknown-session "The driver session does not exist.")]
    [(not (= session-generation
             (odra-agent-driver-session-generation session)))
     (driver-denial 'stale-session "The driver session generation is stale.")]
    [(not (eq? (odra-agent-driver-session-state session) 'available))
     (driver-denial 'busy-session "The driver session is not available.")]
    [(not (= task-generation
             (odra-agent-driver-session-task-generation session)))
     (driver-denial 'stale-task "The task generation is stale.")]
    [(not (driver-for-session registry session))
     (driver-denial 'driver-replaced "The bound driver is unavailable.")]
    [(>= (length (inspect-agent-task-turns
                  store (odra-agent-driver-session-task-id session)))
         maximum-agent-turns-per-task)
     (driver-denial 'turn-limit "The task turn limit has been reached.")]
    [(> (length input-identities) maximum-agent-turn-input-interactions)
     (driver-denial 'input-limit "Too many input interactions were selected.")]
    [(or (> (length context-references)
            maximum-agent-turn-context-references)
         (not (andmap odra-agent-owner-reference? context-references)))
     (driver-denial 'context-limit "The context reference set is invalid.")]
    [else
     (define interactions
       (resolve-turn-interactions
        store (odra-agent-driver-session-task-id session) input-identities))
     (define agent-identity
       (odra-agent-driver-session-agent-identity session))
     (define agent
       (agent-catalog-agent-by-identity catalog agent-identity))
     (define capabilities
       (and agent
            (= (odra-agent-definition-projection-definition-generation agent)
               (odra-agent-driver-session-agent-definition-generation session))
            (discover-agent-capabilities
             catalog authority-store agent-identity #:at now)))
     (cond
       [(ormap not interactions)
        (driver-denial
         'invalid-interaction "An input interaction is unavailable.")]
       [(not capabilities)
        (driver-denial
         'stale-agent "The bound agent definition is unavailable.")]
       [(> (context-size interactions context-references capabilities)
           (odra-agent-resource-profile-context-bytes
            (odra-agent-driver-session-effective-limits session)))
        (driver-denial 'context-limit "The admitted context is too large.")]
       [else
        (define busy-session
          (struct-copy odra-agent-driver-session session
                       [generation (add1 session-generation)]
                       [state 'busy]
                       [last-observed-at now]))
        (define deadline
          (+ now
             (odra-agent-resource-profile-turn-deadline-milliseconds
              (odra-agent-driver-session-effective-limits session))))
        (define prepared
          (odra-agent-turn
           normalized-identity 1
           (odra-agent-driver-session-task-id session) task-generation
           agent-identity
           (odra-agent-driver-session-agent-definition-generation session)
           (make-agent-record-reference
            'driver-session normalized-session
            (odra-agent-driver-session-generation busy-session))
           'prepared
           (map interaction-reference interactions)
           (append context-references '())
           (odra-agent-catalog-generation catalog)
           (odra-agent-driver-session-effective-limits session)
           deadline '() '() (make-agent-turn-usage) now #f #f))
        (call-with-agent-continuity-transaction
         store 'prepare-agent-turn
         (lambda (connection)
           (unless (write-session! connection busy-session now)
             (error 'prepare-agent-turn! "stale driver session"))
           (unless (write-turn! connection prepared now)
             (error 'prepare-agent-turn! "turn publication failed"))
           prepared))])]))

(define (turn-input-interactions store turn)
  (for/list
      ([reference
        (in-list (odra-agent-turn-input-interaction-references turn))])
    (inspect-agent-interaction
     store (odra-agent-record-reference-identity reference))))

(define (invoke-agent-turn!
         store registry authority-store catalog identity generation now)
  (define turn (inspect-agent-turn store identity))
  (cond
    [(not turn) (driver-denial 'unknown-turn "The turn does not exist.")]
    [(not (= generation (odra-agent-turn-generation turn)))
     (driver-denial 'stale-turn "The turn generation is stale.")]
    [(not (eq? (odra-agent-turn-state turn) 'prepared))
     (driver-denial 'invalid-turn-state "The turn is not prepared.")]
    [(> now (odra-agent-turn-deadline turn))
     (define session-reference
       (odra-agent-turn-driver-session-reference turn))
     (define session
       (inspect-agent-driver-session
        store (odra-agent-record-reference-identity session-reference)))
     (when (and session
                (= (odra-agent-driver-session-generation session)
                   (odra-agent-record-reference-generation session-reference)))
       (terminal-turn
        store turn session 'failed (make-agent-turn-usage)
        (odra-agent-driver-failure
         'turn-timeout "The turn deadline elapsed before invocation." #t)
        now))
     (driver-denial 'turn-timeout "The turn deadline has elapsed.")]
    [(not (= (odra-agent-catalog-generation catalog)
             (odra-agent-turn-visible-capability-generation turn)))
     (driver-denial
      'stale-capability-view "The visible capability generation changed.")]
    [else
     (define session-reference
       (odra-agent-turn-driver-session-reference turn))
     (define session
       (inspect-agent-driver-session
        store (odra-agent-record-reference-identity session-reference)))
     (define driver (and session (driver-for-session registry session)))
     (cond
       [(or (not session)
            (not (= (odra-agent-record-reference-generation session-reference)
                    (odra-agent-driver-session-generation session)))
            (not (eq? (odra-agent-driver-session-state session) 'busy)))
        (driver-denial 'stale-session "The turn session is unavailable.")]
       [(not driver)
        (driver-denial 'driver-replaced "The bound driver is unavailable.")]
       [else
        (define running
          (struct-copy odra-agent-turn turn
                       [generation (add1 generation)] [state 'running]))
        (call-with-agent-continuity-transaction
         store 'start-agent-turn
         (lambda (connection)
           (unless (write-turn! connection running now)
             (error 'invoke-agent-turn! "stale agent turn"))
           running))
        (define interactions (turn-input-interactions store running))
        (define capabilities
          (discover-agent-capabilities
           catalog authority-store (odra-agent-turn-agent-identity running)
           #:at now))
        (define context
          (odra-agent-turn-context
           (odra-agent-turn-identity running)
           (inspect-agent-task store (odra-agent-turn-task-id running))
           (agent-catalog-agent-by-identity
            catalog (odra-agent-turn-agent-identity running))
           session-reference interactions
           (odra-agent-turn-context-references running) capabilities
           (odra-agent-turn-effective-limits running)
           (odra-agent-turn-deadline running)
           (odra-agent-driver-session-continuation-reference session)))
        (odra-agent-turn-invocation
         running
         (checked-driver-call
          (odra-agent-driver-definition-turn-procedure driver) context))])]))

(define (turn-value-shape? value [depth 0])
  (and
   (<= depth 8)
   (cond
     [(or (boolean? value) (exact-integer? value) (symbol? value)) #t]
     [(string? value)
      (bounded-text? value maximum-agent-interaction-payload-bytes #:empty? #t)]
     [(bytes? value)
      (<= (bytes-length value) maximum-agent-interaction-payload-bytes)]
     [(odra-agent-owner-reference? value) #t]
     [(null? value) #t]
     [(list? value)
      (and (<= (length value) 256)
           (andmap (lambda (item) (turn-value-shape? item (add1 depth)))
                   value))]
     [else #f])))

(define (bounded-turn-value? value)
  (and (turn-value-shape? value)
       (<= (bytes-length (string->bytes/utf-8 (format "~s" value)))
           maximum-agent-interaction-payload-bytes)))

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

(define (subset? selected admitted)
  (andmap (lambda (value) (member value admitted)) selected))

(define (draft->request draft turn session catalog now)
  (define capability
    (agent-catalog-capability-by-identity
     catalog (odra-agent-request-draft-capability-identity draft)))
  (define input (odra-agent-request-draft-input draft))
  (cond
    [(not capability) #f]
    [(not (member (odra-agent-capability-projection-identity capability)
                  (odra-agent-definition-projection-requested-capabilities
                   (agent-catalog-agent-by-identity
                    catalog (odra-agent-turn-agent-identity turn)))
                  string=?))
     #f]
    [(not (agent-schema-value?
           (odra-agent-capability-projection-input-schema capability) input))
     #f]
    [(not (equal?
           (agent-schema-owner-references
            (odra-agent-capability-projection-input-schema capability) input)
           (odra-agent-request-draft-target-references draft)))
     #f]
    [(not (subset? (odra-agent-request-draft-requested-effects draft)
                   (odra-agent-capability-projection-effects capability)))
     #f]
    [(not (limits-within?
           (odra-agent-request-draft-requested-limits draft)
           (odra-agent-capability-projection-hard-limits capability)))
     #f]
    [(or (<= (odra-agent-request-draft-valid-until draft) now)
         (> (- (odra-agent-request-draft-valid-until draft) now)
            maximum-agent-request-validity-milliseconds))
     #f]
    [else
     (with-handlers ([exn:fail? (lambda (_) #f)])
       (make-agent-capability-request
        (odra-agent-request-draft-identity draft)
        (odra-agent-turn-task-id turn)
        (odra-agent-turn-task-generation turn)
        (odra-agent-turn-agent-identity turn)
        (odra-agent-turn-agent-definition-generation turn)
        (odra-agent-driver-session-agent-registration-reference session)
        (odra-agent-capability-projection-identity capability)
        (odra-agent-capability-projection-definition-generation capability)
        (make-agent-package-reference
         (odra-agent-capability-projection-package-id capability)
         (odra-agent-capability-projection-package-version capability)
         (odra-agent-capability-projection-contribution-generation capability))
        (make-agent-schema-reference
         (odra-agent-capability-projection-identity capability)
         (odra-agent-capability-projection-definition-generation capability)
         'input
         (odra-agent-capability-projection-compatibility-version capability))
        input
        (odra-agent-request-draft-requested-effects draft)
        (odra-agent-request-draft-requested-limits draft)
        (odra-agent-request-draft-grant-references draft)
        now (odra-agent-request-draft-valid-until draft)
        #:target-references
        (odra-agent-request-draft-target-references draft)
        #:correlation-id
        (odra-agent-request-draft-correlation-id draft)
        #:idempotency-id
        (odra-agent-request-draft-idempotency-id draft)))]))

(define (output-kind->interaction-kind kind)
  (case kind
    [(question) 'question]
    [(progress) 'progress]
    [(proposal) 'proposal]
    [(terminal) 'result]
    [(failure) 'failure]
    [else #f]))

(define (usage-within-turn? usage limits item-count output-bytes)
  (and (<= (odra-agent-turn-usage-provider-events usage)
           (odra-agent-resource-profile-provider-events limits))
       (>= (odra-agent-turn-usage-provider-events usage) item-count)
       (<= (odra-agent-turn-usage-output-bytes usage)
           (odra-agent-resource-profile-output-bytes limits))
       (>= (odra-agent-turn-usage-output-bytes usage) output-bytes)
       (<= (odra-agent-turn-usage-input-bytes usage)
           (odra-agent-resource-profile-context-bytes limits))))

(define (terminal-turn store turn session state usage failure now
                       #:interactions [interactions '()]
                       #:requests [requests '()]
                       #:continuation-reference [continuation-reference #f])
  (define next-turn
    (struct-copy odra-agent-turn turn
                 [generation (add1 (odra-agent-turn-generation turn))]
                 [state state]
                 [output-interaction-references
                  (for/list ([interaction (in-list interactions)])
                    (make-agent-record-reference
                     'interaction
                     (odra-agent-interaction-identity interaction) 1))]
                 [proposed-request-references
                  (for/list ([request (in-list requests)])
                    (make-agent-record-reference
                     'capability-request
                     (odra-agent-capability-request-identity request) 1))]
                 [usage-record usage]
                 [ended-at now]
                 [failure failure]))
  (define next-session
    (struct-copy odra-agent-driver-session session
                 [generation
                  (add1 (odra-agent-driver-session-generation session))]
                 [continuation-reference continuation-reference]
                 [state (if (and failure
                                 (not (odra-agent-driver-failure-retryable?
                                       failure)))
                            'failed
                            'available)]
                 [last-observed-at now]
                 [closed-at (and failure
                                 (not (odra-agent-driver-failure-retryable?
                                       failure))
                                 now)]
                 [failure (and failure
                               (not (odra-agent-driver-failure-retryable?
                                     failure))
                               failure)]))
  (call-with-agent-continuity-transaction
   store 'publish-agent-turn-output
   (lambda (connection)
     (for ([interaction (in-list interactions)])
       (continuity-transaction-insert-interaction!
        connection
        (odra-agent-interaction-identity interaction)
        (odra-agent-interaction-task-id interaction)
        1 (odra-agent-interaction-kind interaction)
        (encode-datum (agent-interaction-storage-datum interaction)) now))
     (for ([request (in-list requests)])
       (continuity-transaction-insert-request!
        connection
        (odra-agent-capability-request-identity request)
        (odra-agent-capability-request-task-id request)
        (odra-agent-capability-request-task-generation request)
        (odra-agent-capability-request-agent-identity request)
        (odra-agent-capability-request-capability-identity request)
        (encode-datum (agent-capability-request-storage-datum request))
        now (odra-agent-capability-request-valid-until request)))
     (unless (write-turn! connection next-turn now)
       (error 'finalize-agent-turn! "stale agent turn"))
     (unless (write-session! connection next-session now)
       (error 'finalize-agent-turn! "stale driver session"))
     next-turn)))

(define (finalize-agent-turn! store catalog invocation recipient now)
  (define invoked-turn (odra-agent-turn-invocation-turn invocation))
  (define current
    (inspect-agent-turn store (odra-agent-turn-identity invoked-turn)))
  (define output (odra-agent-turn-invocation-output invocation))
  (define canonical-recipient
    (immutable-identity recipient 'finalize-agent-turn! "recipient"))
  (cond
    [(or (not current)
         (not (= (odra-agent-turn-generation current)
                 (odra-agent-turn-generation invoked-turn)))
         (not (eq? (odra-agent-turn-state current) 'running)))
     (driver-denial 'stale-turn "The running turn is unavailable.")]
    [else
     (define session-reference
       (odra-agent-turn-driver-session-reference current))
     (define session
       (inspect-agent-driver-session
        store (odra-agent-record-reference-identity session-reference)))
     (cond
       [(or (not session)
            (not (= (odra-agent-driver-session-generation session)
                    (odra-agent-record-reference-generation
                     session-reference))))
        (driver-denial 'stale-session "The turn session is unavailable.")]
       [(odra-agent-driver-failure? output)
        (terminal-turn
         store current session 'failed (make-agent-turn-usage) output now)]
       [(or (not (odra-agent-turn-output? output))
            (> now (odra-agent-turn-deadline current)))
        (define failure
          (odra-agent-driver-failure
           (if (> now (odra-agent-turn-deadline current))
               'turn-timeout
               'malformed-provider-output)
           "The driver turn did not produce valid bounded output."
           #f))
        (terminal-turn
         store current session 'failed (make-agent-turn-usage) failure now)]
       [else
        (define items (odra-agent-turn-output-items output))
        (define request-items
          (filter (lambda (item)
                    (eq? (odra-agent-turn-output-item-kind item) 'request))
                  items))
        (define interaction-items
          (filter (lambda (item)
                    (not (eq? (odra-agent-turn-output-item-kind item) 'request)))
                  items))
        (define task (inspect-agent-task store (odra-agent-turn-task-id current)))
        (define interactions
          (for/list ([item (in-list interaction-items)]
                     [index (in-naturals 1)])
            (define kind (output-kind->interaction-kind
                          (odra-agent-turn-output-item-kind item)))
            (and kind
                 (bounded-turn-value?
                  (odra-agent-turn-output-item-payload item))
                 (odra-agent-interaction
                  (string->immutable-string
                   (format "~a.output-~a"
                           (odra-agent-turn-identity current) index))
                  1 (odra-agent-turn-agent-identity current)
                  (odra-agent-turn-agent-identity current)
                  canonical-recipient (odra-agent-turn-task-id current)
                  (odra-agent-task-parent-task-id task)
                  #f kind (odra-agent-turn-output-item-payload item)
                  (odra-agent-turn-context-references current)
                  (and (eq? kind 'question) "agent-question")
                  'participants (odra-agent-turn-identity current) #f now #f
                  (make-agent-interaction-provenance
                   'agent (odra-agent-turn-agent-identity current)
                   #:reference
                   (odra-agent-driver-session-identity session))))))
        (define requests
          (for/list ([item (in-list request-items)])
            (define payload (odra-agent-turn-output-item-payload item))
            (and (odra-agent-request-draft? payload)
                 (draft->request payload current session catalog now))))
        (define output-bytes
          (bytes-length (string->bytes/utf-8 (format "~s" items))))
        (define continuation
          (odra-agent-turn-output-continuation-reference output))
        (define agent
          (agent-catalog-agent-by-identity
           catalog (odra-agent-turn-agent-identity current)))
        (define valid?
          (and task agent
               (andmap values interactions)
               (andmap values requests)
               (usage-within-turn?
                (odra-agent-turn-output-usage output)
                (odra-agent-turn-effective-limits current)
                (length items) output-bytes)
               (or (not continuation)
                   (eq? (odra-agent-definition-projection-continuation-policy
                         agent)
                        'bounded))
               (<= (+ (continuity-store-interaction-count store)
                      (length interactions))
                   maximum-retained-agent-interactions)
               (<= (+ (continuity-store-request-count store)
                      (length requests))
                   maximum-retained-agent-capability-requests)
               (for/and ([interaction (in-list interactions)])
                 (not (inspect-agent-interaction
                       store (odra-agent-interaction-identity interaction))))
               (for/and ([request (in-list requests)])
                 (not (inspect-agent-capability-request
                       store (odra-agent-capability-request-identity request))))))
        (if valid?
            (terminal-turn
             store current session 'completed
             (odra-agent-turn-output-usage output) #f now
             #:interactions interactions #:requests requests
             #:continuation-reference continuation)
            (terminal-turn
             store current session 'failed (make-agent-turn-usage)
             (odra-agent-driver-failure
              'malformed-provider-output
              "The driver turn did not produce valid bounded output."
              #f)
             now))])]))

(define (cancel-agent-turn! store registry identity generation now)
  (define turn (inspect-agent-turn store identity))
  (cond
    [(not turn) (driver-denial 'unknown-turn "The turn does not exist.")]
    [(not (= generation (odra-agent-turn-generation turn)))
     (driver-denial 'stale-turn "The turn generation is stale.")]
    [(memq (odra-agent-turn-state turn)
           '(completed cancelled failed reconciling))
     (driver-denial 'terminal-turn "The turn is terminal.")]
    [else
     (define session-reference
       (odra-agent-turn-driver-session-reference turn))
     (define session
       (inspect-agent-driver-session
        store (odra-agent-record-reference-identity session-reference)))
     (cond
       [(or (not session)
            (not (= (odra-agent-driver-session-generation session)
                    (odra-agent-record-reference-generation
                     session-reference))))
        (driver-denial 'stale-session "The turn session is unavailable.")]
       [else
        (define driver (driver-for-session registry session))
        (when driver
          (checked-driver-call
           (odra-agent-driver-definition-cancel-procedure driver) turn))
        (terminal-turn
         store turn session 'cancelled (make-agent-turn-usage) #f now)])]))

(define (reconcile-agent-driver-session! store identity generation now)
  (define session (inspect-agent-driver-session store identity))
  (cond
    [(not session)
     (driver-denial 'unknown-session "The driver session does not exist.")]
    [(not (= generation (odra-agent-driver-session-generation session)))
     (driver-denial 'stale-session "The driver session generation is stale.")]
    [(memq (odra-agent-driver-session-state session)
           '(closed failed reconciling))
     (driver-denial 'terminal-session
                    "The driver session does not require reconciliation.")]
    [else
     (define reconciling
       (struct-copy odra-agent-driver-session session
                    [generation (add1 generation)]
                    [state 'reconciling]
                    [last-observed-at now]
                    [failure
                     (odra-agent-driver-failure
                      'runtime-ownership-lost
                      "Runtime ownership requires a fresh bounded observation."
                      #t)]))
     (call-with-agent-continuity-transaction
      store 'reconcile-driver-session
      (lambda (connection)
        (unless (write-session! connection reconciling now)
          (error 'reconcile-agent-driver-session! "stale driver session"))
        reconciling))]))

(define (reconcile-agent-turn! store identity generation now)
  (define turn (inspect-agent-turn store identity))
  (cond
    [(not turn) (driver-denial 'unknown-turn "The turn does not exist.")]
    [(not (= generation (odra-agent-turn-generation turn)))
     (driver-denial 'stale-turn "The turn generation is stale.")]
    [(memq (odra-agent-turn-state turn)
           '(completed cancelled failed reconciling))
     (driver-denial 'terminal-turn
                    "The turn does not require reconciliation.")]
    [else
     (define reconciling
       (struct-copy odra-agent-turn turn
                    [generation (add1 generation)]
                    [state 'reconciling]
                    [failure
                     (odra-agent-driver-failure
                      'runtime-ownership-lost
                      "Turn output requires a fresh bounded observation."
                      #t)]))
     (call-with-agent-continuity-transaction
      store 'reconcile-agent-turn
      (lambda (connection)
        (unless (write-turn! connection reconciling now)
          (error 'reconcile-agent-turn! "stale agent turn"))
        reconciling))]))

(define (driver-for-session registry session)
  (define projection (odra-agent-driver-session-driver-projection session))
  (define driver
    (hash-ref (odra-agent-driver-registry-definitions registry)
              (odra-agent-driver-projection-identity projection) #f))
  (cond
    [(and driver
          (= (odra-agent-driver-definition-generation driver)
             (odra-agent-driver-projection-generation projection)))
     driver]
    [else
     (hash-ref
      (odra-agent-driver-registry-retained-definitions registry)
      (cons (odra-agent-driver-projection-identity projection)
            (odra-agent-driver-projection-generation projection))
      #f)]))

(define (close-agent-driver-session! store registry identity generation now)
  (define current (inspect-agent-driver-session store identity))
  (cond
    [(not current)
     (driver-denial 'unknown-session "The driver session does not exist.")]
    [(not (= generation (odra-agent-driver-session-generation current)))
     (driver-denial 'stale-session "The driver session generation is stale.")]
    [(memq (odra-agent-driver-session-state current) '(closed failed))
     (driver-denial 'terminal-session "The driver session is terminal.")]
    [else
     (define driver (driver-for-session registry current))
     (if (not driver)
         (driver-denial 'driver-replaced "The bound driver is unavailable.")
         (begin
           (checked-driver-call
            (odra-agent-driver-definition-close-procedure driver) current)
           (let ([closed
                  (struct-copy odra-agent-driver-session current
                               [generation (add1 generation)]
                               [state 'closed]
                               [last-observed-at now]
                               [closed-at now])])
             (call-with-agent-continuity-transaction
              store 'close-driver-session
              (lambda (connection)
                (unless (write-session! connection closed now)
                  (error 'close-agent-driver-session! "stale driver session"))
                closed)))))]))

(define (replace-agent-driver-session!
         store registry catalog identity generation driver-identity now)
  (define current (inspect-agent-driver-session store identity))
  (cond
    [(not current)
     (driver-denial 'unknown-session "The driver session does not exist.")]
    [(not (= generation (odra-agent-driver-session-generation current)))
     (driver-denial 'stale-session "The driver session generation is stale.")]
    [(memq (odra-agent-driver-session-state current) '(closed failed))
     (driver-denial 'terminal-session "The driver session is terminal.")]
    [else
     (define resolved
       (resolve-open-input
        store registry catalog
        (odra-agent-driver-session-task-id current)
        (odra-agent-driver-session-task-generation current)
        (odra-agent-driver-session-agent-identity current)
        (immutable-identity driver-identity
                            'replace-agent-driver-session!
                            "driver-identity")))
     (if (odra-agent-driver-denial? resolved)
         resolved
         (match-let ([(list task agent driver) resolved])
           (define previous-driver (driver-for-session registry current))
           (when previous-driver
             (checked-driver-call
              (odra-agent-driver-definition-close-procedure previous-driver)
              current))
           (define opening
             (opening-session
              (odra-agent-driver-session-identity current)
              (add1 generation)
              (odra-agent-driver-session-agent-registration-reference current)
              task agent driver now))
           (call-with-agent-continuity-transaction
            store 'replace-driver-session
            (lambda (connection)
              (unless (write-session! connection opening now)
                (error 'replace-agent-driver-session! "stale driver session"))
              opening))
           (complete-session-open store opening driver now)))]))
