#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/agent/api.rkt"
         "../../src/agent/registry.rkt")

(define (agent identity)
  (make-agent identity #:interaction-kinds '(request result)))

(define (capability identity owner)
  (make-agent-capability identity owner (lambda (_context) (void))))

(test-case "catalog composition is deterministic and inspectable"
  (define second
    (make-agent-contribution-source
     "odra.second" "1.0.0" 4
     (list (agent 'odra.second.agent))
     (list (capability 'odra.second.capability 'odra.second))))
  (define first
    (make-agent-contribution-source
     "odra.first" "1.0.0" 2
     (list (agent 'odra.first.agent))
     (list (capability 'odra.first.capability 'odra.first))
     #:authorities '(project-read)))
  (define catalog (compose-agent-catalog 9 (list second first)))
  (check-equal?
   (map odra-agent-contribution-source-package-id
        (odra-agent-catalog-sources catalog))
   '("odra.first" "odra.second"))
  (check-equal?
   (map odra-agent-definition-projection-identity
        (odra-agent-catalog-agents catalog))
   '("odra.first.agent" "odra.second.agent"))
  (check-equal?
   (odra-agent-capability-projection-package-id
    (agent-catalog-capability-by-identity
     catalog "odra.second.capability"))
   "odra.second")
  (check-equal?
   (odra-agent-capability-projection-package-authorities
    (agent-catalog-capability-by-identity
     catalog "odra.first.capability"))
   '(project-read)))

(test-case "identity conflicts reject the complete candidate"
  (define confirmed
    (compose-agent-catalog
     2
     (list
      (make-agent-contribution-source
       "odra.first" "1.0.0" 1 (list (agent 'odra.shared)) '()))))
  (check-exn
   #rx"agent identities must be unique"
   (lambda ()
     (compose-agent-catalog
      3
      (list
       (make-agent-contribution-source
        "odra.first" "1.0.0" 1 (list (agent 'odra.shared)) '())
       (make-agent-contribution-source
        "odra.second" "1.0.0" 1 (list (agent 'odra.shared)) '())))))
  (check-equal? (odra-agent-catalog-generation confirmed) 2)
  (check-equal?
   (odra-agent-definition-projection-package-id
    (agent-catalog-agent-by-identity confirmed "odra.shared"))
   "odra.first"))

(test-case "replacement changes exact package generation"
  (define first
    (make-agent-contribution-source
     "odra.fixture" "1.0.0" 2 (list (agent 'odra.fixture.agent)) '()))
  (define replacement
    (make-agent-contribution-source
     "odra.fixture" "1.1.0" 3 (list (agent 'odra.fixture.agent)) '()))
  (define before (compose-agent-catalog 2 (list first)))
  (define after (compose-agent-catalog 3 (list replacement)))
  (check-equal?
   (odra-agent-definition-projection-package-version
    (agent-catalog-agent-by-identity before "odra.fixture.agent"))
   "1.0.0")
  (check-equal?
   (odra-agent-definition-projection-definition-generation
    (agent-catalog-agent-by-identity after "odra.fixture.agent"))
   3))

(test-case "empty catalog publishes an inspectable generation"
  (define catalog (empty-agent-catalog))
  (check-equal? (odra-agent-catalog-generation catalog) 1)
  (check-equal? (odra-agent-catalog-agents catalog) '())
  (check-equal? (odra-agent-catalog-capabilities catalog) '()))
