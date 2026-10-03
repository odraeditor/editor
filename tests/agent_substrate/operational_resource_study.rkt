#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         "../../src/agent/admission.rkt"
         "../../src/agent/audit.rkt"
         "../../src/agent/authority.rkt"
         "../../src/agent/continuity.rkt"
         "../../src/agent/definition.rkt"
         "../../src/agent/driver.rkt"
         "../../src/agent/execution.rkt"
         "../../src/agent/inspection.rkt"
         "../../src/agent/registry.rkt")

(define maximum-study-memory-bytes (* 256 1024 1024))
(define maximum-study-elapsed-milliseconds 60000)
(define study-valid-until maximum-agent-request-validity-milliseconds)

(define (identity prefix index)
  (string->symbol (format "~a.~a" prefix index)))

(define (study-catalog)
  (compose-agent-catalog
   1
   (list
    (make-agent-contribution-source
     "odra.resource-study" "1.0.0" 1
     (list
      (make-agent
       'odra.resource-study.agent
       #:interaction-kinds '(progress result)
       #:provider-requirements '(odra.agent-driver)
       #:requested-capabilities '(odra.resource-study.observe)))
     (list
      (make-agent-capability
       'odra.resource-study.observe 'odra.resource-study
       (lambda (_context)
         (make-agent-capability-owner-result
          'succeeded
          #:result '((accepted #t))
          #:confirmed-effects '(observe)
          #:safe-summary "The resource-study operation completed."))
       #:input-schema
       '(record
         (target required (owner-reference odra.resource-study.target 1)))
       #:result-schema '(record (accepted required boolean))
       #:target-kinds '(odra.resource-study.target)
       #:effects '(observe)
       #:idempotency-class 'read-only))))))

(define (study-driver)
  (make-agent-driver
   'odra.resource-study.driver 1
   (lambda (_context)
     (odra-agent-driver-open-result 'provider.resource-study #f))
   (lambda (_context)
     (make-agent-turn-output
      (list
       (make-agent-turn-output-item 'progress '(status measured)))
      #:usage
      (make-agent-turn-usage
       #:provider-events 1 #:input-bytes 64 #:output-bytes 4096)))
   (lambda (_turn) (void))
   (lambda (_session) (void))))

(define (study-target-registry)
  (define registry (make-agent-target-registry))
  (register-agent-target-kind!
   registry
   (make-agent-target-kind-definition
    'odra.resource-study 'odra.resource-study.target 1
    (lambda (_reference) 'valid)
    (lambda (reference scope)
      (if (equal? (odra-agent-owner-reference-identity reference)
                  (odra-agent-target-scope-selector scope))
          'valid
          'outside-scope))
    #:source "Agent substrate operational resource study."))
  registry)

(define authority-policy
  (make-agent-authority-policy
   #:effects '(observe)
   #:maximum-validity-milliseconds study-valid-until
   #:source "Agent substrate operational resource study."))

(define admission-policy
  (make-agent-admission-policy
   'odra.resource-study.policy 1
   #:admitted-effects '(observe)
   #:maximum-request-validity-milliseconds study-valid-until
   #:source "Agent substrate operational resource study."))

(define (ensure who predicate message . arguments)
  (unless predicate
    (apply error who message arguments)))

(define (populate! store authority catalog drivers targets count)
  (for ([index (in-range count)])
    (define task-id (identity "task.resource-study" index))
    (define grant-id (identity "grant.resource-study" index))
    (define session-id (identity "session.resource-study" index))
    (define turn-id (identity "turn.resource-study" index))
    (define request-id (identity "request.resource-study" index))
    (define decision-id (identity "decision.resource-study" index))
    (define attempt-id (identity "attempt.resource-study" index))
    (define lease-id (identity "lease.resource-study" index))
    (define result-id (identity "result.resource-study" index))
    (define audit-id (identity "audit.resource-study" index))
    (define target-id (format "target.resource-study.~a" index))
    (define now (* 100 index))

    (define task
      (create-agent-task!
       store task-id "Measure one bounded substrate operation."
       (make-agent-task-origin 'local-user 'resource.study) now
       #:owner-agent 'odra.resource-study.agent))
    (ensure 'operational-resource-study (odra-agent-task? task)
            "task creation failed at ~a: ~s" index task)

    (define grant
      (grant-agent-capability!
       authority catalog
       (make-agent-grant-request
        grant-id 'odra.resource-study.agent 1
        "odra.resource-study.observe" 1
        (make-agent-target-scope
         'odra.resource-study 'odra.resource-study.target target-id)
        (make-agent-authority-origin 'local-user 'resource.study)
        now
        #:effects '(observe)
        #:task-restriction task-id
        #:valid-until study-valid-until)
       authority-policy now))
    (ensure 'operational-resource-study
            (odra-agent-capability-grant? grant)
            "grant creation failed at ~a: ~s" index grant)

    (define session
      (open-agent-driver-session!
       store drivers catalog session-id
       (make-agent-record-reference
        'agent-registration 'odra.resource-study.agent 1)
       task-id 1 'odra.resource-study.agent
       'odra.resource-study.driver (add1 now)))
    (ensure 'operational-resource-study
            (odra-agent-driver-session? session)
            "driver session creation failed at ~a: ~s" index session)

    (define prepared-turn
      (prepare-agent-turn!
       store drivers authority catalog turn-id session-id 2 1 (+ now 2)))
    (ensure 'operational-resource-study (odra-agent-turn? prepared-turn)
            "turn preparation failed at ~a: ~s" index prepared-turn)
    (define turn-invocation
      (invoke-agent-turn!
       store drivers authority catalog turn-id 1 (+ now 3)))
    (ensure 'operational-resource-study
            (odra-agent-turn-invocation? turn-invocation)
            "turn invocation failed at ~a: ~s" index turn-invocation)
    (define turn
      (finalize-agent-turn!
       store catalog turn-invocation 'resource.study (+ now 4)))
    (ensure 'operational-resource-study
            (and (odra-agent-turn? turn)
                 (eq? (odra-agent-turn-state turn) 'completed))
            "turn completion failed at ~a: ~s" index turn)

    (define target
      (make-agent-owner-reference
       'odra.resource-study 'odra.resource-study.target 1 target-id
       #:generation 1))
    (define request
      (make-agent-capability-request
       request-id task-id 1 'odra.resource-study.agent 1
       (make-agent-record-reference
        'agent-registration 'odra.resource-study.agent 1)
       'odra.resource-study.observe 1
       (make-agent-package-reference 'odra.resource-study "1.0.0" 1)
       (make-agent-schema-reference
        'odra.resource-study.observe 1 'input 1)
       (list (list 'target target)) '(observe)
       default-agent-capability-limits
       (list
        (make-agent-record-reference
         'capability-grant
         (odra-agent-capability-grant-identity grant)
         (odra-agent-capability-grant-generation grant)))
       (+ now 5) study-valid-until
       #:target-references (list target)
       #:correlation-id turn-id
       #:idempotency-id attempt-id))
    (ensure 'operational-resource-study
            (odra-agent-capability-request?
             (record-agent-capability-request! store request))
            "request publication failed at ~a" index)

    (define decision
      (decide-agent-capability-request!
       store authority catalog targets request-id decision-id
       admission-policy (+ now 6)))
    (ensure 'operational-resource-study
            (and (odra-agent-admission-decision? decision)
                 (eq? (odra-agent-admission-decision-state decision)
                      'admitted))
            "request admission failed at ~a: ~s" index decision)

    (define attempt
      (prepare-agent-capability-attempt!
       store attempt-id request-id decision-id lease-id (+ now 7)))
    (ensure 'operational-resource-study
            (odra-agent-operation-attempt? attempt)
            "attempt preparation failed at ~a: ~s" index attempt)
    (define invocation
      (invoke-agent-capability-owner!
       store catalog attempt-id 1 (+ now 8)))
    (ensure 'operational-resource-study
            (odra-agent-capability-invocation? invocation)
            "capability invocation failed at ~a: ~s" index invocation)
    (define result
      (finalize-agent-capability-attempt!
       store catalog invocation result-id (+ now 9)))
    (ensure 'operational-resource-study
            (and (odra-agent-operation-result? result)
                 (eq? (odra-agent-operation-result-state result) 'succeeded))
            "result publication failed at ~a: ~s" index result)

    (define audit
      (record-agent-audit-event!
       store audit-id 'capability-result 'resource.study
       '(status succeeded) (+ now 10)
       #:task-id task-id
       #:effect-class 'observe
       #:subject-references
       (list
        (make-agent-record-reference 'capability-request request-id 1))))
    (ensure 'operational-resource-study
            (odra-agent-audit-event? audit)
            "audit publication failed at ~a: ~s" index audit)))

(define (run-profile label count)
  (define root
    (make-temporary-file "odra-agent-operational-resource-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (collect-garbage)
      (collect-garbage)
      (define baseline-memory (current-memory-use))
      (define started (current-inexact-milliseconds))
      (define store (open-agent-continuity-store root))
      (define authority (make-agent-authority-store))
      (define catalog (study-catalog))
      (define drivers (make-agent-driver-registry))
      (define targets (study-target-registry))
      (register-agent-driver! drivers (study-driver))
      (populate! store authority catalog drivers targets count)

      (define projections
        (inspect-agent-substrate-records
         store authority catalog drivers
         #:at study-valid-until #:limit maximum-agent-inspection-records))
      (define elapsed
        (- (current-inexact-milliseconds) started))
      (define memory
        (max 0 (- (current-memory-use) baseline-memory)))
      (define database-bytes
        (file-size (build-path root agent-continuity-database-name)))
      (define last-request (identity "request.resource-study" (sub1 count)))
      (define last-result (identity "result.resource-study" (sub1 count)))
      (ensure 'operational-resource-study
              (= (length (inspect-agent-tasks store)) count)
              "task count mismatch for ~a" label)
      (ensure 'operational-resource-study
              (= (length (inspect-agent-capability-requests store)) count)
              "request count mismatch for ~a" label)
      (ensure 'operational-resource-study
              (= (length (inspect-agent-request-results store last-request)) 1)
              "result count mismatch for ~a" label)
      (ensure 'operational-resource-study
              (odra-agent-operation-result?
               (inspect-agent-operation-result store last-result))
              "last result is unavailable for ~a" label)
      (ensure 'operational-resource-study
              (= (length (inspect-agent-audit-events store #:limit count))
                 count)
              "audit count mismatch for ~a" label)
      (ensure 'operational-resource-study
              (if (= count maximum-nonterminal-agent-tasks)
                  (= (length projections) maximum-agent-inspection-records)
                  (<= 1 (length projections)
                      maximum-agent-inspection-records))
              "inspection projection bound failed for ~a: ~a"
              label (length projections))
      (ensure 'operational-resource-study
              (<= memory maximum-study-memory-bytes)
              "memory bound exceeded for ~a: ~a" label memory)
      (ensure 'operational-resource-study
              (<= elapsed maximum-study-elapsed-milliseconds)
              "elapsed-time bound exceeded for ~a: ~a" label elapsed)

      (close-agent-continuity-store! store)
      (define reopened (open-agent-continuity-store root))
      (ensure 'operational-resource-study
              (= (length (inspect-agent-tasks reopened)) count)
              "reloaded task count mismatch for ~a" label)
      (ensure 'operational-resource-study
              (= (length (inspect-agent-capability-requests reopened)) count)
              "reloaded request count mismatch for ~a" label)
      (ensure 'operational-resource-study
              (odra-agent-operation-result?
               (inspect-agent-operation-result reopened last-result))
              "reloaded result is unavailable for ~a" label)
      (ensure 'operational-resource-study
              (= (length (inspect-agent-audit-events reopened #:limit count))
                 count)
              "reloaded audit count mismatch for ~a" label)
      (close-agent-continuity-store! reopened)

      (printf
       (string-append
        "study=agent-substrate-operational profile=~a agents=1 "
        "capabilities=1 drivers=1 tasks=~a grants=~a sessions=~a turns=~a "
        "requests=~a attempts=~a results=~a audit_events=~a "
        "inspection_records=~a elapsed_ms=~a memory_bytes=~a "
        "database_bytes=~a reload=valid\n")
       label count count count count count count count count
       (length projections) (inexact->exact (round elapsed)) memory
       database-bytes))
    (lambda () (delete-directory/files root))))

(run-profile 'ordinary 1)
(run-profile 'demanding 32)
(run-profile 'stress maximum-nonterminal-agent-tasks)
