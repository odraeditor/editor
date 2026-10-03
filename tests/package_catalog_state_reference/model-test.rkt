#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "model.rkt")

(define registration
  (catalog-registration
   "official" 1 "catalog-a" 'built-in "root-a" '("origin")
   'preferred 'official-advisories #t 'never))
(define snapshot
  (confirmed-snapshot-reference
   "catalog-a" "snapshot-a" 1 "digest-a" "cache/snapshot-a.rktd"))

(define (enrolled-state)
  (define-values (state rejection)
    (enroll-catalog (empty-catalog-state) registration 'built-in-bootstrap 0))
  (check-false rejection)
  state)

(test-case "explicit enrollment advances one checked generation"
  (define state (enrolled-state))
  (check-equal? (catalog-state-generation state) 1)
  (check-equal? (catalog-state-registrations state) (list registration)))

(test-case "catalog metadata cannot enroll another catalog transitively"
  (define-values (state rejection)
    (enroll-catalog (empty-catalog-state) registration 'snapshot 0))
  (check-equal? state (empty-catalog-state))
  (check-eq? (state-rejection-code rejection) 'transitive-enrollment))

(test-case "registration replacement checks state and registration generations"
  (define state (enrolled-state))
  (define updated
    (struct-copy catalog-registration registration
                 [generation 2]
                 [endpoint-ids '("mirror" "origin")]))
  (define-values (next rejection)
    (replace-catalog-registration state updated 1 1))
  (check-false rejection)
  (check-equal? (catalog-state-generation next) 2)
  (define-values (unchanged stale)
    (replace-catalog-registration next
                                  (struct-copy catalog-registration updated
                                               [generation 3])
                                  1 2))
  (check-equal? unchanged next)
  (check-eq? (state-rejection-code stale) 'stale-generation))

(test-case "disabling registration preserves its confirmed snapshot"
  (define-values (confirmed rejection)
    (confirm-catalog-snapshot (enrolled-state) snapshot 1))
  (check-false rejection)
  (define-values (disabled disable-rejection)
    (set-catalog-enabled confirmed "official" #f 2))
  (check-false disable-rejection)
  (check-false
   (catalog-registration-enabled?
    (car (catalog-state-registrations disabled))))
  (check-eq?
   (catalog-registration-refresh-state
    (car (catalog-state-registrations disabled)))
   'blocked)
  (check-equal? (catalog-state-confirmed-snapshots disabled) (list snapshot)))

(test-case "removing registration preserves independently owned snapshot evidence"
  (define-values (confirmed rejection)
    (confirm-catalog-snapshot (enrolled-state) snapshot 1))
  (check-false rejection)
  (define-values (removed remove-rejection)
    (remove-catalog-registration confirmed "official" 2))
  (check-false remove-rejection)
  (check-equal? (catalog-state-registrations removed) '())
  (check-equal? (catalog-state-confirmed-snapshots removed) (list snapshot)))

(test-case "snapshot confirmation cannot create a registration"
  (define-values (state rejection)
    (confirm-catalog-snapshot (empty-catalog-state) snapshot 0))
  (check-equal? state (empty-catalog-state))
  (check-eq? (state-rejection-code rejection) 'unregistered-catalog))

(test-case "snapshot sequences advance and reject rollback"
  (define-values (first rejection)
    (confirm-catalog-snapshot (enrolled-state) snapshot 1))
  (check-false rejection)
  (define-values (unchanged stale)
    (confirm-catalog-snapshot first snapshot 2))
  (check-equal? unchanged first)
  (check-eq? (state-rejection-code stale) 'stale-snapshot))

(test-case "partial durable publication keeps the old state authoritative"
  (define current (empty-catalog-state))
  (define next (enrolled-state))
  (for ([point '(before-write during-write before-file-sync before-rename)])
    (define-values (visible authority)
      (publish-catalog-state-model current next point))
    (check-equal? visible current)
    (check-eq? authority 'old-authoritative)))

(test-case "startup selects only a complete valid state generation"
  (define current (enrolled-state))
  (define staged
    (struct-copy catalog-state current [generation 2]))
  (define-values (retained current-mode)
    (recover-catalog-state-model #t #t current staged))
  (check-equal? retained current)
  (check-eq? current-mode 'current-authoritative)
  (define-values (recovered staged-mode)
    (recover-catalog-state-model #f #t current staged))
  (check-equal? recovered staged)
  (check-eq? staged-mode 'recover-staged)
  (define-values (empty failure-mode)
    (recover-catalog-state-model #f #f current staged))
  (check-equal? empty (empty-catalog-state))
  (check-eq? failure-mode 'empty-with-quarantine))

(test-case "corrupt state quarantine is stable and unique"
  (define state (quarantine-catalog-state-model
                 (empty-catalog-state) "corrupt-state-a"))
  (check-equal?
   (quarantine-catalog-state-model state "corrupt-state-a")
   state))
