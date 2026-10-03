#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         racket/file
         "../../src/agent/admission.rkt"
         "../../src/agent/authority.rkt"
         "../../src/agent/continuity.rkt"
         "../../src/agent/definition.rkt"
         "../../src/agent/execution.rkt"
         "../../src/agent/registry.rkt")

(define (with-test-store procedure #:observer [observer void])
  (define root
    (make-temporary-file "odra-agent-execution-test~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define store
        (open-agent-continuity-store root #:transaction-observer observer))
      (dynamic-wind
        void
        (lambda () (procedure root store))
        (lambda () (close-agent-continuity-store! store))))
    (lambda () (delete-directory/files root))))

(define (target)
  (make-agent-owner-reference
   'example.text 'example.text.region 1 "allowed" #:generation 1))

(define (make-execution-catalog output-box
                                #:effects [effects '(observe)]
                                #:authorities [authorities '()]
                                #:generation [generation 7])
  (compose-agent-catalog
   generation
   (list
    (make-agent-contribution-source
     "example.integration" "1.0.0" generation
     (list
      (make-agent
       'example.agent #:requested-capabilities '(example.execute)))
     (list
      (make-agent-capability
       'example.execute 'example.text
       (lambda (context)
         (define output (unbox output-box))
         (if (procedure? output) (output context) output))
       #:purpose "Execute one bounded example operation."
       #:input-schema
       '(record (target required (owner-reference example.text.region 1)))
       #:result-schema '(record (accepted required boolean))
       #:target-kinds '(example.text.region)
       #:effects effects
       #:required-authorities authorities
       #:idempotency-class 'read-only))
     #:authorities authorities))))

(define (make-target-registry)
  (define registry (make-agent-target-registry))
  (register-agent-target-kind!
   registry
   (make-agent-target-kind-definition
    'example.text 'example.text.region 1
    (lambda (_reference) 'valid)
    (lambda (reference scope)
      (if (equal? (odra-agent-owner-reference-identity reference)
                  (odra-agent-target-scope-selector scope))
          'valid
          'outside-scope))))
  registry)

(define (prepare-admitted-request!
         store output-box
         #:effects [effects '(observe)]
         #:authorities [authorities '()]
         #:catalog [provided-catalog #f])
  (define catalog
    (or provided-catalog
        (make-execution-catalog
         output-box #:effects effects #:authorities authorities)))
  (define authority-store (make-agent-authority-store))
  (define grant
    (grant-agent-capability!
     authority-store catalog
     (make-agent-grant-request
      'grant.execute 'example.agent 7 "example.execute" 7
      (make-agent-target-scope
       'example.text 'example.text.region "allowed")
      (make-agent-authority-origin 'local-user 'local.actor)
      1 #:effects effects #:valid-until 100000)
     (make-agent-authority-policy
      #:effects effects #:authorities authorities
      #:maximum-validity-milliseconds 100000
      #:source "Execution test authority policy.")
     1))
  (create-agent-task!
   store 'task.execution "Execute one admitted request."
   (make-agent-task-origin 'local-user 'local.actor) 1
   #:owner-agent 'example.agent)
  (define reference (target))
  (define request
    (make-agent-capability-request
     'request.execution 'task.execution 1 'example.agent 7
     (make-agent-record-reference
      'agent-registration 'example.agent 7)
     'example.execute 7
     (make-agent-package-reference 'example.integration "1.0.0" 7)
     (make-agent-schema-reference 'example.execute 7 'input 1)
     (list (list 'target reference)) effects
     default-agent-capability-limits
     (list
      (make-agent-record-reference
       'capability-grant
       (odra-agent-capability-grant-identity grant)
       (odra-agent-capability-grant-generation grant)))
     10 100000
     #:target-references (list reference)
     #:correlation-id 'correlation.execution))
  (record-agent-capability-request! store request)
  (define decision
    (decide-agent-capability-request!
     store authority-store catalog (make-target-registry)
     'request.execution 'decision.execution
     (make-agent-admission-policy
      'policy.execution 1
      #:admitted-effects effects
      #:maximum-request-validity-milliseconds 100000
      #:source "Execution test admission policy.")
     20))
  (unless (and (odra-agent-admission-decision? decision)
               (eq? (odra-agent-admission-decision-state decision) 'admitted))
    (error 'prepare-admitted-request! "request was not admitted: ~s" decision))
  catalog)

(define (prepare-attempt! store)
  (prepare-agent-capability-attempt!
   store 'attempt.execution 'request.execution 'decision.execution
   'lease.execution 30))

(define (successful-owner-result)
  (make-agent-capability-owner-result
   'succeeded
   #:result '((accepted #t))
   #:owner-evidence (list (target))
   #:confirmed-effects '(observe)
   #:safe-summary "The owner confirmed the example result."))

(test-case "exact owner invocation publishes one checked result"
  (with-test-store
   (lambda (_root store)
     (define observed-context (box #f))
     (define output
       (box
        (lambda (context)
          (set-box! observed-context context)
          (successful-owner-result))))
     (define catalog (prepare-admitted-request! store output))
     (prepare-attempt! store)
     (define invocation
       (invoke-agent-capability-owner!
        store catalog 'attempt.execution 1 31))
     (check-equal?
      (odra-agent-capability-execution-context-capability-identity
       (unbox observed-context))
      "example.execute")
     (check-equal?
      (odra-agent-capability-execution-context-input
       (unbox observed-context))
      (odra-agent-capability-request-input
       (inspect-agent-capability-request store 'request.execution)))
     (define result
       (finalize-agent-capability-attempt!
        store catalog invocation 'result.execution 32))
     (check-equal? (odra-agent-operation-result-state result) 'succeeded)
     (check-equal? (odra-agent-operation-result-result result)
                   '((accepted #t)))
     (check-equal?
      (odra-agent-operation-attempt-state
       (inspect-agent-operation-attempt store 'attempt.execution))
      'completed)
     (check-equal? (length (inspect-agent-request-results
                            store 'request.execution))
                   1))))

(test-case "capability owners invoke exact host package operations"
  (with-test-store
   (lambda (_root store)
     (define observed-operation (box #f))
     (define observed-context (box #f))
     (define output
       (box
        (lambda (context)
          (invoke-agent-capability-operation! context 'example.operation))))
     (define catalog (prepare-admitted-request! store output))
     (prepare-attempt! store)
     (define invocation
       (invoke-agent-capability-owner!
        store catalog 'attempt.execution 1 31
        #:operation-invoker
        (lambda (identity context)
          (set-box! observed-operation identity)
          (set-box! observed-context context)
          (successful-owner-result))))
     (check-equal? (unbox observed-operation) "example.operation")
     (check-true
      (odra-agent-capability-execution-context? (unbox observed-context)))
     (define result
       (finalize-agent-capability-attempt!
        store catalog invocation 'result.execution 32))
     (check-equal? (odra-agent-operation-result-state result) 'succeeded))))

(test-case "stale owner generation fails closed"
  (with-test-store
   (lambda (_root store)
     (define output (box (successful-owner-result)))
     (prepare-admitted-request! store output)
     (prepare-attempt! store)
     (define stale-catalog
       (make-execution-catalog output #:generation 8))
     (check-equal?
      (odra-agent-execution-denial-code
       (invoke-agent-capability-owner!
        store stale-catalog 'attempt.execution 1 31))
      'owner-unavailable)
     (define result
       (settle-agent-capability-attempt!
        store stale-catalog 'attempt.execution 2 'result.execution 32))
     (check-equal? (odra-agent-operation-result-state result) 'failed))))

(test-case "expired lease settles without invoking the owner"
  (with-test-store
   (lambda (_root store)
     (define called? (box #f))
     (define output
       (box (lambda (_context)
              (set-box! called? #t)
              (successful-owner-result))))
     (define catalog (prepare-admitted-request! store output))
     (define attempt (prepare-attempt! store))
     (define expired-at
       (add1 (odra-agent-operation-attempt-lease-deadline attempt)))
     (check-equal?
      (odra-agent-execution-denial-code
       (invoke-agent-capability-owner!
        store catalog 'attempt.execution 1 expired-at))
      'attempt-timeout)
     (check-false (unbox called?))
     (define result
       (settle-agent-capability-attempt!
        store catalog 'attempt.execution 2 'result.execution expired-at))
     (check-equal? (odra-agent-operation-result-state result) 'timed-out))))

(test-case "cancellation invalidates the invocation and rejects late output"
  (with-test-store
   (lambda (_root store)
     (define cancellation-check (box #f))
     (define output
       (box
        (lambda (context)
          (set-box!
           cancellation-check
           (odra-agent-capability-execution-context-cancellation-requested?
            context))
          (successful-owner-result))))
     (define catalog (prepare-admitted-request! store output))
     (prepare-attempt! store)
     (define invocation
       (invoke-agent-capability-owner!
        store catalog 'attempt.execution 1 31))
     (define cancelling
       (request-agent-capability-cancellation!
        store 'attempt.execution 2 'local.actor "Stop the operation." 32))
     (check-true ((unbox cancellation-check)))
     (check-equal? (odra-agent-operation-attempt-state cancelling) 'cancelling)
     (check-equal?
      (odra-agent-execution-denial-code
       (finalize-agent-capability-attempt!
        store catalog invocation 'result.late 33))
      'stale-attempt)
     (define result
       (settle-agent-capability-attempt!
        store catalog 'attempt.execution 3 'result.execution 34))
     (check-equal? (odra-agent-operation-result-state result) 'cancelled))))

(test-case "malformed owner output cannot publish success"
  (with-test-store
   (lambda (_root store)
     (define output (box '((accepted #t))))
     (define catalog (prepare-admitted-request! store output))
     (prepare-attempt! store)
     (define invocation
       (invoke-agent-capability-owner!
        store catalog 'attempt.execution 1 31))
     (define result
       (finalize-agent-capability-attempt!
        store catalog invocation 'result.execution 32))
     (check-equal? (odra-agent-operation-result-state result) 'failed)
     (check-false (odra-agent-operation-result-result-schema-reference result)))))

(test-case "schema-invalid success becomes a failed checked result"
  (with-test-store
   (lambda (_root store)
     (define output
       (box
        (make-agent-capability-owner-result
         'succeeded #:result '((accepted "yes"))
         #:confirmed-effects '(observe))))
     (define catalog (prepare-admitted-request! store output))
     (prepare-attempt! store)
     (define invocation
       (invoke-agent-capability-owner!
        store catalog 'attempt.execution 1 31))
     (define result
       (finalize-agent-capability-attempt!
        store catalog invocation 'result.execution 32))
     (check-equal? (odra-agent-operation-result-state result) 'failed))))

(test-case "duplicate owner callback cannot revise a terminal result"
  (with-test-store
   (lambda (_root store)
     (define output (box (successful-owner-result)))
     (define catalog (prepare-admitted-request! store output))
     (prepare-attempt! store)
     (define invocation
       (invoke-agent-capability-owner!
        store catalog 'attempt.execution 1 31))
     (finalize-agent-capability-attempt!
      store catalog invocation 'result.execution 32)
     (check-equal?
      (odra-agent-execution-denial-code
       (finalize-agent-capability-attempt!
        store catalog invocation 'result.duplicate 33))
      'stale-attempt)
     (check-false (inspect-agent-operation-result store 'result.duplicate)))))

(test-case "late consequential callback reports outcome unknown"
  (with-test-store
   (lambda (_root store)
     (define output
       (box
        (make-agent-capability-owner-result
         'succeeded #:result '((accepted #t))
         #:confirmed-effects '(network-access))))
     (define catalog
       (prepare-admitted-request!
        store output
        #:effects '(network-access)
        #:authorities '(network-acquisition)))
     (define attempt (prepare-attempt! store))
     (define invocation
       (invoke-agent-capability-owner!
        store catalog 'attempt.execution 1 31))
     (define result
       (finalize-agent-capability-attempt!
        store catalog invocation 'result.execution
        (add1 (odra-agent-operation-attempt-lease-deadline attempt))))
     (check-equal?
      (odra-agent-operation-result-state result) 'outcome-unknown))))

(test-case "failed result publication rolls back result and attempt"
  (define fail-publication? (box #f))
  (with-test-store
   (lambda (_root store)
     (define output (box (successful-owner-result)))
     (define catalog (prepare-admitted-request! store output))
     (prepare-attempt! store)
     (define invocation
       (invoke-agent-capability-owner!
        store catalog 'attempt.execution 1 31))
     (set-box! fail-publication? #t)
     (check-exn
      #rx"injected result publication failure"
      (lambda ()
        (finalize-agent-capability-attempt!
         store catalog invocation 'result.execution 32)))
     (check-false (inspect-agent-operation-result store 'result.execution))
     (check-equal?
      (odra-agent-operation-attempt-state
       (inspect-agent-operation-attempt store 'attempt.execution))
      'running))
   #:observer
   (lambda (kind _result)
     (when (and (unbox fail-publication?)
                (eq? kind 'publish-capability-result))
       (error 'execution-test "injected result publication failure")))))

(test-case "attempt and result survive store restart"
  (with-test-store
   (lambda (root store)
     (define output (box (successful-owner-result)))
     (define catalog (prepare-admitted-request! store output))
     (prepare-attempt! store)
     (define invocation
       (invoke-agent-capability-owner!
        store catalog 'attempt.execution 1 31))
     (finalize-agent-capability-attempt!
      store catalog invocation 'result.execution 32)
     (close-agent-continuity-store! store)
     (define reopened (open-agent-continuity-store root))
     (check-equal?
      (odra-agent-operation-attempt-result-id
       (inspect-agent-operation-attempt reopened 'attempt.execution))
      "result.execution")
     (check-equal?
      (odra-agent-operation-result-state
       (inspect-agent-operation-result reopened 'result.execution))
      'succeeded)
     (close-agent-continuity-store! reopened))))
