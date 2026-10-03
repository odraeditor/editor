#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         (prefix-in bundle: "../../src/command/language-bundles.rkt")
         (prefix-in language: "../../src/command/languages.rkt")
         "../../src/command/keymap-model.rkt"
         "../../src/command/language-interactions.rkt"
         "../../src/language_bundle/factory-bundles.rkt")

(define rust-bundle (factory-language-bundle-find 'org.odra.rust))
(define direct (factory-language-direct-keymap))
(define modal (factory-language-modal-keymap))

(test-case "Rust activates the shared Factory language context"
  (check-not-false rust-bundle)
  (check-equal?
   (map language:odra-language-id
        (bundle:odra-language-support-bundle-languages rust-bundle))
   '(rust))
  (check-eq? (odra-keymap-precedence direct) 'language-context)
  (check-eq? (odra-keymap-precedence modal) 'language-context)
  (define direct-commands
    (map odra-binding-command (odra-keymap-bindings direct)))
  (define modal-commands
    (map odra-binding-command (odra-keymap-bindings modal)))
  (for ([command
         (in-list
          '("language-show-hover"
            "language-go-to-definition"
            "language-find-references"
            "language-rename"
            "language-format-buffer"
            "language-code-actions"))])
    (check-not-false (member command direct-commands))
    (check-not-false (member command modal-commands)))
  (check-not-false (member "language-format-region" modal-commands)))
