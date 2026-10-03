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
         "definition.rkt")

(provide
 maximum-retained-agent-audit-events
 maximum-agent-audit-references
 maximum-agent-audit-payload-bytes
 (struct-out odra-agent-audit-event)
 (struct-out odra-agent-audit-denial)
 (contract-out
  [record-agent-audit-event!
   (->* (odra-agent-continuity-store? (or/c symbol? string?) symbol?
         (or/c symbol? string?) any/c exact-nonnegative-integer?)
        (#:task-id (or/c #f symbol? string?)
         #:subject-references list?
         #:captured-generations list?
         #:effect-class (or/c #f symbol?)
         #:evidence-references list?
         #:visibility symbol?
         #:redaction-class symbol?)
        (or/c odra-agent-audit-event? odra-agent-audit-denial?))]
  [inspect-agent-audit-event
   (-> odra-agent-continuity-store? (or/c symbol? string?)
       (or/c #f odra-agent-audit-event?))]
  [inspect-agent-audit-events
   (->* (odra-agent-continuity-store?)
        (#:after-sequence exact-nonnegative-integer?
         #:limit exact-positive-integer?)
        (listof odra-agent-audit-event?))]))

(define maximum-retained-agent-audit-events 100000)
(define maximum-agent-audit-references 32)
(define maximum-agent-audit-payload-bytes (* 16 1024))
(define identity-pattern #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")
(define admitted-visibility '(administrator local-user participants public-safe))
(define admitted-redaction '(identity-only none safe-summary))

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

(define (audit-value-shape? value [depth 0])
  (and
   (<= depth 6)
   (cond
     [(or (boolean? value) (exact-integer? value)) #t]
     [(symbol? value) (identity? value)]
     [(string? value)
      (bounded-text? value maximum-agent-audit-payload-bytes #:empty? #t)]
     [(bytes? value)
      (<= (bytes-length value) maximum-agent-audit-payload-bytes)]
     [(null? value) #t]
     [(list? value)
      (and (<= (length value) 128)
           (andmap (lambda (item) (audit-value-shape? item (add1 depth)))
                   value))]
     [else #f])))

(define (bounded-audit-value? value)
  (and (audit-value-shape? value)
       (<= (bytes-length (string->bytes/utf-8 (format "~s" value)))
           maximum-agent-audit-payload-bytes)))

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

(define (record-reference->datum reference)
  (list 'record-reference
        (odra-agent-record-reference-kind reference)
        (odra-agent-record-reference-identity reference)
        (odra-agent-record-reference-generation reference)))

(define (datum->record-reference datum)
  (match datum
    [(list 'record-reference kind identity generation)
     (make-agent-record-reference kind identity generation)]
    [_ (error 'inspect-agent-audit-event
              "invalid persisted audit reference")]))

(struct odra-agent-audit-event
  (identity sequence occurred-at kind actor task-id subject-references
            captured-generations effect-class outcome evidence-references
            visibility redaction-class)
  #:transparent)

(struct odra-agent-audit-denial (code safe-detail) #:transparent)

(define (audit-denial code detail)
  (odra-agent-audit-denial code (string->immutable-string detail)))

(define (audit-event->datum event)
  (list 'audit-event
        (odra-agent-audit-event-identity event)
        (odra-agent-audit-event-sequence event)
        (odra-agent-audit-event-occurred-at event)
        (odra-agent-audit-event-kind event)
        (odra-agent-audit-event-actor event)
        (odra-agent-audit-event-task-id event)
        (map record-reference->datum
             (odra-agent-audit-event-subject-references event))
        (map record-reference->datum
             (odra-agent-audit-event-captured-generations event))
        (odra-agent-audit-event-effect-class event)
        (odra-agent-audit-event-outcome event)
        (map record-reference->datum
             (odra-agent-audit-event-evidence-references event))
        (odra-agent-audit-event-visibility event)
        (odra-agent-audit-event-redaction-class event)))

(define (datum->audit-event datum sequence)
  (match datum
    [(list 'audit-event identity _ occurred-at kind actor task-id subjects
           generations effect outcome evidence visibility redaction)
     (odra-agent-audit-event
      identity sequence occurred-at kind actor task-id
      (map datum->record-reference subjects)
      (map datum->record-reference generations)
      effect outcome (map datum->record-reference evidence)
      visibility redaction)]
    [_ (error 'inspect-agent-audit-event "invalid persisted audit event")]))

(define (inspect-agent-audit-event store identity)
  (define normalized
    (immutable-identity identity 'inspect-agent-audit-event "identity"))
  (define row (continuity-store-audit-record store normalized))
  (and row
       (datum->audit-event
        (decode-datum (vector-ref row 7) 'inspect-agent-audit-event)
        (vector-ref row 0))))

(define (inspect-agent-audit-events
         store #:after-sequence [after-sequence 0] #:limit [limit 256])
  (unless (<= limit 1024)
    (raise-arguments-error
     'inspect-agent-audit-events "audit query limit exceeds 1024"))
  (for/list ([row (in-list
                   (continuity-store-audit-records
                    store after-sequence limit))])
    (datum->audit-event
     (decode-datum (vector-ref row 8) 'inspect-agent-audit-events)
     (vector-ref row 1))))

(define (record-agent-audit-event!
         store identity kind actor outcome occurred-at
         #:task-id [task-id #f]
         #:subject-references [subjects '()]
         #:captured-generations [generations '()]
         #:effect-class [effect #f]
         #:evidence-references [evidence '()]
         #:visibility [visibility 'local-user]
         #:redaction-class [redaction 'safe-summary])
  (define canonical-identity
    (immutable-identity identity 'record-agent-audit-event! "identity"))
  (define canonical-actor
    (immutable-identity actor 'record-agent-audit-event! "actor"))
  (define canonical-task
    (and task-id
         (immutable-identity task-id 'record-agent-audit-event! "task-id")))
  (unless (and (identity? kind)
               (bounded-audit-value? outcome)
               (<= (length subjects) maximum-agent-audit-references)
               (andmap odra-agent-record-reference? subjects)
               (<= (length generations) maximum-agent-audit-references)
               (andmap odra-agent-record-reference? generations)
               (or (not effect)
                   (memq effect admitted-agent-effect-classes))
               (<= (length evidence) maximum-agent-audit-references)
               (andmap odra-agent-record-reference? evidence)
               (memq visibility admitted-visibility)
               (memq redaction admitted-redaction))
    (raise-arguments-error
     'record-agent-audit-event! "invalid bounded audit event"))
  (cond
    [(inspect-agent-audit-event store canonical-identity)
     (audit-denial 'duplicate-audit-event
                   "The audit identity already exists.")]
    [(>= (continuity-store-audit-count store)
         maximum-retained-agent-audit-events)
     (audit-denial 'audit-limit
                   "The retained audit event limit was reached.")]
    [else
     (call-with-agent-continuity-transaction
      store 'record-audit-event
      (lambda (connection)
        (define provisional
          (odra-agent-audit-event
           canonical-identity 0 occurred-at kind canonical-actor canonical-task
           (append subjects '()) (append generations '()) effect outcome
           (append evidence '()) visibility redaction))
        (define sequence
          (continuity-transaction-insert-audit!
           connection canonical-identity occurred-at kind canonical-actor
           canonical-task visibility redaction
           (encode-datum (audit-event->datum provisional))))
        (struct-copy odra-agent-audit-event provisional
                     [sequence sequence])))]))
