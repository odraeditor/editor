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
         "continuity-store.rkt"
         (except-in "continuity.rkt"
                    odra-agent-continuity-store?
                    agent-continuity-database-name
                    open-agent-continuity-store
                    close-agent-continuity-store!)
         "definition.rkt"
         "registry.rkt")

(provide
 maximum-retained-agent-operation-attempts
 maximum-retained-agent-operation-results
 maximum-agent-operation-evidence-references
 maximum-agent-operation-summary-bytes
 (struct-out odra-agent-operation-failure)
 (struct-out odra-agent-operation-cancellation)
 (struct-out odra-agent-operation-attempt)
 (struct-out odra-agent-capability-execution-context)
 (struct-out odra-agent-capability-owner-result)
 (struct-out odra-agent-capability-invocation)
 (struct-out odra-agent-operation-result)
 (struct-out odra-agent-execution-denial)
 (contract-out
  [make-agent-capability-owner-result
   (->* (symbol?)
        (#:result any/c
         #:owner-evidence list?
         #:external-evidence list?
         #:confirmed-effects list?
         #:safe-summary string?)
        odra-agent-capability-owner-result?)]
  [prepare-agent-capability-attempt!
   (-> odra-agent-continuity-store? (or/c symbol? string?)
       (or/c symbol? string?) (or/c symbol? string?)
       (or/c symbol? string?) exact-nonnegative-integer?
       (or/c odra-agent-operation-attempt? odra-agent-execution-denial?))]
  [inspect-agent-operation-attempt
   (-> odra-agent-continuity-store? (or/c symbol? string?)
       (or/c #f odra-agent-operation-attempt?))]
  [inspect-agent-request-attempts
   (-> odra-agent-continuity-store? (or/c symbol? string?)
       (listof odra-agent-operation-attempt?))]
  [invoke-agent-capability-owner!
   (->* (odra-agent-continuity-store? odra-agent-catalog?
         (or/c symbol? string?) exact-positive-integer?
         exact-nonnegative-integer?)
        (#:operation-invoker procedure?)
       (or/c odra-agent-capability-invocation?
             odra-agent-execution-denial?))]
  [invoke-agent-capability-operation!
   (-> odra-agent-capability-execution-context? (or/c symbol? string?)
       odra-agent-capability-owner-result?)]
  [request-agent-capability-cancellation!
   (-> odra-agent-continuity-store? (or/c symbol? string?)
       exact-positive-integer? (or/c symbol? string?) string?
       exact-nonnegative-integer?
       (or/c odra-agent-operation-attempt? odra-agent-execution-denial?))]
  [expire-agent-capability-attempt!
   (-> odra-agent-continuity-store? (or/c symbol? string?)
       exact-positive-integer? exact-nonnegative-integer?
       (or/c odra-agent-operation-attempt? odra-agent-execution-denial?))]
  [finalize-agent-capability-attempt!
   (-> odra-agent-continuity-store? odra-agent-catalog?
       odra-agent-capability-invocation? (or/c symbol? string?)
       exact-nonnegative-integer?
       (or/c odra-agent-operation-result? odra-agent-execution-denial?))]
  [settle-agent-capability-attempt!
   (-> odra-agent-continuity-store? odra-agent-catalog?
       (or/c symbol? string?) exact-positive-integer?
       (or/c symbol? string?) exact-nonnegative-integer?
       (or/c odra-agent-operation-result? odra-agent-execution-denial?))]
  [reconcile-agent-operation-attempt!
   (-> odra-agent-continuity-store? (or/c symbol? string?)
       exact-positive-integer? exact-nonnegative-integer?
       (or/c odra-agent-operation-attempt? odra-agent-execution-denial?))]
  [inspect-agent-operation-result
   (-> odra-agent-continuity-store? (or/c symbol? string?)
       (or/c #f odra-agent-operation-result?))]
  [inspect-agent-request-results
   (-> odra-agent-continuity-store? (or/c symbol? string?)
       (listof odra-agent-operation-result?))]))

(define maximum-retained-agent-operation-attempts 10000)
(define maximum-retained-agent-operation-results 10000)
(define maximum-agent-operation-evidence-references 32)
(define maximum-agent-operation-summary-bytes 4096)

(define admitted-result-states
  '(cancelled failed outcome-unknown rejected revoked succeeded timed-out))
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

(define (canonical-effects? values)
  (and (list? values)
       (equal? values (sort (remove-duplicates values) symbol<?))
       (andmap
        (lambda (value)
          (and (memq value admitted-agent-effect-classes) #t))
        values)))

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

(struct odra-agent-operation-failure
  (code safe-detail retryable? outcome-uncertain?)
  #:transparent)

(struct odra-agent-operation-cancellation
  (state requested-by reason requested-at)
  #:transparent)

(define empty-operation-cancellation
  (odra-agent-operation-cancellation 'none #f #f #f))

(struct odra-agent-operation-attempt
  (identity generation request-id admission-decision-id state lease-id
            lease-deadline invocation-context-generation started-at ended-at
            result-id failure cancellation-record)
  #:transparent)

(struct odra-agent-capability-execution-context
  (attempt-id invocation-context-generation request-id task-id agent-identity
              capability-identity input target-references admitted-effects
              effective-limits deadline cancellation-requested?
              operation-invoker)
  #:transparent)

(struct odra-agent-capability-owner-result
  (state result owner-evidence external-evidence confirmed-effects safe-summary)
  #:transparent)

(define (make-agent-capability-owner-result
         state #:result [result #f]
         #:owner-evidence [owner-evidence '()]
         #:external-evidence [external-evidence '()]
         #:confirmed-effects [confirmed-effects '()]
         #:safe-summary [safe-summary ""])
  (unless (and (memq state admitted-result-states)
               (<= (length owner-evidence)
                   maximum-agent-operation-evidence-references)
               (andmap odra-agent-owner-reference? owner-evidence)
               (<= (length external-evidence)
                   maximum-agent-operation-evidence-references)
               (andmap odra-agent-owner-reference? external-evidence)
               (canonical-effects? confirmed-effects)
               (bounded-text? safe-summary
                              maximum-agent-operation-summary-bytes
                              #:empty? #t))
    (raise-arguments-error
     'make-agent-capability-owner-result
     "invalid bounded capability owner result"))
  (odra-agent-capability-owner-result
   state result (append owner-evidence '()) (append external-evidence '())
   (append confirmed-effects '()) (string->immutable-string safe-summary)))

(struct odra-agent-capability-invocation (attempt output) #:transparent)

(struct odra-agent-operation-result
  (identity request-id attempt-id state result-schema-reference result
            owner-evidence external-evidence confirmed-effects safe-summary
            completed-at)
  #:transparent)

(struct odra-agent-execution-denial (code safe-detail) #:transparent)

(define (execution-denial code detail)
  (odra-agent-execution-denial code (string->immutable-string detail)))

(define (cancellation->datum cancellation)
  (list 'operation-cancellation
        (odra-agent-operation-cancellation-state cancellation)
        (odra-agent-operation-cancellation-requested-by cancellation)
        (odra-agent-operation-cancellation-reason cancellation)
        (odra-agent-operation-cancellation-requested-at cancellation)))

(define (datum->cancellation datum)
  (match datum
    [(list 'operation-cancellation state requested-by reason requested-at)
     (odra-agent-operation-cancellation state requested-by reason requested-at)]
    [_ (error 'inspect-agent-operation-attempt
              "invalid persisted attempt cancellation")]))

(define (failure->datum failure)
  (and failure
       (list 'operation-failure
             (odra-agent-operation-failure-code failure)
             (odra-agent-operation-failure-safe-detail failure)
             (odra-agent-operation-failure-retryable? failure)
             (odra-agent-operation-failure-outcome-uncertain? failure))))

(define (datum->failure datum)
  (match datum
    [#f #f]
    [(list 'operation-failure code detail retryable? uncertain?)
     (odra-agent-operation-failure code detail retryable? uncertain?)]
    [_ (error 'inspect-agent-operation-attempt
              "invalid persisted attempt failure")]))

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
    [_ (error 'inspect-agent-operation-result
              "invalid persisted owner evidence")]))

(define (schema-reference->datum reference)
  (and reference
       (list 'schema-reference
             (odra-agent-schema-reference-capability-identity reference)
             (odra-agent-schema-reference-definition-generation reference)
             (odra-agent-schema-reference-kind reference)
             (odra-agent-schema-reference-compatibility-version reference))))

(define (datum->schema-reference datum)
  (match datum
    [#f #f]
    [(list 'schema-reference identity generation kind version)
     (make-agent-schema-reference identity generation kind version)]
    [_ (error 'inspect-agent-operation-result
              "invalid persisted result schema reference")]))

(define (result-value->datum value)
  (cond
    [(odra-agent-owner-reference? value)
     (list 'result-owner-reference (owner-reference->datum value))]
    [(list? value)
     (cons 'result-list (map result-value->datum value))]
    [(hash? value)
     (cons
      'result-map
      (for/list ([(key item) (in-hash value)])
        (list (result-value->datum key) (result-value->datum item))))]
    [else value]))

(define (datum->result-value datum)
  (match datum
    [(list 'result-owner-reference reference)
     (datum->owner-reference reference)]
    [(list 'result-list values ...)
     (map datum->result-value values)]
    [(list 'result-map entries ...)
     (for/hash ([entry (in-list entries)])
       (match entry
         [(list key item)
          (values (datum->result-value key) (datum->result-value item))]
         [_ (error 'inspect-agent-operation-result
                   "invalid persisted result map")]))]
    [_ datum]))

(define (operation-result->datum result)
  (list 'operation-result
        (odra-agent-operation-result-identity result)
        (odra-agent-operation-result-request-id result)
        (odra-agent-operation-result-attempt-id result)
        (odra-agent-operation-result-state result)
        (schema-reference->datum
         (odra-agent-operation-result-result-schema-reference result))
        (result-value->datum (odra-agent-operation-result-result result))
        (map owner-reference->datum
             (odra-agent-operation-result-owner-evidence result))
        (map owner-reference->datum
             (odra-agent-operation-result-external-evidence result))
        (odra-agent-operation-result-confirmed-effects result)
        (odra-agent-operation-result-safe-summary result)
        (odra-agent-operation-result-completed-at result)))

(define (attempt->datum attempt)
  (list 'operation-attempt
        (odra-agent-operation-attempt-identity attempt)
        (odra-agent-operation-attempt-generation attempt)
        (odra-agent-operation-attempt-request-id attempt)
        (odra-agent-operation-attempt-admission-decision-id attempt)
        (odra-agent-operation-attempt-state attempt)
        (odra-agent-operation-attempt-lease-id attempt)
        (odra-agent-operation-attempt-lease-deadline attempt)
        (odra-agent-operation-attempt-invocation-context-generation attempt)
        (odra-agent-operation-attempt-started-at attempt)
        (odra-agent-operation-attempt-ended-at attempt)
        (odra-agent-operation-attempt-result-id attempt)
        (failure->datum (odra-agent-operation-attempt-failure attempt))
        (cancellation->datum
         (odra-agent-operation-attempt-cancellation-record attempt))))

(define (datum->attempt datum)
  (match datum
    [(list 'operation-attempt identity generation request-id decision-id state
           lease-id deadline context-generation started-at ended-at result-id
           failure cancellation)
     (odra-agent-operation-attempt
      identity generation request-id decision-id state lease-id deadline
      context-generation started-at ended-at result-id
      (datum->failure failure) (datum->cancellation cancellation))]
    [_ (error 'inspect-agent-operation-attempt
              "invalid persisted operation attempt")]))

(define (write-attempt! connection attempt updated-at)
  (continuity-transaction-write-attempt!
   connection
   (odra-agent-operation-attempt-identity attempt)
   (odra-agent-operation-attempt-generation attempt)
   (odra-agent-operation-attempt-request-id attempt)
   (odra-agent-operation-attempt-admission-decision-id attempt)
   (odra-agent-operation-attempt-state attempt)
   (odra-agent-operation-attempt-lease-id attempt)
   (odra-agent-operation-attempt-lease-deadline attempt)
   (encode-datum (attempt->datum attempt))
   (odra-agent-operation-attempt-started-at attempt)
   updated-at
   (odra-agent-operation-attempt-ended-at attempt)
   (odra-agent-operation-attempt-result-id attempt)))

(define (inspect-agent-operation-attempt store identity)
  (define normalized
    (immutable-identity identity 'inspect-agent-operation-attempt "identity"))
  (define row (continuity-store-attempt-record store normalized))
  (and row
       (datum->attempt
        (decode-datum (vector-ref row 6)
                      'inspect-agent-operation-attempt))))

(define (inspect-agent-request-attempts store request-id)
  (define normalized
    (immutable-identity request-id 'inspect-agent-request-attempts "request-id"))
  (for/list ([row (in-list
                   (continuity-store-request-attempt-records store normalized))])
    (datum->attempt
     (decode-datum (vector-ref row 6) 'inspect-agent-request-attempts))))

(define (immutable-copy value)
  (cond
    [(string? value) (string->immutable-string value)]
    [(bytes? value) (bytes->immutable-bytes value)]
    [(pair? value) (map immutable-copy value)]
    [(hash? value)
     (for/hash ([(key item) (in-hash value)])
       (values (immutable-copy key) (immutable-copy item)))]
    [else value]))

(define (request-package-matches-source? request source)
  (define package
    (odra-agent-capability-request-package-reference request))
  (and
   (string=? (odra-agent-package-reference-identity package)
             (odra-agent-contribution-source-package-id source))
   (string=? (odra-agent-package-reference-version package)
             (odra-agent-contribution-source-package-version source))
   (= (odra-agent-package-reference-contribution-generation package)
      (odra-agent-contribution-source-contribution-generation source))))

(define (resolve-capability-owner catalog request)
  (define projection
    (agent-catalog-capability-by-identity
     catalog (odra-agent-capability-request-capability-identity request)))
  (and projection
       (= (odra-agent-capability-request-capability-definition-generation
           request)
          (odra-agent-capability-projection-definition-generation projection))
       (for*/first
           ([source (in-list (odra-agent-catalog-sources catalog))]
            #:when (request-package-matches-source? request source)
            [definition
             (in-list
              (odra-agent-contribution-source-capability-definitions source))]
            #:when
            (string=?
             (odra-agent-capability-definition-identity definition)
             (odra-agent-capability-request-capability-identity request)))
         definition)))

(define (attempt-cancellation-requested? store attempt-id context-generation)
  (define current (inspect-agent-operation-attempt store attempt-id))
  (or (not current)
      (not (= context-generation
              (odra-agent-operation-attempt-invocation-context-generation
               current)))
      (not (eq? 'none
                (odra-agent-operation-cancellation-state
                 (odra-agent-operation-attempt-cancellation-record current))))
      (memq (odra-agent-operation-attempt-state current)
            '(cancelling completed failed reconciling))))

(define (checked-owner-call handler context)
  (with-handlers ([exn:fail?
                   (lambda (_)
                     (odra-agent-operation-failure
                      'owner-failure
                      "The capability owner failed without exposing private diagnostics."
                      #f #f))])
    (handler context)))

(define (unavailable-operation-invoker _identity _context)
  (make-agent-capability-owner-result
   'failed
   #:safe-summary "The requested package operation is unavailable."))

(define (invoke-agent-capability-operation! context identity)
  (define operation-identity
    (immutable-identity
     identity 'invoke-agent-capability-operation! "operation identity"))
  (cond
    [((odra-agent-capability-execution-context-cancellation-requested? context))
     (make-agent-capability-owner-result
      'cancelled
      #:safe-summary "The capability operation was cancelled before invocation.")]
    [else
     (define result
       ((odra-agent-capability-execution-context-operation-invoker context)
        operation-identity context))
     (unless (odra-agent-capability-owner-result? result)
       (raise-result-error
        'invoke-agent-capability-operation!
        "agent capability owner result"
        result))
     result]))

(define (invoke-agent-capability-owner!
         store catalog identity generation now
         #:operation-invoker
         [operation-invoker unavailable-operation-invoker])
  (unless (procedure-arity-includes? operation-invoker 2)
    (raise-arguments-error
     'invoke-agent-capability-owner!
     "operation invoker must accept an operation identity and execution context"
     "operation-invoker" operation-invoker))
  (define attempt (inspect-agent-operation-attempt store identity))
  (cond
    [(not attempt)
     (execution-denial 'unknown-attempt "The operation attempt is absent.")]
    [(not (= generation (odra-agent-operation-attempt-generation attempt)))
     (execution-denial 'stale-attempt "The attempt generation is stale.")]
    [(not (eq? (odra-agent-operation-attempt-state attempt) 'starting))
     (execution-denial 'invalid-attempt-state
                       "The operation attempt is not starting.")]
    [(>= now (odra-agent-operation-attempt-lease-deadline attempt))
     (expire-agent-capability-attempt! store identity generation now)
     (execution-denial 'attempt-timeout
                       "The attempt lease expired before invocation.")]
    [else
     (define request
       (inspect-agent-capability-request
        store (odra-agent-operation-attempt-request-id attempt)))
     (define decision
       (and request
            (inspect-agent-admission-decision
             store (odra-agent-capability-request-identity request))))
     (define definition
       (and request (resolve-capability-owner catalog request)))
     (cond
       [(not request)
        (execution-denial 'unknown-request
                          "The capability request is unavailable.")]
       [(or (not decision)
            (not (string=?
                  (odra-agent-operation-attempt-admission-decision-id attempt)
                  (odra-agent-admission-decision-identity decision)))
            (not (eq? (odra-agent-admission-decision-state decision)
                      'admitted)))
        (execution-denial 'stale-admission
                          "The admitted decision is unavailable.")]
       [(not definition)
        (transition-attempt-to-cancelling!
         store attempt generation "odra.agent-substrate"
         "The exact capability owner became unavailable." now 'owner-loss)
        (execution-denial 'owner-unavailable
                          "The exact capability owner is unavailable.")]
       [else
        (define running
          (struct-copy odra-agent-operation-attempt attempt
                       [generation (add1 generation)]
                       [state 'running]))
        (call-with-agent-continuity-transaction
         store 'start-capability-attempt
         (lambda (connection)
           (unless (write-attempt! connection running now)
             (error 'invoke-agent-capability-owner! "stale attempt"))
           running))
        (define context-generation
          (odra-agent-operation-attempt-invocation-context-generation running))
        (define context
          (odra-agent-capability-execution-context
           (odra-agent-operation-attempt-identity running)
           context-generation
           (odra-agent-capability-request-identity request)
           (odra-agent-capability-request-task-id request)
           (odra-agent-capability-request-agent-identity request)
           (odra-agent-capability-request-capability-identity request)
           (immutable-copy (odra-agent-capability-request-input request))
           (append (odra-agent-capability-request-target-references request) '())
           (append (odra-agent-admission-decision-effective-effects decision) '())
           (odra-agent-admission-decision-effective-limits decision)
           (odra-agent-operation-attempt-lease-deadline running)
           (lambda ()
             (attempt-cancellation-requested?
              store (odra-agent-operation-attempt-identity running)
              context-generation))
           operation-invoker))
        (odra-agent-capability-invocation
         running
         (checked-owner-call
          (odra-agent-capability-definition-handler definition) context))])]))

(define (transition-attempt-to-cancelling!
         store attempt generation actor reason now cause)
  (define cancelling
    (struct-copy odra-agent-operation-attempt attempt
                 [generation (add1 generation)]
                 [state 'cancelling]
                 [invocation-context-generation
                  (add1
                   (odra-agent-operation-attempt-invocation-context-generation
                    attempt))]
                 [cancellation-record
                  (odra-agent-operation-cancellation
                   'requested actor reason now)]
                 [failure
                  (case cause
                    [(timeout)
                     (odra-agent-operation-failure
                      'attempt-timeout
                      "The capability attempt exceeded its deadline."
                      #f
                      (eq? (odra-agent-operation-attempt-state attempt)
                           'running))]
                    [(owner-loss)
                     (odra-agent-operation-failure
                      'owner-unavailable
                      "The exact capability owner became unavailable."
                      #f #f)]
                    [else
                     (and (eq? (odra-agent-operation-attempt-state attempt)
                               'running)
                          (odra-agent-operation-failure
                           'cancelled-in-flight
                           "Cancellation raced with an active owner invocation."
                           #f #t))])]))
  (call-with-agent-continuity-transaction
   store 'cancel-capability-attempt
   (lambda (connection)
     (unless (write-attempt! connection cancelling now)
       (error 'request-agent-capability-cancellation! "stale attempt"))
     cancelling)))

(define (request-agent-capability-cancellation!
         store identity generation actor reason now)
  (define canonical-actor
    (immutable-identity actor
                        'request-agent-capability-cancellation! "actor"))
  (unless (bounded-text? reason maximum-agent-operation-summary-bytes)
    (raise-arguments-error
     'request-agent-capability-cancellation!
     "invalid bounded cancellation reason"))
  (define attempt (inspect-agent-operation-attempt store identity))
  (cond
    [(not attempt)
     (execution-denial 'unknown-attempt "The operation attempt is absent.")]
    [(not (= generation (odra-agent-operation-attempt-generation attempt)))
     (execution-denial 'stale-attempt "The attempt generation is stale.")]
    [(not (memq (odra-agent-operation-attempt-state attempt)
                '(starting running)))
     (execution-denial 'terminal-attempt
                       "The operation attempt cannot be cancelled.")]
    [else
     (transition-attempt-to-cancelling!
      store attempt generation canonical-actor
      (string->immutable-string reason) now 'cancel)]))

(define (expire-agent-capability-attempt! store identity generation now)
  (define attempt (inspect-agent-operation-attempt store identity))
  (cond
    [(not attempt)
     (execution-denial 'unknown-attempt "The operation attempt is absent.")]
    [(not (= generation (odra-agent-operation-attempt-generation attempt)))
     (execution-denial 'stale-attempt "The attempt generation is stale.")]
    [(< now (odra-agent-operation-attempt-lease-deadline attempt))
     (execution-denial 'active-lease "The operation lease remains active.")]
    [(not (memq (odra-agent-operation-attempt-state attempt)
                '(starting running)))
     (execution-denial 'terminal-attempt
                       "The operation attempt cannot expire.")]
    [else
     (transition-attempt-to-cancelling!
      store attempt generation "odra.agent-substrate"
      "The operation lease expired." now 'timeout)]))

(define (prepare-agent-capability-attempt!
         store identity request-id admission-decision-id lease-id now)
  (define canonical-identity
    (immutable-identity identity 'prepare-agent-capability-attempt! "identity"))
  (define canonical-request
    (immutable-identity request-id
                        'prepare-agent-capability-attempt! "request-id"))
  (define canonical-decision
    (immutable-identity admission-decision-id
                        'prepare-agent-capability-attempt!
                        "admission-decision-id"))
  (define canonical-lease
    (immutable-identity lease-id 'prepare-agent-capability-attempt! "lease-id"))
  (define request (inspect-agent-capability-request store canonical-request))
  (define decision
    (inspect-agent-admission-decision store canonical-request))
  (cond
    [(not request)
     (execution-denial 'unknown-request "The capability request is absent.")]
    [(not decision)
     (execution-denial 'unknown-admission "The admission decision is absent.")]
    [(not (string=? canonical-decision
                    (odra-agent-admission-decision-identity decision)))
     (execution-denial 'stale-admission "The admission decision is stale.")]
    [(not (eq? (odra-agent-admission-decision-state decision) 'admitted))
     (execution-denial 'request-not-admitted
                       "The capability request was not admitted.")]
    [(>= now (odra-agent-capability-request-valid-until request))
     (execution-denial 'expired-request "The capability request expired.")]
    [(inspect-agent-operation-attempt store canonical-identity)
     (execution-denial 'duplicate-attempt "The attempt already exists.")]
    [(pair? (inspect-agent-request-attempts store canonical-request))
     (execution-denial 'attempt-exists
                       "The request already has an operation attempt.")]
    [(>= (continuity-store-attempt-count store)
         maximum-retained-agent-operation-attempts)
     (execution-denial 'attempt-limit
                       "The retained operation attempt limit was reached.")]
    [else
     (define limits
       (odra-agent-admission-decision-effective-limits decision))
     (define deadline
       (min (odra-agent-capability-request-valid-until request)
            (+ now
               (odra-agent-capability-limits-deadline-milliseconds limits))))
     (define attempt
       (odra-agent-operation-attempt
        canonical-identity 1 canonical-request canonical-decision 'starting
        canonical-lease deadline 1 now #f #f #f
        empty-operation-cancellation))
     (call-with-agent-continuity-transaction
      store 'prepare-capability-attempt
      (lambda (connection)
        (unless (write-attempt! connection attempt now)
          (error 'prepare-agent-capability-attempt!
                 "attempt publication failed"))
        attempt))]))

;; Result serialization is defined with the publication operations so every
;; stored result is first checked against its active capability contract.
(define (inspect-agent-operation-result store identity)
  (define normalized
    (immutable-identity identity 'inspect-agent-operation-result "identity"))
  (define row (continuity-store-result-record store normalized))
  (and row
       (datum->operation-result
        (decode-datum (vector-ref row 3)
                      'inspect-agent-operation-result))))

(define (inspect-agent-request-results store request-id)
  (define normalized
    (immutable-identity request-id 'inspect-agent-request-results "request-id"))
  (for/list ([row (in-list
                   (continuity-store-request-result-records store normalized))])
    (datum->operation-result
     (decode-datum (vector-ref row 3) 'inspect-agent-request-results))))

(define (datum->operation-result datum)
  (match datum
    [(list 'operation-result identity request-id attempt-id state schema
           result owner-evidence external-evidence effects summary completed-at)
     (odra-agent-operation-result
      identity request-id attempt-id state (datum->schema-reference schema)
      (datum->result-value result)
      (map datum->owner-reference owner-evidence)
      (map datum->owner-reference external-evidence)
      effects summary completed-at)]
    [_ (error 'inspect-agent-operation-result
              "invalid persisted operation result")]))

(define consequential-effects
  '(credential-use external-commit filesystem-write mutate-editor-state
                   mutate-owned-state network-access process-execution))

(define (effects-consequential? effects)
  (for/or ([effect (in-list effects)])
    (and (memq effect consequential-effects) #t)))

(define (effect-subset? selected admitted)
  (and (canonical-effects? selected)
       (andmap (lambda (effect) (memq effect admitted)) selected)))

(define (valid-evidence? references)
  (and (list? references)
       (<= (length references) maximum-agent-operation-evidence-references)
       (andmap odra-agent-owner-reference? references)))

(define (result-value-bytes value)
  (bytes-length
   (string->bytes/utf-8 (format "~s" (result-value->datum value)))))

(define (operation-result-state->attempt-state state)
  (if (memq state '(succeeded rejected cancelled revoked))
      'completed
      'failed))

(define (publish-operation-result!
         store attempt result now #:failure [failure #f])
  (cond
    [(inspect-agent-operation-result
      store (odra-agent-operation-result-identity result))
     (execution-denial 'duplicate-result "The result identity already exists.")]
    [(pair? (inspect-agent-request-results
             store (odra-agent-operation-result-request-id result)))
     (execution-denial 'result-exists
                       "The request already has an operation result.")]
    [(>= (continuity-store-result-count store)
         maximum-retained-agent-operation-results)
     (execution-denial 'result-limit
                       "The retained operation result limit was reached.")]
    [else
     (define terminal-attempt
       (struct-copy odra-agent-operation-attempt attempt
                    [generation
                     (add1 (odra-agent-operation-attempt-generation attempt))]
                    [state
                     (operation-result-state->attempt-state
                      (odra-agent-operation-result-state result))]
                    [invocation-context-generation
                     (add1
                      (odra-agent-operation-attempt-invocation-context-generation
                       attempt))]
                    [ended-at now]
                    [result-id (odra-agent-operation-result-identity result)]
                    [failure failure]))
     (call-with-agent-continuity-transaction
      store 'publish-capability-result
      (lambda (connection)
        (continuity-transaction-insert-result!
         connection
         (odra-agent-operation-result-identity result)
         (odra-agent-operation-result-request-id result)
         (odra-agent-operation-result-attempt-id result)
         (odra-agent-operation-result-state result)
         (encode-datum (operation-result->datum result)) now)
        (unless (write-attempt! connection terminal-attempt now)
          (error 'publish-operation-result! "stale operation attempt"))
        result))]))

(define (make-terminal-operation-result
         identity attempt state now
         #:schema [schema #f]
         #:result [result #f]
         #:owner-evidence [owner-evidence '()]
         #:external-evidence [external-evidence '()]
         #:confirmed-effects [confirmed-effects '()]
         #:summary [summary ""])
  (odra-agent-operation-result
   identity
   (odra-agent-operation-attempt-request-id attempt)
   (odra-agent-operation-attempt-identity attempt)
   state schema result (append owner-evidence '())
   (append external-evidence '()) (append confirmed-effects '())
   (string->immutable-string summary) now))

(define (failure-result-state failure effects)
  (if (and failure
           (odra-agent-operation-failure-outcome-uncertain? failure)
           (effects-consequential? effects))
      'outcome-unknown
      'failed))

(define (finalize-agent-capability-attempt!
         store catalog invocation result-id now)
  (define invoked-attempt (odra-agent-capability-invocation-attempt invocation))
  (define current
    (inspect-agent-operation-attempt
     store (odra-agent-operation-attempt-identity invoked-attempt)))
  (define canonical-result-id
    (immutable-identity result-id
                        'finalize-agent-capability-attempt! "result-id"))
  (cond
    [(or (not current)
         (not (= (odra-agent-operation-attempt-generation current)
                 (odra-agent-operation-attempt-generation invoked-attempt)))
         (not (eq? (odra-agent-operation-attempt-state current) 'running)))
     (execution-denial 'stale-attempt
                       "The running capability attempt is unavailable.")]
    [else
     (define request
       (inspect-agent-capability-request
        store (odra-agent-operation-attempt-request-id current)))
     (define decision
       (and request
            (inspect-agent-admission-decision
             store (odra-agent-capability-request-identity request))))
     (define definition
       (and request (resolve-capability-owner catalog request)))
     (define output (odra-agent-capability-invocation-output invocation))
     (cond
       [(or (not request) (not decision))
        (execution-denial 'stale-admission
                          "The admitted request is unavailable.")]
       [(odra-agent-operation-failure? output)
        (define state
          (failure-result-state
           output (odra-agent-admission-decision-effective-effects decision)))
        (publish-operation-result!
         store current
         (make-terminal-operation-result
          canonical-result-id current state now
          #:summary (odra-agent-operation-failure-safe-detail output))
         now #:failure output)]
       [(>= now (odra-agent-operation-attempt-lease-deadline current))
        (define uncertain?
          (effects-consequential?
           (odra-agent-admission-decision-effective-effects decision)))
        (define failure
          (odra-agent-operation-failure
           'attempt-timeout
           "The owner callback completed after the operation deadline."
           #f uncertain?))
        (publish-operation-result!
         store current
         (make-terminal-operation-result
          canonical-result-id current
          (if uncertain? 'outcome-unknown 'timed-out) now
          #:summary (odra-agent-operation-failure-safe-detail failure))
         now #:failure failure)]
       [(not definition)
        (define uncertain?
          (effects-consequential?
           (odra-agent-admission-decision-effective-effects decision)))
        (define failure
          (odra-agent-operation-failure
           'owner-unavailable
           "The exact capability owner is unavailable for result validation."
           #f uncertain?))
        (publish-operation-result!
         store current
         (make-terminal-operation-result
          canonical-result-id current
          (if uncertain? 'outcome-unknown 'failed) now
          #:summary (odra-agent-operation-failure-safe-detail failure))
         now #:failure failure)]
       [(not (odra-agent-capability-owner-result? output))
        (define failure
          (odra-agent-operation-failure
           'malformed-owner-result
           "The capability owner returned malformed output."
           #f #f))
        (publish-operation-result!
         store current
         (make-terminal-operation-result
          canonical-result-id current 'failed now
          #:summary (odra-agent-operation-failure-safe-detail failure))
         now #:failure failure)]
       [else
        (define state (odra-agent-capability-owner-result-state output))
        (define result-value (odra-agent-capability-owner-result-result output))
        (define effects
          (odra-agent-capability-owner-result-confirmed-effects output))
        (define owner-evidence
          (odra-agent-capability-owner-result-owner-evidence output))
        (define external-evidence
          (odra-agent-capability-owner-result-external-evidence output))
        (define summary
          (odra-agent-capability-owner-result-safe-summary output))
        (define schema
          (odra-agent-capability-definition-result-schema definition))
        (define limits
          (odra-agent-admission-decision-effective-limits decision))
        (define successful?
          (eq? state 'succeeded))
        (define valid?
          (and (memq state admitted-result-states)
               (effect-subset?
                effects
                (odra-agent-admission-decision-effective-effects decision))
               (valid-evidence? owner-evidence)
               (valid-evidence? external-evidence)
               (bounded-text? summary maximum-agent-operation-summary-bytes
                              #:empty? #t)
               (or (not successful?)
                   (and
                    (agent-schema-value? schema result-value)
                    (<= (result-value-bytes result-value)
                        (odra-agent-capability-limits-result-bytes limits))))))
        (if valid?
            (publish-operation-result!
             store current
             (make-terminal-operation-result
              canonical-result-id current state now
              #:schema
              (and successful?
                   (make-agent-schema-reference
                    (odra-agent-capability-request-capability-identity request)
                    (odra-agent-capability-request-capability-definition-generation
                     request)
                    'result
                    (odra-agent-capability-definition-compatibility-version
                     definition)))
              #:result (and successful? result-value)
              #:owner-evidence owner-evidence
              #:external-evidence external-evidence
              #:confirmed-effects effects
              #:summary summary)
             now)
            (let ([failure
                   (odra-agent-operation-failure
                    'invalid-owner-result
                    "The capability owner result failed schema, effect, evidence, or resource validation."
                    #f #f)])
              (publish-operation-result!
               store current
               (make-terminal-operation-result
                canonical-result-id current 'failed now
                #:summary (odra-agent-operation-failure-safe-detail failure))
               now #:failure failure)))])]))

(define (settle-agent-capability-attempt!
         store catalog identity generation result-id now)
  (define attempt (inspect-agent-operation-attempt store identity))
  (define canonical-result-id
    (immutable-identity result-id
                        'settle-agent-capability-attempt! "result-id"))
  (cond
    [(not attempt)
     (execution-denial 'unknown-attempt "The operation attempt is absent.")]
    [(not (= generation (odra-agent-operation-attempt-generation attempt)))
     (execution-denial 'stale-attempt "The attempt generation is stale.")]
    [(not (memq (odra-agent-operation-attempt-state attempt)
                '(cancelling reconciling)))
     (execution-denial 'invalid-attempt-state
                       "The operation attempt is not awaiting settlement.")]
    [else
     (define request
       (inspect-agent-capability-request
        store (odra-agent-operation-attempt-request-id attempt)))
     (define decision
       (and request
            (inspect-agent-admission-decision
             store (odra-agent-capability-request-identity request))))
     (cond
       [(or (not request) (not decision))
        (execution-denial 'stale-admission
                          "The admitted request is unavailable.")]
       [else
        (define failure (odra-agent-operation-attempt-failure attempt))
        (define cancellation
          (odra-agent-operation-attempt-cancellation-record attempt))
        (define effects
          (odra-agent-admission-decision-effective-effects decision))
        (define uncertain?
          (and failure
               (odra-agent-operation-failure-outcome-uncertain? failure)
               (effects-consequential? effects)))
        (define state
          (cond
            [uncertain? 'outcome-unknown]
            [(and failure
                  (eq? (odra-agent-operation-failure-code failure)
                       'attempt-timeout))
             'timed-out]
            [(and failure
                  (eq? (odra-agent-operation-failure-code failure)
                       'owner-unavailable))
             'failed]
            [(eq? (odra-agent-operation-cancellation-state cancellation)
                  'requested)
             'cancelled]
            [else 'failed]))
        (define summary
          (cond
            [failure (odra-agent-operation-failure-safe-detail failure)]
            [(odra-agent-operation-cancellation-reason cancellation)
             (odra-agent-operation-cancellation-reason cancellation)]
            [else "The operation attempt ended without owner output."]))
        (publish-operation-result!
         store attempt
         (make-terminal-operation-result
          canonical-result-id attempt state now #:summary summary)
         now #:failure failure)])]))

(define (reconcile-agent-operation-attempt! store identity generation now)
  (define attempt (inspect-agent-operation-attempt store identity))
  (cond
    [(not attempt)
     (execution-denial 'unknown-attempt "The operation attempt is absent.")]
    [(not (= generation (odra-agent-operation-attempt-generation attempt)))
     (execution-denial 'stale-attempt "The attempt generation is stale.")]
    [(memq (odra-agent-operation-attempt-state attempt)
           '(completed failed reconciling))
     (execution-denial 'terminal-attempt
                       "The attempt does not require reconciliation.")]
    [else
     (define uncertain?
       (memq (odra-agent-operation-attempt-state attempt)
             '(running cancelling)))
     (define reconciling
       (struct-copy odra-agent-operation-attempt attempt
                    [generation (add1 generation)]
                    [state 'reconciling]
                    [invocation-context-generation
                     (add1
                      (odra-agent-operation-attempt-invocation-context-generation
                       attempt))]
                    [failure
                     (odra-agent-operation-failure
                      'runtime-ownership-lost
                      "Operation outcome requires owner reconciliation."
                      #f uncertain?)]))
     (call-with-agent-continuity-transaction
      store 'reconcile-capability-attempt
      (lambda (connection)
        (unless (write-attempt! connection reconciling now)
          (error 'reconcile-agent-operation-attempt! "stale attempt"))
        reconciling))]))
