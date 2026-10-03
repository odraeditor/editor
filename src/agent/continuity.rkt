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
         "registry.rkt"
         "continuity-store.rkt")

(provide
 maximum-nonterminal-agent-tasks
 maximum-agent-task-participants
 maximum-agent-task-depth
 maximum-agent-owner-references
 maximum-agent-objective-bytes
 maximum-retained-agent-interactions
 maximum-agent-interaction-payload-bytes
 maximum-retained-agent-delegations
 (struct-out odra-agent-owner-reference)
 (struct-out odra-agent-task-origin)
 (struct-out odra-agent-task-cancellation)
 (struct-out odra-agent-task)
 (struct-out odra-agent-task-participant)
 (struct-out odra-agent-interaction-provenance)
 (struct-out odra-agent-interaction)
 (struct-out odra-agent-delegation)
 (struct-out odra-agent-continuity-denial)
 odra-agent-continuity-store?
 agent-continuity-database-name
 agent-interaction-storage-datum
 (contract-out
  [make-agent-owner-reference
   (->* ((or/c symbol? string?) (or/c symbol? string?)
         exact-positive-integer? any/c)
        (#:generation exact-positive-integer?)
        odra-agent-owner-reference?)]
  [make-agent-task-origin
   (->* (symbol? (or/c symbol? string?))
        (#:reference (or/c #f symbol? string?))
        odra-agent-task-origin?)]
  [open-agent-continuity-store
   (->* (path-string?)
        (#:transaction-observer procedure?)
        odra-agent-continuity-store?)]
  [close-agent-continuity-store!
   (-> odra-agent-continuity-store? void?)]
  [create-agent-task!
   (->* (odra-agent-continuity-store?
         (or/c symbol? string?) any/c odra-agent-task-origin?
         exact-nonnegative-integer?)
        (#:owner-agent (or/c #f symbol? string?)
         #:parent-task-id (or/c #f symbol? string?)
         #:owner-references list?
         #:authority-policy list?
         #:resource-policy any/c)
        (or/c odra-agent-task? odra-agent-continuity-denial?))]
  [inspect-agent-task
   (-> odra-agent-continuity-store? (or/c symbol? string?)
       (or/c #f odra-agent-task?))]
  [inspect-agent-tasks
   (-> odra-agent-continuity-store? (listof odra-agent-task?))]
  [inspect-agent-task-participants
   (-> odra-agent-continuity-store? (or/c symbol? string?)
       (listof odra-agent-task-participant?))]
  [join-agent-task!
   (->* (odra-agent-continuity-store?
         (or/c symbol? string?) exact-positive-integer?
         (or/c symbol? string?) symbol? exact-nonnegative-integer?)
        (#:visibility symbol?)
        (or/c odra-agent-task-participant?
              odra-agent-continuity-denial?))]
  [leave-agent-task!
   (->* (odra-agent-continuity-store?
         (or/c symbol? string?) (or/c symbol? string?)
         exact-positive-integer? exact-nonnegative-integer?)
        (#:reason (or/c #f symbol?))
        (or/c odra-agent-task-participant?
              odra-agent-continuity-denial?))]
  [transition-agent-task!
   (->* (odra-agent-continuity-store?
         (or/c symbol? string?) exact-positive-integer?
         (or/c symbol? string?) symbol? exact-nonnegative-integer?)
        (#:pending-decision-id (or/c #f symbol? string?)
         #:terminal-result-refs list?)
        (or/c odra-agent-task? odra-agent-continuity-denial?))]
  [cancel-agent-task!
   (-> odra-agent-continuity-store? (or/c symbol? string?)
       exact-positive-integer? (or/c symbol? string?) string?
       exact-nonnegative-integer?
       (or/c odra-agent-task? odra-agent-continuity-denial?))]
  [make-agent-interaction-provenance
   (->* (symbol? (or/c symbol? string?))
        (#:reference (or/c #f symbol? string?))
        odra-agent-interaction-provenance?)]
  [record-agent-interaction!
   (->* (odra-agent-continuity-store?
         (or/c symbol? string?) (or/c symbol? string?)
         (or/c symbol? string?) (or/c symbol? string?)
         symbol? any/c symbol? odra-agent-interaction-provenance?
         exact-nonnegative-integer?)
        (#:acting-agent (or/c #f symbol? string?)
         #:parent-task-id (or/c #f symbol? string?)
         #:owner-namespace (or/c #f symbol? string?)
         #:context-references list?
         #:decision-class (or/c #f symbol? string?)
         #:correlation-id (or/c #f symbol? string?)
         #:idempotency-id (or/c #f symbol? string?)
         #:valid-until (or/c #f exact-positive-integer?))
        (or/c odra-agent-interaction? odra-agent-continuity-denial?))]
  [inspect-agent-interaction
   (-> odra-agent-continuity-store? (or/c symbol? string?)
       (or/c #f odra-agent-interaction?))]
  [inspect-agent-task-interactions
   (-> odra-agent-continuity-store? (or/c symbol? string?)
       (listof odra-agent-interaction?))]
  [create-agent-delegation!
   (->* (odra-agent-continuity-store? odra-agent-authority-store?
         odra-agent-catalog?
         (or/c symbol? string?) (or/c symbol? string?)
         (or/c symbol? string?) (or/c symbol? string?) any/c
         exact-nonnegative-integer?)
        (#:child-task-id (or/c #f symbol? string?)
         #:context-references list?
         #:authority-ceiling list?
         #:deadline (or/c #f exact-positive-integer?))
        (or/c odra-agent-delegation? odra-agent-continuity-denial?))]
  [transition-agent-delegation!
   (->* (odra-agent-continuity-store? odra-agent-authority-store?
         odra-agent-catalog?
         (or/c symbol? string?) exact-positive-integer?
         (or/c symbol? string?) symbol? exact-nonnegative-integer?)
        (#:terminal-result-reference (or/c #f odra-agent-owner-reference?))
        (or/c odra-agent-delegation? odra-agent-continuity-denial?))]
  [inspect-agent-delegation
   (-> odra-agent-continuity-store? (or/c symbol? string?)
       (or/c #f odra-agent-delegation?))]
  [inspect-agent-task-delegations
   (-> odra-agent-continuity-store? (or/c symbol? string?)
       (listof odra-agent-delegation?))]))

(define maximum-nonterminal-agent-tasks 128)
(define maximum-agent-task-participants 16)
(define maximum-agent-task-depth 8)
(define maximum-agent-owner-references 32)
(define maximum-agent-objective-bytes (* 16 1024))
(define maximum-retained-agent-interactions 10000)
(define maximum-agent-interaction-payload-bytes (* 64 1024))
(define maximum-retained-agent-delegations 10000)
(define maximum-agent-inert-depth 4)
(define maximum-agent-inert-items 64)
(define maximum-agent-inert-bytes (* 64 1024))

(define identity-pattern #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")
(define admitted-task-states
  '(created ready running waiting blocked succeeded failed cancelled))
(define terminal-task-states '(succeeded failed cancelled))
(define admitted-participant-roles '(owner delegate observer reviewer))
(define admitted-visibility '(owner participants sender-recipient local-user))
(define admitted-interaction-kinds
  '(request question decision progress proposal result failure cancellation
            acknowledgement))
(define admitted-delegation-states
  '(proposed accepted rejected running completed failed cancelled))

(define delegation-transitions
  '((proposed accepted rejected cancelled)
    (accepted running cancelled)
    (running completed failed cancelled)))

(define task-transitions
  '((created ready cancelled)
    (ready running cancelled)
    (running waiting blocked succeeded failed cancelled)
    (waiting running blocked failed cancelled)
    (blocked running failed cancelled)))

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

(define (inert-shape? value [depth 0])
  (and
   (<= depth maximum-agent-inert-depth)
   (cond
     [(boolean? value) #t]
     [(exact-integer? value)
      (<= (- (expt 2 63)) value (sub1 (expt 2 63)))]
     [(string? value) (bounded-text? value maximum-agent-inert-bytes #:empty? #t)]
     [(bytes? value) (<= (bytes-length value) maximum-agent-inert-bytes)]
     [(symbol? value) (identity? value)]
     [(null? value) #t]
     [(list? value)
      (and (<= (length value) maximum-agent-inert-items)
           (andmap (lambda (item) (inert-shape? item (add1 depth))) value))]
     [else #f])))

(define (inert-value? value maximum-bytes)
  (and (inert-shape? value)
       (<= (bytes-length (string->bytes/utf-8 (format "~s" value)))
           maximum-bytes)))

(define (immutable-copy value)
  (cond
    [(string? value) (string->immutable-string value)]
    [(bytes? value) (bytes->immutable-bytes value)]
    [(pair? value) (map immutable-copy value)]
    [else value]))

(define (encode-datum datum)
  (with-output-to-string
    (lambda () (write datum))))

(define (decode-datum text who)
  (parameterize ([read-accept-reader #f]
                 [read-accept-lang #f])
    (define input (open-input-string text))
    (define datum (read input))
    (unless (eof-object? (read input))
      (error who "persisted record contains trailing data"))
    datum))

(struct odra-agent-owner-reference
  (owner-namespace kind compatibility-version identity generation)
  #:transparent)

(define (make-agent-owner-reference
         owner-namespace kind compatibility-version identity
         #:generation [generation 1])
  (unless (inert-value? identity 4096)
    (raise-arguments-error
     'make-agent-owner-reference "invalid bounded opaque owner identity"
     "identity" identity))
  (odra-agent-owner-reference
   (immutable-identity
    owner-namespace 'make-agent-owner-reference "owner-namespace")
   (immutable-identity kind 'make-agent-owner-reference "kind")
   compatibility-version (immutable-copy identity) generation))

(struct odra-agent-task-origin (kind actor-identity reference) #:transparent)

(define (make-agent-task-origin kind actor-identity #:reference [reference #f])
  (unless (memq kind '(local-user agent package system external-surface))
    (raise-arguments-error
     'make-agent-task-origin "unsupported task origin kind" "kind" kind))
  (odra-agent-task-origin
   kind
   (immutable-identity actor-identity 'make-agent-task-origin "actor-identity")
   (and reference
        (immutable-identity reference 'make-agent-task-origin "reference"))))

(struct odra-agent-task-cancellation
  (state requested-by reason requested-at)
  #:transparent)

(define empty-task-cancellation
  (odra-agent-task-cancellation 'none #f #f #f))

(struct odra-agent-task
  (identity generation objective origin-record state owner-agent parent-task-id
            owner-references authority-policy resource-policy
            pending-decision-id cancellation-record terminal-result-refs
            created-at updated-at)
  #:transparent)

(struct odra-agent-task-participant
  (task-id agent-identity role generation visibility joined-at left-at reason)
  #:transparent)

(struct odra-agent-continuity-denial (code safe-detail) #:transparent)

(struct odra-agent-interaction-provenance
  (kind actor-identity reference)
  #:transparent)

(struct odra-agent-interaction
  (identity generation sender acting-agent recipient task-id parent-task-id
            owner-namespace kind payload context-references decision-class
            visibility correlation-id idempotency-id created-at valid-until
            provenance-record)
  #:transparent)

(struct odra-agent-delegation
  (identity generation parent-task-id child-task-id sender-agent
            recipient-agent requested-outcome context-references
            authority-ceiling state deadline terminal-result-reference
            created-at updated-at)
  #:transparent)

(define (denial code detail)
  (odra-agent-continuity-denial code (string->immutable-string detail)))

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
    [_ (error 'inspect-agent-task "invalid persisted owner reference")]))

(define (origin->datum origin)
  (list 'task-origin
        (odra-agent-task-origin-kind origin)
        (odra-agent-task-origin-actor-identity origin)
        (odra-agent-task-origin-reference origin)))

(define (datum->origin datum)
  (match datum
    [(list 'task-origin kind actor reference)
     (odra-agent-task-origin kind actor reference)]
    [_ (error 'inspect-agent-task "invalid persisted task origin")]))

(define (cancellation->datum cancellation)
  (list 'task-cancellation
        (odra-agent-task-cancellation-state cancellation)
        (odra-agent-task-cancellation-requested-by cancellation)
        (odra-agent-task-cancellation-reason cancellation)
        (odra-agent-task-cancellation-requested-at cancellation)))

(define (datum->cancellation datum)
  (match datum
    [(list 'task-cancellation state requested-by reason requested-at)
     (odra-agent-task-cancellation state requested-by reason requested-at)]
    [_ (error 'inspect-agent-task "invalid persisted cancellation")]))

(define (task->datum task)
  (list
   'agent-task
   (odra-agent-task-identity task)
   (odra-agent-task-generation task)
   (odra-agent-task-objective task)
   (origin->datum (odra-agent-task-origin-record task))
   (odra-agent-task-state task)
   (odra-agent-task-owner-agent task)
   (odra-agent-task-parent-task-id task)
   (map owner-reference->datum (odra-agent-task-owner-references task))
   (map owner-reference->datum (odra-agent-task-authority-policy task))
   (odra-agent-task-resource-policy task)
   (odra-agent-task-pending-decision-id task)
   (cancellation->datum (odra-agent-task-cancellation-record task))
   (map owner-reference->datum (odra-agent-task-terminal-result-refs task))
   (odra-agent-task-created-at task)
   (odra-agent-task-updated-at task)))

(define (datum->task datum)
  (match datum
    [(list 'agent-task identity generation objective origin state owner-agent
           parent-task-id owner-references authority-policy resource-policy
           pending-decision-id cancellation terminal-result-refs
           created-at updated-at)
     (odra-agent-task
      identity generation objective (datum->origin origin) state owner-agent
      parent-task-id (map datum->owner-reference owner-references)
      (map datum->owner-reference authority-policy) resource-policy
      pending-decision-id (datum->cancellation cancellation)
      (map datum->owner-reference terminal-result-refs) created-at updated-at)]
    [_ (error 'inspect-agent-task "invalid persisted task")]))

(define (participant->datum participant)
  (list 'task-participant
        (odra-agent-task-participant-task-id participant)
        (odra-agent-task-participant-agent-identity participant)
        (odra-agent-task-participant-role participant)
        (odra-agent-task-participant-generation participant)
        (odra-agent-task-participant-visibility participant)
        (odra-agent-task-participant-joined-at participant)
        (odra-agent-task-participant-left-at participant)
        (odra-agent-task-participant-reason participant)))

(define (datum->participant datum)
  (match datum
    [(list 'task-participant task-id agent role generation visibility
           joined-at left-at reason)
     (odra-agent-task-participant
      task-id agent role generation visibility joined-at left-at reason)]
    [_ (error 'inspect-agent-task-participants
              "invalid persisted task participant")]))

(define (task-record->task row payload-index)
  (datum->task
   (decode-datum (vector-ref row payload-index) 'inspect-agent-task)))

(define (participant-record->participant row payload-index)
  (datum->participant
   (decode-datum
    (vector-ref row payload-index) 'inspect-agent-task-participants)))

(define (make-agent-interaction-provenance
         kind actor-identity #:reference [reference #f])
  (unless (memq kind '(local-user agent package system external-surface))
    (raise-arguments-error
     'make-agent-interaction-provenance
     "unsupported interaction provenance kind" "kind" kind))
  (odra-agent-interaction-provenance
   kind
   (immutable-identity
    actor-identity 'make-agent-interaction-provenance "actor-identity")
   (and reference
        (immutable-identity
         reference 'make-agent-interaction-provenance "reference"))))

(define (interaction-provenance->datum provenance)
  (list 'interaction-provenance
        (odra-agent-interaction-provenance-kind provenance)
        (odra-agent-interaction-provenance-actor-identity provenance)
        (odra-agent-interaction-provenance-reference provenance)))

(define (datum->interaction-provenance datum)
  (match datum
    [(list 'interaction-provenance kind actor reference)
     (odra-agent-interaction-provenance kind actor reference)]
    [_ (error 'inspect-agent-interaction
              "invalid persisted interaction provenance")]))

(define (interaction->datum interaction)
  (list
   'agent-interaction
   (odra-agent-interaction-identity interaction)
   (odra-agent-interaction-generation interaction)
   (odra-agent-interaction-sender interaction)
   (odra-agent-interaction-acting-agent interaction)
   (odra-agent-interaction-recipient interaction)
   (odra-agent-interaction-task-id interaction)
   (odra-agent-interaction-parent-task-id interaction)
   (odra-agent-interaction-owner-namespace interaction)
   (odra-agent-interaction-kind interaction)
   (odra-agent-interaction-payload interaction)
   (map owner-reference->datum
        (odra-agent-interaction-context-references interaction))
   (odra-agent-interaction-decision-class interaction)
   (odra-agent-interaction-visibility interaction)
   (odra-agent-interaction-correlation-id interaction)
   (odra-agent-interaction-idempotency-id interaction)
   (odra-agent-interaction-created-at interaction)
   (odra-agent-interaction-valid-until interaction)
   (interaction-provenance->datum
    (odra-agent-interaction-provenance-record interaction))))

(define (agent-interaction-storage-datum interaction)
  (interaction->datum interaction))

(define (datum->interaction datum)
  (match datum
    [(list 'agent-interaction identity generation sender acting-agent recipient
           task-id parent-task-id owner-namespace kind payload context-refs
           decision-class visibility correlation-id idempotency-id created-at
           valid-until provenance)
     (odra-agent-interaction
      identity generation sender acting-agent recipient task-id parent-task-id
      owner-namespace kind payload (map datum->owner-reference context-refs)
      decision-class visibility correlation-id idempotency-id created-at
      valid-until (datum->interaction-provenance provenance))]
    [_ (error 'inspect-agent-interaction "invalid persisted interaction")]))

(define (interaction-record->interaction row payload-index)
  (datum->interaction
   (decode-datum
    (vector-ref row payload-index) 'inspect-agent-interaction)))

(define (delegation->datum delegation)
  (list
   'agent-delegation
   (odra-agent-delegation-identity delegation)
   (odra-agent-delegation-generation delegation)
   (odra-agent-delegation-parent-task-id delegation)
   (odra-agent-delegation-child-task-id delegation)
   (odra-agent-delegation-sender-agent delegation)
   (odra-agent-delegation-recipient-agent delegation)
   (odra-agent-delegation-requested-outcome delegation)
   (map owner-reference->datum
        (odra-agent-delegation-context-references delegation))
   (odra-agent-delegation-authority-ceiling delegation)
   (odra-agent-delegation-state delegation)
   (odra-agent-delegation-deadline delegation)
   (and (odra-agent-delegation-terminal-result-reference delegation)
        (owner-reference->datum
         (odra-agent-delegation-terminal-result-reference delegation)))
   (odra-agent-delegation-created-at delegation)
   (odra-agent-delegation-updated-at delegation)))

(define (datum->delegation datum)
  (match datum
    [(list 'agent-delegation identity generation parent-task-id child-task-id
           sender-agent recipient-agent requested-outcome context-references
           authority-ceiling state deadline terminal-result-reference
           created-at updated-at)
     (odra-agent-delegation
      identity generation parent-task-id child-task-id sender-agent
      recipient-agent requested-outcome
      (map datum->owner-reference context-references) authority-ceiling state
      deadline
      (and terminal-result-reference
           (datum->owner-reference terminal-result-reference))
      created-at updated-at)]
    [_ (error 'inspect-agent-delegation "invalid persisted delegation")]))

(define (delegation-record->delegation row payload-index)
  (datum->delegation
   (decode-datum
    (vector-ref row payload-index) 'inspect-agent-delegation)))

(define (inspect-agent-task store identity)
  (define row
    (continuity-store-task-record
     store (immutable-identity identity 'inspect-agent-task "identity")))
  (and row (task-record->task row 2)))

(define (inspect-agent-tasks store)
  (for/list ([row (in-list (continuity-store-task-records store))])
    (task-record->task row 3)))

(define (inspect-agent-task-participants store task-id)
  (for/list
      ([row
        (in-list
         (continuity-store-participant-records
          store
          (immutable-identity
           task-id 'inspect-agent-task-participants "task-id")))])
    (participant-record->participant row 3)))

(define (inspect-agent-interaction store identity)
  (define row
    (continuity-store-interaction-record
     store
     (immutable-identity identity 'inspect-agent-interaction "identity")))
  (and row (interaction-record->interaction row 3)))

(define (inspect-agent-task-interactions store task-id)
  (for/list
      ([row
        (in-list
         (continuity-store-interaction-records
          store
          (immutable-identity
           task-id 'inspect-agent-task-interactions "task-id")))])
    (interaction-record->interaction row 3)))

(define (inspect-agent-delegation store identity)
  (define row
    (continuity-store-delegation-record
     store
     (immutable-identity identity 'inspect-agent-delegation "identity")))
  (and row (delegation-record->delegation row 6)))

(define (inspect-agent-task-delegations store task-id)
  (for/list
      ([row
        (in-list
         (continuity-store-delegation-records
          store
          (immutable-identity
           task-id 'inspect-agent-task-delegations "task-id")))])
    (delegation-record->delegation row 6)))

(define (nonterminal-task? task)
  (not (memq (odra-agent-task-state task) terminal-task-states)))

(define (active-participant? participant)
  (not (odra-agent-task-participant-left-at participant)))

(define (valid-owner-reference-list? value)
  (and (list? value)
       (<= (length value) maximum-agent-owner-references)
       (andmap odra-agent-owner-reference? value)))

(define (task-depth store parent-task-id child-identity)
  (let loop ([identity parent-task-id]
             [depth 1]
             [seen (list child-identity)])
    (cond
      [(> depth maximum-agent-task-depth) #f]
      [(not identity) depth]
      [(member identity seen string=?) #f]
      [else
       (define parent (inspect-agent-task store identity))
       (and parent
            (loop (odra-agent-task-parent-task-id parent)
                  (add1 depth)
                  (cons identity seen)))])))

(define (persist-task! connection task)
  (unless
      (continuity-transaction-write-task!
       connection
       (odra-agent-task-identity task)
       (odra-agent-task-generation task)
       (odra-agent-task-state task)
       (encode-datum (task->datum task))
       (odra-agent-task-created-at task)
       (odra-agent-task-updated-at task))
    (error 'persist-task! "task generation changed during publication")))

(define (persist-participant! connection participant)
  (unless
      (continuity-transaction-write-participant!
       connection
       (odra-agent-task-participant-task-id participant)
       (odra-agent-task-participant-agent-identity participant)
       (odra-agent-task-participant-generation participant)
       (active-participant? participant)
       (encode-datum (participant->datum participant))
       (odra-agent-task-participant-joined-at participant)
       (odra-agent-task-participant-left-at participant))
    (error 'persist-participant!
           "participant generation changed during publication")))

(define (create-agent-task!
         store identity objective origin now
         #:owner-agent [owner-agent #f]
         #:parent-task-id [parent-task-id #f]
         #:owner-references [owner-references '()]
         #:authority-policy [authority-policy '()]
         #:resource-policy [resource-policy '()])
  (define task-id
    (immutable-identity identity 'create-agent-task! "identity"))
  (define owner
    (and owner-agent
         (immutable-identity owner-agent 'create-agent-task! "owner-agent")))
  (define parent-id
    (and parent-task-id
         (immutable-identity
          parent-task-id 'create-agent-task! "parent-task-id")))
  (unless (and (inert-value? objective maximum-agent-objective-bytes)
               (valid-owner-reference-list? owner-references)
               (valid-owner-reference-list? authority-policy)
               (inert-value? resource-policy maximum-agent-inert-bytes))
    (raise-arguments-error
     'create-agent-task! "invalid bounded task content"))
  (cond
    [(inspect-agent-task store task-id)
     (denial 'duplicate-task "A task with this identity already exists.")]
    [(>= (count nonterminal-task? (inspect-agent-tasks store))
         maximum-nonterminal-agent-tasks)
     (denial 'task-limit "The nonterminal task limit has been reached.")]
    [(and parent-id (not (task-depth store parent-id task-id)))
     (denial 'invalid-parent "The parent task is absent, cyclic, or too deep.")]
    [else
     (define task
       (odra-agent-task
        task-id 1 (immutable-copy objective) origin 'created owner parent-id
        (append owner-references '()) (append authority-policy '())
        (immutable-copy resource-policy) #f empty-task-cancellation '()
        now now))
     (define initial-participant
       (and owner
            (odra-agent-task-participant
             task-id owner 'owner 1 'owner now #f #f)))
     (call-with-agent-continuity-transaction
      store 'create-task
      (lambda (connection)
        (persist-task! connection task)
        (when initial-participant
          (persist-participant! connection initial-participant))
        task))]))

(define (participant-at store task-id agent-identity)
  (define row
    (continuity-store-participant-record store task-id agent-identity))
  (and row (participant-record->participant row 2)))

(define (join-agent-task!
         store task-id expected-task-generation agent-identity role now
         #:visibility [visibility 'participants])
  (define canonical-task-id
    (immutable-identity task-id 'join-agent-task! "task-id"))
  (define canonical-agent
    (immutable-identity agent-identity 'join-agent-task! "agent-identity"))
  (unless (and (memq role admitted-participant-roles)
               (not (eq? role 'owner))
               (memq visibility admitted-visibility))
    (raise-arguments-error
     'join-agent-task! "invalid participant role or visibility"))
  (define task (inspect-agent-task store canonical-task-id))
  (define current
    (and task (participant-at store canonical-task-id canonical-agent)))
  (cond
    [(not task) (denial 'absent-task "The task does not exist.")]
    [(not (= expected-task-generation (odra-agent-task-generation task)))
     (denial 'stale-task "The task generation is stale.")]
    [(not (nonterminal-task? task))
     (denial 'terminal-task "A terminal task cannot accept participants.")]
    [(< now (odra-agent-task-updated-at task))
     (denial 'invalid-time "Participant time precedes the task observation.")]
    [(and current (active-participant? current))
     (denial 'duplicate-participant "The participant is already active.")]
    [(>= (count active-participant?
                (inspect-agent-task-participants store canonical-task-id))
         maximum-agent-task-participants)
     (denial 'participant-limit "The task participant limit has been reached.")]
    [else
     (define participant
       (odra-agent-task-participant
        canonical-task-id canonical-agent role
        (if current
            (add1 (odra-agent-task-participant-generation current))
            1)
        visibility
        (if current (odra-agent-task-participant-joined-at current) now)
        #f #f))
     (call-with-agent-continuity-transaction
      store 'join-task
      (lambda (connection)
        (persist-participant! connection participant)
        participant))]))

(define (leave-agent-task!
         store task-id agent-identity expected-participant-generation now
         #:reason [reason #f])
  (define canonical-task-id
    (immutable-identity task-id 'leave-agent-task! "task-id"))
  (define canonical-agent
    (immutable-identity agent-identity 'leave-agent-task! "agent-identity"))
  (when (and reason (not (identity? reason)))
    (raise-arguments-error
     'leave-agent-task! "invalid typed removal reason" "reason" reason))
  (define current (participant-at store canonical-task-id canonical-agent))
  (cond
    [(not current) (denial 'absent-participant "The participant does not exist.")]
    [(not (= expected-participant-generation
             (odra-agent-task-participant-generation current)))
     (denial 'stale-participant "The participant generation is stale.")]
    [(not (active-participant? current))
     (denial 'inactive-participant "The participant has already left.")]
    [(< now (odra-agent-task-participant-joined-at current))
     (denial 'invalid-time "Removal time precedes the participant join.")]
    [(eq? (odra-agent-task-participant-role current) 'owner)
     (denial 'owner-participant
             "The current owner cannot leave without an ownership transition.")]
    [else
     (define left
       (struct-copy
        odra-agent-task-participant current
        [generation (add1 (odra-agent-task-participant-generation current))]
        [left-at now]
        [reason reason]))
     (call-with-agent-continuity-transaction
      store 'leave-task
      (lambda (connection)
        (persist-participant! connection left)
        left))]))

(define (valid-task-transition? from to)
  (define entry (assq from task-transitions))
  (and entry (memq to (cdr entry)) #t))

(define (transition-agent-task!
         store task-id expected-generation acting-agent next-state now
         #:pending-decision-id [pending-decision-id #f]
         #:terminal-result-refs [terminal-result-refs '()])
  (define canonical-task-id
    (immutable-identity task-id 'transition-agent-task! "task-id"))
  (define actor
    (immutable-identity acting-agent 'transition-agent-task! "acting-agent"))
  (define decision-id
    (and pending-decision-id
         (immutable-identity
          pending-decision-id 'transition-agent-task! "pending-decision-id")))
  (unless (and (memq next-state admitted-task-states)
               (valid-owner-reference-list? terminal-result-refs))
    (raise-arguments-error
     'transition-agent-task! "invalid task transition content"))
  (define task (inspect-agent-task store canonical-task-id))
  (define participant
    (and task (participant-at store canonical-task-id actor)))
  (cond
    [(not task) (denial 'absent-task "The task does not exist.")]
    [(not (= expected-generation (odra-agent-task-generation task)))
     (denial 'stale-task "The task generation is stale.")]
    [(or (not participant) (not (active-participant? participant)))
     (denial 'absent-participant
             "The acting agent is not an active task participant.")]
    [(< now (odra-agent-task-updated-at task))
     (denial 'invalid-time "Transition time precedes the task observation.")]
    [(not (valid-task-transition? (odra-agent-task-state task) next-state))
     (denial 'invalid-transition "The requested task transition is invalid.")]
    [(and (eq? next-state 'succeeded) (null? terminal-result-refs))
     (denial 'missing-result
             "A succeeded task requires checked result or evidence references.")]
    [(and (not (eq? next-state 'waiting)) decision-id)
     (denial 'invalid-decision-state
             "A pending decision may be attached only to a waiting task.")]
    [else
     (define cancellation
       (if (eq? next-state 'cancelled)
           (odra-agent-task-cancellation 'completed actor 'task-cancelled now)
           (odra-agent-task-cancellation-record task)))
     (define next-task
       (struct-copy
        odra-agent-task task
        [generation (add1 (odra-agent-task-generation task))]
        [state next-state]
        [pending-decision-id (and (eq? next-state 'waiting) decision-id)]
        [cancellation-record cancellation]
        [terminal-result-refs (append terminal-result-refs '())]
        [updated-at now]))
     (call-with-agent-continuity-transaction
      store 'transition-task
      (lambda (connection)
        (persist-task! connection next-task)
        next-task))]))

(define (cancel-agent-task! store task-id expected-generation actor reason now)
  (define canonical-task-id
    (immutable-identity task-id 'cancel-agent-task! "task-id"))
  (define canonical-actor
    (immutable-identity actor 'cancel-agent-task! "actor"))
  (unless (bounded-text? reason maximum-agent-objective-bytes)
    (raise-arguments-error
     'cancel-agent-task! "invalid bounded cancellation reason"
     "reason" reason))
  (define task (inspect-agent-task store canonical-task-id))
  (cond
    [(not task) (denial 'absent-task "The task does not exist.")]
    [(not (= expected-generation (odra-agent-task-generation task)))
     (denial 'stale-task "The task generation is stale.")]
    [(memq (odra-agent-task-state task) '(cancelled failed succeeded))
     (denial 'terminal-task "The task is already terminal.")]
    [(< now (odra-agent-task-updated-at task))
     (denial 'invalid-time "Cancellation time precedes the task observation.")]
    [else
     (define cancelled
       (struct-copy
        odra-agent-task task
        [generation (add1 expected-generation)]
        [state 'cancelled]
        [pending-decision-id #f]
        [cancellation-record
         (odra-agent-task-cancellation
          'completed canonical-actor (string->immutable-string reason) now)]
        [updated-at now]))
     (call-with-agent-continuity-transaction
      store 'cancel-task
      (lambda (connection)
        (persist-task! connection cancelled)
        cancelled))]))

(define (record-agent-interaction!
         store identity task-id sender recipient kind payload visibility
         provenance now
         #:acting-agent [acting-agent #f]
         #:parent-task-id [parent-task-id #f]
         #:owner-namespace [owner-namespace #f]
         #:context-references [context-references '()]
         #:decision-class [decision-class #f]
         #:correlation-id [correlation-id #f]
         #:idempotency-id [idempotency-id #f]
         #:valid-until [valid-until #f])
  (define interaction-id
    (immutable-identity identity 'record-agent-interaction! "identity"))
  (define canonical-task-id
    (immutable-identity task-id 'record-agent-interaction! "task-id"))
  (define canonical-sender
    (immutable-identity sender 'record-agent-interaction! "sender"))
  (define canonical-recipient
    (immutable-identity recipient 'record-agent-interaction! "recipient"))
  (define canonical-acting-agent
    (and acting-agent
         (immutable-identity
          acting-agent 'record-agent-interaction! "acting-agent")))
  (define canonical-parent-task-id
    (and parent-task-id
         (immutable-identity
          parent-task-id 'record-agent-interaction! "parent-task-id")))
  (define canonical-owner-namespace
    (and owner-namespace
         (immutable-identity
          owner-namespace 'record-agent-interaction! "owner-namespace")))
  (define canonical-decision-class
    (and decision-class
         (immutable-identity
          decision-class 'record-agent-interaction! "decision-class")))
  (define canonical-correlation-id
    (and correlation-id
         (immutable-identity
          correlation-id 'record-agent-interaction! "correlation-id")))
  (define canonical-idempotency-id
    (and idempotency-id
         (immutable-identity
          idempotency-id 'record-agent-interaction! "idempotency-id")))
  (unless (and (memq kind admitted-interaction-kinds)
               (memq visibility admitted-visibility)
               (inert-value? payload maximum-agent-interaction-payload-bytes)
               (valid-owner-reference-list? context-references)
               (or (not valid-until) (> valid-until now)))
    (raise-arguments-error
     'record-agent-interaction! "invalid bounded interaction envelope"))
  (define task (inspect-agent-task store canonical-task-id))
  (define participant
    (and task canonical-acting-agent
         (participant-at store canonical-task-id canonical-acting-agent)))
  (cond
    [(not task) (denial 'absent-task "The task does not exist.")]
    [(inspect-agent-interaction store interaction-id)
     (denial 'duplicate-interaction
             "An interaction with this identity already exists.")]
    [(not (equal? canonical-parent-task-id
                  (odra-agent-task-parent-task-id task)))
     (denial 'invalid-parent "The interaction parent does not match the task.")]
    [(not (string=?
           canonical-sender
           (odra-agent-interaction-provenance-actor-identity provenance)))
     (denial 'invalid-provenance
             "Interaction provenance does not identify its sender.")]
    [(and canonical-acting-agent
          (or (not participant) (not (active-participant? participant))))
     (denial 'absent-participant
             "The acting agent is not an active task participant.")]
    [(>= (continuity-store-interaction-count store)
         maximum-retained-agent-interactions)
     (denial 'interaction-limit
             "The retained interaction limit has been reached.")]
    [else
     (define interaction
       (odra-agent-interaction
        interaction-id 1 canonical-sender canonical-acting-agent
        canonical-recipient canonical-task-id canonical-parent-task-id
        canonical-owner-namespace kind (immutable-copy payload)
        (append context-references '()) canonical-decision-class visibility
        canonical-correlation-id canonical-idempotency-id now valid-until
        provenance))
     (call-with-agent-continuity-transaction
      store 'record-interaction
      (lambda (connection)
        (continuity-transaction-insert-interaction!
         connection interaction-id canonical-task-id 1 kind
         (encode-datum (interaction->datum interaction)) now)
        interaction))]))

(define (delegation-authority-valid?
         authority-store catalog task-id sender recipient authority-ceiling at)
  (for/and ([capability (in-list authority-ceiling)])
    (and
     (agent-capability-authority-effective?
      authority-store catalog sender capability at
      #:task-id task-id #:delegation? #t)
     (agent-capability-authority-effective?
      authority-store catalog recipient capability at #:task-id task-id))))

(define (persist-delegation! connection delegation)
  (unless
      (continuity-transaction-write-delegation!
       connection
       (odra-agent-delegation-identity delegation)
       (odra-agent-delegation-generation delegation)
       (odra-agent-delegation-parent-task-id delegation)
       (odra-agent-delegation-child-task-id delegation)
       (odra-agent-delegation-sender-agent delegation)
       (odra-agent-delegation-recipient-agent delegation)
       (odra-agent-delegation-state delegation)
       (encode-datum (delegation->datum delegation))
       (odra-agent-delegation-created-at delegation)
       (odra-agent-delegation-updated-at delegation))
    (error 'persist-delegation!
           "delegation generation changed during publication")))

(define (canonical-capability-ceiling capabilities who)
  (unless (and (<= (length capabilities) maximum-agent-owner-references)
               (andmap identity? capabilities))
    (raise-arguments-error who "invalid bounded authority ceiling"
                           "authority-ceiling" capabilities))
  (sort
   (remove-duplicates (map (lambda (value)
                             (immutable-identity value who "capability"))
                           capabilities)
                      string=?)
   string<?))

(define (create-agent-delegation!
         store authority-store catalog identity parent-task-id sender-agent
         recipient-agent requested-outcome now
         #:child-task-id [child-task-id #f]
         #:context-references [context-references '()]
         #:authority-ceiling [authority-ceiling '()]
         #:deadline [deadline #f])
  (define delegation-id
    (immutable-identity identity 'create-agent-delegation! "identity"))
  (define parent-id
    (immutable-identity
     parent-task-id 'create-agent-delegation! "parent-task-id"))
  (define child-id
    (and child-task-id
         (immutable-identity
          child-task-id 'create-agent-delegation! "child-task-id")))
  (define sender
    (immutable-identity
     sender-agent 'create-agent-delegation! "sender-agent"))
  (define recipient
    (immutable-identity
     recipient-agent 'create-agent-delegation! "recipient-agent"))
  (define ceiling
    (canonical-capability-ceiling
     authority-ceiling 'create-agent-delegation!))
  (unless (and (not (string=? sender recipient))
               (inert-value? requested-outcome maximum-agent-objective-bytes)
               (valid-owner-reference-list? context-references)
               (or (not deadline) (> deadline now)))
    (raise-arguments-error
     'create-agent-delegation! "invalid bounded delegation"))
  (define parent (inspect-agent-task store parent-id))
  (define child (and child-id (inspect-agent-task store child-id)))
  (define sender-participant
    (and parent (participant-at store parent-id sender)))
  (define recipient-participant
    (and parent (participant-at store parent-id recipient)))
  (cond
    [(not parent) (denial 'absent-task "The parent task does not exist.")]
    [(not (nonterminal-task? parent))
     (denial 'terminal-task "A terminal task cannot delegate work.")]
    [(inspect-agent-delegation store delegation-id)
     (denial 'duplicate-delegation
             "A delegation with this identity already exists.")]
    [(or (not sender-participant)
         (not (active-participant? sender-participant))
         (not (memq (odra-agent-task-participant-role sender-participant)
                    '(owner delegate))))
     (denial 'invalid-sender
             "The sender is not an active delegating participant.")]
    [(or (not recipient-participant)
         (not (active-participant? recipient-participant))
         (not (eq? (odra-agent-task-participant-role recipient-participant)
                   'delegate)))
     (denial 'invalid-recipient
             "The recipient is not an active delegate participant.")]
    [(and child-id
          (or (not child)
              (not (equal? parent-id
                           (odra-agent-task-parent-task-id child)))))
     (denial 'invalid-child
             "The child task is absent or does not belong to the parent.")]
    [(not (delegation-authority-valid?
           authority-store catalog parent-id sender recipient ceiling now))
     (denial 'authority-reduced
             "Delegation exceeds current sender or recipient authority.")]
    [(>= (continuity-store-delegation-count store)
         maximum-retained-agent-delegations)
     (denial 'delegation-limit
             "The retained delegation limit has been reached.")]
    [else
     (define delegation
       (odra-agent-delegation
        delegation-id 1 parent-id child-id sender recipient
        (immutable-copy requested-outcome) (append context-references '())
        ceiling 'proposed deadline #f now now))
     (call-with-agent-continuity-transaction
      store 'create-delegation
      (lambda (connection)
        (persist-delegation! connection delegation)
        delegation))]))

(define (valid-delegation-transition? from to)
  (define entry (assq from delegation-transitions))
  (and entry (memq to (cdr entry)) #t))

(define (transition-agent-delegation!
         store authority-store catalog identity expected-generation
         acting-agent next-state now
         #:terminal-result-reference [terminal-result-reference #f])
  (define delegation-id
    (immutable-identity identity 'transition-agent-delegation! "identity"))
  (define actor
    (immutable-identity
     acting-agent 'transition-agent-delegation! "acting-agent"))
  (unless (memq next-state admitted-delegation-states)
    (raise-arguments-error
     'transition-agent-delegation! "invalid delegation state"
     "next-state" next-state))
  (define delegation (inspect-agent-delegation store delegation-id))
  (cond
    [(not delegation)
     (denial 'absent-delegation "The delegation does not exist.")]
    [(not (= expected-generation
             (odra-agent-delegation-generation delegation)))
     (denial 'stale-delegation "The delegation generation is stale.")]
    [(< now (odra-agent-delegation-updated-at delegation))
     (denial 'invalid-time
             "Transition time precedes the delegation observation.")]
    [(not (valid-delegation-transition?
           (odra-agent-delegation-state delegation) next-state))
     (denial 'invalid-transition
             "The requested delegation transition is invalid.")]
    [(and (memq next-state '(accepted rejected running completed failed))
          (not (string=?
                actor (odra-agent-delegation-recipient-agent delegation))))
     (denial 'invalid-actor
             "Only the recipient can publish this delegation transition.")]
    [(and (eq? next-state 'cancelled)
          (not (member actor
                       (list (odra-agent-delegation-sender-agent delegation)
                             (odra-agent-delegation-recipient-agent delegation))
                       string=?)))
     (denial 'invalid-actor
             "Only a delegation participant can cancel the delegation.")]
    [(and (memq next-state '(accepted running))
          (not
           (delegation-authority-valid?
            authority-store catalog
            (odra-agent-delegation-parent-task-id delegation)
            (odra-agent-delegation-sender-agent delegation)
            (odra-agent-delegation-recipient-agent delegation)
            (odra-agent-delegation-authority-ceiling delegation)
            now)))
     (denial 'authority-reduced
             "Current authority no longer admits this delegation.")]
    [(and (eq? next-state 'completed) (not terminal-result-reference))
     (denial 'missing-result
             "A completed delegation requires a result reference.")]
    [else
     (define next-delegation
       (struct-copy
        odra-agent-delegation delegation
        [generation (add1 (odra-agent-delegation-generation delegation))]
        [state next-state]
        [terminal-result-reference terminal-result-reference]
        [updated-at now]))
     (call-with-agent-continuity-transaction
      store 'transition-delegation
      (lambda (connection)
        (persist-delegation! connection next-delegation)
        next-delegation))]))
