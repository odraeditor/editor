#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/agent/authority.rkt"
         "../../src/agent/definition.rkt"
         "../../src/agent/registry.rkt")

(define handler-entered? #f)

(define (capability identity authority effects)
  (make-agent-capability
   identity 'example.text
   (lambda (_context) (set! handler-entered? #t))
   #:purpose (format "Exercise ~a." identity)
   #:input-schema
   '(record (target required (owner-reference example.text.region 1)))
   #:result-schema '(record (accepted required boolean))
   #:target-kinds '(example.text.region)
   #:effects effects
   #:required-authorities (list authority)))

(define (fixture-catalog #:authorities [authorities '(project-read project-write)])
  (define source
    (make-agent-contribution-source
     "example.integration" "1.0.0" 7
     (list
      (make-agent
       'example.agent
       #:requested-capabilities '(example.observe example.write))
      (make-agent
       'example.other-agent
       #:requested-capabilities '(example.observe)))
     (list
      (capability 'example.observe 'project-read '(filesystem-read observe))
      (capability
       'example.write 'project-write
       '(filesystem-write mutate-editor-state)))
     #:authorities authorities))
  (compose-agent-catalog 7 (list source)))

(define scope
  (make-agent-target-scope
   'example.text 'example.text.region "project.notes"))

(define origin
  (make-agent-authority-origin 'local-user 'local.actor))

(define policy
  (make-agent-authority-policy
   #:effects '(filesystem-read filesystem-write observe)
   #:authorities '(project-read project-write)
   #:limit-ceiling
   (make-agent-capability-limits
    #:deadline-milliseconds 10000
    #:input-bytes 4096
    #:result-bytes 8192
    #:target-references 2)
   #:maximum-validity-milliseconds 50000
   #:maximum-delegation-depth 1
   #:source "Test policy."))

(define (request identity
                 #:agent [agent "example.agent"]
                 #:agent-generation [agent-generation 7]
                 #:capability [capability-pattern "example.observe"]
                 #:capability-generation [capability-generation 7]
                 #:effects [effects '(filesystem-read observe)]
                 #:target-scope [target-scope scope]
                 #:valid-from [valid-from 0]
                 #:valid-until [valid-until 100000]
                 #:delegation-depth [delegation-depth 3])
  (make-agent-grant-request
   identity agent agent-generation capability-pattern capability-generation
   target-scope origin valid-from
   #:effects effects
   #:delegation-depth delegation-depth
   #:valid-until valid-until))

(test-case "discovery returns inert metadata and deny-by-default state"
  (set! handler-entered? #f)
  (define discovered
    (discover-agent-capabilities
     (fixture-catalog) (make-agent-authority-store) "example.agent" #:at 10))
  (check-equal?
   (map odra-agent-capability-discovery-identity discovered)
   '("example.observe" "example.write"))
  (check-true
   (andmap
    (lambda (entry)
      (eq? (odra-agent-capability-discovery-grant-state entry) 'ungranted))
    discovered))
  (check-false handler-entered?)
  (check-equal?
   (discover-agent-capabilities
    (fixture-catalog) (make-agent-authority-store) "example.absent")
   '()))

(test-case "effective grants intersect every authority and resource ceiling"
  (define catalog (fixture-catalog))
  (define store (make-agent-authority-store))
  (define grant
    (grant-agent-capability!
     store catalog (request 'grant.observe) policy 10))
  (check-true (odra-agent-capability-grant? grant))
  (check-equal? (odra-agent-capability-grant-effects grant)
                '(filesystem-read observe))
  (check-equal?
   (odra-agent-capability-limits-deadline-milliseconds
    (odra-agent-capability-grant-limits grant))
   10000)
  (check-equal?
   (odra-agent-capability-limits-target-references
    (odra-agent-capability-grant-limits grant))
   2)
  (check-equal? (odra-agent-capability-grant-valid-until grant) 50000)
  (check-equal? (odra-agent-capability-grant-delegation-depth grant) 1)
  (check-true (agent-capability-grant-effective? catalog grant 10))
  (define discovered
    (discover-agent-capabilities catalog store "example.agent" #:at 10))
  (check-equal?
   (odra-agent-capability-discovery-grant-state (car discovered))
   'granted)
  (check-equal? (odra-agent-capability-discovery-active-grants
                 (car discovered))
                1)
  (check-equal?
   (inspect-agent-grants store #:agent "example.other-agent" #:at 10)
   '()))

(test-case "broader policy never widens the explicit grant"
  (define broad-policy
    (make-agent-authority-policy
     #:effects '(filesystem-read observe)
     #:authorities '(project-read)
     #:maximum-validity-milliseconds 100000))
  (define grant
    (grant-agent-capability!
     (make-agent-authority-store) (fixture-catalog)
     (request 'grant.narrow #:effects '(observe)) broad-policy 1))
  (check-true (odra-agent-capability-grant? grant))
  (check-equal? (odra-agent-capability-grant-effects grant) '(observe)))

(test-case "default policy and missing package authority deny grants"
  (define denied
    (grant-agent-capability!
     (make-agent-authority-store) (fixture-catalog)
     (request 'grant.denied) default-agent-authority-policy 1))
  (check-equal? (odra-agent-authority-denial-code denied) 'policy-authority)
  (define missing-authority
    (grant-agent-capability!
     (make-agent-authority-store)
     (fixture-catalog #:authorities '(project-write))
     (request 'grant.package-authority) policy 1))
  (check-equal?
   (odra-agent-authority-denial-code missing-authority)
   'package-authority))

(test-case "absent stale ambiguous and cross-agent grants are rejected"
  (define catalog (fixture-catalog))
  (define (denial-code candidate)
    (odra-agent-authority-denial-code
     (grant-agent-capability!
      (make-agent-authority-store) catalog candidate policy 1)))
  (check-equal?
   (denial-code (request 'grant.stale-agent #:agent-generation 6))
   'stale-agent)
  (check-equal?
   (denial-code (request 'grant.stale-capability #:capability-generation 6))
   'stale-capability)
  (check-equal?
   (denial-code (request 'grant.ambiguous #:capability "example.*"))
   'ambiguous-capability)
  (check-equal?
   (denial-code
    (request 'grant.cross-agent
             #:agent "example.other-agent"
             #:capability "example.write"))
   'absent-capability))

(test-case "malformed and cross-owner scopes are rejected"
  (check-exn
   #rx"invalid bounded inert scope selector"
   (lambda ()
     (make-agent-target-scope 'example.text 'example.text.region '())))
  (check-exn
   #rx"invalid bounded inert scope selector"
   (lambda ()
     (make-agent-target-scope
      'example.text 'example.text.region (make-string 4097 #\x))))
  (check-exn
   #rx"invalid bounded inert scope selector"
   (lambda ()
     (make-agent-target-scope
      'example.text 'example.text.region (expt 2 64))))
  (define cross-owner
    (make-agent-target-scope
     'example.other 'example.text.region "project.notes"))
  (define denied
    (grant-agent-capability!
     (make-agent-authority-store) (fixture-catalog)
     (request 'grant.cross-owner #:target-scope cross-owner) policy 1))
  (check-equal? (odra-agent-authority-denial-code denied) 'invalid-scope))

(test-case "expiry and revocation remove effective authority immediately"
  (define catalog (fixture-catalog))
  (define store (make-agent-authority-store))
  (define grant
    (grant-agent-capability!
     store catalog (request 'grant.lifecycle) policy 10))
  (check-true (agent-capability-grant-effective? catalog grant 49999))
  (check-false (agent-capability-grant-effective? catalog grant 50000))
  (check-equal?
   (odra-agent-grant-projection-state
    (car (inspect-agent-grants store #:at 50000)))
   'expired)

  (define revocation-store (make-agent-authority-store))
  (define revocable
    (grant-agent-capability!
     revocation-store catalog (request 'grant.revocable) policy 10))
  (define revoked
    (revoke-agent-capability-grant!
     revocation-store "grant.revocable" 1 "User revoked access." 20))
  (check-true (odra-agent-capability-grant? revoked))
  (check-equal? (odra-agent-capability-grant-generation revoked) 2)
  (check-false (agent-capability-grant-effective? catalog revoked 20))
  (check-equal?
   (odra-agent-capability-discovery-grant-state
    (car
     (discover-agent-capabilities
      catalog revocation-store "example.agent" #:at 20)))
   'revoked)
  (check-equal?
   (odra-agent-authority-denial-code
    (revoke-agent-capability-grant!
     revocation-store "grant.revocable" 1 "Stale request." 21))
   'stale-grant))

(test-case "catalog replacement invalidates cross-generation authority"
  (define first-catalog (fixture-catalog))
  (define store (make-agent-authority-store))
  (define grant
    (grant-agent-capability!
     store first-catalog (request 'grant.generation) policy 10))
  (define replacement-source
    (make-agent-contribution-source
     "example.integration" "1.1.0" 8
     (list
      (make-agent
       'example.agent
       #:requested-capabilities '(example.observe)))
     (list
      (capability 'example.observe 'project-read '(filesystem-read observe)))
     #:authorities '(project-read)))
  (define replacement-catalog
    (compose-agent-catalog 8 (list replacement-source)))
  (check-true (agent-capability-grant-effective? first-catalog grant 10))
  (check-false
   (agent-capability-grant-effective? replacement-catalog grant 10)))

(test-case "publication failure preserves the confirmed grant set"
  (define store
    (make-agent-authority-store #:publisher (lambda (_candidate) #f)))
  (define denied
    (grant-agent-capability!
     store (fixture-catalog) (request 'grant.allocation-fault) policy 1))
  (check-equal?
   (odra-agent-authority-denial-code denied)
   'publication-failure)
  (check-equal? (inspect-agent-grants store #:at 1) '()))
