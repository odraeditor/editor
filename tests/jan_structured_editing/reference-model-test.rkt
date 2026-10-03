#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         rackunit
         "model.rkt")

;; Local visibility cycles are deterministic and return to their starting state.
(test-case "local visibility has one three-state cycle"
  (check-equal? (local-cycle 'heading-only) 'direct-children)
  (check-equal? (local-cycle 'direct-children) 'complete-subtree)
  (check-equal? (local-cycle 'complete-subtree) 'heading-only)
  (check-false (local-cycle 'unknown)))

;; Global visibility is also one deterministic cycle owned by an individual view.
(test-case "global visibility has one three-state cycle"
  (check-equal? (global-cycle 'overview) 'contents)
  (check-equal? (global-cycle 'contents) 'show-all)
  (check-equal? (global-cycle 'show-all) 'overview)
  (check-false (global-cycle 'unknown)))

;; Hidden ranges normalize independent of discovery order and never overlap.
(test-case "hidden ranges normalize canonically"
  (define expected '((2 12) (20 30)))
  (check-equal?
   (normalize-hidden-ranges 40 '((20 25) (2 8) (7 12) (25 30)))
   expected)
  (check-equal?
   (normalize-hidden-ranges 40 '((25 30) (7 12) (2 8) (20 25)))
   expected))

;; Invalid, empty, reversed, or out-of-source ranges reject the whole candidate.
(test-case "invalid hidden range candidates reject atomically"
  (for ([ranges (in-list '(((0 0)) ((8 2)) ((0 11)) ((-1 2)) ((a 2))))])
    (check-false (normalize-hidden-ranges 10 ranges))))

;; Reveal removes the containing interval without changing unrelated folds.
(test-case "reveal affects only the containing hidden range"
  (define ranges '((2 8) (12 20) (30 40)))
  (check-equal? (reveal-position 50 ranges 15) '((2 8) (30 40)))
  (check-equal? (reveal-position 50 ranges 25) ranges)
  (check-false (reveal-position 50 ranges 51)))

;; Complete list content shifts as a unit and promotion cannot cross column zero.
(test-case "list indentation preserves owned lines"
  (define item '((2 "- Parent") (4 "continuation") (4 "- Child")))
  (check-equal? (shift-list-indentation item 2 'promote)
                '((0 "- Parent") (2 "continuation") (2 "- Child")))
  (check-equal? (shift-list-indentation item 2 'demote)
                '((4 "- Parent") (6 "continuation") (6 "- Child")))
  (check-false (shift-list-indentation '((0 "- Root")) 2 'promote)))

;; Region validation is all-or-nothing for completeness, overlap, and capacity.
(test-case "structural targets normalize only when complete and disjoint"
  (define complete '((0 10) (10 20) (30 40)))
  (check-equal? (normalize-structural-targets complete '((30 40) (0 10)) 3)
                '((0 10) (30 40)))
  (check-false (normalize-structural-targets complete '((0 9)) 3))
  (check-false (normalize-structural-targets '((0 20) (5 10)) '((0 20) (5 10)) 3))
  (check-false (normalize-structural-targets complete complete 2)))

;; Drawer close syntax is fixed and block names always agree at both edges.
(test-case "structure delimiters are generated as one pair"
  (check-equal? (structure-delimiters 'drawer "NOTES") '(":NOTES:" ":END:"))
  (check-equal? (structure-delimiters 'block "warning")
                '("#+begin_warning" "#+end_warning"))
  (check-false (structure-delimiters 'block "bad name")))

;; Empty creation and delimited conversion are rectangular and independently bounded.
(test-case "table creation and delimited conversion are bounded"
  (check-equal? (make-empty-table 2 3 6) '(("" "" "") ("" "" "")))
  (check-false (make-empty-table 2 3 5))
  (check-equal? (delimited-text->table "alpha, beta\ngamma,delta\n" #\, 4)
                '(("alpha" "beta") ("gamma" "delta")))
  (check-false (delimited-text->table "alpha,beta\ngamma\n" #\, 4)))

;; Ragged rows pad without modifying values and separators adopt table width.
(test-case "table normalization preserves values and separators"
  (check-equal? (normalize-table '(("a" "b") separator ("c")) 4)
                '(("a" "b") (separator 2) ("c" "")))
  (check-false (normalize-table '(("a") 7) 4))
  (check-false (normalize-table '(("a" "b") ("c" "d")) 3)))

;; Alignment uses display cells, so wide and combining Unicode remain column-safe.
(test-case "table alignment separates display width from stored content"
  (check-equal?
   (align-table '(("name" "value") separator ("λ" "界") ("é" "ok")) 8)
   '("| name | value |" "|------+-------|" "| λ    | 界    |" "| é    | ok    |")))

;; Rectangles are copied with half-open coordinates and reject separator crossings.
(test-case "table rectangles validate complete data cells"
  (define table '(("a" "b" "c") ("d" "e" "f") ("g" "h" "i")))
  (check-equal? (table-rectangle table 0 2 1 3 9) '(("b" "c") ("e" "f")))
  (check-false (table-rectangle '(("a") separator ("b")) 0 2 0 1 3))
  (check-false (table-rectangle table 0 4 0 1 9)))

;; Rich-capable surfaces retain derived display items; terminals retain exact source roles.
(test-case "rich presentation has an exact terminal fallback"
  (define source "* Heading\nText *bold* \\alpha.\n")
  (define items '((0 9 role "heading") (15 21 markup "bold") (22 28 entity "α")))
  (check-equal? (hash-ref (derive-rich-presentation source 'rich items) 'items) items)
  (check-equal? (hash-ref (derive-rich-presentation source 'terminal items) 'items)
                '((0 9 role "heading")))
  (check-equal? (hash-ref (derive-rich-presentation source 'terminal items) 'source) source))

;; Preview admission never grants image authority implicitly.
(test-case "preview admission selects pending or source fallback"
  (check-equal? (admit-preview 'latex #t #t #f) 'pending)
  (check-equal? (admit-preview 'image #f #t #f) 'source-fallback)
  (check-equal? (admit-preview 'image #t #f #f) 'source-fallback)
  (check-false (admit-preview 'image #t #t #f))
  (check-equal? (admit-preview 'image #t #t #t) 'pending))

;; Cache publication is exact and evicts the oldest copied result first.
(test-case "preview cache publication is bounded and stale-safe"
  (check-equal? (publish-preview-cache '((1 4) (2 4)) 3 5 10 #t) '((2 4) (3 5)))
  (check-false (publish-preview-cache '((1 4)) 2 5 8 #f))
  (check-false (publish-preview-cache '() 1 9 8 #t)))

;; Configured authoring generations normalize atomically and reject conflicts.
(test-case "authoring configuration is complete and conflict checked"
  (define configured
    (normalize-authoring-configuration
     2
     '((note block "#+begin_note\n#+end_note\n"))
     '((team task-state ("READY" "DONE")))))
  (check-equal? (hash-ref configured 'generation) 2)
  (check-false
   (normalize-authoring-configuration
    3
    '((same block "one") (same drawer "two"))
    '())))

;; Factory candidates remain first and retain ownership across configured duplicates.
(test-case "contextual completion preserves factory candidates"
  (define configured
    (normalize-authoring-configuration
     2 '() '((team task-state ("READY" "DONE")))))
  (check-equal? (contextual-candidates 'task-state configured)
                '("TODO" "DONE" "READY"))
  (check-equal? (contextual-candidates 'keyword #f)
                '("#+title:" "#+author:" "#+options:")))

;; Factory template keys are protected while new configured syntax remains available.
(test-case "structure templates resolve with factory precedence"
  (define configured
    (normalize-authoring-configuration
     2
     '((src document "configured")
       (note block "#+begin_note\n#+end_note\n"))
     '()))
  (check-equal? (resolve-structure-template 'src configured)
                '(document "#+begin_src \n\n#+end_src\n"))
  (check-equal? (resolve-structure-template 'note configured)
                '(block "#+begin_note\n#+end_note\n")))

;; Deep contexts win and recognized later-stage syntax never falls through.
(test-case "contextual precedence exposes future-stage unavailability"
  (define contexts
    '((document 0 40 1 #f)
      (heading 0 20 3 #f)
      (future-property 5 12 11 planning-and-agenda)))
  (check-equal? (hash-ref (resolve-authoring-context contexts 1) 'context) 'heading)
  (define future (resolve-authoring-context contexts 7))
  (check-equal? (hash-ref future 'status) 'unavailable)
  (check-equal? (hash-ref future 'owner) 'planning-and-agenda))

;; Semantic repeat resolves against the new point and stores no stale range.
(test-case "semantic repetition resolves a fresh contextual target"
  (define contexts '((heading 0 8 3 #f) (heading 12 30 3 #f)))
  (define repeated
    (repeat-authoring-context contexts 14 '#hasheq((command . move-down))))
  (check-equal? (hash-ref repeated 'range) '(12 30))
  (check-equal? (hash-ref repeated 'command) 'move-down))

;; Every selected profile fits its independently bounded dimension.
(test-case "resource profiles fit the accepted Stage 2 limits"
  (for ([profile (in-list structured-editing-resource-profiles)])
    (check-true (validate-resource-profile profile))
    (check-true (positive? (estimate-retained-bytes profile)))
    (check-true (positive? (estimate-temporary-bytes profile)))))

;; Each exact boundary rejects a one-unit overflow without relying on aggregates.
(test-case "every resource dimension rejects one-unit overflow"
  (define boundary (last structured-editing-resource-profiles))
  (for ([key (in-list '(hidden-ranges sparse-matches semantic-targets
                                      table-cells rewrite-splices
                                      completion-candidates completion-bytes
                                      templates completion-sources
                                      configuration-bytes
                                      active-previews-per-view
                                      preview-result-bytes preview-cache-bytes))])
    (check-false
     (validate-resource-profile
      (hash-set boundary key
                (add1 (hash-ref structured-editing-limits key)))))))
