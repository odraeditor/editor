#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/command/personal.rkt"
         "../../src/hosting/personal-command-registry.rkt"
         (submod "../../src/hosting/personal-command-registry.rkt" test-support))

(define (definition name result)
  (make-command name (lambda (_context) result)))

  (test-case "prepared procedures activate by generation"
  (define registry (make-personal-command-registry))
  (define candidate
    (personal-command-prepare
     registry 2
     (list (definition 'first-command 'first)
           (definition 'second-command 'second))))
  (check-equal? (personal-command-generation-state candidate) 'prepared)
  (check-equal? (personal-command-registry-retained-generations registry) 1)
  (define route
    (personal-command-route-by-name candidate "second-command"))
  (check-equal? (personal-command-route-slot route) 2)
  (personal-command-activate! registry candidate)
  (check-equal? (personal-command-registry-active-generation registry) 2)
  (check-eq?
   (call-with-personal-command-procedure
    registry route (lambda (procedure) (procedure #f)))
   'second))

  (test-case "replacement releases idle generations"
  (define registry (make-personal-command-registry))
  (define first
    (personal-command-prepare registry 2 (list (definition 'shared-command 'first))))
  (define first-route (car (personal-command-generation-routes first)))
  (personal-command-activate! registry first)
  (define second
    (personal-command-prepare registry 3 (list (definition 'shared-command 'second))))
  (define second-route (car (personal-command-generation-routes second)))
  (personal-command-activate! registry second)
  (check-equal? (personal-command-generation-state first) 'closed)
  (check-equal? (personal-command-registry-retained-generations registry) 1)
  (define stale
    (call-with-personal-command-procedure registry first-route values))
  (check-true (personal-command-route-failure? stale))
  (check-eq? (personal-command-route-failure-code stale) 'stale-generation)
  (check-eq?
   (call-with-personal-command-procedure
    registry second-route (lambda (procedure) (procedure #f)))
   'second))

  (test-case "active turn delays retirement"
  (define registry (make-personal-command-registry))
  (define first
    (personal-command-prepare registry 2 (list (definition 'nested-command 'first))))
  (define route (car (personal-command-generation-routes first)))
  (personal-command-activate! registry first)
  (call-with-personal-command-procedure
   registry route
   (lambda (procedure)
     (define second
       (personal-command-prepare
        registry 3 (list (definition 'replacement-command 'second))))
     (personal-command-activate! registry second)
     (check-equal? (personal-command-generation-state first) 'retiring)
     (check-equal? (personal-command-generation-turns first) 1)
     (check-eq? (procedure #f) 'first)))
  (check-equal? (personal-command-generation-state first) 'closed)
  (check-equal? (personal-command-registry-retained-generations registry) 1))

  (test-case "discard and faults release candidate roots"
  (define registry (make-personal-command-registry))
  (define discarded
    (personal-command-prepare registry 2 (list (definition 'discarded-command 'unused))))
  (personal-command-discard! registry discarded)
  (check-equal? (personal-command-generation-state discarded) 'closed)
  (check-equal? (personal-command-registry-retained-generations registry) 0)

  (check-exn
   #rx"simulated allocation failure"
   (lambda ()
     (parameterize
         ([current-personal-command-storage-builder
           (lambda (_generation _definitions)
             (error 'registry-test "simulated allocation failure"))])
       (personal-command-prepare
        registry 3 (list (definition 'failed-command 'unused))))))
  (check-equal? (personal-command-registry-retained-generations registry) 0)

  (define active
    (personal-command-prepare registry 4 (list (definition 'active-command 'active))))
  (personal-command-activate! registry active)
  (personal-command-registry-close! registry)
  (check-equal? (personal-command-generation-state active) 'closed)
  (check-false (personal-command-registry-active-generation registry))
  (check-equal? (personal-command-registry-retained-generations registry) 0)
  (check-exn #rx"registry is closed"
             (lambda ()
               (personal-command-prepare
                registry 5 (list (definition 'late-command 'late))))))
