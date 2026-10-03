#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         "../command/catalog.rkt"
         "../command/personal.rkt")

(provide
 maximum-personal-command-generation
 (contract-out
  [personal-command-route? (-> any/c boolean?)]
  [personal-command-route-generation
   (-> personal-command-route? exact-positive-integer?)]
  [personal-command-route-slot
   (-> personal-command-route? exact-positive-integer?)]
  [personal-command-route-name (-> personal-command-route? string?)]
  [personal-command-route-failure? (-> any/c boolean?)]
  [personal-command-route-failure-code
   (-> personal-command-route-failure? symbol?)]
  [personal-command-route-failure-expected
   (-> personal-command-route-failure? exact-nonnegative-integer?)]
  [personal-command-route-failure-actual
   (-> personal-command-route-failure? exact-nonnegative-integer?)]
  [make-personal-command-registry (-> personal-command-registry?)]
  [personal-command-registry? (-> any/c boolean?)]
  [personal-command-generation? (-> any/c boolean?)]
  [personal-command-generation-id
   (-> personal-command-generation? exact-positive-integer?)]
  [personal-command-generation-state
   (-> personal-command-generation? symbol?)]
  [personal-command-generation-turns
   (-> personal-command-generation? exact-nonnegative-integer?)]
  [personal-command-registry-active-generation
   (-> personal-command-registry? (or/c #f exact-positive-integer?))]
  [personal-command-registry-retained-generations
   (-> personal-command-registry? exact-nonnegative-integer?)]
  [personal-command-prepare
   (-> personal-command-registry? exact-positive-integer? list?
       personal-command-generation?)]
  [personal-command-generation-routes
   (-> personal-command-generation? list?)]
  [personal-command-route-by-name
   (-> personal-command-generation? string? (or/c #f personal-command-route?))]
  [personal-command-activate!
   (-> personal-command-registry? personal-command-generation? void?)]
  [personal-command-discard!
   (-> personal-command-registry? personal-command-generation? void?)]
  [personal-command-retire-active!
   (-> personal-command-registry? void?)]
  [personal-command-registry-close!
   (-> personal-command-registry? void?)]
  [call-with-personal-command-procedure
   (-> personal-command-registry? personal-command-route? procedure? any/c)]
  [call-with-personal-command-slot
   (-> personal-command-registry? exact-positive-integer?
       exact-positive-integer? string? procedure? any/c)]))

(define maximum-personal-command-generation (sub1 (expt 2 64)))

(struct personal-command-route (generation slot name)
  #:guard
  (lambda (generation slot name _)
    (unless (and (exact-positive-integer? generation)
                 (<= generation maximum-personal-command-generation)
                 (exact-positive-integer? slot)
                 (<= slot maximum-personal-commands)
                 (string? name))
      (raise-arguments-error
       'personal-command-route "invalid bounded personal command route"))
    (values generation slot (string->immutable-string name))))
(struct personal-command-route-failure (code expected actual))
(struct personal-command-registry
  ([active #:mutable] generations [closed? #:mutable]))
(struct personal-command-generation
  (owner id [route-vector #:mutable] [procedure-vector #:mutable]
         [state #:mutable] [turns #:mutable]))

(define current-personal-command-storage-builder
  (make-parameter
   (lambda (generation definitions)
     (values
      (list->vector
       (for/list ([definition (in-list definitions)]
                  [slot (in-naturals 1)])
         (personal-command-route
          generation slot (odra-command-definition-name definition))))
      (list->vector
       (map odra-command-definition-implementation definitions))))))

(define (make-personal-command-registry)
  (personal-command-registry #f (make-hasheqv) #f))

(define (personal-command-registry-active-generation registry)
  (define active (personal-command-registry-active registry))
  (and active (personal-command-generation-id active)))

(define (personal-command-registry-retained-generations registry)
  (hash-count (personal-command-registry-generations registry)))

;; personal-command-prepare retains one complete procedure generation only
;; after every definition and route slot has been admitted.
(define (personal-command-prepare registry generation definitions)
  (ensure-open-registry 'personal-command-prepare registry)
  (unless (<= generation maximum-personal-command-generation)
    (raise-arguments-error
     'personal-command-prepare
     "personal command generation exceeds the admitted bound"
     "generation" generation
     "limit" maximum-personal-command-generation))
  (unless (and (<= (length definitions) maximum-personal-commands)
               (andmap command? definitions))
    (raise-arguments-error
     'personal-command-prepare
     "expected a bounded list of personal commands"
     "definitions" definitions))
  (when (hash-has-key? (personal-command-registry-generations registry)
                       generation)
    (raise-arguments-error
     'personal-command-prepare
     "personal command generation is already retained"
     "generation" generation))
  (define-values (routes procedures)
    ((current-personal-command-storage-builder) generation definitions))
  (unless (and (vector? routes)
               (vector? procedures)
               (= (vector-length routes) (length definitions))
               (= (vector-length procedures) (length definitions))
               (for/and ([route (in-vector routes)]
                         [slot (in-naturals 1)])
                 (and (personal-command-route? route)
                      (= (personal-command-route-generation route) generation)
                      (= (personal-command-route-slot route) slot)))
               (for/and ([procedure (in-vector procedures)])
                 (procedure? procedure)))
    (raise-result-error
     'personal-command-prepare
     "matching route and procedure vectors"
     (list routes procedures)))
  (define candidate
    (personal-command-generation registry generation routes procedures
                                 'prepared 0))
  (hash-set! (personal-command-registry-generations registry)
             generation candidate)
  candidate)

(define (personal-command-generation-routes generation)
  (for/list ([route (in-vector
                     (personal-command-generation-route-vector generation))])
    route))

(define (personal-command-route-by-name generation name)
  (for/first ([route (in-vector
                      (personal-command-generation-route-vector generation))]
              #:when (string=? name (personal-command-route-name route)))
    route))

;; personal-command-activate! publishes one retained candidate and retires the
;; prior active generation after any already admitted turns finish.
(define (personal-command-activate! registry candidate)
  (ensure-owned-generation 'personal-command-activate! registry candidate)
  (ensure-open-registry 'personal-command-activate! registry)
  (unless (eq? (personal-command-generation-state candidate) 'prepared)
    (raise-arguments-error
     'personal-command-activate!
     "personal command candidate is not prepared"
     "state" (personal-command-generation-state candidate)))
  (define previous (personal-command-registry-active registry))
  (when previous
    (set-personal-command-generation-state! previous 'retiring))
  (set-personal-command-generation-state! candidate 'active)
  (set-personal-command-registry-active! registry candidate)
  (when previous (release-if-idle! previous))
  (void))

(define (personal-command-discard! registry candidate)
  (ensure-owned-generation 'personal-command-discard! registry candidate)
  (unless (eq? (personal-command-generation-state candidate) 'prepared)
    (raise-arguments-error
     'personal-command-discard!
     "only a prepared personal command candidate can be discarded"
     "state" (personal-command-generation-state candidate)))
  (set-personal-command-generation-state! candidate 'retiring)
  (release-if-idle! candidate)
  (void))

(define (personal-command-retire-active! registry)
  (define active (personal-command-registry-active registry))
  (when active
    (set-personal-command-registry-active! registry #f)
    (set-personal-command-generation-state! active 'retiring)
    (release-if-idle! active))
  (void))

(define (personal-command-registry-close! registry)
  (unless (personal-command-registry-closed? registry)
    (set-personal-command-registry-closed?! registry #t)
    (set-personal-command-registry-active! registry #f)
    (for ([generation
           (in-list
            (hash-values (personal-command-registry-generations registry)))])
      (set-personal-command-generation-state! generation 'retiring)
      (release-if-idle! generation)))
  (void))

;; call-with-personal-command-procedure resolves one exact active route and
;; retains its generation until the admitted dynamic turn exits.
(define (call-with-personal-command-procedure registry route command)
  (define active (personal-command-registry-active registry))
  (cond
    [(or (personal-command-registry-closed? registry) (not active))
     (personal-command-route-failure
      'unavailable
      (personal-command-route-generation route)
      (or (personal-command-registry-active-generation registry) 0))]
    [(not (= (personal-command-route-generation route)
             (personal-command-generation-id active)))
     (personal-command-route-failure
      'stale-generation
      (personal-command-route-generation route)
      (personal-command-generation-id active))]
    [else
     (define slot (personal-command-route-slot route))
     (define routes (personal-command-generation-route-vector active))
     (cond
       [(or (zero? slot) (> slot (vector-length routes)))
        (personal-command-route-failure
         'invalid-slot (vector-length routes) slot)]
       [(not (equal? route (vector-ref routes (sub1 slot))))
        (personal-command-route-failure 'invalid-route slot slot)]
       [else
        (define procedure
          (vector-ref (personal-command-generation-procedure-vector active)
                      (sub1 slot)))
        (dynamic-wind
         (lambda ()
           (set-personal-command-generation-turns!
            active (add1 (personal-command-generation-turns active))))
         (lambda () (command procedure))
         (lambda ()
           (set-personal-command-generation-turns!
            active (sub1 (personal-command-generation-turns active)))
           (release-if-idle! active)))])]))

;; call-with-personal-command-slot resolves one copied native route without exposing roots.
(define (call-with-personal-command-slot registry generation slot name command)
  (define active (personal-command-registry-active registry))
  (cond
    [(or (not active)
         (not (= generation (personal-command-generation-id active))))
     (personal-command-route-failure
      'stale-generation
      generation
      (or (personal-command-registry-active-generation registry) 0))]
    [(> slot (vector-length
              (personal-command-generation-route-vector active)))
     (personal-command-route-failure
      'invalid-slot
      (vector-length (personal-command-generation-route-vector active))
      slot)]
    [else
     (define route
       (vector-ref (personal-command-generation-route-vector active) (sub1 slot)))
     (if (string=? name (personal-command-route-name route))
         (call-with-personal-command-procedure registry route command)
         (personal-command-route-failure 'invalid-route slot slot))]))

(define (release-if-idle! generation)
  (when (and (eq? (personal-command-generation-state generation) 'retiring)
             (zero? (personal-command-generation-turns generation)))
    (define registry (personal-command-generation-owner generation))
    (hash-remove! (personal-command-registry-generations registry)
                  (personal-command-generation-id generation))
    (set-personal-command-generation-route-vector! generation #())
    (set-personal-command-generation-procedure-vector! generation #())
    (set-personal-command-generation-state! generation 'closed)))

(define (ensure-open-registry who registry)
  (when (personal-command-registry-closed? registry)
    (raise-arguments-error who "personal command registry is closed")))

(define (ensure-owned-generation who registry generation)
  (unless (and (eq? registry (personal-command-generation-owner generation))
               (eq? generation
                    (hash-ref
                     (personal-command-registry-generations registry)
                     (personal-command-generation-id generation)
                     (lambda () #f))))
    (raise-arguments-error who
                           "personal command generation is not retained by this registry")))

(module+ test-support
  (provide current-personal-command-storage-builder))
