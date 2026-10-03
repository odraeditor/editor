#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         rackunit
         "reference-model.rkt")

;; The manifest is the complete Stage 1 syntax-family inventory.
(test-case "fixture manifest covers every Jan syntax family"
  (check-true (validate-fixture-manifest (load-fixture-manifest))))

;; Closure requires an exact evidence set and no pending syntax-family entries.
(test-case "fixture manifest rejects incomplete closure state"
  (define manifest (load-fixture-manifest))
  (check-false (validate-fixture-manifest (hash-set manifest 'pending '(heading))))
  (check-false (validate-fixture-manifest (hash-set manifest 'status 'active)))
  (define entries (hash-ref manifest 'entries))
  (define first-entry (car entries))
  (define incomplete-entry
    (hash-set first-entry 'evidence (cdr (hash-ref first-entry 'evidence))))
  (check-false
   (validate-fixture-manifest
    (hash-set manifest 'entries (cons incomplete-entry (cdr entries))))))

;; Capacity profiles must fit every selected subordinate and aggregate ceiling.
(test-case "resource profiles fit the selected Jan limits"
  (check-true (validate-resource-profiles resource-profiles)))

;; Each aggregate estimate includes retained source, nodes, facts, and diagnostics.
(test-case "adversarial retained analysis remains bounded"
  (define adversarial (last resource-profiles))
  (check-true
   (<= (estimated-retained-bytes adversarial)
       (hash-ref resource-limits 'retained-bytes)))
  (check-equal? (estimated-temporary-bytes adversarial)
                (hash-ref resource-limits 'temporary-bytes)))

;; A one-unit overflow in any independently bounded dimension must reject.
(test-case "resource model rejects subordinate limit overflow"
  (for ([key (in-list '(source-bytes nodes structural-depth inline-depth
                                     attributes-per-node index-facts diagnostics
                                     incremental-edits temporary-bytes))])
    (define limit-key key)
    (define rejected
      (hash-set (car resource-profiles)
                key
                (add1 (hash-ref resource-limits limit-key))))
    (check-false (validate-resource-profiles (list rejected)))))
