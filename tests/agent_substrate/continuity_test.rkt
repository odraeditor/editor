#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         racket/file
         "../../src/agent/authority.rkt"
         "../../src/agent/continuity.rkt"
         "../../src/agent/definition.rkt"
         "../../src/agent/registry.rkt")

(define (call-with-test-store procedure
                              #:transaction-observer [observer void])
  (define root
    (make-temporary-file "odra-agent-continuity-test~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define store
        (open-agent-continuity-store
         root #:transaction-observer observer))
      (dynamic-wind
        void
        (lambda () (procedure root store))
        (lambda () (close-agent-continuity-store! store))))
    (lambda () (delete-directory/files root))))

(define task-origin
  (make-agent-task-origin 'local-user 'local.actor))

(define (owner-reference identity)
  (make-agent-owner-reference
   'example.text 'example.text.region 1 identity #:generation 7))

(define (continuity-capability)
  (make-agent-capability
   'example.observe 'example.text (lambda (_context) (void))
   #:purpose "Observe one example target."
   #:input-schema
   '(record (target required (owner-reference example.text.region 1)))
   #:result-schema '(record (accepted required boolean))
   #:target-kinds '(example.text.region)
   #:effects '(filesystem-read observe)
   #:required-authorities '(project-read)))

(define (continuity-catalog)
  (compose-agent-catalog
   7
   (list
    (make-agent-contribution-source
     "example.integration" "1.0.0" 7
     (list
      (make-agent
       'example.sender #:requested-capabilities '(example.observe))
      (make-agent
       'example.recipient #:requested-capabilities '(example.observe)))
     (list (continuity-capability))
     #:authorities '(project-read)))))

(define authority-scope
  (make-agent-target-scope
   'example.text 'example.text.region "project.notes"))

(define authority-origin
  (make-agent-authority-origin 'local-user 'local.actor))

(define authority-policy
  (make-agent-authority-policy
   #:effects '(filesystem-read observe)
   #:authorities '(project-read)
   #:maximum-validity-milliseconds 100000
   #:maximum-delegation-depth 2
   #:source "Continuity test policy."))

(define (grant! store catalog identity agent delegation-depth)
  (grant-agent-capability!
   store catalog
   (make-agent-grant-request
    identity agent 7 "example.observe" 7 authority-scope authority-origin 0
    #:effects '(observe)
    #:delegation-depth delegation-depth
    #:valid-until 100000)
   authority-policy 1))

(test-case "tasks and participants survive store restart"
  (define root
    (make-temporary-file "odra-agent-continuity-restart~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define store (open-agent-continuity-store root))
      (define reference (owner-reference '(buffer "opaque-17")))
      (define task
        (create-agent-task!
         store 'task.restart "Preserve one requested outcome." task-origin 10
         #:owner-agent 'example.sender
         #:owner-references (list reference)
         #:resource-policy '(limits (turns 2))))
      (check-true (odra-agent-task? task))
      (check-true
       (file-exists? (build-path root agent-continuity-database-name)))
      (close-agent-continuity-store! store)
      (define reopened (open-agent-continuity-store root))
      (define restored (inspect-agent-task reopened 'task.restart))
      (check-equal? (odra-agent-task-identity restored) "task.restart")
      (check-equal?
       (odra-agent-owner-reference-identity
        (car (odra-agent-task-owner-references restored)))
       '(buffer "opaque-17"))
      (check-equal?
       (map odra-agent-task-participant-agent-identity
            (inspect-agent-task-participants reopened 'task.restart))
       '("example.sender"))
      (close-agent-continuity-store! reopened))
    (lambda () (delete-directory/files root))))

(test-case "task transitions are generation checked and evidence backed"
  (call-with-test-store
   (lambda (_root store)
     (create-agent-task!
      store 'task.transitions "Advance checked state." task-origin 1
      #:owner-agent 'example.sender)
     (define ready
       (transition-agent-task!
        store 'task.transitions 1 'example.sender 'ready 2))
     (check-equal? (odra-agent-task-generation ready) 2)
     (check-equal?
      (odra-agent-continuity-denial-code
       (transition-agent-task!
        store 'task.transitions 1 'example.sender 'running 3))
      'stale-task)
     (define running
       (transition-agent-task!
        store 'task.transitions 2 'example.sender 'running 3))
     (check-equal? (odra-agent-task-state running) 'running)
     (check-equal?
      (odra-agent-continuity-denial-code
       (transition-agent-task!
        store 'task.transitions 3 'example.sender 'succeeded 4))
      'missing-result)
     (define succeeded
       (transition-agent-task!
        store 'task.transitions 3 'example.sender 'succeeded 4
        #:terminal-result-refs (list (owner-reference "result-17"))))
     (check-equal? (odra-agent-task-state succeeded) 'succeeded)
     (check-equal?
      (odra-agent-continuity-denial-code
       (join-agent-task!
        store 'task.transitions 4 'example.recipient 'reviewer 5))
      'terminal-task))))

(test-case "participant departure rejects stale and owner removal"
  (call-with-test-store
   (lambda (_root store)
     (create-agent-task!
      store 'task.participants "Coordinate participants." task-origin 1
      #:owner-agent 'example.sender)
     (define joined
       (join-agent-task!
        store 'task.participants 1 'example.recipient 'reviewer 2))
     (check-equal? (odra-agent-task-participant-generation joined) 1)
     (define left
       (leave-agent-task!
        store 'task.participants 'example.recipient 1 3
        #:reason 'review-complete))
     (check-equal? (odra-agent-task-participant-left-at left) 3)
     (check-equal?
      (odra-agent-continuity-denial-code
       (leave-agent-task!
        store 'task.participants 'example.recipient 1 4))
      'stale-participant)
     (check-equal?
      (odra-agent-continuity-denial-code
       (leave-agent-task!
        store 'task.participants 'example.sender 1 4))
      'owner-participant))))

(test-case "interaction envelopes remain bounded attributable and opaque"
  (call-with-test-store
   (lambda (_root store)
     (create-agent-task!
      store 'task.interactions "Record interactions." task-origin 1
      #:owner-agent 'example.sender)
     (define provenance
       (make-agent-interaction-provenance 'agent 'example.sender))
     (define reference (owner-reference '(document "opaque-document")))
     (define interaction
       (record-agent-interaction!
        store 'interaction.progress 'task.interactions
        'example.sender 'local.actor 'progress
        '(status "working") 'participants provenance 2
        #:acting-agent 'example.sender
        #:context-references (list reference)
        #:correlation-id 'correlation.one))
     (check-equal? (odra-agent-interaction-kind interaction) 'progress)
     (check-equal?
      (odra-agent-owner-reference-identity
       (car (odra-agent-interaction-context-references interaction)))
      '(document "opaque-document"))
     (check-equal?
      (odra-agent-continuity-denial-code
       (record-agent-interaction!
        store 'interaction.bad-provenance 'task.interactions
        'local.actor 'example.sender 'request "Review this."
        'sender-recipient provenance 3))
      'invalid-provenance)
     (check-exn
      #rx"invalid bounded interaction envelope"
      (lambda ()
        (record-agent-interaction!
         store 'interaction.oversized 'task.interactions
         'example.sender 'local.actor 'progress
         (make-string (add1 maximum-agent-interaction-payload-bytes) #\x)
         'participants provenance 3
         #:acting-agent 'example.sender))))))

(test-case "parent ancestry is acyclic and bounded"
  (call-with-test-store
   (lambda (_root store)
     (check-equal?
      (odra-agent-continuity-denial-code
       (create-agent-task!
        store 'task.self "Reject self ancestry." task-origin 1
        #:parent-task-id 'task.self))
      'invalid-parent)
     (create-agent-task! store 'task.root "Root." task-origin 1)
     (for ([depth (in-range 1 maximum-agent-task-depth)])
       (create-agent-task!
        store
        (string->symbol (format "task.depth-~a" depth))
        "Child."
        task-origin
        (+ depth 1)
        #:parent-task-id
        (if (= depth 1)
            'task.root
            (string->symbol (format "task.depth-~a" (sub1 depth))))))
     (check-equal?
      (odra-agent-continuity-denial-code
       (create-agent-task!
        store 'task.too-deep "Too deep." task-origin 20
        #:parent-task-id
        (string->symbol
         (format "task.depth-~a" (sub1 maximum-agent-task-depth)))))
      'invalid-parent))))

(test-case "failed multi-record publication rolls back completely"
  (call-with-test-store
   (lambda (_root store)
     (check-exn
      #rx"injected publication failure"
      (lambda ()
        (create-agent-task!
         store 'task.rollback "Rollback task and owner." task-origin 1
         #:owner-agent 'example.sender)))
     (check-false (inspect-agent-task store 'task.rollback))
     (check-equal?
      (inspect-agent-task-participants store 'task.rollback) '()))
   #:transaction-observer
   (lambda (kind _result)
     (when (eq? kind 'create-task)
       (error 'continuity-test "injected publication failure")))))

(test-case "delegation uses current independent authority for both agents"
  (call-with-test-store
   (lambda (_root store)
     (define catalog (continuity-catalog))
     (define authority-store (make-agent-authority-store))
     (define sender-grant
       (grant! authority-store catalog 'grant.sender "example.sender" 2))
     (define recipient-grant
       (grant! authority-store catalog 'grant.recipient "example.recipient" 0))
     (check-true (odra-agent-capability-grant? sender-grant))
     (check-true (odra-agent-capability-grant? recipient-grant))
     (create-agent-task!
      store 'task.delegation "Delegate bounded work." task-origin 1
      #:owner-agent 'example.sender)
     (join-agent-task!
      store 'task.delegation 1 'example.recipient 'delegate 2)
     (define delegation
       (create-agent-delegation!
        store authority-store catalog 'delegation.one 'task.delegation
        'example.sender 'example.recipient "Observe the target." 3
        #:authority-ceiling '(example.observe)))
     (check-equal? (odra-agent-delegation-state delegation) 'proposed)
     (define accepted
       (transition-agent-delegation!
        store authority-store catalog 'delegation.one 1
        'example.recipient 'accepted 4))
     (check-equal? (odra-agent-delegation-state accepted) 'accepted)
     (revoke-agent-capability-grant!
      authority-store "grant.recipient" 1 "Test authority reduction." 5)
     (check-equal?
      (odra-agent-continuity-denial-code
       (transition-agent-delegation!
        store authority-store catalog 'delegation.one 2
        'example.recipient 'running 6))
      'authority-reduced)
     (check-equal?
      (odra-agent-delegation-state
       (inspect-agent-delegation store 'delegation.one))
      'accepted))))
