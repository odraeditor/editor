#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/package_catalog/contracts.rkt"
         "../../src/package_catalog/integrity.rkt"
         (submod "../../src/package_catalog/contracts.rkt" test-support))

(define root-public-key
  "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
(define publisher-public-key
  "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c")
(define root-key-id (package-catalog-public-key-id root-public-key))
(define publisher-key-id (package-catalog-public-key-id publisher-public-key))
(define root
  (odra-package-catalog-root-key
   root-key-id 1 'ed25519 root-public-key 10 #f))
(define catalog-id (package-catalog-identity root))
(define policy
  (odra-package-catalog-policy
   "policy-one" 1 1 "eligibility/v1" "authority/v1" "assessment/v1"
   "decision/v1" "retention/v1"))
(define curator
  (odra-package-catalog-curator-authorization
   "primary-curator" "maintainer" 'human 10 #f '("policy-one")))
(define publisher
  (odra-package-catalog-publisher-authorization
   "snapshot-publisher" (list publisher-key-id) 1 10 #f))
(define endpoint
  (odra-package-catalog-endpoint
   "origin" catalog-id "https://catalog.example/odra/index.rktd"
   'https 'origin 10 #t))

(define (proposal #:roots [roots (list root)]
                  #:curators [curators (list curator)]
                  #:publishers [publishers (list publisher)]
                  #:policies [policies (list policy)]
                  #:endpoints [endpoints (list endpoint)])
  (odra-package-catalog-profile-proposal
   1 catalog-id "Odra Package Catalog" roots curators publishers policies
   endpoints))

(define (hex-identity value)
  (define text (number->string value 16))
  (string-append (make-string (- 64 (string-length text)) #\0) text))

(test-case "root authority cannot satisfy ordinary publisher authorization"
  (define invalid-publisher
    (odra-package-catalog-publisher-authorization
     "root-backed-publisher" (list root-key-id) 1 10 #f))
  (define-values
    (confirmed rejection)
    (confirm-package-catalog-profile
     (proposal #:publishers (list invalid-publisher))))
  (check-false confirmed)
  (check-eq? (odra-package-catalog-rejection-code rejection)
             'invalid-authority)
  (check-eq? (odra-package-catalog-rejection-field rejection)
             'publisher-authorizations))

(test-case "regressive policy activation rejects a newer generation"
  (define policy-two
    (odra-package-catalog-policy
     "policy-two" 2 1 "eligibility/v2" "authority/v2" "assessment/v2"
     "decision/v2" "retention/v2"))
  (define policy-one-late
    (struct-copy odra-package-catalog-policy policy [effective-from 2]))
  (define curator-both
    (odra-package-catalog-curator-authorization
     "primary-curator" "maintainer" 'human 10 #f
     '("policy-one" "policy-two")))
  (define-values
    (confirmed rejection)
    (confirm-package-catalog-profile
     (proposal #:policies (list policy-two policy-one-late)
               #:curators (list curator-both))))
  (check-false confirmed)
  (check-eq? (odra-package-catalog-rejection-code rejection)
             'stale-generation))

(test-case "invalid root and authorization intervals fail before confirmation"
  (check-exn
   exn:fail?
   (lambda ()
     (odra-package-catalog-root-key
      root-key-id 1 'ed25519 root-public-key 20 10)))
  (check-exn
   exn:fail?
   (lambda ()
     (odra-package-catalog-curator-authorization
      "primary-curator" "maintainer" 'human 20 10 '("policy-one"))))
  (check-exn
   exn:fail?
   (lambda ()
     (odra-package-catalog-publisher-authorization
      "snapshot-publisher" (list publisher-key-id) 1 20 10))))

(test-case "collection maxima reject before canonical identity work"
  (define roots
    (for/list ([generation
                (in-range 1 (+ maximum-package-catalog-root-keys 2))])
      (odra-package-catalog-root-key
       (hex-identity generation) generation 'ed25519 (hex-identity (+ 100 generation))
       10 #f)))
  (define-values
    (confirmed rejection)
    (confirm-package-catalog-profile (proposal #:roots roots)))
  (check-false confirmed)
  (check-eq? (odra-package-catalog-rejection-code rejection) 'limit)
  (check-eq? (odra-package-catalog-rejection-field rejection) 'root-keys)
  (check-equal? (odra-package-catalog-rejection-limit rejection)
                maximum-package-catalog-root-keys))

(test-case "normalization allocation failure becomes a bounded typed rejection"
  (define-values
    (confirmed rejection)
    (confirm-package-catalog-profile-with-normalizer-for-test
     (proposal)
     (lambda (_proposal)
       (raise
        (exn:fail:out-of-memory
         "fixture allocation failure" (current-continuation-marks))))))
  (check-false confirmed)
  (check-eq? (odra-package-catalog-rejection-code rejection) 'allocation)
  (check-eq? (odra-package-catalog-rejection-field rejection) 'profile)
  (check-false (odra-package-catalog-rejection-actual rejection)))

(test-case "discarded confirmed profiles retain no catalog-owned root"
  (define discarded-profile
    (let-values ([(confirmed rejection)
                  (confirm-package-catalog-profile (proposal))])
      (check-false rejection)
      (make-weak-box confirmed)))
  (collect-garbage)
  (collect-garbage)
  (check-false (weak-box-value discarded-profile)))
