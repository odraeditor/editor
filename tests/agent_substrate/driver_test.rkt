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
         "../../src/agent/driver.rkt"
         "../../src/agent/registry.rkt")

(define (test-capability)
  (make-agent-capability
   'example.observe 'example.text (lambda (_context) (void))
   #:purpose "Observe one example target."
   #:input-schema
   '(record (target required (owner-reference example.text.region 1)))
   #:result-schema '(record (accepted required boolean))
   #:target-kinds '(example.text.region)
   #:effects '(observe)
   #:required-authorities '(project-read)))

(define (test-catalog)
  (compose-agent-catalog
   7
   (list
    (make-agent-contribution-source
     "example.integration" "1.0.0" 7
     (list
      (make-agent
       'example.agent
       #:interaction-kinds '(failure progress proposal question result)
       #:provider-requirements '(odra.agent-driver)
       #:requested-capabilities '(example.observe)
       #:continuation-policy 'bounded))
     (list (test-capability))
     #:authorities '(project-read)))))

(define (test-grant! authority-store catalog)
  (grant-agent-capability!
   authority-store catalog
   (make-agent-grant-request
    'grant.observe 'example.agent 7 "example.observe" 7
    (make-agent-target-scope
     'example.text 'example.text.region "project.notes")
    (make-agent-authority-origin 'local-user 'local.actor)
    0
    #:effects '(observe)
    #:task-restriction 'task.driver
    #:valid-until 100000)
   (make-agent-authority-policy
    #:effects '(observe)
    #:authorities '(project-read)
    #:maximum-validity-milliseconds 100000
    #:source "Driver test policy.")
   1))

(define (test-driver identity generation output-box
                     #:cancelled [cancelled (box #f)]
                     #:closed [closed (box #f)])
  (make-agent-driver
   identity generation
   (lambda (_context)
     (odra-agent-driver-open-result
      (string->symbol (format "~a.session" identity))
      'continuation.initial))
   (lambda (context)
     (define value (unbox output-box))
     (if (procedure? value) (value context) value))
   (lambda (_turn) (set-box! cancelled #t))
   (lambda (_session) (set-box! closed #t))))

(define (with-fixture procedure
                      #:observer [observer void]
                      #:output [initial-output
                                (make-agent-turn-output
                                 (list
                                  (make-agent-turn-output-item
                                   'progress '(status working)))
                                 #:usage
                                 (make-agent-turn-usage
                                  #:provider-events 1
                                  #:output-bytes 4096))])
  (define root
    (make-temporary-file "odra-agent-driver-test~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define store
        (open-agent-continuity-store root #:transaction-observer observer))
      (define registry (make-agent-driver-registry))
      (define authority-store (make-agent-authority-store))
      (define catalog (test-catalog))
      (define output-box (box initial-output))
      (define cancelled (box #f))
      (define closed (box #f))
      (register-agent-driver!
       registry
       (test-driver 'example.driver 1 output-box
                    #:cancelled cancelled #:closed closed))
      (test-grant! authority-store catalog)
      (create-agent-task!
       store 'task.driver "Run one provider-neutral turn."
       (make-agent-task-origin 'local-user 'local.actor) 1
       #:owner-agent 'example.agent)
      (dynamic-wind
        void
        (lambda ()
          (procedure root store registry authority-store catalog output-box
                     cancelled closed))
        (lambda () (close-agent-continuity-store! store))))
    (lambda () (delete-directory/files root))))

(define registration-reference
  (make-agent-record-reference 'agent-registration 'registration.example 1))

(define (open-session store registry catalog
                      #:identity [identity 'session.driver]
                      #:driver [driver 'example.driver])
  (open-agent-driver-session!
   store registry catalog identity registration-reference
   'task.driver 1 'example.agent driver 2))

(define (prepare-turn store registry authority-store catalog
                      #:identity [identity 'turn.driver]
                      #:session [session 'session.driver]
                      #:generation [generation 2]
                      #:at [at 3])
  (prepare-agent-turn!
   store registry authority-store catalog identity session generation 1 at))

(test-case "driver definitions reject stale replacement"
  (define registry (make-agent-driver-registry))
  (define output (box (make-agent-turn-output '())))
  (check-true
   (odra-agent-driver-projection?
    (register-agent-driver!
     registry (test-driver 'example.driver 1 output))))
  (check-equal?
   (odra-agent-driver-denial-code
    (register-agent-driver!
     registry (test-driver 'example.driver 1 output)))
   'stale-driver)
  (check-equal?
   (odra-agent-driver-projection-generation
    (register-agent-driver!
     registry (test-driver 'example.driver 2 output)))
   2))

(test-case "driver sessions persist and close exact generations"
  (with-fixture
   (lambda (root store registry _authority catalog _output _cancelled closed)
     (define session (open-session store registry catalog))
     (check-equal? (odra-agent-driver-session-state session) 'available)
     (check-equal? (odra-agent-driver-session-generation session) 2)
     (close-agent-continuity-store! store)
     (define reopened (open-agent-continuity-store root))
     (define restored
       (inspect-agent-driver-session reopened 'session.driver))
     (check-equal? (odra-agent-driver-session-state restored) 'available)
     (define ended
       (close-agent-driver-session! reopened registry 'session.driver 2 4))
     (check-equal? (odra-agent-driver-session-state ended) 'closed)
     (check-true (unbox closed))
     (close-agent-continuity-store! reopened))))

(test-case "deterministic turn publishes interactions and request proposals"
  (with-fixture
   (lambda (_root store registry authority catalog output _cancelled _closed)
     (define target
       (make-agent-owner-reference
        'example.text 'example.text.region 1 "note-17" #:generation 3))
     (define draft
       (make-agent-request-draft
        'request.driver 'example.observe
        (list (list 'target target)) '(observe)
        default-agent-capability-limits
        (list
         (make-agent-record-reference
          'capability-grant 'grant.observe 1))
        1000
        #:target-references (list target)
        #:correlation-id 'turn.driver))
     (set-box!
      output
      (make-agent-turn-output
       (list
        (make-agent-turn-output-item 'progress '(status working))
        (make-agent-turn-output-item 'request draft)
        (make-agent-turn-output-item 'terminal '(status complete)))
       #:continuation-reference 'continuation.next
       #:usage
       (make-agent-turn-usage
        #:input-tokens 10 #:output-tokens 20 #:cost-micros 30
        #:provider-events 3 #:input-bytes 512 #:output-bytes 4096)))
     (open-session store registry catalog)
     (prepare-turn store registry authority catalog)
     (define invocation
       (invoke-agent-turn! store registry authority catalog 'turn.driver 1 4))
     (define completed
       (finalize-agent-turn! store catalog invocation 'local.actor 5))
     (check-equal? (odra-agent-turn-state completed) 'completed)
     (check-equal?
      (map odra-agent-interaction-kind
           (inspect-agent-task-interactions store 'task.driver))
      '(progress result))
     (check-true
      (odra-agent-capability-request?
       (inspect-agent-capability-request store 'request.driver)))
     (check-equal?
      (odra-agent-driver-session-continuation-reference
       (inspect-agent-driver-session store 'session.driver))
      "continuation.next"))))

(test-case "malformed output publishes no partial interaction"
  (with-fixture
   (lambda (_root store registry authority catalog output _cancelled _closed)
     (set-box!
      output
      (odra-agent-turn-output
       (list
        (make-agent-turn-output-item 'progress '(status valid))
        (make-agent-turn-output-item 'request 'not-a-request-draft))
       #f
       (make-agent-turn-usage #:provider-events 2 #:output-bytes 4096)))
     (open-session store registry catalog)
     (prepare-turn store registry authority catalog)
     (define invocation
       (invoke-agent-turn! store registry authority catalog 'turn.driver 1 4))
     (define failed
       (finalize-agent-turn! store catalog invocation 'local.actor 5))
     (check-equal? (odra-agent-turn-state failed) 'failed)
     (check-equal? (inspect-agent-task-interactions store 'task.driver) '())
     (check-equal? (inspect-agent-capability-requests store) '()))))

(test-case "expired prepared turn releases the session"
  (with-fixture
   (lambda (_root store registry authority catalog _output _cancelled _closed)
     (open-session store registry catalog)
     (define prepared
       (prepare-turn store registry authority catalog))
     (define deadline (odra-agent-turn-deadline prepared))
     (check-equal?
      (odra-agent-driver-denial-code
       (invoke-agent-turn!
        store registry authority catalog 'turn.driver 1 (add1 deadline)))
      'turn-timeout)
     (check-equal?
      (odra-agent-turn-state (inspect-agent-turn store 'turn.driver))
      'failed)
     (check-equal?
      (odra-agent-driver-session-state
       (inspect-agent-driver-session store 'session.driver))
      'available))))

(test-case "turn cancellation prevents late output publication"
  (with-fixture
   (lambda (_root store registry authority catalog _output cancelled _closed)
     (open-session store registry catalog)
     (prepare-turn store registry authority catalog)
     (define invocation
       (invoke-agent-turn! store registry authority catalog 'turn.driver 1 4))
     (define cancelled-turn
       (cancel-agent-turn! store registry 'turn.driver 2 5))
     (check-equal? (odra-agent-turn-state cancelled-turn) 'cancelled)
     (check-true (unbox cancelled))
     (check-equal?
      (odra-agent-driver-denial-code
       (finalize-agent-turn! store catalog invocation 'local.actor 6))
      'stale-turn))))

(test-case "driver replacement requires explicit session rebind"
  (with-fixture
   (lambda (_root store registry authority catalog output _cancelled closed)
     (open-session store registry catalog)
     (register-agent-driver!
      registry (test-driver 'example.driver 2 output))
     (define replaced
       (replace-agent-driver-session!
        store registry catalog 'session.driver 2 'example.driver 3))
     (check-equal? (odra-agent-driver-session-state replaced) 'available)
     (check-true (unbox closed))
     (check-equal?
      (odra-agent-driver-projection-generation
       (odra-agent-driver-session-driver-projection replaced))
      2))))

(test-case "provider loss blocks a turn without changing task identity"
  (with-fixture
   (lambda (_root store registry authority catalog output _cancelled _closed)
     (open-session store registry catalog)
     (define replacement-registry (make-agent-driver-registry))
     (register-agent-driver!
      replacement-registry (test-driver 'example.driver 2 output))
     (check-equal?
      (odra-agent-driver-denial-code
       (prepare-turn store replacement-registry authority catalog))
      'driver-replaced)
     (check-equal?
      (odra-agent-task-identity (inspect-agent-task store 'task.driver))
      "task.driver"))))

(test-case "turn limits reject excess context and provider usage"
  (with-fixture
   (lambda (_root store registry authority catalog output _cancelled _closed)
     (open-session store registry catalog)
     (check-equal?
      (odra-agent-driver-denial-code
       (prepare-agent-turn!
        store registry authority catalog 'turn.too-wide 'session.driver 2 1 3
        #:context-references
        (build-list
         (add1 maximum-agent-turn-context-references)
         (lambda (index)
           (make-agent-owner-reference
            'example.text 'example.text.region 1 index)))))
      'context-limit)
     (prepare-turn store registry authority catalog)
     (set-box!
      output
      (make-agent-turn-output
       (list (make-agent-turn-output-item 'progress '(status working)))
       #:usage
       (make-agent-turn-usage
        #:provider-events 4097 #:output-bytes 4096)))
     (define invocation
       (invoke-agent-turn! store registry authority catalog 'turn.driver 1 4))
     (define failed
       (finalize-agent-turn! store catalog invocation 'local.actor 5))
     (check-equal? (odra-agent-turn-state failed) 'failed))))

(test-case "failed output transaction rolls back every record"
  (define fail-publication? (box #f))
  (with-fixture
   (lambda (_root store registry authority catalog _output _cancelled _closed)
     (open-session store registry catalog)
     (prepare-turn store registry authority catalog)
     (define invocation
       (invoke-agent-turn! store registry authority catalog 'turn.driver 1 4))
     (set-box! fail-publication? #t)
     (check-exn
      #rx"injected turn publication failure"
      (lambda ()
        (finalize-agent-turn! store catalog invocation 'local.actor 5)))
     (check-equal? (inspect-agent-task-interactions store 'task.driver) '())
     (check-equal?
      (odra-agent-turn-state (inspect-agent-turn store 'turn.driver))
      'running))
   #:observer
   (lambda (kind _result)
     (when (and (unbox fail-publication?)
                (eq? kind 'publish-agent-turn-output))
       (error 'driver-test "injected turn publication failure")))))
