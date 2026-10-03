#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/package_catalog/contracts.rkt"
         "../../src/package_catalog/integrity.rkt"
         "../../src/package_catalog/snapshot-records.rkt"
         "../../src/package_catalog/snapshot-verification.rkt"
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
(define endpoint
  (odra-package-catalog-endpoint
   "origin" catalog-id "https://catalog.example/snapshots" 'https 'origin 0 #t))
(define-values
  (profile profile-rejection)
  (confirm-package-catalog-profile
   (odra-package-catalog-profile-proposal
    1 catalog-id "Catalog" (list root) '() (list publisher) (list policy)
    (list endpoint))))

(define (signed-snapshot sequence previous issued-at expires-at
                         #:catalog-id [selected-catalog-id catalog-id]
                         #:metadata-size [metadata-size 1024]
                         #:publisher-id [publisher-id "snapshot-publisher"]
                         #:assertion-digest [assertion-digest (make-string 64 #\a)])
  (define draft
    (odra-package-catalog-snapshot
     1 (make-string 64 #\0) selected-catalog-id sequence previous "policy-v1"
     issued-at expires-at assertion-digest (make-string 64 #\b) metadata-size
     publisher-id '()))
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

(define first (signed-snapshot 1 #f 10 100))
(define second (signed-snapshot 2 (odra-package-catalog-snapshot-id first) 20 120))

(test-case "complete signed bootstrap and successor snapshots verify"
  (check-false profile-rejection)
  (check-true
   (verify-package-catalog-snapshot profile (list publisher-key) #f 20 1024 first))
  (check-true
   (verify-package-catalog-snapshot
    profile (list publisher-key) first 30 1024 second)))

(test-case "latest signed bootstrap requires explicit built-in policy"
  (check-eq?
   (odra-package-catalog-snapshot-failure-code
    (verify-package-catalog-snapshot
     profile (list publisher-key) #f 30 1024 second))
   'history)
  (check-true
   (verify-package-catalog-snapshot
    profile (list publisher-key) #f 30 1024 second
    #:allow-bootstrap-latest? #t)))

(test-case "snapshot content digest and signature both bind immutable content"
  (define tampered
    (struct-copy odra-package-catalog-snapshot second
                 [assertion-set-digest (make-string 64 #\c)]))
  (check-eq?
   (odra-package-catalog-snapshot-failure-code
    (verify-package-catalog-snapshot
     profile (list publisher-key) first 30 1024 tampered))
   'snapshot-digest)
  (define reidentified
    (struct-copy odra-package-catalog-snapshot tampered
                 [id (package-catalog-snapshot-content-digest tampered)]))
  (check-eq?
   (odra-package-catalog-snapshot-failure-code
    (verify-package-catalog-snapshot
     profile (list publisher-key) first 30 1024 reidentified))
   'signature))

(test-case "rollback and predecessor substitution reject"
  (define rollback (signed-snapshot 1 #f 20 120))
  (check-eq?
   (odra-package-catalog-snapshot-failure-code
    (verify-package-catalog-snapshot
     profile (list publisher-key) first 30 1024 rollback))
   'sequence)
  (define substituted (signed-snapshot 2 (make-string 64 #\f) 20 120))
  (check-eq?
   (odra-package-catalog-snapshot-failure-code
    (verify-package-catalog-snapshot
     profile (list publisher-key) first 30 1024 substituted))
   'history))

(test-case "future expired and size-mismatched snapshots reject"
  (check-eq?
   (odra-package-catalog-snapshot-failure-code
    (verify-package-catalog-snapshot
     profile (list publisher-key) #f 9 1024 first))
   'not-yet-valid)
  (check-eq?
   (odra-package-catalog-snapshot-failure-code
    (verify-package-catalog-snapshot
     profile (list publisher-key) #f 100 1024 first))
   'expiry)
  (check-eq?
   (odra-package-catalog-snapshot-failure-code
    (verify-package-catalog-snapshot
     profile (list publisher-key) #f 20 1000 first))
   'metadata-size))

(test-case "foreign catalogs and unknown publishers reject"
  (define foreign
    (signed-snapshot 1 #f 10 100 #:catalog-id (make-string 64 #\e)))
  (check-eq?
   (odra-package-catalog-snapshot-failure-code
    (verify-package-catalog-snapshot
     profile (list publisher-key) #f 20 1024 foreign))
   'catalog-identity)
  (define unknown
    (signed-snapshot 1 #f 10 100 #:publisher-id "unknown-publisher"))
  (check-eq?
   (odra-package-catalog-snapshot-failure-code
    (verify-package-catalog-snapshot
     profile (list publisher-key) #f 20 1024 unknown))
   'publisher-authorization))
