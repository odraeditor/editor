#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         rackunit
         "../../src/agent/admission.rkt"
         "../../src/agent/audit.rkt"
         "../../src/agent/authority.rkt"
         "../../src/agent/continuity.rkt"
         "../../src/agent/definition.rkt"
         "../../src/agent/driver.rkt"
         "../../src/agent/execution.rkt"
         "../../src/agent/registry.rkt"
         "../../src/command/api.rkt"
         "../../src/package/runtime.rkt"
         "support/rot13_canary.rkt")

(define (catalog-agent catalog)
  (agent-catalog-agent-by-identity catalog "odra.rot13-canary"))

(define (catalog-capability catalog)
  (agent-catalog-capability-by-identity catalog "odra.rot13.region"))

(define (buffer-reference)
  (make-agent-owner-reference
   'odra.rot13 'odra.editor.buffer 1 "buffer.main" #:generation 1))

(define (region-reference)
  (make-agent-owner-reference
   'odra.rot13 'odra.editor.region 1 '("buffer.main" 0 15) #:generation 1))

(define (target-registry)
  (define registry (make-agent-target-registry))
  (define (valid? reference)
    (if (= (odra-agent-owner-reference-generation reference) 1)
        'valid
        'stale))
  (define (contained? reference scope)
    (define identity (odra-agent-owner-reference-identity reference))
    (define selected (odra-agent-target-scope-selector scope))
    (if (or (equal? identity selected)
            (and (list? identity)
                 (pair? identity)
                 (equal? (car identity) selected)))
        'valid
        'outside-scope))
  (for ([kind (in-list '(odra.editor.buffer odra.editor.region))])
    (register-agent-target-kind!
     registry
     (make-agent-target-kind-definition
      'odra.rot13 kind 1 valid? contained?
      #:source "ROT13 canary editor target fixture.")))
  registry)

(define capability-limits
  (make-agent-capability-limits
   #:deadline-milliseconds 5000
   #:input-bytes 4096
   #:result-bytes 4096
   #:target-references 2))

(define authority-policy
  (make-agent-authority-policy
   #:effects '(mutate-editor-state observe)
   #:authorities '(racket-extension)
   #:limit-ceiling capability-limits
   #:maximum-validity-milliseconds 10000
   #:source "ROT13 canary authority policy."))

(define admission-policy
  (make-agent-admission-policy
   'local.rot13 1
   #:admitted-effects '(mutate-editor-state observe)
   #:human-decision-effects '(mutate-editor-state)
   #:human-actors '(local.actor)
   #:maximum-request-validity-milliseconds 10000
   #:source "ROT13 canary admission policy."))

(define (grant-canary! authority catalog agent capability)
  (grant-agent-capability!
   authority catalog
   (make-agent-grant-request
    'grant.rot13
    (odra-agent-definition-projection-identity agent)
    (odra-agent-definition-projection-definition-generation agent)
    (odra-agent-capability-projection-identity capability)
    (odra-agent-capability-projection-definition-generation capability)
    (make-agent-target-scope
     'odra.rot13 'odra.editor.buffer "buffer.main")
    (make-agent-authority-origin 'local-user 'local.actor)
    1
    #:effects '(mutate-editor-state observe)
    #:limits capability-limits
    #:task-restriction 'task.rot13
    #:valid-until 1000)
   authority-policy
   1))

(define (deterministic-driver output)
  (make-agent-driver
   'odra.agent-driver.deterministic 1
   (lambda (_context)
     (odra-agent-driver-open-result 'provider.deterministic #f))
   (lambda (_context) output)
   (lambda (_turn) (void))
   (lambda (_session) (void))
   #:source "ROT13 canary deterministic driver."))

(define (canary-output grant buffer region)
  (make-agent-turn-output
   (list
    (make-agent-turn-output-item 'progress '(status preparing))
    (make-agent-turn-output-item
     'request
     (make-agent-request-draft
      'request.rot13 'odra.rot13.region
      (list (list 'buffer buffer)
            (list 'region region)
            (list 'revision 1))
      '(mutate-editor-state observe)
      capability-limits
      (list
       (make-agent-record-reference
        'capability-grant
        (odra-agent-capability-grant-identity grant)
        (odra-agent-capability-grant-generation grant)))
      1000
      #:target-references (list buffer region)
      #:correlation-id 'turn.rot13
      #:idempotency-id 'operation.rot13))
    (make-agent-turn-output-item 'terminal '(status complete)))
   #:usage
   (make-agent-turn-usage
    #:provider-events 3 #:input-bytes 256 #:output-bytes 4096)))

(define (run-driver-turn! store catalog authority agent output)
  (define drivers (make-agent-driver-registry))
  (register-agent-driver! drivers (deterministic-driver output))
  (create-agent-task!
   store 'task.rot13 "Apply ROT13 to the selected region."
   (make-agent-task-origin 'local-user 'local.actor) 1
   #:owner-agent (odra-agent-definition-projection-identity agent))
  (open-agent-driver-session!
   store drivers catalog 'session.rot13
   (make-agent-record-reference
    'agent-registration
    (odra-agent-definition-projection-identity agent)
    (odra-agent-definition-projection-definition-generation agent))
   'task.rot13 1
   (odra-agent-definition-projection-identity agent)
   'odra.agent-driver.deterministic 2)
  (prepare-agent-turn!
   store drivers authority catalog 'turn.rot13 'session.rot13 2 1 3)
  (define invocation
    (invoke-agent-turn!
     store drivers authority catalog 'turn.rot13 1 4))
  (define completed
    (finalize-agent-turn! store catalog invocation 'local.actor 5))
  (check-equal? (odra-agent-turn-state completed) 'completed)
  drivers)

(test-case "deterministic ROT13 agent publishes one checked editor transaction"
  (define root (make-temporary-file "odra-rot13-canary-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define runtime (make-rot13-canary-runtime root))
      (define catalog (package-runtime-agent-catalog runtime))
      (define agent (catalog-agent catalog))
      (define capability (catalog-capability catalog))
      (check-not-false agent)
      (check-not-false capability)
      (define store (open-agent-continuity-store root))
      (define authority (make-agent-authority-store))
      (define ungranted
        (discover-agent-capabilities
         catalog authority
         (odra-agent-definition-projection-identity agent)
         #:at 1))
      (check-equal? (length ungranted) 1)
      (check-equal?
       (odra-agent-capability-discovery-grant-state (car ungranted))
       'ungranted)
      (define grant (grant-canary! authority catalog agent capability))
      (check-equal?
       (odra-agent-capability-discovery-grant-state
        (car
         (discover-agent-capabilities
          catalog authority
          (odra-agent-definition-projection-identity agent)
          #:at 2)))
       'granted)
      (define buffer (buffer-reference))
      (define region (region-reference))
      (run-driver-turn!
       store catalog authority agent (canary-output grant buffer region))
      (define request
        (inspect-agent-capability-request store 'request.rot13))
      (check-not-false request)
      (record-agent-human-decision!
       store 'request.rot13 'human.rot13 'local.actor 'approve-once
       admission-policy 6 1000)
      (define decision
        (decide-agent-capability-request!
         store authority catalog (target-registry)
         'request.rot13 'decision.rot13 admission-policy 7))
      (check-equal? (odra-agent-admission-decision-state decision) 'admitted)
      (prepare-agent-capability-attempt!
       store 'attempt.rot13 'request.rot13 'decision.rot13 'lease.rot13 8)
      (define editor (make-test-editor "Hello from Odra"))
      (define invocation
        (call-with-test-editor-context
         editor 0 15
         (lambda (command-context)
           (invoke-agent-capability-owner!
            store catalog 'attempt.rot13 1 9
            #:operation-invoker
            (lambda (identity execution-context)
              (check-equal? identity "rot13-region")
              (define command-result
                (call-with-contained-package-command
                 (lambda ()
                   (package-runtime-command-call
                    runtime identity command-context))))
              (if (command-rejection? command-result)
                  (make-agent-capability-owner-result
                   'failed
                   #:safe-summary "The ROT13 package operation was rejected.")
                  (make-agent-capability-owner-result
                   'succeeded
                   #:result
                   (list
                    (list 'revision
                          (add1
                           (odra-agent-owner-reference-generation
                            (car
                             (odra-agent-capability-execution-context-target-references
                              execution-context))))))
                   #:owner-evidence (list region)
                   #:confirmed-effects '(mutate-editor-state observe)
                   #:safe-summary "ROT13 changed the selected region.")))))))
      (define result
        (finalize-agent-capability-attempt!
         store catalog invocation 'result.rot13 10))
      (check-equal? (odra-agent-operation-result-state result) 'succeeded)
      (check-equal? (test-editor-text editor) "Uryyb sebz Bqen")
      (check-equal? (test-editor-splices editor) 1)
      (record-agent-audit-event!
       store 'audit.rot13 'capability-result 'local.actor
       '(status succeeded) 11
       #:task-id 'task.rot13
       #:effect-class 'mutate-editor-state
       #:subject-references
       (list
        (make-agent-record-reference
         'capability-request 'request.rot13 1)))
      (check-equal? (length (inspect-agent-audit-events store)) 1)
      (test-editor-undo! editor)
      (check-equal? (test-editor-text editor) "Hello from Odra")
      (test-editor-redo! editor)
      (check-equal? (test-editor-text editor) "Uryyb sebz Bqen")
      (close-agent-continuity-store! store)
      (define reopened (open-agent-continuity-store root))
      (check-equal?
       (odra-agent-operation-result-state
        (inspect-agent-operation-result reopened 'result.rot13))
       'succeeded)
      (check-equal? (length (inspect-agent-audit-events reopened)) 1)
      (close-agent-continuity-store! reopened)
      (package-runtime-close! runtime))
    (lambda () (delete-directory/files root))))

(test-case "cancellation revocation and integration removal fail closed"
  (define root (make-temporary-file "odra-rot13-canary-lifecycle-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define runtime (make-rot13-canary-runtime root))
      (define catalog (package-runtime-agent-catalog runtime))
      (define agent (catalog-agent catalog))
      (define capability (catalog-capability catalog))
      (define store (open-agent-continuity-store root))
      (define authority (make-agent-authority-store))
      (define grant (grant-canary! authority catalog agent capability))
      (define buffer (buffer-reference))
      (define region (region-reference))
      (run-driver-turn!
       store catalog authority agent (canary-output grant buffer region))
      (record-agent-human-decision!
       store 'request.rot13 'human.rot13 'local.actor 'approve-once
       admission-policy 6 1000)
      (define decision
        (decide-agent-capability-request!
         store authority catalog (target-registry)
         'request.rot13 'decision.rot13 admission-policy 7))
      (check-equal? (odra-agent-admission-decision-state decision) 'admitted)
      (prepare-agent-capability-attempt!
       store 'attempt.rot13 'request.rot13 'decision.rot13 'lease.rot13 8)
      (define cancelling
        (request-agent-capability-cancellation!
         store 'attempt.rot13 1 'local.actor "Cancel the canary." 9))
      (check-equal? (odra-agent-operation-attempt-state cancelling) 'cancelling)
      (define cancelled
        (settle-agent-capability-attempt!
         store catalog 'attempt.rot13
         (odra-agent-operation-attempt-generation cancelling)
         'result.rot13 10))
      (check-equal? (odra-agent-operation-result-state cancelled) 'cancelled)
      (define revoked
        (revoke-agent-capability-grant!
         authority
         (odra-agent-capability-grant-identity grant)
         (odra-agent-capability-grant-generation grant)
         "Canary revocation check." 11))
      (check-equal? (odra-agent-capability-grant-state revoked) 'revoked)
      (define original-request
        (inspect-agent-capability-request store 'request.rot13))
      (define revoked-request
        (struct-copy
         odra-agent-capability-request original-request
         [identity "request.revoked"]
         [created-at 12]))
      (record-agent-capability-request! store revoked-request)
      (define rejected
        (decide-agent-capability-request!
         store authority catalog (target-registry)
         'request.revoked 'decision.revoked admission-policy 13))
      (check-equal? (odra-agent-admission-decision-state rejected) 'rejected)
      (check-true
       (void?
        (package-runtime-deactivate!
         runtime "odra.rot13-agent-integration" 4 5)))
      (check-false
       (catalog-capability (package-runtime-agent-catalog runtime)))
      (check-equal?
       (package-runtime-active-generation runtime "odra.rot13") 2)
      (close-agent-continuity-store! store)
      (package-runtime-close! runtime))
    (lambda () (delete-directory/files root))))

(test-case "direct ROT13 remains independent from the agent substrate"
  (define root (make-temporary-file "odra-direct-rot13-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define runtime (make-rot13-canary-runtime root))
      (check-true
       (void?
        (package-runtime-deactivate!
         runtime "odra.rot13-agent-integration" 4 5)))
      (check-true
       (void?
        (package-runtime-deactivate!
         runtime "odra.rot13-canary-agent" 3 6)))
      (check-equal?
       (odra-agent-catalog-agents (package-runtime-agent-catalog runtime))
       '())
      (check-equal?
       (odra-agent-catalog-capabilities (package-runtime-agent-catalog runtime))
       '())
      (define editor (make-test-editor "Hello from Odra"))
      (define (run-direct!)
        (call-with-test-editor-context
         editor 0 15
         (lambda (context)
           (call-with-contained-package-command
            (lambda ()
              (package-runtime-command-call
               runtime "rot13-region" context))))))
      (check-true (void? (run-direct!)))
      (check-equal? (test-editor-text editor) "Uryyb sebz Bqen")
      (check-true (void? (run-direct!)))
      (check-equal? (test-editor-text editor) "Hello from Odra")
      (check-equal? (test-editor-splices editor) 2)
      (test-editor-undo! editor)
      (check-equal? (test-editor-text editor) "Uryyb sebz Bqen")
      (test-editor-undo! editor)
      (check-equal? (test-editor-text editor) "Hello from Odra")
      (test-editor-redo! editor)
      (check-equal? (test-editor-text editor) "Uryyb sebz Bqen")
      (test-editor-redo! editor)
      (check-equal? (test-editor-text editor) "Hello from Odra")
      (package-runtime-close! runtime))
    (lambda () (delete-directory/files root))))
