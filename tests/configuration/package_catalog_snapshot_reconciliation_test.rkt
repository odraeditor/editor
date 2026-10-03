#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         rackunit
         "../../src/package_catalog/contracts.rkt"
         "../../src/package_catalog/integrity.rkt"
         "../../src/package_catalog/snapshot-records.rkt"
         "../../src/package_catalog/snapshot-reconciliation.rkt"
         "../../src/package_catalog/state-persistence.rkt"
         "../../src/package_catalog/state-records.rkt"
         (submod "../../src/package_catalog/integrity.rkt" test-support))

(define root-public-key
  "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
(define publisher-public-key
  "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c")
(define publisher-secret-key
  (string-append
   "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
   publisher-public-key))
(define root-id (package-catalog-public-key-id root-public-key))
(define publisher-key-id (package-catalog-public-key-id publisher-public-key))
(define root
  (odra-package-catalog-root-key root-id 1 'ed25519 root-public-key 1 #f))
(define catalog-id (package-catalog-identity root))
(define publisher-key
  (odra-package-catalog-publisher-key
   publisher-key-id 'ed25519 publisher-public-key))
(define publisher
  (odra-package-catalog-publisher-authorization
   "snapshot-publisher" (list publisher-key-id) 1 1 #f))
(define policy
  (odra-package-catalog-policy
   "policy-v1" 1 1 "eligible" "authority" "assessment" "decision"
   "retention"))
(define origin
  (odra-package-catalog-endpoint
   "origin" catalog-id "https://catalog.example/snapshots" 'https 'origin 0 #t))
(define mirror
  (odra-package-catalog-endpoint
   "mirror" catalog-id "https://mirror.example/snapshots" 'https 'mirror 1 #t))
(define endpoint-states
  (list (odra-package-catalog-state-endpoint 1 1 origin #f)
        (odra-package-catalog-state-endpoint 1 1 mirror #f)))
(define registration
  (odra-package-catalog-registration
   1 "official" 1 catalog-id 'built-in root-id '("mirror" "origin")
   0 'enforce #t 'never))
(define-values
  (profile profile-rejection)
  (confirm-package-catalog-profile
   (odra-package-catalog-profile-proposal
    1 catalog-id "Catalog" (list root) '() (list publisher) (list policy)
    (list origin mirror))))

(define (signed-snapshot sequence previous assertion-digest)
  (define draft
    (odra-package-catalog-snapshot
     1 (make-string 64 #\0) catalog-id sequence previous "policy-v1"
     (* sequence 10) 200 assertion-digest (make-string 64 #\b) 1024
     "snapshot-publisher" '()))
  (define identified
    (struct-copy odra-package-catalog-snapshot draft
                 [id (package-catalog-snapshot-content-digest draft)]))
  (define message
    (package-catalog-signature-message
     package-catalog-publisher-signature-domain
     (package-catalog-snapshot-signing-payload identified)))
  (struct-copy
   odra-package-catalog-snapshot identified
   [signatures
    (list
     (odra-package-catalog-signature
      'ed25519 publisher-key-id package-catalog-publisher-signature-domain
      (sign-for-test message publisher-secret-key)))]))

(define first (signed-snapshot 1 #f (make-string 64 #\a)))
(define second
  (signed-snapshot 2 (odra-package-catalog-snapshot-id first)
                   (make-string 64 #\c)))

(define (observation endpoint state [snapshot #f])
  (odra-package-catalog-snapshot-observation
   endpoint state snapshot (if snapshot 1024 0)
   (if snapshot "" "endpoint unavailable")))

(define (with-root action)
  (define root-path
    (make-temporary-file "odra-package-catalog-snapshot-cache-~a" 'directory))
  (file-or-directory-permissions root-path #o700)
  (dynamic-wind void (lambda () (action root-path))
                (lambda () (delete-directory/files root-path))))

(define (registered-state)
  (define-values (state rejection)
    (package-catalog-state-register
     (package-catalog-empty-state "default") registration endpoint-states
     'built-in-bootstrap 1))
  (check-false rejection)
  state)

(test-case "origin and exact mirror confirm one snapshot identity"
  (check-false profile-rejection)
  (define result
    (reconcile-package-catalog-snapshots
     profile (list publisher-key) first
     (list (observation origin 'available second)
           (observation mirror 'available second))
     30))
  (check-eq? (odra-package-catalog-snapshot-reconciliation-mode result)
             'confirmed)
  (check-equal?
   (odra-package-catalog-snapshot-reconciliation-endpoint-ids result)
   '("mirror" "origin")))

(test-case "valid mirror recovers an unavailable origin"
  (define result
    (reconcile-package-catalog-snapshots
     profile (list publisher-key) first
     (list (observation origin 'unavailable)
           (observation mirror 'available second))
     30))
  (check-eq? (odra-package-catalog-snapshot-reconciliation-mode result)
             'confirmed)
  (check-equal?
   (odra-package-catalog-snapshot-reconciliation-endpoint-ids result)
   '("mirror")))

(test-case "offline reconciliation retains the last confirmed snapshot"
  (define result
    (reconcile-package-catalog-snapshots
     profile (list publisher-key) first
     (list (observation origin 'unavailable)
           (observation mirror 'unavailable))
     300))
  (check-eq? (odra-package-catalog-snapshot-reconciliation-mode result) 'offline)
  (check-equal? (odra-package-catalog-snapshot-reconciliation-snapshot result)
                first))

(test-case "signed origin and mirror divergence retains prior state"
  (define fork
    (signed-snapshot 2 (odra-package-catalog-snapshot-id first)
                     (make-string 64 #\d)))
  (define result
    (reconcile-package-catalog-snapshots
     profile (list publisher-key) first
     (list (observation origin 'available second)
           (observation mirror 'available fork))
     30))
  (check-eq? (odra-package-catalog-snapshot-reconciliation-mode result)
             'divergent)
  (check-equal? (odra-package-catalog-snapshot-reconciliation-snapshot result)
                first))

(test-case "confirmed cache publishes before durable state references it"
  (with-root
   (lambda (root-path)
     (define reconciliation
       (reconcile-package-catalog-snapshots
        profile (list publisher-key) first
        (list (observation origin 'available second)) 30))
     (define cached
       (package-catalog-snapshot-cache-persist root-path reconciliation))
     (check-true (odra-package-catalog-snapshot-cache-result? cached))
     (check-eq? (odra-package-catalog-snapshot-cache-result-status cached)
                'published)
     (check-equal?
      (package-catalog-snapshot-module-load
       (odra-package-catalog-snapshot-cache-result-path cached))
      second)
     (define reference
       (package-catalog-snapshot-confirmed-reference
        second
        (odra-package-catalog-snapshot-cache-result-reference cached)
        30))
     (check-equal?
      (odra-package-catalog-confirmed-snapshot-reference-digest reference)
      (package-catalog-snapshot-module-digest second))
     (define-values (state rejection)
       (package-catalog-state-confirm-snapshot
        (registered-state) reference 2))
     (check-false rejection)
     (check-equal?
      (odra-package-catalog-state-confirmed-snapshots state)
      (list reference))
     (define duplicate
       (package-catalog-snapshot-cache-persist root-path reconciliation))
     (check-eq? (odra-package-catalog-snapshot-cache-result-status duplicate)
                'already-present))))
