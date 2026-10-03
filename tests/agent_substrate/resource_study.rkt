#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require "../../src/agent/api.rkt"
         "../../src/agent/registry.rkt")

(define maximum-study-memory-bytes (* 128 1024 1024))

(collect-garbage)
(collect-garbage)
(define baseline-memory (current-memory-use))

(define ordinary-source
  (make-agent-contribution-source
   "odra.ordinary" "1.0.0" 1
   (list (make-agent 'odra.ordinary.agent))
   (list
    (make-agent-capability
     'odra.ordinary.observe 'odra.ordinary (lambda (_context) (void))))))
(define ordinary-catalog (compose-agent-catalog 1 (list ordinary-source)))
(define ordinary-memory
  (max 0 (- (current-memory-use) baseline-memory)))

(define agents
  (for/list ([index (in-range maximum-active-agent-definitions)])
    (make-agent
     (format "odra.study.agent.~a" index)
     #:display-name (format "Study Agent ~a" index)
     #:interaction-kinds '(progress request result)
     #:provider-requirements '(odra.agent-driver)
     #:requested-capabilities
     (list (format "odra.study.capability.~a" index)))))

(define capabilities
  (for/list ([index (in-range maximum-active-agent-capability-definitions)])
    (make-agent-capability
     (format "odra.study.capability.~a" index)
     'odra.study
     (lambda (_context) (void))
     #:input-schema
     '(record (target required (owner-reference odra.study.target 1)))
     #:result-schema '(record (accepted required boolean))
     #:target-kinds '(odra.study.target)
     #:effects '(observe))))

(define source
  (make-agent-contribution-source
   "odra.study" "1.0.0" 2 agents capabilities))
(define catalog (compose-agent-catalog 2 (list source)))
(define demanding-memory
  (max 0 (- (current-memory-use) baseline-memory)))

(define rejected?
  (with-handlers ([exn:fail? (lambda (_) #t)])
    (make-agent-contribution-source
     "odra.rejected" "1.0.0" 3
     (for/list ([index
                 (in-range (add1 maximum-active-agent-definitions))])
       (make-agent (format "odra.rejected.agent.~a" index)))
     '())
    #f))

(define valid?
  (and (= (length (odra-agent-catalog-agents ordinary-catalog)) 1)
       (= (length (odra-agent-catalog-capabilities ordinary-catalog)) 1)
       (= (length (odra-agent-catalog-agents catalog))
          maximum-active-agent-definitions)
       (= (length (odra-agent-catalog-capabilities catalog))
          maximum-active-agent-capability-definitions)
       (<= demanding-memory maximum-study-memory-bytes)
       rejected?))

(unless valid?
  (error 'agent-substrate-resource-study
         "definition scale or memory bounds were not satisfied"))

(printf
 "study=agent-substrate ordinary_agents=1 ordinary_capabilities=1 ordinary_memory_bytes=~a demanding_agents=~a demanding_capabilities=~a demanding_memory_bytes=~a memory_limit_bytes=~a rejected_over_limit=~a valid=~a\n"
 ordinary-memory
 (length (odra-agent-catalog-agents catalog))
 (length (odra-agent-catalog-capabilities catalog))
 demanding-memory
 maximum-study-memory-bytes
 rejected?
 valid?)
