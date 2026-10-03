#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         "admission.rkt"
         "audit.rkt"
         "authority.rkt"
         "continuity.rkt"
         "driver.rkt"
         "execution.rkt"
         "lifecycle.rkt"
         "recovery.rkt"
         "registry.rkt")

(provide
 maximum-agent-inspection-records
 (struct-out odra-agent-inspection-link)
 (struct-out odra-agent-inspection-projection)
 (contract-out
  [inspect-agent-substrate-records
   (->* (odra-agent-continuity-store? odra-agent-authority-store?
         odra-agent-catalog? odra-agent-driver-registry?)
        (#:at exact-nonnegative-integer? #:limit exact-positive-integer?)
        (listof odra-agent-inspection-projection?))]
  [inspect-agent-substrate-kind
   (->* (odra-agent-continuity-store? odra-agent-authority-store?
         odra-agent-catalog? odra-agent-driver-registry? symbol?)
        (#:at exact-nonnegative-integer? #:limit exact-positive-integer?)
        (listof odra-agent-inspection-projection?))]
  [inspect-agent-substrate-detail
   (->* (odra-agent-continuity-store? odra-agent-authority-store?
         odra-agent-catalog? odra-agent-driver-registry? symbol? string?)
        (#:at exact-nonnegative-integer?)
        (or/c #f odra-agent-inspection-projection?))]))

(define maximum-agent-inspection-records 1024)

(struct odra-agent-inspection-link (kind identity label) #:transparent)

(struct odra-agent-inspection-projection
  (kind identity generation label state summary attention? details relations)
  #:transparent)

(define (bounded-list values limit)
  (if (> (length values) limit) (take values limit) values))

(define (link kind identity label)
  (odra-agent-inspection-link kind identity label))

(define (projection kind identity generation label state summary
                    #:attention? [attention? #f]
                    #:details [details '()]
                    #:relations [relations '()])
  (odra-agent-inspection-projection
   kind identity generation label state summary attention?
   (append details '()) (append relations '())))

(define (agent-available? definition drivers)
  (for/and
      ([required
        (in-list
         (odra-agent-definition-projection-provider-requirements definition))])
    (for/or ([driver (in-list drivers)])
      (string=? required (odra-agent-driver-projection-role driver)))))

(define (agent-projection definition drivers)
  (define available? (agent-available? definition drivers))
  (projection
   'agent
   (odra-agent-definition-projection-identity definition)
   (odra-agent-definition-projection-definition-generation definition)
   (odra-agent-definition-projection-display-name definition)
   (if available? 'available 'unavailable)
   (if available?
       (odra-agent-definition-projection-description definition)
       "A required agent driver is unavailable.")
   #:attention? (not available?)
   #:details
   (list
    (cons 'package (odra-agent-definition-projection-package-id definition))
    (cons 'package-version
          (odra-agent-definition-projection-package-version definition))
    (cons 'contribution-generation
          (odra-agent-definition-projection-contribution-generation definition))
    (cons 'interaction-kinds
          (odra-agent-definition-projection-interaction-kinds definition))
    (cons 'provider-requirements
          (odra-agent-definition-projection-provider-requirements definition))
    (cons 'continuation-policy
          (odra-agent-definition-projection-continuation-policy definition)))
   #:relations
   (for/list
       ([identity
         (in-list
          (odra-agent-definition-projection-requested-capabilities definition))])
     (link 'capability identity identity))))

(define (capability-projection definition)
  (projection
   'capability
   (odra-agent-capability-projection-identity definition)
   (odra-agent-capability-projection-definition-generation definition)
   (odra-agent-capability-projection-identity definition)
   'available
   (odra-agent-capability-projection-purpose definition)
   #:details
   (list
    (cons 'owner (odra-agent-capability-projection-owner-namespace definition))
    (cons 'package (odra-agent-capability-projection-package-id definition))
    (cons 'package-version
          (odra-agent-capability-projection-package-version definition))
    (cons 'target-kinds
          (odra-agent-capability-projection-target-kinds definition))
    (cons 'effects (odra-agent-capability-projection-effects definition))
    (cons 'approval-class
          (odra-agent-capability-projection-approval-class definition))
    (cons 'idempotency-class
          (odra-agent-capability-projection-idempotency-class definition))
    (cons 'retirement-policy
          (odra-agent-capability-projection-retirement-policy definition)))))

(define (driver-projection driver)
  (projection
   'driver
   (odra-agent-driver-projection-identity driver)
   (odra-agent-driver-projection-generation driver)
   (odra-agent-driver-projection-identity driver)
   'available
   (format "Provider-neutral driver for ~a."
           (odra-agent-driver-projection-role driver))
   #:details
   (list (cons 'role (odra-agent-driver-projection-role driver))
         (cons 'features (odra-agent-driver-projection-features driver)))))

(define (grant-projection grant)
  (define state (odra-agent-grant-projection-state grant))
  (projection
   'grant
   (odra-agent-grant-projection-identity grant)
   (odra-agent-grant-projection-generation grant)
   (format "~a for ~a"
           (odra-agent-grant-projection-capability-identity grant)
           (odra-agent-grant-projection-agent-identity grant))
   state
   (format "~a capability authority is ~a."
           (odra-agent-grant-projection-capability-identity grant) state)
   #:attention? (memq state '(expired revoked))
   #:details
   (list
    (cons 'effects (odra-agent-grant-projection-effects grant))
    (cons 'valid-from (odra-agent-grant-projection-valid-from grant))
    (cons 'valid-until (odra-agent-grant-projection-valid-until grant))
    (cons 'task-restriction
          (odra-agent-grant-projection-task-restriction grant)))
   #:relations
   (list
    (link 'agent
          (odra-agent-grant-projection-agent-identity grant)
          (odra-agent-grant-projection-agent-identity grant))
    (link 'capability
          (odra-agent-grant-projection-capability-identity grant)
          (odra-agent-grant-projection-capability-identity grant)))))

(define (task-projection task)
  (define owner (or (odra-agent-task-owner-agent task) "Unassigned"))
  (projection
   'task (odra-agent-task-identity task) (odra-agent-task-generation task)
   (odra-agent-task-objective task) (odra-agent-task-state task)
   (format "~a task owned by ~a." (odra-agent-task-state task) owner)
   #:attention? (or (odra-agent-task-pending-decision-id task)
                    (memq (odra-agent-task-state task)
                          '(blocked failed waiting)))
   #:details
   (list
    (cons 'owner-agent (odra-agent-task-owner-agent task))
    (cons 'parent-task (odra-agent-task-parent-task-id task))
    (cons 'created-at (odra-agent-task-created-at task))
    (cons 'updated-at (odra-agent-task-updated-at task)))
   #:relations
   (append
    (if (odra-agent-task-owner-agent task)
        (list (link 'agent owner owner)) '())
    (if (odra-agent-task-pending-decision-id task)
        (list
         (link 'decision
               (odra-agent-task-pending-decision-id task)
               "Pending decision"))
        '()))))

(define (interaction-projection interaction)
  (projection
   'interaction
   (odra-agent-interaction-identity interaction)
   (odra-agent-interaction-generation interaction)
   (format "~a from ~a"
           (odra-agent-interaction-kind interaction)
           (odra-agent-interaction-sender interaction))
   'recorded
   (format "Recorded ~a interaction."
           (odra-agent-interaction-kind interaction))
   #:attention? (memq (odra-agent-interaction-kind interaction)
                      '(failure question request))
   #:details
   (list
    (cons 'actor (odra-agent-interaction-acting-agent interaction))
    (cons 'visibility (odra-agent-interaction-visibility interaction))
    (cons 'created-at (odra-agent-interaction-created-at interaction)))
   #:relations
   (list
    (link 'task (odra-agent-interaction-task-id interaction)
          (odra-agent-interaction-task-id interaction)))))

(define (session-projection session)
  (projection
   'driver-session
   (odra-agent-driver-session-identity session)
   (odra-agent-driver-session-generation session)
   (format "~a session" (odra-agent-driver-session-agent-identity session))
   (odra-agent-driver-session-state session)
   (format "~a driver session is ~a."
           (odra-agent-driver-projection-identity
            (odra-agent-driver-session-driver-projection session))
           (odra-agent-driver-session-state session))
   #:attention? (memq (odra-agent-driver-session-state session)
                      '(cancelling failed reconciling))
   #:details
   (list
    (cons 'driver
          (odra-agent-driver-projection-identity
           (odra-agent-driver-session-driver-projection session)))
    (cons 'opened-at (odra-agent-driver-session-opened-at session))
    (cons 'last-observed-at
          (odra-agent-driver-session-last-observed-at session)))
   #:relations
   (list
    (link 'task (odra-agent-driver-session-task-id session)
          (odra-agent-driver-session-task-id session))
    (link 'agent (odra-agent-driver-session-agent-identity session)
          (odra-agent-driver-session-agent-identity session)))))

(define (turn-projection turn)
  (projection
   'turn (odra-agent-turn-identity turn) (odra-agent-turn-generation turn)
   (format "~a turn" (odra-agent-turn-agent-identity turn))
   (odra-agent-turn-state turn)
   (format "Agent turn is ~a." (odra-agent-turn-state turn))
   #:attention? (memq (odra-agent-turn-state turn)
                      '(failed reconciling waiting))
   #:details
   (list (cons 'deadline (odra-agent-turn-deadline turn))
         (cons 'started-at (odra-agent-turn-started-at turn))
         (cons 'ended-at (odra-agent-turn-ended-at turn)))
   #:relations
   (list
    (link 'task (odra-agent-turn-task-id turn)
          (odra-agent-turn-task-id turn))
    (link 'driver-session
          (odra-agent-record-reference-identity
           (odra-agent-turn-driver-session-reference turn))
          "Driver session"))))

(define (request-projection request decision)
  (define state
    (if decision (odra-agent-admission-decision-state decision) 'pending))
  (projection
   'request
   (odra-agent-capability-request-identity request)
   1
   (format "~a request" (odra-agent-capability-request-capability-identity request))
   state
   (format "~a requested ~a."
           (odra-agent-capability-request-agent-identity request)
           (odra-agent-capability-request-capability-identity request))
   #:attention? (memq state '(needs-human-decision pending rejected))
   #:details
   (list
    (cons 'effects (odra-agent-capability-request-requested-effects request))
    (cons 'created-at (odra-agent-capability-request-created-at request))
    (cons 'valid-until (odra-agent-capability-request-valid-until request))
    (cons 'target-count
          (length (odra-agent-capability-request-target-references request))))
   #:relations
   (list
    (link 'task (odra-agent-capability-request-task-id request)
          (odra-agent-capability-request-task-id request))
    (link 'agent (odra-agent-capability-request-agent-identity request)
          (odra-agent-capability-request-agent-identity request))
    (link 'capability
          (odra-agent-capability-request-capability-identity request)
          (odra-agent-capability-request-capability-identity request)))))

(define (decision-projection decision)
  (projection
   'decision
   (odra-agent-admission-decision-identity decision)
   1
   (format "Decision for ~a"
           (odra-agent-admission-decision-request-id decision))
   (odra-agent-admission-decision-state decision)
   (or (odra-agent-admission-decision-reason-detail decision)
       "The request passed admission.")
   #:attention? (eq? (odra-agent-admission-decision-state decision)
                     'needs-human-decision)
   #:details
   (list
    (cons 'reason (odra-agent-admission-decision-reason-code decision))
    (cons 'effects
          (odra-agent-admission-decision-effective-effects decision))
    (cons 'decided-at (odra-agent-admission-decision-decided-at decision)))
   #:relations
   (list
    (link 'request (odra-agent-admission-decision-request-id decision)
          (odra-agent-admission-decision-request-id decision)))))

(define (attempt-projection attempt)
  (projection
   'attempt
   (odra-agent-operation-attempt-identity attempt)
   (odra-agent-operation-attempt-generation attempt)
   (format "Attempt for ~a"
           (odra-agent-operation-attempt-request-id attempt))
   (odra-agent-operation-attempt-state attempt)
   (format "Capability attempt is ~a."
           (odra-agent-operation-attempt-state attempt))
   #:attention? (memq (odra-agent-operation-attempt-state attempt)
                      '(cancelling failed reconciling))
   #:details
   (list
    (cons 'lease-deadline
          (odra-agent-operation-attempt-lease-deadline attempt))
    (cons 'started-at (odra-agent-operation-attempt-started-at attempt))
    (cons 'ended-at (odra-agent-operation-attempt-ended-at attempt)))
   #:relations
   (list
    (link 'request (odra-agent-operation-attempt-request-id attempt)
          (odra-agent-operation-attempt-request-id attempt)))))

(define (result-projection result)
  (projection
   'result
   (odra-agent-operation-result-identity result)
   1
   (format "Result for ~a" (odra-agent-operation-result-request-id result))
   (odra-agent-operation-result-state result)
   (odra-agent-operation-result-safe-summary result)
   #:attention? (memq (odra-agent-operation-result-state result)
                      '(failed outcome-unknown rejected revoked timed-out))
   #:details
   (list
    (cons 'effects (odra-agent-operation-result-confirmed-effects result))
    (cons 'owner-evidence-count
          (length (odra-agent-operation-result-owner-evidence result)))
    (cons 'external-evidence-count
          (length (odra-agent-operation-result-external-evidence result)))
    (cons 'completed-at (odra-agent-operation-result-completed-at result)))
   #:relations
   (list
    (link 'request (odra-agent-operation-result-request-id result)
          (odra-agent-operation-result-request-id result))
    (link 'attempt (odra-agent-operation-result-attempt-id result)
          (odra-agent-operation-result-attempt-id result)))))

(define (audit-projection event)
  (define summary
    (if (eq? (odra-agent-audit-event-redaction-class event) 'identity-only)
        "Details are redacted to identities."
        (format "~s" (odra-agent-audit-event-outcome event))))
  (projection
   'audit (odra-agent-audit-event-identity event)
   (odra-agent-audit-event-sequence event)
   (format "~a by ~a"
           (odra-agent-audit-event-kind event)
           (odra-agent-audit-event-actor event))
   'recorded summary
   #:details
   (list
    (cons 'occurred-at (odra-agent-audit-event-occurred-at event))
    (cons 'visibility (odra-agent-audit-event-visibility event))
    (cons 'redaction (odra-agent-audit-event-redaction-class event))
    (cons 'effect (odra-agent-audit-event-effect-class event)))))

(define (reconciliation-projection marker)
  (projection
   'reconciliation
   (odra-agent-reconciliation-marker-identity marker)
   (odra-agent-reconciliation-marker-generation marker)
   (format "Reconcile ~a"
           (odra-agent-reconciliation-marker-subject-kind marker))
   (odra-agent-reconciliation-marker-state marker)
   (format "~a requires a fresh bounded observation."
           (odra-agent-reconciliation-marker-subject-identity marker))
   #:attention? #t
   #:details
   (list
    (cons 'prior-generation
          (odra-agent-reconciliation-marker-prior-generation marker))
    (cons 'prior-state
          (odra-agent-reconciliation-marker-prior-state marker))
    (cons 'updated-at
          (odra-agent-reconciliation-marker-updated-at marker)))))

(define (all-records store authority-store catalog driver-registry at)
  (define drivers (inspect-agent-drivers driver-registry))
  (define tasks (inspect-agent-tasks store))
  (define requests (inspect-agent-capability-requests store))
  (append
   (map (lambda (definition) (agent-projection definition drivers))
        (odra-agent-catalog-agents catalog))
   (map capability-projection (odra-agent-catalog-capabilities catalog))
   (map driver-projection drivers)
   (map grant-projection (inspect-agent-grants authority-store #:at at))
   (map task-projection tasks)
   (append-map
    (lambda (task)
      (map interaction-projection
           (inspect-agent-task-interactions
            store (odra-agent-task-identity task))))
    tasks)
   (append-map
    (lambda (task)
      (map session-projection
           (inspect-agent-task-driver-sessions
            store (odra-agent-task-identity task))))
    tasks)
   (append-map
    (lambda (task)
      (map turn-projection
           (inspect-agent-task-turns store (odra-agent-task-identity task))))
    tasks)
   (append-map
    (lambda (request)
      (define decision
        (inspect-agent-admission-decision
         store (odra-agent-capability-request-identity request)))
      (append
       (list (request-projection request decision))
       (if decision (list (decision-projection decision)) '())
       (map attempt-projection
            (inspect-agent-request-attempts
             store (odra-agent-capability-request-identity request)))
       (map result-projection
            (inspect-agent-request-results
             store (odra-agent-capability-request-identity request)))))
    requests)
   (map audit-projection
        (inspect-agent-audit-events store #:limit 1024))
   (map reconciliation-projection
        (inspect-agent-reconciliation-markers store))))

(define (projection<? left right)
  (define left-kind
    (symbol->string (odra-agent-inspection-projection-kind left)))
  (define right-kind
    (symbol->string (odra-agent-inspection-projection-kind right)))
  (or (string<? left-kind right-kind)
      (and
       (string=? left-kind right-kind)
       (let ([left-label (odra-agent-inspection-projection-label left)]
             [right-label (odra-agent-inspection-projection-label right)])
         (or (string<? left-label right-label)
             (and
              (string=? left-label right-label)
              (string<?
               (odra-agent-inspection-projection-identity left)
               (odra-agent-inspection-projection-identity right))))))))

(define (validated-limit who limit)
  (unless (<= limit maximum-agent-inspection-records)
    (raise-arguments-error
     who "inspection limit exceeds 1024" "limit" limit))
  limit)

(define (inspect-agent-substrate-records
         store authority-store catalog driver-registry
         #:at [at 0] #:limit [limit 256])
  (bounded-list
   (sort (all-records store authority-store catalog driver-registry at)
         projection<?)
   (validated-limit 'inspect-agent-substrate-records limit)))

(define (inspect-agent-substrate-kind
         store authority-store catalog driver-registry kind
         #:at [at 0] #:limit [limit 256])
  (bounded-list
   (filter
    (lambda (record)
      (eq? kind (odra-agent-inspection-projection-kind record)))
    (sort (all-records store authority-store catalog driver-registry at)
          projection<?))
   (validated-limit 'inspect-agent-substrate-kind limit)))

(define (inspect-agent-substrate-detail
         store authority-store catalog driver-registry kind identity
         #:at [at 0])
  (for/first
      ([record
        (in-list
         (all-records store authority-store catalog driver-registry at))]
       #:when
       (and (eq? kind (odra-agent-inspection-projection-kind record))
            (string=? identity
                      (odra-agent-inspection-projection-identity record))))
    record))
