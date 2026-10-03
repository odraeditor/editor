#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         racket/file
         racket/runtime-path
         "../../src/configuration/root.rkt"
         "../../src/configuration/personal.rkt")

(define-runtime-path configuration-fixtures "../fixtures/configuration")

(define fixtures-root
  (simplify-path configuration-fixtures))

(define (load-fixture name)
  (define root (build-path fixtures-root name))
  (define source (personal-config-source root))
  (personal-config-reload (personal-config-initialize) 1 source))

(define (confirmed? result)
  (eq? (odra-personal-config-result-status result) 'confirmed))

(define (observation-state result)
  (odra-personal-config-observation-state
   (odra-personal-config-state-observation
    (odra-personal-config-result-state result))))

  (test-case "single-file fixture creates no dirs"
  (define result (load-fixture "single-file"))
  (check-true (confirmed? result))
  (check-eq? (observation-state result) 'confirmed)
  (check-eq?
   (configuration-path-kind (build-path fixtures-root "single-file")
                            (build-path fixtures-root "single-file" "init.rkt"))
   'personal-entrypoint)
  (check-false
   (directory-exists? (build-path fixtures-root "single-file" "settings"))))

  (test-case "modular fixture keeps user organization"
  (define result (load-fixture "modular"))
  (check-true (confirmed? result))
  (check-eq? (observation-state result) 'confirmed)
  (check-eq?
   (configuration-path-kind (build-path fixtures-root "modular")
                            (build-path fixtures-root "modular" "settings"))
   'functional-configuration)
  (check-eq?
   (configuration-path-kind (build-path fixtures-root "modular")
                            (build-path fixtures-root "modular" "settings" "editor.rkt"))
   'functional-configuration))
