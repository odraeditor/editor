#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         "keymap-model.rkt")

(provide
 (contract-out
  [factory-language-direct-keymap (-> odra-keymap?)]
  [factory-language-modal-keymap (-> odra-keymap?)]))

;; Logical key and modifier values match the fixed-width native interaction ABI.
(define unicode-scalar-key 1)
(define control-modifier #x01)
(define factory-language-provenance
  (odra-provenance "odra-language" "factory language interaction" ""))

(define (key scalar [modifiers 0])
  (odra-key-stroke unicode-scalar-key (char->integer scalar) modifiers))

(define (binding command-name . strokes)
  (keymap-bind
   (apply key-sequence strokes)
   command-name
   factory-language-provenance))

(define (state-binding selector command-name . strokes)
  (keymap-for-states
   (apply binding command-name strokes)
   (list selector)))

(define (states-binding selectors command-name . strokes)
  (keymap-for-states
   (apply binding command-name strokes)
   selectors))

(define direct-command-keys
  '(("language-show-hover" . #\h)
    ("language-go-to-definition" . #\d)
    ("language-find-references" . #\r)
    ("language-document-symbols" . #\s)
    ("language-workspace-symbols" . #\S)
    ("language-rename" . #\n)
    ("language-format-buffer" . #\f)
    ("language-code-actions" . #\a)
    ("describe-language-support" . #\i)
    ("restart-language-service" . #\R)))

;; factory-language-direct-keymap owns the Direct C-c C-l language prefix.
(define (factory-language-direct-keymap)
  (odra-keymap
   3 1 "direct-language-context" 0 0 'language-context 0
   0 0 0 0 'fallthrough
   (for/list ([entry (in-list direct-command-keys)])
     (binding
      (car entry)
      (key #\c control-modifier)
      (key #\l control-modifier)
      (key (cdr entry))))
   '() '() factory-language-provenance))

;; factory-language-modal-keymap owns Normal and Visual language bindings.
(define (factory-language-modal-keymap)
  (define normal (odra-profile-state-selector 2 1))
  (define visual-character (odra-profile-state-selector 2 3))
  (define visual-line (odra-profile-state-selector 2 4))
  (define visual-states (list visual-character visual-line))
  (define (normal-binding command-name . strokes)
    (apply state-binding normal command-name strokes))
  (define (normal-language-binding command-name scalar)
    (normal-binding command-name (key #\g) (key #\l) (key scalar)))
  (define (visual-language-binding command-name scalar)
    (states-binding visual-states command-name (key #\g) (key #\l) (key scalar)))
  (odra-keymap
   5 1 "modal-language-context" 0 0 'language-context 0
   0 0 0 0 'fallthrough
   (list
    (normal-binding "language-go-to-definition" (key #\g) (key #\d))
    (normal-binding "language-find-references" (key #\g) (key #\r))
    (normal-binding "language-show-hover" (key #\K))
    (normal-language-binding "language-document-symbols" #\s)
    (normal-language-binding "language-workspace-symbols" #\S)
    (normal-language-binding "language-rename" #\n)
    (normal-language-binding "language-format-buffer" #\f)
    (normal-language-binding "language-code-actions" #\a)
    (normal-language-binding "describe-language-support" #\i)
    (normal-language-binding "restart-language-service" #\R)
    (visual-language-binding "language-format-region" #\f)
    (visual-language-binding "language-code-actions" #\a))
   '() '() factory-language-provenance))

(module+ test
  (require rackunit)

  (define direct (factory-language-direct-keymap))
  (check-equal? (odra-keymap-precedence direct) 'language-context)
  (check-equal? (length (odra-keymap-bindings direct)) 10)
  (check-not-false
   (member
    (binding "language-go-to-definition"
             (key #\c control-modifier) (key #\l control-modifier) (key #\d))
    (odra-keymap-bindings direct)))
  (define modal (factory-language-modal-keymap))
  (check-equal? (odra-keymap-precedence modal) 'language-context)
  (check-equal? (length (odra-keymap-bindings modal)) 12)
  (define region-format
    (for/first ([candidate (in-list (odra-keymap-bindings modal))]
                #:when (string=? (odra-binding-command candidate)
                                 "language-format-region"))
      candidate))
  (check-not-false region-format)
  (check-equal?
   (odra-binding-selectors region-format)
   (list (odra-profile-state-selector 2 3)
         (odra-profile-state-selector 2 4))))
