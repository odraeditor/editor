#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/package_catalog/integrity.rkt"
         "../../src/package_catalog/security-advisories.rkt"
         "../../src/package_catalog/security-advisory-verification.rkt"
         (submod "../../src/package_catalog/integrity.rkt" test-support))

(define public-key
  "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c")
(define secret-key
  (string-append
   "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
   public-key))
(define other-public-key
  "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
(define other-secret-key
  (string-append
   "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
   other-public-key))
(define key-id (package-catalog-public-key-id public-key))
(define other-key-id (package-catalog-public-key-id other-public-key))
(define catalog-id (make-string 64 #\c))
(define package-id "org.example.package")
(define release-id (make-string 64 #\d))
(define artifact-digest (make-string 64 #\e))
(define issuer
  (odra-security-advisory-issuer
   "official-security" catalog-id (list key-id) 1 10 #f 'trusted))
(define key
  (odra-security-advisory-key
   key-id "official-security" 'ed25519 public-key))

(define (placeholder-signature key-identity)
  (odra-package-catalog-signature
   'ed25519 key-identity package-catalog-advisory-signature-domain
   (make-string 128 #\0)))

(define (make-signed-advisory
         #:issuer-id [issuer-id "official-security"]
         #:catalog [issuer-catalog-id catalog-id]
         #:key-identity [signing-key-id key-id]
         #:secret [signing-secret-key secret-key]
         #:id [id "odra-2026-001"]
         #:generation [generation 1]
         #:state [state 'active]
         #:issued-at [issued-at 20]
         #:previous [previous #f]
         #:artifact [artifact artifact-digest])
  (define reference
    (and previous
         (odra-security-advisory-generation-reference
          (odra-security-advisory-id previous)
          (odra-security-advisory-generation previous)
          (security-advisory-content-digest previous))))
  (define candidate
    (odra-security-advisory
     1 id issuer-id issuer-catalog-id generation state 'malicious 'critical
     'confirmed (list package-id) (list release-id) (list artifact)
     '(block-acquisition block-activation quarantine warn)
     "Confirmed malicious content." issued-at reference
     (list (placeholder-signature signing-key-id))))
  (define message
    (package-catalog-signature-message
     package-catalog-advisory-signature-domain
     (security-advisory-signing-payload candidate)))
  (struct-copy
   odra-security-advisory candidate
   [signatures
    (list
     (odra-package-catalog-signature
      'ed25519 signing-key-id package-catalog-advisory-signature-domain
      (sign-for-test message signing-secret-key)))]))

(define first (make-signed-advisory))

(test-case "issuer-specific signatures verify without catalog membership"
  (check-true (verify-security-advisory issuer (list key) #f 30 first)))

(test-case "exact package release and artifact selectors never match prefixes"
  (check-true
   (security-advisory-matches-release?
    first package-id #f (list (make-string 64 #\a))))
  (check-true
   (security-advisory-matches-release?
    first "org.example.other" release-id '()))
  (check-true
   (security-advisory-matches-release?
    first "org.example.other" #f (list artifact-digest)))
  (check-false
   (security-advisory-matches-release?
    first "org.example" #f
    (list (string-append (substring artifact-digest 0 63) "f")))))

(test-case "correction supersession and withdrawal extend exact history"
  (define corrected
    (make-signed-advisory
     #:generation 2 #:state 'corrected #:issued-at 21 #:previous first))
  (define superseded
    (make-signed-advisory
     #:generation 3 #:state 'superseded #:issued-at 22 #:previous corrected))
  (define withdrawn
    (make-signed-advisory
     #:generation 4 #:state 'withdrawn #:issued-at 23 #:previous superseded))
  (define result
    (verify-security-advisory-history
     (list issuer) (list key) (list first corrected superseded withdrawn) 30))
  (check-equal? (length result) 1)
  (check-eq? (odra-security-advisory-state (car result)) 'withdrawn))

(test-case "a correction cannot rewrite its predecessor"
  (define substituted-first
    (make-signed-advisory #:artifact (make-string 64 #\a)))
  (define corrected
    (make-signed-advisory
     #:generation 2 #:state 'corrected #:issued-at 21
     #:previous substituted-first))
  (define result
    (verify-security-advisory issuer (list key) first 30 corrected))
  (check-true (odra-package-catalog-integrity-failure? result))
  (check-eq? (odra-package-catalog-integrity-failure-code result)
             'advisory-history))

(test-case "conflicting trusted issuers retain independent latest records"
  (define other-issuer
    (odra-security-advisory-issuer
     "community-security" (make-string 64 #\b) (list other-key-id) 1
     10 #f 'trusted))
  (define other-key
    (odra-security-advisory-key
     other-key-id "community-security" 'ed25519 other-public-key))
  (define conflicting
    (make-signed-advisory
     #:issuer-id "community-security" #:catalog (make-string 64 #\b)
     #:key-identity other-key-id #:secret other-secret-key #:state 'withdrawn))
  (define result
    (verify-security-advisory-history
     (list issuer other-issuer) (list key other-key) (list first conflicting) 30))
  (check-equal? (length result) 2)
  (check-equal?
   (map odra-security-advisory-issuer-id result)
   '("community-security" "official-security")))

(test-case "future stale and untrusted advisories fail closed"
  (define future (make-signed-advisory #:issued-at 31))
  (define future-result
    (verify-security-advisory issuer (list key) #f 30 future))
  (check-eq? (odra-package-catalog-integrity-failure-code future-result)
             'advisory-issuer)
  (define revoked
    (struct-copy odra-security-advisory-issuer issuer [status 'revoked]))
  (define revoked-result
    (verify-security-advisory revoked (list key) #f 30 first))
  (check-eq? (odra-package-catalog-integrity-failure-code revoked-result)
             'advisory-issuer))

(test-case "wrong-domain advisory signatures fail closed"
  (define wrong-domain
    (struct-copy
     odra-security-advisory first
     [signatures
      (list
       (struct-copy
        odra-package-catalog-signature
        (car (odra-security-advisory-signatures first))
        [domain package-catalog-publisher-signature-domain]))]))
  (define result
    (verify-security-advisory issuer (list key) #f 30 wrong-domain))
  (check-eq? (odra-package-catalog-integrity-failure-code result)
             'signature-domain))
