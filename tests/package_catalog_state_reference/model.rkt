#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list)

(provide
 configuration-origins
 refresh-states
 (struct-out catalog-registration)
 (struct-out confirmed-snapshot-reference)
 (struct-out catalog-state-failure)
 (struct-out catalog-state)
 (struct-out state-rejection)
 empty-catalog-state
 enroll-catalog
 replace-catalog-registration
 set-catalog-enabled
 remove-catalog-registration
 confirm-catalog-snapshot
 publish-catalog-state-model
 recover-catalog-state-model
 quarantine-catalog-state-model)

(define configuration-origins '(administrator built-in project user))
(define refresh-states '(blocked current failed never offline stale))
(define explicit-enrollment-sources
  '(administrator-action built-in-bootstrap project-configuration user-action))

(struct catalog-registration
  (id generation catalog-id configuration-origin trust-root-ref endpoint-ids
      package-precedence advisory-policy enabled? refresh-state)
  #:transparent)
(struct confirmed-snapshot-reference
  (catalog-id snapshot-id sequence digest cache-ref)
  #:transparent)
(struct catalog-state-failure
  (id catalog-id code generation detail)
  #:transparent)
(struct catalog-state
  (format-version generation registrations confirmed-snapshots failures quarantine)
  #:transparent)
(struct state-rejection (code field expected actual) #:transparent)

(define (empty-catalog-state)
  (catalog-state 1 0 '() '() '() '()))

(define (find-registration state registration-id)
  (for/first ([registration (in-list (catalog-state-registrations state))]
              #:when (string=? (catalog-registration-id registration)
                               registration-id))
    registration))

(define (replace-by-id registrations candidate)
  (sort
   (cons candidate
         (filter
          (lambda (registration)
            (not (string=? (catalog-registration-id registration)
                           (catalog-registration-id candidate))))
          registrations))
   string<? #:key catalog-registration-id))

(define (valid-registration? registration)
  (and (catalog-registration? registration)
       (positive? (catalog-registration-generation registration))
       (memq (catalog-registration-configuration-origin registration)
             configuration-origins)
       (string? (catalog-registration-trust-root-ref registration))
       (positive? (string-length
                   (catalog-registration-trust-root-ref registration)))
       (list? (catalog-registration-endpoint-ids registration))
       (equal? (catalog-registration-endpoint-ids registration)
               (sort
                (remove-duplicates
                 (catalog-registration-endpoint-ids registration)
                 string=?)
                string<?))
       (or (not (catalog-registration-enabled? registration))
           (pair? (catalog-registration-endpoint-ids registration)))
       (memq (catalog-registration-refresh-state registration) refresh-states)))

(define (enroll-catalog state registration source expected-state-generation)
  (cond
    [(not (= expected-state-generation (catalog-state-generation state)))
     (values state
             (state-rejection 'stale-generation 'catalog-state
                              (catalog-state-generation state)
                              expected-state-generation))]
    [(not (memq source explicit-enrollment-sources))
     (values state
             (state-rejection 'transitive-enrollment 'source
                              explicit-enrollment-sources source))]
    [(not (valid-registration? registration))
     (values state (state-rejection 'invalid-registration 'registration #f #f))]
    [(find-registration state (catalog-registration-id registration))
     (values state
             (state-rejection 'duplicate-registration 'registration-id #f
                              (catalog-registration-id registration)))]
    [else
     (values
      (struct-copy
       catalog-state state
       [generation (add1 (catalog-state-generation state))]
       [registrations
        (replace-by-id (catalog-state-registrations state) registration)])
      #f)]))

(define (replace-catalog-registration
         state candidate expected-state-generation expected-registration-generation)
  (define current
    (find-registration state (catalog-registration-id candidate)))
  (cond
    [(not (= expected-state-generation (catalog-state-generation state)))
     (values state
             (state-rejection 'stale-generation 'catalog-state
                              (catalog-state-generation state)
                              expected-state-generation))]
    [(not current)
     (values state
             (state-rejection 'missing-registration 'registration-id #f
                              (catalog-registration-id candidate)))]
    [(not (= expected-registration-generation
             (catalog-registration-generation current)))
     (values state
             (state-rejection 'stale-generation 'registration
                              (catalog-registration-generation current)
                              expected-registration-generation))]
    [(not (= (catalog-registration-generation candidate)
             (add1 expected-registration-generation)))
     (values state
             (state-rejection 'invalid-generation 'registration
                              (add1 expected-registration-generation)
                              (catalog-registration-generation candidate)))]
    [(not (string=? (catalog-registration-catalog-id current)
                    (catalog-registration-catalog-id candidate)))
     (values state
             (state-rejection 'identity-change 'catalog-id
                              (catalog-registration-catalog-id current)
                              (catalog-registration-catalog-id candidate)))]
    [(not (valid-registration? candidate))
     (values state (state-rejection 'invalid-registration 'registration #f #f))]
    [else
     (values
      (struct-copy
       catalog-state state
       [generation (add1 (catalog-state-generation state))]
       [registrations
        (replace-by-id (catalog-state-registrations state) candidate)])
      #f)]))

(define (set-catalog-enabled state registration-id enabled? expected-state-generation)
  (define current (find-registration state registration-id))
  (if current
      (replace-catalog-registration
       state
       (struct-copy catalog-registration current
                    [generation (add1 (catalog-registration-generation current))]
                    [enabled? enabled?]
                    [refresh-state
                     (if enabled?
                         (catalog-registration-refresh-state current)
                         'blocked)])
       expected-state-generation
       (catalog-registration-generation current))
      (values state
              (state-rejection 'missing-registration 'registration-id #f
                               registration-id))))

(define (remove-catalog-registration state registration-id expected-state-generation)
  (define current (find-registration state registration-id))
  (cond
    [(not (= expected-state-generation (catalog-state-generation state)))
     (values state
             (state-rejection 'stale-generation 'catalog-state
                              (catalog-state-generation state)
                              expected-state-generation))]
    [(not current)
     (values state
             (state-rejection 'missing-registration 'registration-id #f
                              registration-id))]
    [else
     (values
      (struct-copy
       catalog-state state
       [generation (add1 (catalog-state-generation state))]
       [registrations
        (filter
         (lambda (registration)
           (not (string=? registration-id
                          (catalog-registration-id registration))))
         (catalog-state-registrations state))])
      #f)]))

(define (confirm-catalog-snapshot state reference expected-state-generation)
  (cond
    [(not (= expected-state-generation (catalog-state-generation state)))
     (values state
             (state-rejection 'stale-generation 'catalog-state
                              (catalog-state-generation state)
                              expected-state-generation))]
    [(not
      (for/or ([registration (in-list (catalog-state-registrations state))])
        (string=? (catalog-registration-catalog-id registration)
                  (confirmed-snapshot-reference-catalog-id reference))))
     (values state
             (state-rejection 'unregistered-catalog 'catalog-id #f
                              (confirmed-snapshot-reference-catalog-id reference)))]
    [else
     (define previous
       (for/first
        ([candidate (in-list (catalog-state-confirmed-snapshots state))]
         #:when
         (string=? (confirmed-snapshot-reference-catalog-id candidate)
                   (confirmed-snapshot-reference-catalog-id reference)))
        candidate))
     (if (and previous
              (<= (confirmed-snapshot-reference-sequence reference)
                  (confirmed-snapshot-reference-sequence previous)))
         (values state
                 (state-rejection
                  'stale-snapshot 'sequence
                  (add1 (confirmed-snapshot-reference-sequence previous))
                  (confirmed-snapshot-reference-sequence reference)))
         (values
          (struct-copy
           catalog-state state
           [generation (add1 (catalog-state-generation state))]
           [confirmed-snapshots
            (sort
             (cons
              reference
              (filter
               (lambda (candidate)
                 (not
                  (string=?
                   (confirmed-snapshot-reference-catalog-id candidate)
                   (confirmed-snapshot-reference-catalog-id reference))))
               (catalog-state-confirmed-snapshots state)))
             string<? #:key confirmed-snapshot-reference-catalog-id)])
          #f))]))

(define (publish-catalog-state-model current candidate crash-point)
  (unless (= (catalog-state-generation candidate)
             (add1 (catalog-state-generation current)))
    (raise-arguments-error 'publish-catalog-state-model
                           "candidate generation must increment once"))
  (case crash-point
    [(before-write during-write before-file-sync before-rename)
     (values current 'old-authoritative)]
    [(after-rename before-directory-sync)
     (values candidate 'new-visible-durability-uncertain)]
    [(after-directory-sync) (values candidate 'new-authoritative)]
    [else
     (raise-argument-error 'publish-catalog-state-model
                           "known crash point" crash-point)]))

(define (recover-catalog-state-model current-valid? staged-valid? current staged)
  (cond
    [current-valid? (values current 'current-authoritative)]
    [staged-valid? (values staged 'recover-staged)]
    [else (values (empty-catalog-state) 'empty-with-quarantine)]))

(define (quarantine-catalog-state-model state reference)
  (if (member reference (catalog-state-quarantine state) string=?)
      state
      (struct-copy catalog-state state
                   [quarantine
                    (sort (cons reference (catalog-state-quarantine state))
                          string<?)])))
