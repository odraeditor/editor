#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         "personal-command-registry.rkt"
         "../command/catalog.rkt"
         "../command/keymaps.rkt"
         "../command/personal.rkt"
         "../command/personal-inspection.rkt"
         "personal-command-containment.rkt")

(provide
 (contract-out
  [personal-command-runtime-prepare!
   (->* (exact-positive-integer? list? (or/c #f odra-interaction-profile?))
        (list?) void?)]
  [personal-command-runtime-catalog
   (-> exact-positive-integer? odra-command-catalog?)]
  [personal-command-runtime-profile-catalog
   (-> exact-positive-integer? odra-interaction-profile-catalog?)]
  [personal-command-runtime-activate! (-> exact-positive-integer? void?)]
  [personal-command-runtime-discard! (-> exact-positive-integer? void?)]
  [personal-command-runtime-call
   (-> exact-positive-integer? exact-positive-integer? string? procedure? any/c)]
  [personal-command-runtime-note-rejection!
   (-> exact-positive-integer? string? void?)]
  [personal-command-runtime-inspection (-> personal-command-inspection?)]
  [personal-command-runtime-reset! (-> void?)]))

(define registry (make-personal-command-registry))
(define active-catalog (factory-command-catalog))
(define active-profile-catalog (factory-interaction-profile-catalog 1))
(define pending-generation #f)
(define pending-command-generation #f)
(define pending-catalog #f)
(define pending-profile-catalog #f)
(define rejected-generation 0)
(define latest-rejection "")

;; personal-command-runtime-prepare! retains one unpublished compatible candidate.
(define (personal-command-runtime-prepare! generation definitions profile
                                           [ksawery-definitions '()])
  (unless (and (list? definitions) (andmap command? definitions))
    (raise-argument-error
     'personal-command-runtime-prepare! "a list of personal commands" definitions))
  (when pending-generation
    (personal-command-runtime-discard! pending-generation))
  (define command-generation
    (personal-command-prepare registry generation definitions))
  (with-handlers ([exn?
                   (lambda (failure)
                     (personal-command-discard! registry command-generation)
                     (raise failure))])
    (define catalog
      (if (and (null? definitions) (null? ksawery-definitions))
          (factory-command-catalog)
          (compose-personal-command-catalog
           generation definitions ksawery-definitions)))
    (define profile-catalog
      (personal-interaction-profile-catalog generation profile))
    (set! pending-generation generation)
    (set! pending-command-generation command-generation)
    (set! pending-catalog catalog)
    (set! pending-profile-catalog profile-catalog))
  (void))

;; personal-command-runtime-catalog returns only an exact prepared or active generation.
(define (personal-command-runtime-catalog generation)
  (cond
    [(equal? generation pending-generation) pending-catalog]
    [(equal? generation (personal-command-registry-active-generation registry))
     active-catalog]
    [else (factory-command-catalog)]))

(define (personal-command-runtime-profile-catalog generation)
  (cond
    [(equal? generation pending-generation) pending-profile-catalog]
    [(equal? generation (personal-command-registry-active-generation registry))
     active-profile-catalog]
    [else (interaction-profile-catalog-candidate generation)]))

(define (personal-command-runtime-activate! generation)
  (unless (and (equal? generation pending-generation)
               pending-command-generation pending-catalog pending-profile-catalog)
    (raise-arguments-error
     'personal-command-runtime-activate!
     "personal command generation is not prepared"
     "generation" generation))
  (personal-command-activate! registry pending-command-generation)
  (set! active-catalog pending-catalog)
  (set! active-profile-catalog pending-profile-catalog)
  (clear-pending!)
  (void))

(define (personal-command-runtime-discard! generation)
  (unless (equal? generation pending-generation)
    (raise-arguments-error
     'personal-command-runtime-discard!
     "personal command generation is not prepared"
     "generation" generation))
  (personal-command-discard! registry pending-command-generation)
  (clear-pending!)
  (void))

(define (clear-pending!)
  (set! pending-generation #f)
  (set! pending-command-generation #f)
  (set! pending-catalog #f)
  (set! pending-profile-catalog #f))

(define (personal-command-runtime-call generation slot name command)
  (personal-command-runtime-call-result
   (call-with-personal-command-slot registry generation slot name command)))

(define (personal-command-runtime-note-rejection! generation diagnostic)
  (set! rejected-generation generation)
  (set! latest-rejection diagnostic)
  (void))

(define (personal-command-runtime-inspection)
  (compose-personal-command-inspection
   (or (personal-command-registry-active-generation registry) 1)
   rejected-generation latest-rejection active-catalog active-profile-catalog
   (personal-command-last-turn)))

(define (personal-command-runtime-call-result result)
  (when (personal-command-route-failure? result)
    (raise-arguments-error
     'personal-command-runtime-call
     "personal command route is unavailable"
     "code" (personal-command-route-failure-code result)
     "expected" (personal-command-route-failure-expected result)
     "actual" (personal-command-route-failure-actual result)))
  result)

(define (personal-command-runtime-reset!)
  (personal-command-registry-close! registry)
  (set! registry (make-personal-command-registry))
  (set! active-catalog (factory-command-catalog))
  (set! active-profile-catalog (factory-interaction-profile-catalog 1))
  (set! rejected-generation 0)
  (set! latest-rejection "")
  (clear-pending!)
  (void))

(module+ test
  (require rackunit)

  (personal-command-runtime-reset!)
  (personal-command-runtime-prepare!
   9
   (list (make-command 'runtime-command (lambda (_context) 'called)))
   #f)
  (define catalog (personal-command-runtime-catalog 9))
  (check-equal? (length (odra-command-catalog-definitions catalog)) 8)
  (check-exn #rx"unavailable"
             (lambda ()
               (personal-command-runtime-call
                9 1 "runtime-command" (lambda (_implementation) (void)))))
  (personal-command-runtime-activate! 9)
  (define active-inspection (personal-command-runtime-inspection))
  (check-equal?
   (personal-command-inspection-active-generation active-inspection) 9)
  (check-equal?
   (map personal-command-inspection-entry-name
        (personal-command-inspection-commands active-inspection))
   '("runtime-command"))
  (check-equal?
   (personal-command-runtime-call 9 1 "runtime-command"
                                  (lambda (implementation) (implementation #f)))
   'called)
  (personal-command-runtime-note-rejection!
   10 "bad /home/example/.config/odra/init.rkt\u001b[31m")
  (define rejected-inspection (personal-command-runtime-inspection))
  (check-equal?
   (personal-command-inspection-rejected-generation rejected-inspection) 10)
  (check-false
   (regexp-match?
    #rx"\033"
    (personal-command-inspection-latest-rejection rejected-inspection)))
  (check-false
   (regexp-match?
    #rx"/home/example"
    (personal-command-inspection-latest-rejection rejected-inspection)))
  (check-exn #rx"unavailable"
             (lambda ()
               (personal-command-runtime-call
                8 1 "runtime-command" (lambda (_implementation) (void)))))
  (personal-command-runtime-prepare! 10 '() #f)
  (personal-command-runtime-discard! 10)
  (check-equal? (personal-command-runtime-catalog 9) catalog)
  (personal-command-runtime-reset!)
  (check-exn #rx"unavailable"
             (lambda ()
               (personal-command-runtime-call
                9 1 "runtime-command" (lambda (_implementation) (void))))))
