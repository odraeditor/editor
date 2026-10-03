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

(define direct (factory-language-direct-keymap))
(define modal (factory-language-modal-keymap))

(test-case "Web languages share complete Direct and Modal language interactions"
  (for ([identity (in-list '(org.odra.javascript org.odra.typescript
                             org.odra.html org.odra.css))]
        [language-id (in-list '(javascript typescript html css))])
    (define factory (factory-language-bundle-find identity))
    (check-not-false factory)
    (check-equal?
     (map language:odra-language-id
          (bundle:odra-language-support-bundle-languages factory))
     (list language-id))
    (check-equal?
     (length (bundle:odra-language-support-bundle-services factory))
     1)
    (check-equal?
     (length (bundle:odra-language-support-bundle-formatters factory))
     1))
  (check-eq? (odra-keymap-precedence direct) 'language-context)
  (check-eq? (odra-keymap-precedence modal) 'language-context)
  (define direct-commands
    (map odra-binding-command (odra-keymap-bindings direct)))
  (define modal-commands
    (map odra-binding-command (odra-keymap-bindings modal)))
  (for ([command (in-list '("language-show-hover"
                            "language-go-to-definition"
                            "language-find-references"
                            "language-rename"
                            "language-format-buffer"
                            "language-code-actions"
                            "describe-language-support"
                            "restart-language-service"))])
    (check-not-false (member command direct-commands))
    (check-not-false (member command modal-commands)))
  (check-not-false (member "language-format-region" modal-commands)))
