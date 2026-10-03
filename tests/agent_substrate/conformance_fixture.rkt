#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require "../../src/agent/admission.rkt"
         "../../src/agent/api.rkt"
         "../../src/agent/authority.rkt"
         "../../src/agent/continuity.rkt"
         "../../src/agent/driver.rkt")

(provide package-id package-version contribution-generation package-authorities
         agent-definition capability-definition driver-definition
         target-reference target-registry request-input)

(define package-id "example.agent-conformance")
(define package-version "1.0.0")
(define contribution-generation 1)
(define package-authorities '(project-read))

(define agent-definition
  (make-agent
   'example.conformance.agent
   #:display-name "Example Conformance Agent"
   #:interaction-kinds '(progress result)
   #:provider-requirements '(odra.agent-driver)
   #:requested-capabilities '(example.conformance.observe)))

(define capability-definition
  (make-agent-capability
   'example.conformance.observe 'example.conformance
   (lambda (_context)
     (make-agent-capability-owner-result
      'succeeded
      #:result '((accepted #t))
      #:confirmed-effects '(observe)
      #:safe-summary "The example target was observed."))
   #:purpose "Observe one exact example target."
   #:input-schema
   '(record
     (target required (owner-reference example.conformance.target 1)))
   #:result-schema '(record (accepted required boolean))
   #:target-kinds '(example.conformance.target)
   #:effects '(observe)
   #:required-authorities '(project-read)
   #:idempotency-class 'read-only))

(define driver-definition
  (make-agent-driver
   'example.conformance.driver 1
   (lambda (_context)
     (odra-agent-driver-open-result 'provider.conformance #f))
   (lambda (_context)
     (make-agent-turn-output
      (list (make-agent-turn-output-item 'progress '(status ready)))
      #:usage
      (make-agent-turn-usage
       #:provider-events 1 #:input-bytes 64 #:output-bytes 4096)))
   (lambda (_turn) (void))
   (lambda (_session) (void))))

(define target-reference
  (make-agent-owner-reference
   'example.conformance 'example.conformance.target 1 "target.example"
   #:generation 1))

(define target-registry
  (let ([registry (make-agent-target-registry)])
    (register-agent-target-kind!
     registry
     (make-agent-target-kind-definition
      'example.conformance 'example.conformance.target 1
      (lambda (_reference) 'valid)
      (lambda (reference scope)
        (if (equal? (odra-agent-owner-reference-identity reference)
                    (odra-agent-target-scope-selector scope))
            'valid
            'outside-scope))
      #:source "Generic conformance fixture."))
    registry))

(define request-input
  (list (list 'target target-reference)))
