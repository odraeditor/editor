#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/path
         rackunit
         "../../src/package_catalog/contracts.rkt"
         "../../src/package_catalog/state-persistence.rkt"
         "../../src/package_catalog/state-records.rkt")

(define catalog-id (make-string 64 #\a))
(define root-key-id (make-string 64 #\b))
(define snapshot-id (make-string 64 #\c))
(define snapshot-digest (make-string 64 #\d))
(define endpoint
  (odra-package-catalog-endpoint
   "origin" catalog-id "https://catalog.example/odra/index.rktd"
   'https 'origin 10 #t))
(define endpoint-state
  (odra-package-catalog-state-endpoint 1 1 endpoint #f))
(define registration
  (odra-package-catalog-registration
   1 "official" 1 catalog-id 'built-in root-key-id '("origin")
   10 'enforce #t 'never))
(define confirmed
  (odra-package-catalog-confirmed-snapshot-reference
   1 catalog-id snapshot-id 1 snapshot-digest
   "snapshots/official/1.rktd" 100))

(define (with-root action)
  (define root (make-temporary-file "odra-package-catalog-persist-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind void (lambda () (action root))
                (lambda () (delete-directory/files root))))

(define (persist! root state)
  (define result (package-catalog-state-persist root state))
  (check-true (odra-record-publication? result) (format "~s" result))
  result)

(define (registered-state)
  (define empty (package-catalog-empty-state "default"))
  (define-values (state rejection)
    (package-catalog-state-register
     empty registration (list endpoint-state) 'built-in-bootstrap 1))
  (check-false rejection)
  state)

(test-case "explicit registration publishes and restarts durably"
  (with-root
   (lambda (root)
     (persist! root (package-catalog-empty-state "default"))
     (define state (registered-state))
     (define publication (persist! root state))
     (check-true (odra-record-publication-file-synced? publication))
     (check-true (odra-record-publication-directory-synced? publication))
     (define startup (package-catalog-state-startup root "default"))
     (check-eq? (odra-package-catalog-startup-mode startup) 'confirmed)
     (check-equal? (odra-package-catalog-startup-state startup) state))))

(test-case "catalog data cannot request transitive registration"
  (define empty (package-catalog-empty-state "default"))
  (define-values (state rejection)
    (package-catalog-state-register
     empty registration (list endpoint-state) 'snapshot 1))
  (check-equal? state empty)
  (check-eq? (odra-package-catalog-state-rejection-code rejection)
             'transitive-enrollment))

(test-case "disablement is durable and performs no package lifecycle operation"
  (with-root
   (lambda (root)
     (persist! root (package-catalog-empty-state "default"))
     (persist! root (registered-state))
     (define-values (disabled rejection)
       (package-catalog-state-set-enabled (registered-state) "official" #f 2))
     (check-false rejection)
     (persist! root disabled)
     (define recovered
       (odra-package-catalog-startup-state
        (package-catalog-state-startup root "default")))
     (define recovered-registration
       (car (odra-package-catalog-state-registrations recovered)))
     (check-false
      (odra-package-catalog-registration-enabled? recovered-registration))
     (check-eq?
      (odra-package-catalog-registration-refresh-state recovered-registration)
      'blocked))))

(test-case "removal retains the independently confirmed snapshot reference"
  (define registered (registered-state))
  (define-values (with-confirmed confirm-rejection)
    (package-catalog-state-confirm-snapshot registered confirmed 2))
  (check-false confirm-rejection)
  (define-values (removed remove-rejection)
    (package-catalog-state-remove with-confirmed "official" 3))
  (check-false remove-rejection)
  (check-equal? (odra-package-catalog-state-registrations removed) '())
  (check-equal? (odra-package-catalog-state-endpoints removed) '())
  (check-equal? (odra-package-catalog-state-confirmed-snapshots removed)
                (list confirmed)))

(test-case "cleanup excludes confirmed and quarantined durable references"
  (define registered (registered-state))
  (define-values (with-confirmed rejection)
    (package-catalog-state-confirm-snapshot registered confirmed 2))
  (check-false rejection)
  (define state
    (package-catalog-state-with-checksum
     (struct-copy odra-package-catalog-state with-confirmed
                  [quarantine '("quarantine/damaged.rktd")]
                  [checksum (make-string 64 #\0)])))
  (check-equal?
   (package-catalog-state-reachable-references state)
   '("quarantine/damaged.rktd" "snapshots/official/1.rktd"))
  (check-equal?
   (package-catalog-state-cleanup-plan
    state
    '("snapshots/official/1.rktd" "snapshots/official/old.rktd"
                                      "quarantine/damaged.rktd"))
   '("snapshots/official/old.rktd")))

(test-case "stale persistence leaves authoritative bytes unchanged"
  (with-root
   (lambda (root)
     (define initial (package-catalog-empty-state "default"))
     (persist! root initial)
     (define path (package-catalog-state-path root))
     (define before (file->bytes path))
     (define result (package-catalog-state-persist root initial))
     (check-true (odra-record-publication-failure? result))
     (check-eq? (odra-record-publication-failure-code result)
                'invalid-generation)
     (check-equal? (file->bytes path) before))))
