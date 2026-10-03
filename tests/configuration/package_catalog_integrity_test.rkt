#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/package_catalog/contracts.rkt"
         "../../src/package_catalog/integrity.rkt"
         (submod "../../src/package_catalog/integrity.rkt" test-support))

(define root-public-key
  "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
(define root-secret-key
  (string-append
   "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
   root-public-key))
(define publisher-public-key
  "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c")
(define publisher-secret-key
  (string-append
   "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
   publisher-public-key))
(define root-key-id (package-catalog-public-key-id root-public-key))
(define publisher-key-id (package-catalog-public-key-id publisher-public-key))
(define root
  (odra-package-catalog-root-key
   root-key-id 1 'ed25519 root-public-key 10 #f))
(define catalog-id (package-catalog-identity root))
(define publisher-key
  (odra-package-catalog-publisher-key
   publisher-key-id 'ed25519 publisher-public-key))
(define policy
  (odra-package-catalog-policy
   "official-policy" 1 1 "eligibility/v1" "authority/v1" "assessment/v1"
   "decision/v1" "retention/v1"))
(define curator
  (odra-package-catalog-curator-authorization
   "primary-curator" "maintainer" 'human 10 #f '("official-policy")))
(define publisher
  (odra-package-catalog-publisher-authorization
   "snapshot-publisher" (list publisher-key-id) 1 10 #f))
(define endpoint
  (odra-package-catalog-endpoint
   "origin" catalog-id "https://catalog.example/odra/index.rktd"
   'https 'origin 10 #t))
(define-values
  (profile profile-rejection)
  (confirm-package-catalog-profile
   (odra-package-catalog-profile-proposal
    1 catalog-id "Odra Package Catalog" (list root) (list curator)
    (list publisher) (list policy) (list endpoint))))

(define root-message
  (package-catalog-signature-message
   package-catalog-root-signature-domain
   (list 'package-catalog-profile
         (odra-package-catalog-profile-format-version profile)
         (odra-package-catalog-profile-identity profile)
         (odra-package-catalog-profile-display-name profile)
         (list
          (list root-key-id 1 'ed25519 root-public-key 10 #f))
         (list
          (list "primary-curator" "maintainer" 'human 10 #f
                '("official-policy")))
         (list
          (list "snapshot-publisher" (list publisher-key-id) 1 10 #f))
         (list
          (list "official-policy" 1 1 "eligibility/v1" "authority/v1"
                "assessment/v1" "decision/v1" "retention/v1"))
         (list
          (list "origin" catalog-id
                "https://catalog.example/odra/index.rktd"
                'https 'origin 10 #t)))))
(define root-signature
  (odra-package-catalog-signature
   'ed25519 root-key-id package-catalog-root-signature-domain
   (sign-for-test root-message root-secret-key)))
(define publisher-payload
  (list 'catalog-snapshot catalog-id 1 "snapshot-digest"))
(define publisher-message
  (package-catalog-signature-message
   package-catalog-publisher-signature-domain publisher-payload))
(define publisher-signature
  (odra-package-catalog-signature
   'ed25519 publisher-key-id package-catalog-publisher-signature-domain
   (sign-for-test publisher-message publisher-secret-key)))

(test-case "catalog identity is derived from initial public root material"
  (check-false profile-rejection)
  (check-equal? (package-catalog-public-key-id root-public-key) root-key-id)
  (check-true (verify-package-catalog-profile-identity profile)))

(test-case "canonical profile bytes are deterministic and immutable"
  (define first (package-catalog-profile->canonical-bytes profile))
  (define second (package-catalog-profile->canonical-bytes profile))
  (check-equal? first second)
  (check-true (immutable? first)))

(test-case "root signature verifies only in the root authority domain"
  (check-true (verify-package-catalog-root-signature profile root-signature))
  (define wrong-domain-signature
    (odra-package-catalog-signature
     'ed25519 root-key-id package-catalog-publisher-signature-domain
     (odra-package-catalog-signature-value root-signature)))
  (define failure
    (verify-package-catalog-root-signature profile wrong-domain-signature))
  (check-true (odra-package-catalog-integrity-failure? failure))
  (check-eq? (odra-package-catalog-integrity-failure-code failure)
             'signature-domain))

(test-case "constrained publisher signature satisfies its authorization"
  (check-true
   (verify-package-catalog-publisher-signatures
    publisher (list publisher-key) (list publisher-signature) 10
    publisher-payload)))

(test-case "root key cannot substitute for an ordinary publisher key"
  (define root-as-publisher
    (odra-package-catalog-publisher-key root-key-id 'ed25519 root-public-key))
  (define failure
    (verify-package-catalog-publisher-signatures
     publisher (list root-as-publisher) (list root-signature) 10
     publisher-payload))
  (check-true (odra-package-catalog-integrity-failure? failure))
  (check-eq? (odra-package-catalog-integrity-failure-code failure)
             'publisher-authorization))

(test-case "tampered publisher payload rejects its detached signature"
  (define failure
    (verify-package-catalog-publisher-signatures
     publisher (list publisher-key) (list publisher-signature) 10
     (list 'catalog-snapshot catalog-id 2 "snapshot-digest")))
  (check-true (odra-package-catalog-integrity-failure? failure))
  (check-eq? (odra-package-catalog-integrity-failure-code failure) 'signature))
