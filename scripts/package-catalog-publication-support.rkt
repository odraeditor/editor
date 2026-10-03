#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/file
         "../src/package_catalog/contracts.rkt"
         "../src/package_catalog/curation-publication.rkt"
         "../src/package_catalog/snapshot-records.rkt")

(provide
 (struct-out package-catalog-publication-repository)
 (contract-out
  [load-package-catalog-publication-repository
   (-> path-string? package-catalog-publication-repository?)]
  [validate-package-catalog-publication-repository
   (-> package-catalog-publication-repository?
       odra-package-catalog-publication?)]
  [publish-package-catalog-publication-repository
   (-> path-string? package-catalog-publication-repository?
       odra-package-catalog-publication-output?)]))

(struct package-catalog-publication-repository
  (profile publisher-keys previous-snapshot publication)
  #:transparent)

(define (require-export module-path export)
  (with-handlers ([exn:fail?
                   (lambda (exception)
                     (raise-user-error
                      'package-catalog-publication
                      "repository export ~a is unavailable: ~a"
                      export (exn-message exception)))])
    (dynamic-require module-path export)))

(define (load-package-catalog-publication-repository path)
  (define module-path (path->complete-path path))
  (unless (file-exists? module-path)
    (raise-user-error 'package-catalog-publication
                      "repository module is unavailable"))
  (define profile (require-export module-path 'profile))
  (define publisher-keys (require-export module-path 'publisher-keys))
  (define previous (require-export module-path 'previous-snapshot))
  (define publication (require-export module-path 'publication))
  (unless (odra-package-catalog-profile? profile)
    (raise-user-error 'package-catalog-publication
                      "repository profile is invalid"))
  (unless (and (list? publisher-keys)
               (andmap odra-package-catalog-publisher-key? publisher-keys))
    (raise-user-error 'package-catalog-publication
                      "repository publisher keys are invalid"))
  (unless (or (not previous) (odra-package-catalog-snapshot? previous))
    (raise-user-error 'package-catalog-publication
                      "repository predecessor snapshot is invalid"))
  (unless (odra-package-catalog-publication? publication)
    (raise-user-error 'package-catalog-publication
                      "repository publication is invalid"))
  (package-catalog-publication-repository
   profile publisher-keys previous publication))

(define (validate-package-catalog-publication-repository repository)
  (define publication
    (package-catalog-publication-repository-publication repository))
  (define result
    (verify-package-catalog-publication
     (package-catalog-publication-repository-profile repository)
     (package-catalog-publication-repository-publisher-keys repository)
     (package-catalog-publication-repository-previous-snapshot repository)
     publication))
  (when (odra-package-catalog-publication-failure? result)
    (raise-user-error
     'package-catalog-publication
     "validation failed: ~a/~a"
     (odra-package-catalog-publication-failure-code result)
     (odra-package-catalog-publication-failure-field result)))
  publication)

(define (publish-package-catalog-publication-repository root repository)
  (define publication
    (validate-package-catalog-publication-repository repository))
  (define result
    (package-catalog-publication-persist
     root
     (package-catalog-publication-repository-profile repository)
     (package-catalog-publication-repository-publisher-keys repository)
     (package-catalog-publication-repository-previous-snapshot repository)
     publication))
  (when (odra-package-catalog-publication-failure? result)
    (raise-user-error
     'package-catalog-publication
     "publication failed: ~a/~a"
     (odra-package-catalog-publication-failure-code result)
     (odra-package-catalog-publication-failure-field result)))
  result)
