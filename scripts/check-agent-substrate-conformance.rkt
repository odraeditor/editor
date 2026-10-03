#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/cmdline
         racket/contract/base
         racket/file
         "../src/agent/admission.rkt"
         "../src/agent/authority.rkt"
         "../src/agent/continuity.rkt"
         "../src/agent/definition.rkt"
         "../src/agent/driver.rkt"
         "../src/agent/execution.rkt"
         "../src/agent/registry.rkt")

(provide
 (contract-out
  [run-agent-substrate-conformance
   (-> path-string? (listof symbol?))]))

(define required-exports
  '(package-id package-version contribution-generation package-authorities
    agent-definition capability-definition driver-definition
    target-reference target-registry request-input))

(define (load-fixture path)
  (define module-path (path->complete-path path))
  (for/hash ([name (in-list required-exports)])
    (values name (dynamic-require module-path name))))

(define (ensuref condition message . arguments)
  (unless condition
    (raise-user-error
     'agent-substrate-conformance
     (apply format message arguments))))

(define (run-agent-substrate-conformance fixture-path)
  (define fixture (load-fixture fixture-path))
  (define package-id (hash-ref fixture 'package-id))
  (define package-version (hash-ref fixture 'package-version))
  (define generation (hash-ref fixture 'contribution-generation))
  (define package-authorities (hash-ref fixture 'package-authorities))
  (define agent-definition (hash-ref fixture 'agent-definition))
  (define capability-definition (hash-ref fixture 'capability-definition))
  (define driver-definition (hash-ref fixture 'driver-definition))
  (define target-reference (hash-ref fixture 'target-reference))
  (define target-registry (hash-ref fixture 'target-registry))
  (define request-input (hash-ref fixture 'request-input))

  (ensuref (and (string? package-id) (string? package-version)
                (exact-positive-integer? generation)
                (list? package-authorities))
           "package identity, version, generation, or authorities are invalid")
  (ensuref (odra-agent-definition? agent-definition)
           "agent-definition is not an agent definition")
  (ensuref (odra-agent-capability-definition? capability-definition)
           "capability-definition is not a capability definition")
  (ensuref (odra-agent-driver-definition? driver-definition)
           "driver-definition is not a driver definition")
  (ensuref (odra-agent-owner-reference? target-reference)
           "target-reference is not an owner reference")
  (ensuref (odra-agent-target-registry? target-registry)
           "target-registry is not a target registry")

  (define catalog
    (compose-agent-catalog
     generation
     (list
      (make-agent-contribution-source
       package-id package-version generation
       (list agent-definition) (list capability-definition)
       #:authorities package-authorities))))
  (define agent-identity
    (odra-agent-definition-identity agent-definition))
  (define capability-identity
    (odra-agent-capability-definition-identity capability-definition))
  (define agent
    (agent-catalog-agent-by-identity catalog agent-identity))
  (define capability
    (agent-catalog-capability-by-identity catalog capability-identity))
  (ensuref agent "agent definition did not enter the catalog")
  (ensuref capability "capability definition did not enter the catalog")
  (ensuref
   (member capability-identity
           (odra-agent-definition-projection-requested-capabilities agent)
           string=?)
   "agent does not request the fixture capability")

  (define drivers (make-agent-driver-registry))
  (define registered-driver
    (register-agent-driver! drivers driver-definition))
  (ensuref (odra-agent-driver-projection? registered-driver)
           "driver definition was rejected: ~s" registered-driver)

  (define root
    (make-temporary-file "odra-agent-conformance-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define store (open-agent-continuity-store root))
      (define authority (make-agent-authority-store))
      (define task
        (create-agent-task!
         store 'conformance.task "Run the generic conformance workflow."
         (make-agent-task-origin 'local-user 'conformance.actor) 1
         #:owner-agent agent-identity))
      (ensuref (odra-agent-task? task)
               "agent task was rejected: ~s" task)

      (define effects
        (odra-agent-capability-projection-effects capability))
      (define required-authorities
        (odra-agent-capability-projection-required-authorities capability))
      (define policy-authorities
        (map string->symbol required-authorities))
      (define limits
        (odra-agent-capability-projection-default-limits capability))
      (define grant
        (grant-agent-capability!
         authority catalog
         (make-agent-grant-request
          'conformance.grant agent-identity generation
          capability-identity generation
          (make-agent-target-scope
           (odra-agent-owner-reference-owner-namespace target-reference)
           (odra-agent-owner-reference-kind target-reference)
           (odra-agent-owner-reference-identity target-reference))
          (make-agent-authority-origin 'local-user 'conformance.actor)
          1
          #:effects effects
          #:limits limits
          #:task-restriction 'conformance.task
          #:valid-until 10000)
         (make-agent-authority-policy
          #:effects effects
          #:authorities policy-authorities
          #:limit-ceiling
          (odra-agent-capability-projection-hard-limits capability)
          #:maximum-validity-milliseconds 10000
          #:source "Generic agent substrate conformance runner.")
         1))
      (ensuref (odra-agent-capability-grant? grant)
               "capability grant was rejected: ~s" grant)

      (define session
        (open-agent-driver-session!
         store drivers catalog 'conformance.session
         (make-agent-record-reference
          'agent-registration agent-identity generation)
         'conformance.task 1 agent-identity
         (odra-agent-driver-definition-identity driver-definition) 2))
      (ensuref (odra-agent-driver-session? session)
               "driver session was rejected: ~s" session)
      (define prepared-turn
        (prepare-agent-turn!
         store drivers authority catalog 'conformance.turn
         'conformance.session 2 1 3))
      (ensuref (odra-agent-turn? prepared-turn)
               "agent turn was rejected: ~s" prepared-turn)
      (define turn-invocation
        (invoke-agent-turn!
         store drivers authority catalog 'conformance.turn 1 4))
      (ensuref (odra-agent-turn-invocation? turn-invocation)
               "driver invocation was rejected: ~s" turn-invocation)
      (define completed-turn
        (finalize-agent-turn!
         store catalog turn-invocation 'conformance.actor 5))
      (ensuref
       (and (odra-agent-turn? completed-turn)
            (eq? (odra-agent-turn-state completed-turn) 'completed))
       "driver output failed conformance: ~s" completed-turn)

      (define request
        (make-agent-capability-request
         'conformance.request 'conformance.task 1 agent-identity generation
         (make-agent-record-reference
          'agent-registration agent-identity generation)
         capability-identity generation
         (make-agent-package-reference package-id package-version generation)
         (make-agent-schema-reference capability-identity generation 'input 1)
         request-input effects limits
         (list
          (make-agent-record-reference
           'capability-grant
           (odra-agent-capability-grant-identity grant)
           (odra-agent-capability-grant-generation grant)))
         6 10000
         #:target-references (list target-reference)
         #:correlation-id 'conformance.turn
         #:idempotency-id 'conformance.operation))
      (define recorded-request
        (record-agent-capability-request! store request))
      (ensuref (odra-agent-capability-request? recorded-request)
               "capability request was rejected: ~s" recorded-request)
      (define decision
        (decide-agent-capability-request!
         store authority catalog target-registry
         'conformance.request 'conformance.decision
         (make-agent-admission-policy
          'conformance.policy 1
          #:admitted-effects effects
          #:maximum-request-validity-milliseconds 10000
          #:source "Generic agent substrate conformance runner.")
         7))
      (ensuref
       (and (odra-agent-admission-decision? decision)
            (eq? (odra-agent-admission-decision-state decision) 'admitted))
       "capability request failed admission: ~s" decision)

      (define attempt
        (prepare-agent-capability-attempt!
         store 'conformance.attempt 'conformance.request
         'conformance.decision 'conformance.lease 8))
      (ensuref (odra-agent-operation-attempt? attempt)
               "capability attempt was rejected: ~s" attempt)
      (define invocation
        (invoke-agent-capability-owner!
         store catalog 'conformance.attempt 1 9))
      (ensuref (odra-agent-capability-invocation? invocation)
               "capability owner invocation was rejected: ~s" invocation)
      (define result
        (finalize-agent-capability-attempt!
         store catalog invocation 'conformance.result 10))
      (ensuref
       (and (odra-agent-operation-result? result)
            (eq? (odra-agent-operation-result-state result) 'succeeded))
       "capability owner output failed conformance: ~s" result)

      (close-agent-continuity-store! store)
      (define reopened (open-agent-continuity-store root))
      (ensuref (odra-agent-task?
                (inspect-agent-task reopened 'conformance.task))
               "task did not survive store reload")
      (ensuref (odra-agent-driver-session?
                (inspect-agent-driver-session reopened 'conformance.session))
               "driver session did not survive store reload")
      (ensuref (odra-agent-operation-result?
                (inspect-agent-operation-result reopened 'conformance.result))
               "capability result did not survive store reload")
      (close-agent-continuity-store! reopened))
    (lambda () (delete-directory/files root)))

  '(agent-definition driver capability-owner admission execution reload))

(module+ main
  (define fixture-path #f)
  (command-line
   #:program "check-agent-substrate-conformance.rkt"
   #:once-each
   [("--fixture") path "Agent substrate conformance fixture module"
                    (set! fixture-path path)]
   #:args () (void))
  (unless fixture-path
    (raise-user-error
     'agent-substrate-conformance "--fixture is required"))
  (define cases (run-agent-substrate-conformance fixture-path))
  (printf "agent-substrate-conformance: pass cases=~a\n" (length cases)))

(module+ test
  (require racket/runtime-path
           rackunit)
  (define-runtime-path fixture
    "../tests/agent_substrate/conformance_fixture.rkt")
  (check-equal?
   (run-agent-substrate-conformance fixture)
   '(agent-definition driver capability-owner admission execution reload)))
