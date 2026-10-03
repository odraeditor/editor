#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/set
         rackunit
         "model.rkt")

(define bundle-a
  (installed-bundle "org.example.a" "1.0.0" "manifest-a"
                    '("artifact-a") '() 'installed-disabled #f #f))
(define active-a
  (struct-copy installed-bundle bundle-a [lifecycle 'active-confirmed]))
(define lock-a
  (activation-lock 1 1 (hash "org.example.a" "1.0.0")
                   '("manifest-a" "artifact-a") "lock-checksum"))

(test-case "bundle lifecycle admits only recorded edges"
  (define-values (pending failure)
    (advance-bundle-lifecycle bundle-a 'enabled-pending))
  (check-false failure)
  (check-eq? (installed-bundle-lifecycle pending) 'enabled-pending)
  (define-values (invalid rejection)
    (advance-bundle-lifecycle bundle-a 'active-confirmed))
  (check-false invalid)
  (check-eq? (state-rejection-code rejection) 'invalid-transition))

(test-case "operation requires exact predecessor generations"
  (define state (installed-state 2 1 lock-a #f (list active-a) '() '()))
  (define operation (bundle-operation "install-b" 'install 'resolve 1 1 '("manifest-b") #f))
  (define-values (prepared rejection) (begin-operation state operation))
  (check-false rejection)
  (check-equal? (installed-state-operations prepared) (list operation))
  (define-values (unchanged stale)
    (begin-operation state (struct-copy bundle-operation operation [base-state-generation 0])))
  (check-equal? unchanged state)
  (check-eq? (state-rejection-code stale) 'stale-generation))

(test-case "operation phases are monotonic and failure is terminal"
  (define operation (bundle-operation "install-b" 'install 'resolve 0 0 '() #f))
  (define-values (review failure) (advance-operation operation 'review))
  (check-false failure)
  (check-eq? (bundle-operation-phase review) 'review)
  (define-values (failed failed-error) (advance-operation review 'failed))
  (check-false failed-error)
  (define-values (resumed rejection) (advance-operation failed 'cleanup))
  (check-false resumed)
  (check-eq? (state-rejection-code rejection) 'invalid-transition))

(test-case "partial write never replaces authoritative state"
  (define old (empty-installed-state))
  (define next (struct-copy installed-state old [generation 1]))
  (for ([point '(before-write during-write before-file-sync before-rename)])
    (define-values (visible authority) (publish-state-model old next point))
    (check-equal? visible old)
    (check-eq? authority 'old-authoritative)))

(test-case "rename is visible before directory durability"
  (define old (empty-installed-state))
  (define next (struct-copy installed-state old [generation 1]))
  (define-values (visible uncertain)
    (publish-state-model old next 'after-rename))
  (check-equal? visible next)
  (check-eq? uncertain 'new-visible-durability-uncertain))

(test-case "startup resumes only idempotent phases"
  (define resumable
    (bundle-operation "verify-a" 'verify 'verify 1 1 '("artifact-a") #f))
  (define state (installed-state 2 1 lock-a #f (list active-a) (list resumable) '()))
  (define-values (_ disposition) (recover-state-model state))
  (check-eq? disposition 'resume-operation)
  (define ambiguous
    (struct-copy bundle-operation resumable [phase 'publish]))
  (define-values (recovered rolled-back)
    (recover-state-model (struct-copy installed-state state
                                      [operations (list ambiguous)])))
  (check-eq? rolled-back 'rollback-previous)
  (check-false (installed-state-lock recovered)))

(test-case "safe mode omits active lock without deleting content"
  (define state (installed-state 2 1 lock-a #f (list active-a) '() '()))
  (define-values (safe disposition) (recover-state-model state #:safe-mode? #t))
  (check-eq? disposition 'factory-only)
  (check-false (installed-state-lock safe))
  (check-equal? (installed-state-bundles safe) (list active-a)))

(test-case "quarantine references are stable and unique"
  (define once (quarantine-state-model (empty-installed-state) "bad-state-1"))
  (define twice (quarantine-state-model once "bad-state-1"))
  (check-equal? (installed-state-quarantine twice) '("bad-state-1")))

(test-case "version one state migrates deterministically"
  (define migrated
    (migrate-state-model (list 'installed-state 1 7 (list bundle-a) #f)))
  (check-equal? (installed-state-format migrated) 2)
  (check-equal? (installed-state-generation migrated) 7)
  (check-equal? (installed-state-bundles migrated) (list bundle-a)))

(test-case "garbage collection retains every referenced digest"
  (define removed
    (installed-bundle "org.example.old" "0.9.0" "manifest-old"
                      '("artifact-shared" "artifact-old") '() 'removed #f #f))
  (define operation
    (bundle-operation "update-a" 'update 'acquire 1 1
                      '("artifact-pending") #f))
  (define previous
    (activation-lock 0 1 (hash) '("artifact-previous") "previous"))
  (define state
    (installed-state 2 1 lock-a previous (list active-a removed)
                     (list operation) '()))
  (check-equal?
   (garbage-collection-plan
    state
    '("manifest-a" "artifact-a" "manifest-old" "artifact-shared"
                   "artifact-old" "artifact-pending" "artifact-previous"
                   "unreferenced"))
   '("artifact-old" "artifact-shared" "manifest-old" "unreferenced")))
