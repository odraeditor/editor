#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require file/sha1
         racket/contract/base
         racket/match
         racket/port
         "audit.rkt"
         "continuity-store.rkt"
         "driver.rkt"
         "execution.rkt")

(provide
 maximum-agent-reconciliation-markers
 (struct-out odra-agent-reconciliation-marker)
 (struct-out odra-agent-recovery-summary)
 (contract-out
  [inspect-agent-reconciliation-marker
   (-> odra-agent-continuity-store? string?
       (or/c #f odra-agent-reconciliation-marker?))]
  [inspect-agent-reconciliation-markers
   (-> odra-agent-continuity-store?
       (listof odra-agent-reconciliation-marker?))]
  [reconcile-agent-substrate!
   (->* (odra-agent-continuity-store? exact-nonnegative-integer?)
        (#:actor (or/c symbol? string?))
        odra-agent-recovery-summary?)]))

(define maximum-agent-reconciliation-markers 10000)

(struct odra-agent-reconciliation-marker
  (identity generation state subject-kind subject-identity prior-generation
            prior-state updated-at)
  #:transparent)

(struct odra-agent-recovery-summary
  (driver-sessions turns operation-attempts unchanged denied)
  #:transparent)

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

(define (marker-identity kind identity)
  (string->immutable-string
   (string-append
    "recovery." (symbol->string kind) "."
    (sha1 (open-input-string (string-append (symbol->string kind) ":" identity))))))

(define (marker->datum marker)
  (list 'reconciliation-marker
        (odra-agent-reconciliation-marker-prior-generation marker)
        (odra-agent-reconciliation-marker-prior-state marker)))

(define (row->marker row)
  (match (decode-datum (vector-ref row 5)
                       'inspect-agent-reconciliation-marker)
    [(list 'reconciliation-marker prior-generation prior-state)
     (odra-agent-reconciliation-marker
      (string->immutable-string (vector-ref row 0))
      (vector-ref row 1)
      (string->symbol (vector-ref row 2))
      (string->symbol (vector-ref row 3))
      (string->immutable-string (vector-ref row 4))
      prior-generation prior-state (vector-ref row 6))]
    [_ (error 'inspect-agent-reconciliation-marker
              "invalid persisted reconciliation marker")]))

(define (inspect-agent-reconciliation-marker store identity)
  (define row (continuity-store-reconciliation-record store identity))
  (and row
       (row->marker
        (vector identity
                (vector-ref row 0)
                (vector-ref row 1)
                (vector-ref row 2)
                (vector-ref row 3)
                (vector-ref row 4)
                (vector-ref row 5)))))

(define (inspect-agent-reconciliation-markers store)
  (map row->marker (continuity-store-reconciliation-records store)))

(define (persist-marker! store kind identity generation state now)
  (define canonical-id (marker-identity kind identity))
  (define prior (inspect-agent-reconciliation-marker store canonical-id))
  (define marker
    (odra-agent-reconciliation-marker
     canonical-id
     (if prior
         (add1 (odra-agent-reconciliation-marker-generation prior))
         1)
     'reconciling kind (string->immutable-string identity) generation state now))
  (call-with-agent-continuity-transaction
   store 'record-reconciliation-marker
   (lambda (connection)
     (unless
         (continuity-transaction-write-reconciliation!
          connection
          (odra-agent-reconciliation-marker-identity marker)
          (odra-agent-reconciliation-marker-generation marker)
          (odra-agent-reconciliation-marker-state marker)
          (odra-agent-reconciliation-marker-subject-kind marker)
          (odra-agent-reconciliation-marker-subject-identity marker)
          (encode-datum (marker->datum marker)) now)
       (error 'reconcile-agent-substrate! "stale reconciliation marker"))
     marker)))

(define (record-recovery-audit! store marker actor now)
  (record-agent-audit-event!
   store
   (string-append
    "audit." (odra-agent-reconciliation-marker-identity marker) "."
    (number->string (odra-agent-reconciliation-marker-generation marker)))
   'startup-reconciliation actor
   (list 'reconciling
         (odra-agent-reconciliation-marker-subject-kind marker)
         (odra-agent-reconciliation-marker-subject-identity marker)
         (odra-agent-reconciliation-marker-prior-generation marker)
         (odra-agent-reconciliation-marker-prior-state marker))
   now
   #:visibility 'administrator
   #:redaction-class 'identity-only))

(define (reconcile-records! store rows kind reconcile! actor now)
  (for/fold ([changed 0] [unchanged 0] [denied 0])
            ([row (in-list rows)])
    (define identity (vector-ref row 0))
    (define generation (vector-ref row 1))
    (define state (string->symbol (vector-ref row 2)))
    (define result (reconcile! store identity generation now))
    (cond
      [(or (odra-agent-driver-denial? result)
           (odra-agent-execution-denial? result))
       (values changed unchanged (add1 denied))]
      [else
       (define marker
         (persist-marker! store kind identity generation state now))
       (record-recovery-audit! store marker actor now)
       (values (add1 changed) unchanged denied)])))

(define (reconcile-agent-substrate! store now #:actor [actor 'local-user])
  (define-values (sessions sessions-unchanged sessions-denied)
    (reconcile-records!
     store (continuity-store-recovery-session-records store)
     'driver-session reconcile-agent-driver-session! actor now))
  (define-values (turns turns-unchanged turns-denied)
    (reconcile-records!
     store (continuity-store-recovery-turn-records store)
     'agent-turn reconcile-agent-turn! actor now))
  (define-values (attempts attempts-unchanged attempts-denied)
    (reconcile-records!
     store (continuity-store-recovery-attempt-records store)
     'operation-attempt reconcile-agent-operation-attempt! actor now))
  (odra-agent-recovery-summary
   sessions turns attempts
   (+ sessions-unchanged turns-unchanged attempts-unchanged)
   (+ sessions-denied turns-denied attempts-denied)))
