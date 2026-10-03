#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.

(require rackunit
         "builtins.rkt"
         "keymap-model.rkt")

(define (single-key-commands profile kind)
  (for*/list ([keymap (in-list (odra-interaction-profile-maps profile))]
              [binding (in-list (odra-keymap-bindings keymap))]
              [strokes (in-value
                        (odra-key-sequence-strokes
                         (odra-binding-sequence binding)))]
              #:when (and (= (length strokes) 1)
                          (= (odra-key-stroke-kind (car strokes)) kind)))
    (odra-binding-command binding)))

(test-case "direct indentation keys retain their semantic commands"
  (define profile (factory-interaction-profile-definition))
  (define tab-commands (single-key-commands profile 11))
  (define backspace-commands (single-key-commands profile 8))
  (check-not-false (member "insert-indentation" tab-commands))
  (check-not-false (member "delete-previous-grapheme" backspace-commands))
  (check-false (member "normalize-indentation-to-tabs" tab-commands))
  (check-false (member "normalize-indentation-to-spaces" tab-commands)))
