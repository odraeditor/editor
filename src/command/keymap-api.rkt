#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require "keymap-model.rkt"
         (only-in "builtins.rkt"
                  factory-interaction-profile-definition
                  factory-modal-interaction-profile-definition))

(provide
 (all-from-out "keymap-model.rkt")
 factory-interaction-profile
 factory-modal-interaction-profile)

;; factory-interaction-profile returns the complete shipped profile as an
;; immutable base for personal composition.
(define (factory-interaction-profile)
  (factory-interaction-profile-definition))

;; factory-modal-interaction-profile returns the shipped modal profile for selection.
(define (factory-modal-interaction-profile)
  (factory-modal-interaction-profile-definition))
