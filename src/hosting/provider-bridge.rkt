#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.

(require (only-in "personal-configuration-bridge.rkt"
                  runtime-personal-configuration-root
                  runtime-ksawery-annotation-projection-batch
                  runtime-ksawery-command-family-batch
                  runtime-ksawery-conflict-assistance-batch
                  runtime-ksawery-external-operation-batch
                  runtime-ksawery-status-projection-batch)
         (only-in "../configuration/platform-roots.rkt"
                  odra-platform-roots-package-data
                  runtime-platform-roots-current)
         (only-in "../language_bundle/factory-bundles.rkt"
                  factory-language-bundles)
         (only-in "../language_bundle/keymap-projection.rkt"
                  language-keymap-projection)
         (only-in "../package/lifecycle-service.rkt"
                  package-lifecycle-runtime-keymaps))

(provide runtime-provider-invoke-batch)

;; runtime-provider-invoke-batch dispatches one generic provider request by semantic service identity.
(define (runtime-provider-invoke-batch service-bytes generation operation name-bytes payload)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #"" (string->bytes/utf-8 (exn-message failure))))])
    (define service (bytes->string/utf-8 service-bytes))
    (case (string->symbol service)
      [(source-control.status-projection)
       (runtime-ksawery-status-projection-batch payload)]
      [(source-control.annotation-projection)
       (runtime-ksawery-annotation-projection-batch payload)]
      [(source-control.command-family)
       (runtime-ksawery-command-family-batch generation operation name-bytes)]
      [(source-control.external-operation)
       (runtime-ksawery-external-operation-batch
        generation operation name-bytes payload)]
      [(source-control.conflict-assistance)
       (runtime-ksawery-conflict-assistance-batch operation payload)]
      [(language.keymap-projection)
       (define roots (runtime-platform-roots-current))
       (define root
         (or (and roots (odra-platform-roots-package-data roots))
             (runtime-personal-configuration-root)))
       (list #t
             (language-keymap-projection
              (factory-language-bundles)
              (string->symbol (bytes->string/utf-8 name-bytes))
              (string->symbol (bytes->string/utf-8 payload))
              (if root (package-lifecycle-runtime-keymaps root) '()))
             #"")]
      [else
       (list #f #"" (string->bytes/utf-8 "Unknown provider service"))])))

(module+ test
  (require rackunit)

  (check-equal?
   (runtime-provider-invoke-batch #"unknown.service" 0 0 #"" #"")
   (list #f #"" #"Unknown provider service"))
  (define jan-projection
    (runtime-provider-invoke-batch
     #"language.keymap-projection" 1 0 #"jan" #"direct"))
  (define jan-header #"odra-language-keymap\t1\tjan.direct\t0\t65\n")
  (check-true (car jan-projection))
  (check-true
   (bytes=? (subbytes (cadr jan-projection) 0 (bytes-length jan-header))
            jan-header))
  (check-equal? (caddr jan-projection) #""))
