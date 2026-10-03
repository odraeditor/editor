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
         "../../src/agent/registry.rkt")

(define handler-entered? #f)

(define (call-with-test-store procedure
                              #:transaction-observer [observer void])
  (define root
    (make-temporary-file "odra-agent-admission-test~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define store
        (open-agent-continuity-store
         root #:transaction-observer observer))
      (dynamic-wind
        void
        (lambda () (procedure store))
        (lambda () (close-agent-continuity-store! store))))
    (lambda () (delete-directory/files root))))

(define (capability #:approval [approval 'policy]
                    #:hard-limits [hard-limits default-agent-capability-limits])
  (make-agent-capability
   'example.observe 'example.text
   (lambda (_context) (set! handler-entered? #t))
   #:purpose "Observe one bounded target."
   #:input-schema
   '(record
     (target required (owner-reference example.text.region 1))
     (text required (string 128)))
   #:result-schema '(record (accepted required boolean))
   #:target-kinds '(example.text.region)
   #:effects '(filesystem-read observe)
   #:required-authorities '(project-read)
   #:default-limits hard-limits
   #:hard-limits hard-limits
   #:approval-class approval
   #:idempotency-class 'read-only))

(define (catalog #:approval [approval 'policy]
                 #:hard-limits [hard-limits default-agent-capability-limits])
  (compose-agent-catalog
   7
   (list
    (make-agent-contribution-source
     "example.integration" "1.0.0" 7
     (list
      (make-agent
       'example.agent #:requested-capabilities '(example.observe)))
     (list (capability #:approval approval #:hard-limits hard-limits))
     #:authorities '(project-read)))))

(define grant-scope
  (make-agent-target-scope
   'example.text 'example.text.region "allowed"))

(define grant-origin
  (make-agent-authority-origin 'local-user 'local.actor))

(define grant-policy
  (make-agent-authority-policy
   #:effects '(filesystem-read observe)
   #:authorities '(project-read)
   #:maximum-validity-milliseconds 100000
   #:source "Admission test authority."))

(define admission-policy
  (make-agent-admission-policy
   'local.admission 3
   #:admitted-effects '(filesystem-read observe)
   #:human-actors '(local.actor)
   #:maximum-request-validity-milliseconds 5000
   #:source "Admission test policy."))

(define human-admission-policy
  (make-agent-admission-policy
   'local.admission 4
   #:admitted-effects '(filesystem-read observe)
   #:human-decision-effects '(filesystem-read)
   #:human-actors '(local.actor)
   #:maximum-request-validity-milliseconds 5000
   #:source "Human admission test policy."))

(define (target-registry)
  (define registry (make-agent-target-registry))
  (register-agent-target-kind!
   registry
   (make-agent-target-kind-definition
    'example.text 'example.text.region 1
    (lambda (reference)
      (if (= (odra-agent-owner-reference-generation reference) 1)
          'valid
          'stale))
    (lambda (reference scope)
      (if (equal? (odra-agent-owner-reference-identity reference)
                  (odra-agent-target-scope-selector scope))
          'valid
          'outside-scope))
    #:source "Admission test target."))
  registry)

(define (prepare! store #:approval [approval 'policy]
                  #:hard-limits [hard-limits default-agent-capability-limits])
  (define active-catalog
    (catalog #:approval approval #:hard-limits hard-limits))
  (define authority-store (make-agent-authority-store))
  (define grant
    (grant-agent-capability!
     authority-store active-catalog
     (make-agent-grant-request
      'grant.observe "example.agent" 7 "example.observe" 7
      grant-scope grant-origin 0
      #:effects '(filesystem-read observe)
      #:valid-until 100000)
     grant-policy 1))
  (unless (odra-agent-capability-grant? grant)
    (error 'prepare! "test grant was not admitted"))
  (define task
    (create-agent-task!
     store 'task.admission "Admit one capability request."
     (make-agent-task-origin 'local-user 'local.actor) 1
     #:owner-agent 'example.agent))
  (unless (odra-agent-task? task)
    (error 'prepare! "test task was not created"))
  (values active-catalog authority-store grant (target-registry)))

(define (target identity #:generation [generation 1])
  (make-agent-owner-reference
   'example.text 'example.text.region 1 identity
   #:generation generation))

(define (request identity grant
                 #:input [input #f]
                 #:target [target-reference (target "allowed")]
                 #:task-generation [task-generation 1]
                 #:agent-generation [agent-generation 7]
                 #:capability-generation [capability-generation 7]
                 #:package-generation [package-generation 7]
                 #:limits [limits default-agent-capability-limits]
                 #:effects [effects '(filesystem-read observe)]
                 #:created-at [created-at 10]
                 #:valid-until [valid-until 1000]
                 #:human-decision-reference [human-reference #f])
  (define actual-input
    (or input
        (list (list 'target target-reference)
              (list 'text "observe"))))
  (make-agent-capability-request
   identity 'task.admission task-generation
   'example.agent agent-generation
   (make-agent-record-reference
    'agent-registration 'example.agent agent-generation)
   'example.observe capability-generation
   (make-agent-package-reference
    'example.integration "1.0.0" package-generation)
   (make-agent-schema-reference
    'example.observe capability-generation 'input 1)
   actual-input effects limits
   (list
    (make-agent-record-reference
     'capability-grant
     (odra-agent-capability-grant-identity grant)
     (odra-agent-capability-grant-generation grant)))
   created-at valid-until
   #:target-references (list target-reference)
   #:human-decision-reference human-reference
   #:correlation-id 'correlation.one))

(define (record! store candidate)
  (define recorded (record-agent-capability-request! store candidate))
  (unless (odra-agent-capability-request? recorded)
    (error 'record! "test request was not recorded"))
  recorded)

(test-case "valid requests persist and admit without executing handlers"
  (call-with-test-store
   (lambda (store)
     (set! handler-entered? #f)
     (define-values (active-catalog authority-store grant targets)
       (prepare! store))
     (record! store (request 'request.valid grant))
     (define decision
       (decide-agent-capability-request!
        store authority-store active-catalog targets
        'request.valid 'decision.valid admission-policy 20))
     (check-equal? (odra-agent-admission-decision-state decision) 'admitted)
     (check-equal?
      (odra-agent-admission-decision-effective-effects decision)
      '(filesystem-read observe))
     (check-equal?
      (odra-agent-capability-request-input
       (inspect-agent-capability-request store 'request.valid))
      (odra-agent-capability-request-input (request 'request.copy grant)))
     (check-false handler-entered?))))

(test-case "schema package and generation mismatches reject deterministically"
  (call-with-test-store
   (lambda (store)
     (define-values (active-catalog authority-store grant targets)
       (prepare! store))
     (define bad-schema
       (request
        'request.schema grant
        #:input
        (list (list 'target (target "allowed")) (list 'text 17))))
     (record! store bad-schema)
     (define schema-decision
       (decide-agent-capability-request!
        store authority-store active-catalog targets
        'request.schema 'decision.schema admission-policy 20))
     (check-equal?
      (odra-agent-admission-decision-reason-code schema-decision)
      'schema-mismatch)
     (record! store
              (request 'request.package grant #:package-generation 6))
     (check-equal?
      (odra-agent-admission-decision-reason-code
       (decide-agent-capability-request!
        store authority-store active-catalog targets
        'request.package 'decision.package admission-policy 20))
      'stale-package)
     (record! store
              (request 'request.task-generation grant #:task-generation 2))
     (check-equal?
      (odra-agent-admission-decision-reason-code
       (decide-agent-capability-request!
        store authority-store active-catalog targets
        'request.task-generation 'decision.task-generation
        admission-policy 20))
      'stale-task)
     (record! store
              (request
               'request.effects grant
               #:effects '(mutate-editor-state observe)))
     (check-equal?
      (odra-agent-admission-decision-reason-code
       (decide-agent-capability-request!
        store authority-store active-catalog targets
        'request.effects 'decision.effects admission-policy 20))
      'effect-escape))))

(test-case "target scope escape is rejected by the registered owner"
  (call-with-test-store
   (lambda (store)
     (define-values (active-catalog authority-store grant targets)
       (prepare! store))
     (define outside (target "outside"))
     (record! store
              (request
               'request.outside grant
               #:target outside
               #:input
               (list (list 'target outside) (list 'text "observe"))))
     (define decision
       (decide-agent-capability-request!
        store authority-store active-catalog targets
        'request.outside 'decision.outside admission-policy 20))
     (check-equal? (odra-agent-admission-decision-state decision) 'rejected)
     (check-equal?
      (odra-agent-admission-decision-reason-code decision) 'target-escape))))

(test-case "revoked and expired authority cannot admit captured requests"
  (call-with-test-store
   (lambda (store)
     (define-values (active-catalog authority-store grant targets)
       (prepare! store))
     (record! store (request 'request.revoked grant))
     (revoke-agent-capability-grant!
      authority-store "grant.observe" 1 "Admission revocation test." 15)
     (check-equal?
      (odra-agent-admission-decision-reason-code
       (decide-agent-capability-request!
        store authority-store active-catalog targets
        'request.revoked 'decision.revoked admission-policy 20))
      'stale-grant)
     (record! store
              (request 'request.expired grant #:valid-until 25))
     (check-equal?
      (odra-agent-admission-decision-reason-code
       (decide-agent-capability-request!
        store authority-store active-catalog targets
        'request.expired 'decision.expired admission-policy 25))
      'expired-request))))

(test-case "capability and policy limits reject broader requests"
  (call-with-test-store
   (lambda (store)
     (define hard-limits
       (make-agent-capability-limits
        #:deadline-milliseconds 1000
        #:input-bytes 1024
        #:result-bytes 1024
        #:target-references 1))
     (define-values (active-catalog authority-store grant targets)
       (prepare! store #:hard-limits hard-limits))
     (record! store (request 'request.limit grant))
     (check-equal?
      (odra-agent-admission-decision-reason-code
       (decide-agent-capability-request!
        store authority-store active-catalog targets
        'request.limit 'decision.limit admission-policy 20))
      'limit-escape)
     (define deny-policy
       (make-agent-admission-policy
        'local.deny 1
        #:admitted-effects '(observe)
        #:maximum-request-validity-milliseconds 5000))
     (record! store
              (request 'request.policy grant #:limits hard-limits))
     (check-equal?
      (odra-agent-admission-decision-reason-code
       (decide-agent-capability-request!
        store authority-store active-catalog targets
        'request.policy 'decision.policy deny-policy 20))
      'policy-effect))))

(test-case "admission decisions are immutable and repeated reads are stable"
  (call-with-test-store
   (lambda (store)
     (define-values (active-catalog authority-store grant targets)
       (prepare! store))
     (record! store (request 'request.once grant))
     (define first
       (decide-agent-capability-request!
        store authority-store active-catalog targets
        'request.once 'decision.once admission-policy 20))
     (define repeated
       (decide-agent-capability-request!
        store authority-store active-catalog targets
        'request.once 'decision.once admission-policy 30))
     (check-equal? repeated first)
     (check-equal?
      (odra-agent-admission-denial-code
       (decide-agent-capability-request!
        store authority-store active-catalog targets
        'request.once 'decision.other admission-policy 30))
      'duplicate-decision))))

(test-case "approve once is request scoped consumed and non-transferable"
  (call-with-test-store
   (lambda (store)
     (define-values (active-catalog authority-store grant targets)
       (prepare! store #:approval 'ask-once))
     (record! store (request 'request.approved grant))
     (define human
       (record-agent-human-decision!
        store 'request.approved 'human.approved 'local.actor 'approve-once
        human-admission-policy 15 500))
     (check-true (odra-agent-human-decision? human))
     (define admitted
       (decide-agent-capability-request!
        store authority-store active-catalog targets
        'request.approved 'decision.approved human-admission-policy 20))
     (check-equal? (odra-agent-admission-decision-state admitted) 'admitted)
     (define consumed
       (inspect-agent-human-decision store 'request.approved))
     (check-equal? (odra-agent-human-decision-generation consumed) 2)
     (check-equal?
      (odra-agent-human-decision-consumed-by consumed) "decision.approved")
     (record! store
              (request
               'request.second grant
               #:human-decision-reference
               (make-agent-record-reference
                'human-decision 'human.approved 1)))
     (define second
       (decide-agent-capability-request!
        store authority-store active-catalog targets
        'request.second 'decision.second human-admission-policy 20))
     (check-equal?
      (odra-agent-admission-decision-state second) 'needs-human-decision))))

(test-case "human rejection cancellation and duplication remain one request"
  (for ([value (in-list '(reject cancel-task))])
    (call-with-test-store
     (lambda (store)
       (define-values (active-catalog authority-store grant targets)
         (prepare! store #:approval 'always))
       (define request-id
         (if (eq? value 'reject) 'request.rejected 'request.cancelled))
       (define decision-id
         (if (eq? value 'reject) 'decision.rejected 'decision.cancelled))
       (record! store (request request-id grant))
       (record-agent-human-decision!
        store request-id 'human.final 'local.actor value
        human-admission-policy 15 500)
       (check-equal?
        (odra-agent-admission-denial-code
         (record-agent-human-decision!
          store request-id 'human.repeated 'local.actor value
          human-admission-policy 16 500))
        'duplicate-human-decision)
       (define decision
         (decide-agent-capability-request!
          store authority-store active-catalog targets
          request-id decision-id human-admission-policy 20))
       (check-equal? (odra-agent-admission-decision-state decision) 'rejected)
       (check-equal?
        (odra-agent-admission-decision-reason-code decision)
        (if (eq? value 'reject) 'human-rejected 'human-cancelled))))))

(test-case "failed admission publication rolls back and never executes"
  (call-with-test-store
   (lambda (store)
     (set! handler-entered? #f)
     (define-values (active-catalog authority-store grant targets)
       (prepare! store))
     (record! store (request 'request.rollback grant))
     (check-exn
      #rx"injected admission failure"
      (lambda ()
        (decide-agent-capability-request!
         store authority-store active-catalog targets
         'request.rollback 'decision.rollback admission-policy 20)))
     (check-false
      (inspect-agent-admission-decision store 'request.rollback))
     (check-false handler-entered?))
   #:transaction-observer
   (lambda (kind _result)
     (when (eq? kind 'decide-capability-request)
       (error 'admission-test "injected admission failure")))))
