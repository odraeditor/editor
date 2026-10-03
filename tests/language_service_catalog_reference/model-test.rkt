#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         rackunit
         "model.rkt")

(define (definition handle identity source scope
                    #:languages [languages '(odin)]
                    #:enabled? [enabled? #t]
                    #:default? [default? #f])
  (service-definition handle identity languages source scope enabled? default?))

(define baseline
  (list (definition 1 "ols" 'factory "" #:default? #t)
        (definition 2 "odin-lsp" 'package "package-a")
        (definition 3 "project-lsp" 'project "project-a")))

(define selections
  (list (explicit-selection 'odin "odin-lsp" 'personal "")
        (explicit-selection 'odin "project-lsp" 'project "project-a")))

(define (confirmed definitions [choices '()] [generation 1])
  (define-values (catalog accepted? rejection)
    (confirm-service-catalog #f generation definitions choices))
  (check-true accepted?)
  (check-false rejection)
  catalog)

;; Every registration permutation produces the same canonical catalog and selection.
(test-case "service resolution is independent from registration order"
  (define expected (confirmed baseline selections))
  (for ([candidate (in-list (permutations baseline))])
    (define catalog (confirmed candidate (reverse selections)))
    (check-equal? catalog expected)
    (define-values (resolved rejection) (resolve-service catalog 'odin "project-a"))
    (check-false rejection)
    (check-equal? (service-resolution-handle resolved) 3)
    (check-equal? (service-resolution-kind resolved) 'explicit-project)))

;; Equal package identities conflict symmetrically and reveal the factory fallback.
(test-case "package conflicts preserve lower-precedence fallback"
  (define catalog
    (confirmed
     (list (definition 11 "ols" 'factory "" #:default? #t)
           (definition 13 "ols" 'package "package-a" #:default? #t)
           (definition 17 "ols" 'package "package-b" #:default? #t))))
  (check-equal? (service-catalog-package-conflicts catalog) '("ols"))
  (define-values (resolved rejection) (resolve-service catalog 'odin "project-a"))
  (check-false rejection)
  (check-equal? (service-resolution-handle resolved) 11)
  (check-equal? (service-resolution-conflicted resolved) 1))

;; Higher complete records shadow lower identities without merging their fields.
(test-case "personal replacement and factory restoration are scoped"
  (define catalog
    (confirmed
     (list (definition 21 "ols" 'factory "" #:default? #t)
           (definition 23 "ols" 'personal "")
           (definition 29 "racket-lsp" 'factory "" #:languages '(racket) #:default? #t))))
  (define-values (normal normal-rejection) (resolve-service catalog 'odin "project-a"))
  (define-values (restored restored-rejection)
    (resolve-service catalog 'odin "project-a" #:factory? #t))
  (define-values (racket racket-rejection) (resolve-service catalog 'racket "project-a"))
  (check-false normal-rejection)
  (check-false restored-rejection)
  (check-false racket-rejection)
  (check-equal? (service-resolution-handle normal) 23)
  (check-equal? (service-resolution-handle restored) 21)
  (check-equal? (service-resolution-kind restored) 'factory-restoration)
  (check-equal? (service-resolution-handle racket) 29))

;; Ambiguous defaults and invalid explicit choices reject the candidate generation.
(test-case "invalid selection policy preserves the prior catalog"
  (define current (confirmed (list (definition 31 "ols" 'factory "" #:default? #t)) '() 7))
  (define-values (ambiguous accepted? ambiguous-rejection)
    (confirm-service-catalog
     current
     8
     (list (definition 37 "alpha" 'personal "" #:default? #t)
           (definition 41 "beta" 'personal "" #:default? #t))
     '()))
  (check-false accepted?)
  (check-equal? (service-rejection-code ambiguous-rejection) 'ambiguous-default)
  (check-equal? (service-catalog-generation ambiguous) 7)
  (define-values (invalid invalid-accepted? invalid-rejection)
    (confirm-service-catalog
     current
     8
     (service-catalog-definitions current)
     (list (explicit-selection 'odin "missing" 'personal ""))))
  (check-false invalid-accepted?)
  (check-equal? (service-rejection-code invalid-rejection) 'invalid-explicit)
  (check-equal? (service-catalog-generation invalid) 7))

;; A stale candidate never changes the canonical confirmed snapshot.
(test-case "stale generation preserves confirmed service records"
  (define current (confirmed baseline selections 9))
  (define-values (stale accepted? rejection)
    (confirm-service-catalog current 9 (reverse baseline) selections))
  (check-false accepted?)
  (check-equal? (service-rejection-code rejection) 'stale-generation)
  (check-equal? (service-catalog-generation stale) 9)
  (check-equal? (service-catalog-definitions stale)
                (service-catalog-definitions current)))
