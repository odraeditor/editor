#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require db
         rackunit
         racket/file
         "../../src/agent/admission.rkt"
         "../../src/agent/audit.rkt"
         "../../src/agent/authority.rkt"
         "../../src/agent/continuity.rkt"
         "../../src/agent/definition.rkt"
         "../../src/agent/driver.rkt"
         "../../src/agent/execution.rkt"
         "../../src/agent/lifecycle.rkt"
         "../../src/agent/recovery.rkt"
         "../../src/agent/registry.rkt")

(define (with-test-store procedure #:observer [observer void])
  (define root
    (make-temporary-file "odra-agent-recovery-test~a" 'directory))
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

(define (test-catalog generation #:effects [effects '(observe)])
  (compose-agent-catalog
   generation
   (list
    (make-agent-contribution-source
     "example.integration" "1.0.0" generation
     (list
      (make-agent
       'example.agent
       #:provider-requirements '(odra.agent-driver)
       #:requested-capabilities '(example.observe)))
     (list
      (make-agent-capability
       'example.observe 'example.text
       (lambda (_context)
         (make-agent-capability-owner-result
          'succeeded #:result '((accepted #t))
          #:confirmed-effects effects))
       #:input-schema
       '(record (target required (owner-reference example.text.region 1)))
       #:result-schema '(record (accepted required boolean))
       #:target-kinds '(example.text.region)
       #:effects effects
       #:idempotency-class 'read-only))))))

(define (test-grant! store catalog #:effects [effects '(observe)])
  (grant-agent-capability!
   store catalog
   (make-agent-grant-request
    'grant.observe 'example.agent 7 "example.observe" 7
    (make-agent-target-scope
     'example.text 'example.text.region "note-1")
    (make-agent-authority-origin 'local-user 'local.actor)
    1 #:effects effects #:task-restriction 'task.recovery
    #:valid-until 100000)
   (make-agent-authority-policy
    #:effects effects
    #:maximum-validity-milliseconds 100000
    #:source "Recovery test policy.")
   1))

(define (test-target)
  (make-agent-owner-reference
   'example.text 'example.text.region 1 "note-1" #:generation 3))

(define (test-target-registry)
  (define registry (make-agent-target-registry))
  (register-agent-target-kind!
   registry
   (make-agent-target-kind-definition
    'example.text 'example.text.region 1
    (lambda (_reference) 'valid)
    (lambda (_reference _scope) 'valid)))
  registry)

(define (prepare-live-state! store authority-store catalog
                             #:effects [effects '(observe)])
  (create-agent-task!
   store 'task.recovery "Recover interrupted substrate work."
   (make-agent-task-origin 'local-user 'local.actor) 1
   #:owner-agent 'example.agent
   #:owner-references (list (test-target)))
  (define driver-registry (make-agent-driver-registry))
  (register-agent-driver!
   driver-registry
   (make-agent-driver
    'example.driver 1
    (lambda (_context)
      (odra-agent-driver-open-result 'provider.session #f))
    (lambda (_context) (make-agent-turn-output '()))
    void void))
  (open-agent-driver-session!
   store driver-registry catalog 'session.recovery
   (make-agent-record-reference
    'agent-registration 'registration.recovery 1)
   'task.recovery 1 'example.agent 'example.driver 2)
  (prepare-agent-turn!
   store driver-registry authority-store catalog
   'turn.recovery 'session.recovery 2 1 3)
  (define grant (car (inspect-agent-grants authority-store #:at 4)))
  (define target (test-target))
  (record-agent-capability-request!
   store
   (make-agent-capability-request
    'request.recovery 'task.recovery 1 'example.agent 7
    (make-agent-record-reference
     'agent-registration 'example.agent 7)
    'example.observe 7
    (make-agent-package-reference 'example.integration "1.0.0" 7)
    (make-agent-schema-reference 'example.observe 7 'input 1)
    (list (list 'target target)) effects
    default-agent-capability-limits
    (list
     (make-agent-record-reference
      'capability-grant
      (odra-agent-grant-projection-identity grant)
      (odra-agent-grant-projection-generation grant)))
    4 100000 #:target-references (list target)))
  (decide-agent-capability-request!
   store authority-store catalog (test-target-registry)
   'request.recovery 'decision.recovery
   (make-agent-admission-policy
    'policy.recovery 1
    #:admitted-effects effects
    #:maximum-request-validity-milliseconds 100000
    #:source "Recovery test admission policy.")
   5)
  (prepare-agent-capability-attempt!
   store 'attempt.recovery 'request.recovery 'decision.recovery
   'lease.recovery 6))

(test-case "audit is ordered bounded redacted and transactionally appended"
  (with-test-store
   (lambda (_root store)
     (define first
       (record-agent-audit-event!
        store 'audit.first 'request-admitted 'local.actor '(status admitted) 1
        #:visibility 'administrator #:redaction-class 'identity-only))
     (define second
       (record-agent-audit-event!
        store 'audit.second 'attempt-started 'local.actor '(status running) 2))
     (check-equal? (map odra-agent-audit-event-sequence
                        (inspect-agent-audit-events store))
                   (list (odra-agent-audit-event-sequence first)
                         (odra-agent-audit-event-sequence second)))
     (check-equal?
      (odra-agent-audit-event-redaction-class
       (inspect-agent-audit-event store 'audit.first))
      'identity-only)
     (check-equal?
      (odra-agent-audit-denial-code
       (record-agent-audit-event!
        store 'audit.first 'request-admitted 'local.actor 'duplicate 3))
      'duplicate-audit-event)))
  (with-test-store
   (lambda (_root store)
     (check-exn
      exn:fail?
      (lambda ()
        (record-agent-audit-event!
         store 'audit.rollback 'request-admitted 'local.actor 'rollback 1)))
     (check-false (inspect-agent-audit-event store 'audit.rollback)))
   #:observer
   (lambda (kind _result)
     (when (eq? kind 'record-audit-event)
       (error 'test "interrupt audit publication")))))

(test-case "startup reconciliation never replays live durable work"
  (with-test-store
   (lambda (root store)
     (define catalog (test-catalog 7))
     (define authority-store (make-agent-authority-store))
     (test-grant! authority-store catalog)
     (prepare-live-state! store authority-store catalog)
     (define summary (reconcile-agent-substrate! store 20))
     (check-equal?
      (list (odra-agent-recovery-summary-driver-sessions summary)
            (odra-agent-recovery-summary-turns summary)
            (odra-agent-recovery-summary-operation-attempts summary))
      '(1 1 1))
     (check-equal?
      (odra-agent-driver-session-state
       (inspect-agent-driver-session store 'session.recovery))
      'reconciling)
     (check-equal?
      (odra-agent-turn-state (inspect-agent-turn store 'turn.recovery))
      'reconciling)
     (check-equal?
      (odra-agent-operation-attempt-state
       (inspect-agent-operation-attempt store 'attempt.recovery))
      'reconciling)
     (check-equal? (length (inspect-agent-reconciliation-markers store)) 3)
     (check-equal? (length (inspect-agent-audit-events store)) 3)
     (check-equal?
      (odra-agent-recovery-summary-driver-sessions
       (reconcile-agent-substrate! store 21))
      0)
     (close-agent-continuity-store! store)
     (define reopened (open-agent-continuity-store root))
     (check-equal?
      (odra-agent-operation-attempt-state
       (inspect-agent-operation-attempt reopened 'attempt.recovery))
      'reconciling)
     (close-agent-continuity-store! reopened))))

(test-case "package retirement preserves explanatory history"
  (with-test-store
   (lambda (root store)
     (define catalog (test-catalog 7))
     (define authority-store (make-agent-authority-store))
     (test-grant! authority-store catalog)
     (prepare-live-state! store authority-store catalog)
     (define owner-state (build-path root "canonical-owner-state"))
     (call-with-output-file owner-state
       (lambda (output) (display "owner-controlled" output)))
     (define summary
       (reconcile-agent-package-lifecycle!
        store authority-store catalog (empty-agent-catalog) 30))
     (check-equal? (odra-agent-lifecycle-summary-tombstones summary) 2)
     (check-equal? (odra-agent-lifecycle-summary-grants summary) 1)
     (check-equal? (odra-agent-lifecycle-summary-sessions summary) 1)
     (check-equal? (odra-agent-lifecycle-summary-turns summary) 1)
     (check-equal? (odra-agent-lifecycle-summary-attempts summary) 1)
     (check-true (odra-agent-lifecycle-summary-indexes-rebuilt? summary))
     (define tombstones (inspect-agent-definition-tombstones store))
     (check-equal? (length tombstones) 2)
     (check-false (regexp-match? #px"handler|provider.session|owner-controlled"
                                 (format "~s" tombstones)))
     (check-equal?
      (odra-agent-owner-reference-identity
       (car
        (odra-agent-capability-request-target-references
         (inspect-agent-capability-request store 'request.recovery))))
      "note-1")
     (check-equal? (file->string owner-state) "owner-controlled")
     (define preserved
       (preserve-agent-substrate-history! store catalog 40))
     (check-equal? (odra-agent-history-preservation-tasks preserved) 1)
     (check-equal? (odra-agent-history-preservation-requests preserved) 1)
     (check-equal? (odra-agent-history-preservation-tombstones preserved) 2)
     (check-equal?
      (cleanup-agent-reconciliation-history! store 31 41)
      0))))

(test-case "missing SQLite indexes are restored before lifecycle reconciliation"
  (define root
    (make-temporary-file "odra-agent-index-recovery-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define store (open-agent-continuity-store root))
      (create-agent-task!
       store 'task.index-recovery "Restore a missing durable index."
       (make-agent-task-origin 'local-user 'local.actor) 1)
      (close-agent-continuity-store! store)
      (define database-path
        (build-path root agent-continuity-database-name))
      (define connection
        (sqlite3-connect #:database database-path #:mode 'create))
      (query-exec connection "DROP INDEX agent_interactions_task_idx")
      (check-equal?
       (query-value
        connection
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'agent_interactions_task_idx'")
       0)
      (disconnect connection)

      (define reopened (open-agent-continuity-store root))
      (define verification
        (sqlite3-connect #:database database-path #:mode 'create))
      (check-equal?
       (query-value
        verification
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'agent_interactions_task_idx'")
       1)
      (disconnect verification)
      (define summary
        (reconcile-agent-package-lifecycle!
         reopened (make-agent-authority-store)
         (empty-agent-catalog) (empty-agent-catalog) 10))
      (check-true (odra-agent-lifecycle-summary-indexes-rebuilt? summary))
      (check-equal?
       (odra-agent-task-identity
        (inspect-agent-task reopened 'task.index-recovery))
       "task.index-recovery")
      (close-agent-continuity-store! reopened))
    (lambda () (delete-directory/files root))))

(test-case "interrupted consequential effects remain uncertain across restart"
  (define root
    (make-temporary-file "odra-agent-uncertain-recovery-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define effects '(mutate-editor-state))
      (define catalog (test-catalog 7 #:effects effects))
      (define authority-store (make-agent-authority-store))
      (define store (open-agent-continuity-store root))
      (test-grant! authority-store catalog #:effects effects)
      (prepare-live-state!
       store authority-store catalog #:effects effects)
      (define invocation
        (invoke-agent-capability-owner!
         store catalog 'attempt.recovery 1 7))
      (check-true (odra-agent-capability-invocation? invocation))
      (close-agent-continuity-store! store)

      (define reopened (open-agent-continuity-store root))
      (define summary (reconcile-agent-substrate! reopened 20))
      (check-equal?
       (odra-agent-recovery-summary-operation-attempts summary)
       1)
      (define reconciling
        (inspect-agent-operation-attempt reopened 'attempt.recovery))
      (check-equal? (odra-agent-operation-attempt-state reconciling)
                    'reconciling)
      (check-not-false
       (odra-agent-operation-failure-outcome-uncertain?
        (odra-agent-operation-attempt-failure reconciling)))
      (define result
        (settle-agent-capability-attempt!
         reopened catalog 'attempt.recovery
         (odra-agent-operation-attempt-generation reconciling)
         'result.uncertain 21))
      (check-equal? (odra-agent-operation-result-state result)
                    'outcome-unknown)
      (close-agent-continuity-store! reopened)

      (define verified (open-agent-continuity-store root))
      (check-equal?
       (odra-agent-operation-result-state
        (inspect-agent-operation-result verified 'result.uncertain))
       'outcome-unknown)
      (close-agent-continuity-store! verified))
    (lambda () (delete-directory/files root))))
