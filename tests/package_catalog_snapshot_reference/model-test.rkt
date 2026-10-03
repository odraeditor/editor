#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "model.rkt")

(define first
  (catalog-snapshot "snapshot-1" "catalog" 1 #f "policy" 10 30
                    "assertions-1" "advisories-1" 1024 "publisher" '(sig)))
(define second
  (catalog-snapshot "snapshot-2" "catalog" 2 "snapshot-1" "policy" 20 40
                    "assertions-2" "advisories-2" 2048 "publisher" '(sig)))

(test-case "bootstrap and successor history validate"
  (check-true (validate-snapshot-history #f first 20 1024))
  (check-true (validate-snapshot-history first second 30 2048)))

(test-case "rollback and unexpected predecessors retain confirmed state"
  (for ([candidate
         (list (struct-copy catalog-snapshot second [sequence 1])
               (struct-copy catalog-snapshot second [previous-digest "other"]))]
        [code '(sequence predecessor)])
    (define rejection (validate-snapshot-history first candidate 30 2048))
    (check-eq? (snapshot-rejection-code rejection) code)
    (check-equal? (snapshot-rejection-retained rejection) first)))

(test-case "expiry and declared metadata size reject"
  (check-eq?
   (snapshot-rejection-code (validate-snapshot-history first second 40 2048))
   'expired)
  (check-eq?
   (snapshot-rejection-code (validate-snapshot-history first second 30 2047))
   'metadata-size))

(test-case "equal origin and mirror observations confirm once"
  (define-values (mode candidate endpoints)
    (reconcile-snapshot-observations
     first
     (list (snapshot-observation "origin" 'origin 'available second #t)
           (snapshot-observation "mirror" 'mirror 'available second #t))))
  (check-eq? mode 'confirmed)
  (check-equal? candidate second)
  (check-equal? endpoints '("mirror" "origin")))

(test-case "signed divergence retains previous confirmation"
  (define fork (struct-copy catalog-snapshot second [id "snapshot-fork"]))
  (define-values (mode retained evidence)
    (reconcile-snapshot-observations
     first
     (list (snapshot-observation "origin" 'origin 'available second #t)
           (snapshot-observation "mirror" 'mirror 'available fork #t))))
  (check-eq? mode 'divergent)
  (check-equal? retained first)
  (check-equal? (length evidence) 2))

(test-case "offline mode retains the previous confirmed snapshot"
  (define-values (mode retained evidence)
    (reconcile-snapshot-observations
     first
     (list (snapshot-observation "origin" 'origin 'unavailable #f #f)
           (snapshot-observation "mirror" 'mirror 'unavailable #f #f))))
  (check-eq? mode 'offline)
  (check-equal? retained first)
  (check-equal? evidence '()))

(test-case "resource profiles stay within explicit native bounds"
  (check-true (validate-snapshot-resource-profile
               (car snapshot-resource-profiles)))
  (check-false
   (validate-snapshot-resource-profile
    (hash-set (car snapshot-resource-profiles) 'observations 65))))
