#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/package_catalog/contracts.rkt")

(define digest-a (make-string 64 #\a))
(define digest-b (make-string 64 #\b))
(define digest-c (make-string 64 #\c))
(define root-a
  (odra-package-catalog-root-key digest-a 1 'ed25519 digest-b 10 #f))
(define policy-a
  (odra-package-catalog-policy
   "official-policy" 1 1 "eligibility/v1" "authority/v1" "assessment/v1"
   "decision/v1" "retention/v1"))
(define curator-a
  (odra-package-catalog-curator-authorization
   "primary-curator" "maintainer" 'human 10 #f '("official-policy")))
(define publisher-a
  (odra-package-catalog-publisher-authorization
   "snapshot-publisher" (list digest-c) 1 10 100))
(define endpoint-a
  (odra-package-catalog-endpoint
   "origin" digest-a "https://catalog.example/odra/index.rktd"
   'https 'origin 10 #t))

(define (proposal #:display-name [display-name "Odra Package Catalog"]
                  #:roots [roots (list root-a)]
                  #:curators [curators (list curator-a)]
                  #:publishers [publishers (list publisher-a)]
                  #:policies [policies (list policy-a)]
                  #:endpoints [endpoints (list endpoint-a)])
  (odra-package-catalog-profile-proposal
   current-package-catalog-identity-format-version digest-a display-name
   roots curators publishers policies endpoints))

(test-case "confirmed catalog identity is independent of endpoints and display text"
  (define-values (first first-rejection) (confirm-package-catalog-profile (proposal)))
  (define-values
    (second second-rejection)
    (confirm-package-catalog-profile
     (proposal
      #:display-name "Renamed Catalog"
      #:endpoints
      (list
       (odra-package-catalog-endpoint
        "mirror" digest-a "https://mirror.example/odra/index.rktd"
        'https 'mirror 20 #t)))))
  (check-false first-rejection)
  (check-false second-rejection)
  (check-true (same-package-catalog-identity? first second)))

(test-case "profile confirmation normalizes unordered independent records"
  (define root-b
    (odra-package-catalog-root-key digest-b 2 'ed25519 digest-c 20 #f))
  (define endpoint-b
    (odra-package-catalog-endpoint
     "mirror" digest-a "https://mirror.example/odra/index.rktd"
     'https 'mirror 20 #t))
  (define-values
    (confirmed rejection)
    (confirm-package-catalog-profile
     (proposal #:roots (list root-b root-a)
               #:endpoints (list endpoint-b endpoint-a))))
  (check-false rejection)
  (check-equal? (map odra-package-catalog-root-key-id
                     (odra-package-catalog-profile-roots confirmed))
                (list digest-a digest-b))
  (check-equal? (map odra-package-catalog-endpoint-id
                     (odra-package-catalog-profile-endpoints confirmed))
                '("mirror" "origin")))

(test-case "record constructors retain immutable copies of caller text"
  (define mutable-name (string-copy "Mutable Catalog"))
  (define mutable-policy (string-copy "official-policy"))
  (define mutable-policies (list mutable-policy))
  (define authorization
    (odra-package-catalog-curator-authorization
     "copy-curator" "maintainer" 'human 10 #f mutable-policies))
  (define candidate (proposal #:display-name mutable-name
                              #:curators (list authorization)))
  (string-set! mutable-name 0 #\X)
  (string-set! mutable-policy 0 #\X)
  (check-equal? (odra-package-catalog-profile-proposal-display-name candidate)
                "Mutable Catalog")
  (check-equal?
   (odra-package-catalog-curator-authorization-policy-ids authorization)
   '("official-policy"))
  (check-true
   (immutable? (odra-package-catalog-profile-proposal-display-name candidate))))

(test-case "only human subjects can receive curator authority"
  (check-exn
   exn:fail?
   (lambda ()
     (odra-package-catalog-curator-authorization
      "automated-curator" "assessment-service" 'ai-assisted 10 #f
      '("official-policy")))))

(test-case "publisher authorization is threshold constrained and time bounded"
  (check-false
   (package-catalog-publisher-authorization-active?
    publisher-a 9 (list digest-c)))
  (check-true
   (package-catalog-publisher-authorization-active?
    publisher-a 10 (list digest-c)))
  (check-false
   (package-catalog-publisher-authorization-active?
    publisher-a 101 (list digest-c)))
  (check-exn
   exn:fail?
   (lambda ()
     (odra-package-catalog-publisher-authorization
      "invalid-publisher" (list digest-b) 2 10 #f))))

(test-case "profile confirmation returns a typed rejection for foreign endpoints"
  (define foreign-endpoint
    (odra-package-catalog-endpoint
     "foreign" digest-b "https://catalog.example/foreign/index.rktd"
     'https 'origin 10 #t))
  (define-values
    (confirmed rejection)
    (confirm-package-catalog-profile (proposal #:endpoints (list foreign-endpoint))))
  (check-false confirmed)
  (check-true (odra-package-catalog-rejection? rejection))
  (check-eq? (odra-package-catalog-rejection-code rejection) 'invalid-field)
  (check-eq? (odra-package-catalog-rejection-field rejection) 'endpoints))

(test-case "profile confirmation rejects duplicate semantic generations"
  (define root-b
    (odra-package-catalog-root-key digest-b 1 'ed25519 digest-c 20 #f))
  (define-values
    (confirmed rejection)
    (confirm-package-catalog-profile (proposal #:roots (list root-a root-b))))
  (check-false confirmed)
  (check-eq? (odra-package-catalog-rejection-code rejection)
             'duplicate-identity)
  (check-eq? (odra-package-catalog-rejection-field rejection)
             'root-generations))
