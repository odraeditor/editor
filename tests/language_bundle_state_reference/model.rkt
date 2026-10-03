#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         racket/match
         racket/set)

(provide
 lifecycle-states
 operation-phases
 (struct-out installed-bundle)
 (struct-out activation-lock)
 (struct-out bundle-operation)
 (struct-out installed-state)
 (struct-out state-rejection)
 empty-installed-state
 advance-bundle-lifecycle
 begin-operation
 advance-operation
 publish-state-model
 recover-state-model
 quarantine-state-model
 migrate-state-model
 reachable-content
 garbage-collection-plan)

(define lifecycle-states
  '(staged verified installed-disabled enabled-pending active-confirmed
           activation-rejected update-pending rollback-available
           removal-pending removed quarantined))
(define operation-phases
  '(resolve review acquire verify durable-install prepare validate publish
            cleanup complete failed))
(define idempotent-recovery-phases
  '(resolve review acquire verify durable-install prepare validate cleanup))

(struct installed-bundle
  (id version manifest artifacts dependencies lifecycle predecessor pinned?)
  #:transparent)
(struct activation-lock
  (generation state-generation bundles content checksum)
  #:transparent)
(struct bundle-operation
  (id kind phase base-state-generation base-lock-generation content result)
  #:transparent)
(struct installed-state
  (format generation lock previous-lock bundles operations quarantine)
  #:transparent)
(struct state-rejection (code field expected actual) #:transparent)

(define (empty-installed-state)
  (installed-state 2 0 #f #f '() '() '()))

(define lifecycle-transitions
  (hash
   'staged '(verified quarantined)
   'verified '(installed-disabled quarantined)
   'installed-disabled '(enabled-pending removal-pending quarantined)
   'enabled-pending '(active-confirmed activation-rejected quarantined)
   'active-confirmed '(update-pending removal-pending quarantined)
   'activation-rejected '(enabled-pending removal-pending quarantined)
   'update-pending '(active-confirmed rollback-available quarantined)
   'rollback-available '(enabled-pending removal-pending quarantined)
   'removal-pending '(removed quarantined)
   'removed '()
   'quarantined '()))

(define (advance-bundle-lifecycle bundle next)
  (if (member next (hash-ref lifecycle-transitions
                            (installed-bundle-lifecycle bundle) '()))
      (values (struct-copy installed-bundle bundle [lifecycle next]) #f)
      (values #f
              (state-rejection 'invalid-transition 'lifecycle
                               (hash-ref lifecycle-transitions
                                         (installed-bundle-lifecycle bundle) '())
                               next))))

(define (begin-operation state operation)
  (cond
    [(not (= (bundle-operation-base-state-generation operation)
             (installed-state-generation state)))
     (values state (state-rejection 'stale-generation 'installed-state
                                    (installed-state-generation state)
                                    (bundle-operation-base-state-generation operation)))]
    [(not (= (bundle-operation-base-lock-generation operation)
             (if (installed-state-lock state)
                 (activation-lock-generation (installed-state-lock state))
                 0)))
     (values state (state-rejection 'stale-generation 'activation-lock
                                    (if (installed-state-lock state)
                                        (activation-lock-generation
                                         (installed-state-lock state))
                                        0)
                                    (bundle-operation-base-lock-generation operation)))]
    [(pair? (installed-state-operations state))
     (values state (state-rejection 'operation-active 'operations 0 1))]
    [else
     (values (struct-copy installed-state state [operations (list operation)]) #f)]))

(define (phase-index phase)
  (index-of operation-phases phase))

(define (advance-operation operation next)
  (define current-index (phase-index (bundle-operation-phase operation)))
  (define next-index (phase-index next))
  (if (and current-index next-index
           (or (and (= next-index (add1 current-index))
                    (not (memq (bundle-operation-phase operation)
                               '(complete failed))))
               (and (eq? next 'failed)
                    (not (memq (bundle-operation-phase operation)
                               '(complete failed))))))
      (values (struct-copy bundle-operation operation [phase next]) #f)
      (values #f (state-rejection 'invalid-transition 'operation-phase
                                  (bundle-operation-phase operation) next))))

;; The authoritative visible generation changes only after atomic rename.
(define (publish-state-model current candidate crash-point)
  (unless (= (installed-state-generation candidate)
             (add1 (installed-state-generation current)))
    (raise-arguments-error 'publish-state-model "candidate generation must increment once"))
  (case crash-point
    [(before-write during-write before-file-sync before-rename)
     (values current 'old-authoritative)]
    [(after-rename before-directory-sync)
     (values candidate 'new-visible-durability-uncertain)]
    [(after-directory-sync)
     (values candidate 'new-authoritative)]
    [else (raise-argument-error 'publish-state-model "known crash point" crash-point)]))

(define (lock-valid? state lock)
  (and (activation-lock? lock)
       (= (activation-lock-state-generation lock)
          (installed-state-generation state))
       (for/and ([(id version) (in-hash (activation-lock-bundles lock))])
         (for/or ([bundle (in-list (installed-state-bundles state))])
           (and (equal? id (installed-bundle-id bundle))
                (equal? version (installed-bundle-version bundle))
                (eq? (installed-bundle-lifecycle bundle) 'active-confirmed))))))

(define (recover-state-model state #:safe-mode? [safe-mode? #f])
  (cond
    [safe-mode?
     (values (struct-copy installed-state state [lock #f]) 'factory-only)]
    [(lock-valid? state (installed-state-lock state))
     (define operation (and (pair? (installed-state-operations state))
                            (car (installed-state-operations state))))
     (cond
       [(not operation) (values state 'confirmed)]
       [(memq (bundle-operation-phase operation) idempotent-recovery-phases)
        (values state 'resume-operation)]
       [else
        (values (struct-copy installed-state state
                             [lock (installed-state-previous-lock state)]
                             [operations '()])
                'rollback-previous)])]
    [(lock-valid? state (installed-state-previous-lock state))
     (values (struct-copy installed-state state
                          [lock (installed-state-previous-lock state)]
                          [operations '()])
             'rollback-previous)]
    [else
     (values (struct-copy installed-state state [lock #f] [operations '()])
             'factory-only)]))

(define (quarantine-state-model state reference)
  (if (member reference (installed-state-quarantine state) equal?)
      state
      (struct-copy installed-state state
                   [quarantine (sort (cons reference
                                           (installed-state-quarantine state))
                                     string<?)])))

(define (migrate-state-model datum)
  (match datum
    [(list 'installed-state 1 generation bundles lock)
     (installed-state 2 generation lock #f bundles '() '())]
    [(? installed-state? state)
     (and (= (installed-state-format state) 2) state)]
    [_ #f]))

(define (bundle-content bundle)
  (set-add (list->set (installed-bundle-artifacts bundle))
           (installed-bundle-manifest bundle)))

(define (reachable-content state)
  (define retained-bundles
    (for/fold ([content (set)]) ([bundle (in-list (installed-state-bundles state))]
                                 #:when (or (installed-bundle-pinned? bundle)
                                            (not (eq? (installed-bundle-lifecycle bundle)
                                                      'removed))))
      (set-union content (bundle-content bundle))))
  (for/fold ([content retained-bundles])
            ([owner (in-list
                     (append (filter values
                                     (list (installed-state-lock state)
                                           (installed-state-previous-lock state)))
                             (installed-state-operations state)))])
    (set-union content
               (list->set
                (if (activation-lock? owner)
                    (activation-lock-content owner)
                    (bundle-operation-content owner))))))

(define (garbage-collection-plan state content-store)
  (define reachable (reachable-content state))
  (sort (set->list (set-subtract (list->set content-store) reachable)) string<?))
