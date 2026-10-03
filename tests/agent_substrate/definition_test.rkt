#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/agent/api.rkt"
         "../../src/agent/definition.rkt")

(test-case "agent definitions remain inert"
  (define entered? #f)
  (define agent
    (make-agent
     'odra.canary
     #:display-name "Canary"
     #:description "Deterministic conformance agent."
     #:interaction-kinds '(progress request result)
     #:provider-requirements '(odra.agent-driver)
     #:requested-capabilities '(odra.rot13.region)
     #:continuation-policy 'bounded))
  (define capability
    (make-agent-capability
     'odra.rot13.region 'odra.rot13
     (lambda (_context) (set! entered? #t))
     #:purpose "Transform one selected region."
     #:input-schema
     '(record (region required (owner-reference odra.buffer-region 1)))
     #:result-schema
     '(record (revision required (integer 0 9223372036854775807)))
     #:target-kinds '(odra.buffer-region)
     #:effects '(mutate-editor-state)
     #:required-authorities '(odra.buffer-edit)
     #:approval-class 'ask-once
     #:idempotency-class 'idempotent
     #:verification-class 'immediate))
  (check-true (agent? agent))
  (check-true (agent-capability? capability))
  (check-false entered?)
  (check-equal? (odra-agent-definition-identity agent) "odra.canary")
  (check-equal?
   (odra-agent-capability-definition-identity capability)
   "odra.rot13.region"))

(test-case "schemas accept only bounded inert structural data"
  (check-true (agent-schema? 'boolean))
  (check-true
   (agent-schema?
    '(record
      (count required (integer 0 64))
      (label optional (string 256))
      (targets required (list 8 (owner-reference odra.node 1))))))
  (check-false
   (agent-schema?
    '(record
      (label required (string 256))
      (count required (integer 0 64)))))
  (check-false (agent-schema? '(procedure arbitrary)))
  (check-false (agent-schema? '(string 65537))))

(test-case "definitions reject authority and resource overreach"
  (check-exn
   #rx"invalid bounded agent resource profile"
   (lambda ()
     (make-agent-resource-profile
      #:turn-deadline-milliseconds (add1 (* 15 60 1000)))))
  (check-exn
   #rx"invalid bounded capability limits"
   (lambda ()
     (make-agent-capability-limits #:target-references 33)))
  (check-exn
   #rx"invalid bounded agent capability definition"
   (lambda ()
     (make-agent-capability
      'odra.bad 'odra.fixture (lambda (_context) (void))
      #:effects '(unknown-effect)))))
