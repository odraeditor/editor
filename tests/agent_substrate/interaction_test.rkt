#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         racket/file
         racket/list
         racket/string
         "../../src/agent/admission.rkt"
         "../../src/agent/audit.rkt"
         "../../src/agent/authority.rkt"
         "../../src/agent/continuity.rkt"
         "../../src/agent/controls.rkt"
         "../../src/agent/definition.rkt"
         "../../src/agent/driver.rkt"
         "../../src/agent/inspection.rkt"
         "../../src/agent/presentation.rkt"
         "../../src/agent/registry.rkt")

(define (with-test-store procedure)
  (define root
    (make-temporary-file "odra-agent-interaction-test~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define store (open-agent-continuity-store root))
      (dynamic-wind
        void
        (lambda () (procedure root store))
        (lambda () (close-agent-continuity-store! store))))
    (lambda () (delete-directory/files root))))

(define (test-catalog generation)
  (compose-agent-catalog
   generation
   (list
    (make-agent-contribution-source
     "example.integration" "1.0.0" generation
     (list
      (make-agent
       'example.agent
       #:display-name "Example Agent"
       #:description "Handles bounded example work."
       #:requested-capabilities '(example.observe)))
     (list
      (make-agent-capability
       'example.observe 'example.text (lambda (_context) (void))
       #:purpose "Observe one bounded example target."
       #:input-schema
       '(record (target required (owner-reference example.text.region 1)))
       #:result-schema '(record (accepted required boolean))
       #:target-kinds '(example.text.region)
       #:effects '(observe)))))))

(define (target)
  (make-agent-owner-reference
   'example.text 'example.text.region 1 "note-1" #:generation 1))

(define (target-registry)
  (define registry (make-agent-target-registry))
  (register-agent-target-kind!
   registry
   (make-agent-target-kind-definition
    'example.text 'example.text.region 1
    (lambda (_reference) 'valid)
    (lambda (_reference _scope) 'valid)))
  registry)

(define (authority-policy)
  (make-agent-authority-policy
   #:effects '(observe)
   #:maximum-validity-milliseconds 100000
   #:source "Local interaction test policy."))

(define (grant-request identity)
  (make-agent-grant-request
   identity 'example.agent 7 "example.observe" 7
   (make-agent-target-scope
    'example.text 'example.text.region "note-1")
   (make-agent-authority-origin 'local-user 'local.actor)
   1 #:effects '(observe) #:task-restriction 'task.local
   #:valid-until 100000))

(define (empty-driver-registry)
  (make-agent-driver-registry))

(define (start-task! store authority-store catalog drivers)
  (define candidate
    (car
     (agent-control-candidates
      store authority-store catalog drivers 'agent-task-start)))
  (start-local-agent-task!
   store catalog candidate 'task.local "Explain the current note."
   'local.actor 2 #:context-references (list (target))))

(define (record-request! store grant)
  (record-agent-capability-request!
   store
   (make-agent-capability-request
    'request.local 'task.local 1 'example.agent 7
    (make-agent-record-reference 'agent-registration 'example.agent 7)
    'example.observe 7
    (make-agent-package-reference 'example.integration "1.0.0" 7)
    (make-agent-schema-reference 'example.observe 7 'input 1)
    (list (list 'target (target))) '(observe)
    default-agent-capability-limits
    (list
     (make-agent-record-reference
      'capability-grant
      (odra-agent-capability-grant-identity grant)
      (odra-agent-capability-grant-generation grant)))
    3 100000 #:target-references (list (target)))))

(test-case "inspection and candidates are human-readable bounded and redacted"
  (with-test-store
   (lambda (_root store)
     (define catalog (test-catalog 7))
     (define authority-store (make-agent-authority-store))
     (define drivers (empty-driver-registry))
     (start-task! store authority-store catalog drivers)
     (record-agent-interaction!
      store 'interaction.hidden 'task.local 'example.agent 'local.actor
      'progress "secret-token" 'owner
      (make-agent-interaction-provenance 'agent 'example.agent) 3
      #:acting-agent 'example.agent)
     (record-agent-audit-event!
      store 'audit.hidden 'test-event 'local.actor
      '(token "secret-token") 4 #:redaction-class 'identity-only)
     (define records
       (inspect-agent-substrate-records
        store authority-store catalog drivers #:at 4))
     (check-not-false
      (member 'agent (map odra-agent-inspection-projection-kind records)))
     (check-not-false
      (member 'task (map odra-agent-inspection-projection-kind records)))
     (define audit
       (inspect-agent-substrate-detail
        store authority-store catalog drivers 'audit "audit.hidden" #:at 4))
     (check-false (regexp-match? #px"secret-token" (format "~s" audit)))
     (define task-surface (present-agent-task store 'task.local #:width 24))
     (check-false
      (regexp-match? #px"secret-token" (format "~s" task-surface)))
     (define candidates
       (agent-control-candidates
        store authority-store catalog drivers 'agent-list #:query "example"))
     (check-equal? (length candidates) 1)
     (define surface
       (present-agent-candidates 'agent-list candidates #:width 24))
     (check-true
      (for/and ([row (in-list (odra-agent-local-surface-rows surface))])
        (<= (string-length (odra-agent-surface-row-content row)) 24)))
     (check-equal?
      (odra-agent-local-surface-status
       (present-agent-candidates 'agent-revoke '()))
      'empty))))

(test-case "direct task entry records user text as inert interaction data"
  (with-test-store
   (lambda (root store)
     (define catalog (test-catalog 7))
     (define authority-store (make-agent-authority-store))
     (define drivers (empty-driver-registry))
     (define task (start-task! store authority-store catalog drivers))
     (check-true (odra-agent-task? task))
     (define candidate
       (car
        (agent-control-candidates
         store authority-store catalog drivers 'agent-send)))
     (define text "(error 'must-not-run \"text is data\")")
     (define interaction
       (send-local-agent-interaction!
        store candidate 'interaction.local text 'local.actor 3))
     (check-equal? (odra-agent-interaction-payload interaction) text)
     (define stale-catalog (test-catalog 8))
     (define agent-candidate
       (car
        (agent-control-candidates
         store authority-store catalog drivers 'agent-task-start)))
     (check-equal?
      (odra-agent-control-denial-code
       (start-local-agent-task!
        store stale-catalog agent-candidate 'task.stale "Stale task."
        'local.actor 4))
      'stale-selection)
     (close-agent-continuity-store! store)
     (define reopened (open-agent-continuity-store root))
     (define surface (present-agent-task reopened 'task.local #:width 40))
     (check-equal? (length (odra-agent-local-surface-rows surface)) 1)
     (check-equal? (odra-agent-local-surface-kind surface) 'task)
     (close-agent-continuity-store! reopened))))

(test-case "grant decision revocation and cancellation use canonical operations"
  (with-test-store
   (lambda (_root store)
     (define catalog (test-catalog 7))
     (define authority-store (make-agent-authority-store))
     (define drivers (empty-driver-registry))
     (start-task! store authority-store catalog drivers)
     (define capability-candidate
       (car
        (agent-control-candidates
         store authority-store catalog drivers 'agent-grant)))
     (define granted
       (control-grant-agent-capability!
        authority-store catalog capability-candidate
        (grant-request 'grant.local) (authority-policy) 2))
     (check-equal? (odra-agent-control-outcome-state granted) 'granted)
     (define grant (odra-agent-control-outcome-value granted))
     (record-request! store grant)
     (define request-candidate
       (car
        (agent-control-candidates
         store authority-store catalog drivers 'agent-request-decide
         #:at 4)))
     (define admission-policy
       (make-agent-admission-policy
        'policy.local 1
        #:admitted-effects '(observe)
        #:human-decision-effects '(observe)
        #:human-actors '(local.actor)
        #:maximum-request-validity-milliseconds 100000
        #:source "Local request decision policy."))
     (define decided
       (control-decide-agent-request!
        store authority-store catalog (target-registry) drivers
        request-candidate 'human.local 'decision.local 'local.actor
        'approve-once admission-policy 4 100000))
     (check-equal? (odra-agent-control-outcome-state decided) 'admitted)
     (check-equal?
      (odra-agent-human-decision-consumed-by
       (inspect-agent-human-decision store 'request.local))
      "decision.local")
     (define revoke-candidate
       (car
        (agent-control-candidates
         store authority-store catalog drivers 'agent-revoke #:at 5)))
     (define revoked
       (control-revoke-agent-grant!
        authority-store revoke-candidate "No longer needed." 5))
     (check-equal? (odra-agent-control-outcome-state revoked) 'revoked)
     (define cancel-candidate
       (car
        (agent-control-candidates
         store authority-store catalog drivers 'agent-cancel #:at 6)))
     (define cancelled
       (control-cancel-agent-work!
        store drivers cancel-candidate 'local.actor "Stop local work." 6))
     (check-equal? (odra-agent-control-outcome-state cancelled) 'cancelled)
     (check-equal?
      (odra-agent-task-state (inspect-agent-task store 'task.local))
      'cancelled)
     (check-equal?
      (odra-agent-control-denial-code
       (control-cancel-agent-work!
        store drivers cancel-candidate 'local.actor "Repeat." 7))
      'stale-selection))))

(test-case "large agent lists remain filtered and bounded"
  (with-test-store
   (lambda (_root store)
     (define agents
       (for/list ([index (in-range 64)])
         (make-agent
          (string->symbol (format "example.agent-~a" index))
          #:display-name (format "Agent ~a" index))))
     (define catalog
       (compose-agent-catalog
        1
        (list
         (make-agent-contribution-source
          "example.many" "1.0.0" 1 agents '()))))
     (define candidates
       (agent-control-candidates
        store (make-agent-authority-store) catalog (empty-driver-registry)
        'agent-list #:query "Agent 5" #:limit 16))
     (check-true (<= (length candidates) 16))
     (check-true
      (andmap
       (lambda (candidate)
         (string-contains?
          (string-downcase (odra-agent-control-candidate-label candidate))
          "agent 5"))
       candidates)))))
