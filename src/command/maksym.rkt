#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         "keymap-model.rkt")

(provide
 (contract-out
  [maksym-browsing-command-names (listof symbol?)]
  [maksym-editable-command-names (listof symbol?)]
  [maksym-command-names (listof symbol?)]
  [maksym-command-name? (-> any/c boolean?)]
  [maksym-factory-bindings (-> (listof odra-binding?))]))

(define unicode-scalar-key 1)
(define control-modifier #x01)
(define provenance (odra-provenance "odra" "maksym" ""))

(define maksym-browsing-command-names
  '(maksym-open-directory
    maksym-open-directory-other-pane
    maksym-open-directory-below
    maksym-open-directory-right
    maksym-open-containing-directory
    maksym-open-containing-directory-other-pane
    maksym-next-entry
    maksym-previous-entry
    maksym-parent-directory
    maksym-jump-to-entry
    maksym-open-entry
    maksym-open-entry-other-pane
    maksym-display-entry-other-pane
    maksym-refresh
    maksym-toggle-details
    maksym-cycle-sort
    maksym-mark-entry
    maksym-unmark-entry
    maksym-invert-marks
    maksym-unmark-all
    maksym-next-marked-entry
    maksym-previous-marked-entry
    maksym-create-directory
    maksym-copy-targets
    maksym-move-targets
    maksym-delete-targets
    maksym-copy-names
    maksym-copy-absolute-paths
    maksym-describe-entry-type
    maksym-describe-entry-metadata
    maksym-shell-command
    maksym-shell-command-async
    maksym-shell-command-current-directory
    maksym-filter-name
    maksym-clear-filter
    maksym-rename-pattern
    maksym-find-file-relative))

(define maksym-editable-command-names
  '(maksym-toggle-editable-listing
    maksym-apply-editable-listing
    maksym-cancel-editable-listing
    maksym-editable-next-line
    maksym-editable-previous-line))

(define maksym-command-names
  (append maksym-browsing-command-names maksym-editable-command-names))

(define (maksym-command-name? value)
  (and (symbol? value) (memq value maksym-command-names) #t))

(define (stroke scalar [modifiers 0])
  (odra-key-stroke unicode-scalar-key (char->integer scalar) modifiers))

(define (binding command-name . strokes)
  (keymap-bind (apply key-sequence strokes) command-name provenance))

;; maksym-factory-bindings owns only global entry bindings; buffer-local bindings
;; are installed by the Maksym interaction context.
(define (maksym-factory-bindings)
  (list
   (binding "maksym-open-directory"
            (stroke #\x control-modifier)
            (stroke #\d))
   (binding "maksym-open-directory-other-pane"
            (stroke #\x control-modifier)
            (stroke #\4)
            (stroke #\d))
   (binding "maksym-open-containing-directory"
            (stroke #\x control-modifier)
            (stroke #\j control-modifier))
   (binding "maksym-open-containing-directory-other-pane"
            (stroke #\x control-modifier)
            (stroke #\4)
            (stroke #\j control-modifier))))

(module+ test
  (require rackunit)
  (check-equal? (length maksym-browsing-command-names) 37)
  (check-equal? (length maksym-editable-command-names) 5)
  (check-equal? (length maksym-command-names) 42)
  (check-true (maksym-command-name? 'maksym-apply-editable-listing))
  (check-false (maksym-command-name? 'open-directory))
  (check-equal? (length (maksym-factory-bindings)) 4)
  (check-true (andmap odra-binding? (maksym-factory-bindings))))
