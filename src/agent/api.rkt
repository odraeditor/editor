#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require "definition.rkt"
         "execution.rkt")

(provide
 agent-substrate-api-version
 make-agent-resource-profile
 agent-resource-profile?
 make-agent-capability-limits
 agent-capability-limits?
 default-agent-resource-profile
 default-agent-capability-limits
 make-agent
 agent?
 make-agent-capability
 agent-capability?
 agent-schema?
 make-agent-capability-owner-result
 agent-capability-owner-result?
 agent-capability-execution-context?
 agent-capability-execution-context-attempt-id
 agent-capability-execution-context-request-id
 agent-capability-execution-context-task-id
 agent-capability-execution-context-agent-identity
 agent-capability-execution-context-capability-identity
 agent-capability-execution-context-input
 agent-capability-execution-context-target-references
 agent-capability-execution-context-admitted-effects
 agent-capability-execution-context-effective-limits
 agent-capability-execution-context-deadline
 agent-capability-cancellation-requested?
 agent-capability-invoke-operation!)

(define agent-resource-profile? odra-agent-resource-profile?)
(define agent-capability-limits? odra-agent-capability-limits?)
(define agent-capability-owner-result? odra-agent-capability-owner-result?)
(define agent-capability-execution-context?
  odra-agent-capability-execution-context?)
(define agent-capability-execution-context-attempt-id
  odra-agent-capability-execution-context-attempt-id)
(define agent-capability-execution-context-request-id
  odra-agent-capability-execution-context-request-id)
(define agent-capability-execution-context-task-id
  odra-agent-capability-execution-context-task-id)
(define agent-capability-execution-context-agent-identity
  odra-agent-capability-execution-context-agent-identity)
(define agent-capability-execution-context-capability-identity
  odra-agent-capability-execution-context-capability-identity)
(define agent-capability-execution-context-input
  odra-agent-capability-execution-context-input)
(define agent-capability-execution-context-target-references
  odra-agent-capability-execution-context-target-references)
(define agent-capability-execution-context-admitted-effects
  odra-agent-capability-execution-context-admitted-effects)
(define agent-capability-execution-context-effective-limits
  odra-agent-capability-execution-context-effective-limits)
(define agent-capability-execution-context-deadline
  odra-agent-capability-execution-context-deadline)

(define (agent-capability-cancellation-requested? context)
  (unless (odra-agent-capability-execution-context? context)
    (raise-argument-error
     'agent-capability-cancellation-requested?
     "agent-capability-execution-context?" context))
  ((odra-agent-capability-execution-context-cancellation-requested? context)))

(define (agent-capability-invoke-operation! context identity)
  (invoke-agent-capability-operation! context identity))
