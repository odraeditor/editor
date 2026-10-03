#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require "../../src/agent/authority.rkt"
         "../../src/agent/definition.rkt"
         "../../src/agent/registry.rkt")

(define catalog
  (compose-agent-catalog
   1
   (list
    (make-agent-contribution-source
     "odra.authority-study" "1.0.0" 1
     (list
      (make-agent
       'odra.authority-study.agent
       #:requested-capabilities '(odra.authority-study.observe)))
     (list
      (make-agent-capability
       'odra.authority-study.observe 'odra.authority-study
       (lambda (_context) (void))
       #:target-kinds '(odra.authority-study.target)
       #:effects '(observe)))
     #:authorities '()))))

(define scope
  (make-agent-target-scope
   'odra.authority-study 'odra.authority-study.target "all"))
(define origin
  (make-agent-authority-origin 'local-policy 'odra.authority-study.policy))
(define policy
  (make-agent-authority-policy
   #:effects '(observe)
   #:maximum-validity-milliseconds 100000
   #:source "Authority resource study."))
(define store (make-agent-authority-store))

(collect-garbage)
(collect-garbage)
(define baseline-memory (current-memory-use))
(define started (current-inexact-milliseconds))

(for ([index (in-range maximum-retained-nonexpired-agent-grants)])
  (define result
    (grant-agent-capability!
     store catalog
     (make-agent-grant-request
      (format "odra.authority-study.grant.~a" index)
      'odra.authority-study.agent 1 "odra.authority-study.observe" 1
      scope origin 0 #:effects '(observe) #:valid-until 100000)
     policy 1))
  (unless (odra-agent-capability-grant? result)
    (error 'authority-resource-study "grant publication failed at ~a" index)))

(define rejected
  (grant-agent-capability!
   store catalog
   (make-agent-grant-request
    'odra.authority-study.grant.over-limit
    'odra.authority-study.agent 1 "odra.authority-study.observe" 1
    scope origin 0 #:effects '(observe) #:valid-until 100000)
   policy 1))
(define elapsed (- (current-inexact-milliseconds) started))
(define memory (max 0 (- (current-memory-use) baseline-memory)))
(define retained (length (inspect-agent-grants store #:at 1)))
(define valid?
  (and (= retained maximum-retained-nonexpired-agent-grants)
       (odra-agent-authority-denial? rejected)
       (eq? (odra-agent-authority-denial-code rejected) 'grant-limit)))

(unless valid?
  (error 'authority-resource-study "grant limit was not enforced"))

(printf
 "study=agent-authority retained=~a limit=~a over_limit=~a elapsed_ms=~a memory_bytes=~a valid=~a\n"
 retained maximum-retained-nonexpired-agent-grants
 (odra-agent-authority-denial-code rejected)
 (inexact->exact (round elapsed)) memory valid?)
