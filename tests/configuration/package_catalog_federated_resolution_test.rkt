#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/language_bundle/advisory-response.rkt"
         "../../src/package_catalog/curation-records.rkt"
         "../../src/package_catalog/curation-resolution.rkt"
         "../../src/package_catalog/federated-resolution.rkt"
         "../../src/package_catalog/integrity.rkt"
         "../../src/package_catalog/security-advisories.rkt"
         "../../src/package_catalog/state-records.rkt")

(define (digest character) (make-string 64 character))
(define catalog-a (digest #\a))
(define catalog-b (digest #\b))

(define policy
  (odra-security-advisory-response-policy
   "default-security" 1 '(warn)
   '(block-acquisition block-activation quarantine warn)
   '(block-activation warn) '(warn) #t))

(define (release package-id version release-id artifact-digest)
  (odra-package-release-reference
   1 package-id release-id version "org.example.publisher"
   "https://forge.example/org/package" (make-string 40 #\d) #f (digest #\c)
   (list
    (odra-package-artifact-reference
     'linux 'x86-64 '("artifact.tar.zst") artifact-digest 1024 #f #f
     'unverified))
   (digest #\e) (digest #\f) (digest #\1) (digest #\2)))

(define (assertion catalog id release [status 'admitted])
  (odra-package-curation-assertion
   1 id catalog 1 release "decision-1" "policy-v1" status
   (if (eq? status 'admitted) "" "Not available") '() 1 1))

(define (federated-source catalog registration-id precedence refresh-state
                          assertions)
  (define snapshot-id (digest #\9))
  (odra-federated-package-source
   (odra-package-catalog-registration
    1 registration-id 1 catalog 'user (digest #\8) '("origin") precedence
    'enforce #t refresh-state)
   (odra-package-catalog-confirmed-snapshot-reference
    1 catalog snapshot-id 1 (digest #\7) "catalog/snapshot.rktd" 20)
   (odra-package-curated-source catalog snapshot-id precedence assertions)))

(define (request package-id #:pin [pin #f])
  (odra-package-resolution-request
   package-id "0.0.0" "99.0.0" 'linux 'x86-64 pin))

(define (resolve sources request
                 #:pins [pins '()]
                 #:organizations [organizations '()]
                 #:advisories [advisories '()])
  (resolve-federated-package
   sources request advisories policy 30 '()
   #:source-pins pins #:organization-overrides organizations))

(test-case "search preserves curator attribution and offline freshness"
  (define shared (release "org.example.package" "1.0.0" (digest #\3) (digest #\4)))
  (define matches
    (search-federated-packages
     (list
      (federated-source
       catalog-b "catalog-b" 10 'offline
       (list (assertion catalog-b (digest #\6) shared)))
      (federated-source
       catalog-a "catalog-a" 20 'current
       (list (assertion catalog-a (digest #\5) shared))))
     "org.example" 'linux 'x86-64 10))
  (check-equal? (length matches) 2)
  (check-equal?
   (map
    (lambda (match)
      (odra-federated-catalog-attribution-catalog-id
       (odra-federated-package-match-attribution match)))
    matches)
   (list catalog-a catalog-b))
  (check-equal?
   (map
    (lambda (match)
      (odra-federated-catalog-attribution-freshness
       (odra-federated-package-match-attribution match)))
    matches)
   '(current offline)))

(test-case "search limits only admitted and deprecated matches"
  (define admitted
    (release "org.example.package" "1.0.0" (digest #\3) (digest #\4)))
  (define withdrawn
    (release "org.example.package" "0.9.0" (digest #\5) (digest #\6)))
  (define matches
    (search-federated-packages
     (list
      (federated-source
       catalog-a "catalog-a" 20 'current
       (list (assertion catalog-a (digest #\7) admitted)
             (assertion catalog-a (digest #\8) withdrawn 'withdrawn))))
     "org.example" 'linux 'x86-64 10))
  (check-equal? (length matches) 1)
  (check-equal?
   (odra-federated-package-match-version (car matches))
   "1.0.0"))

(test-case "package pins override organization policy deterministically"
  (define first
    (release "org.example.package" "1.0.0" (digest #\3) (digest #\4)))
  (define second
    (release "org.example.package" "2.0.0" (digest #\5) (digest #\6)))
  (define result
    (resolve
     (list
      (federated-source
       catalog-a "catalog-a" 20 'current
       (list (assertion catalog-a (digest #\7) first)))
      (federated-source
       catalog-b "catalog-b" 10 'current
       (list (assertion catalog-b (digest #\8) second))))
     (request "org.example.package")
     #:pins (list (odra-package-source-pin "org.example.package" catalog-b))
     #:organizations
     (list (odra-package-organization-override "org.example" catalog-a))))
  (check-true (odra-federated-package-resolution? result))
  (check-eq? (odra-federated-package-resolution-pin-origin result) 'package)
  (check-equal?
   (odra-federated-package-resolution-effective-catalog-pin result) catalog-b)
  (check-equal?
   (odra-package-release-reference-version
    (odra-package-resolution-release
     (odra-federated-package-resolution-resolution result)))
   "2.0.0"))

(test-case "most-specific organization override supplies the source pin"
  (define selected
    (release "org.example.package" "1.0.0" (digest #\3) (digest #\4)))
  (define result
    (resolve
     (list
      (federated-source
       catalog-a "catalog-a" 10 'current
       (list (assertion catalog-a (digest #\5) selected))))
     (request "org.example.package")
     #:organizations
     (list (odra-package-organization-override "org" catalog-b)
           (odra-package-organization-override "org.example" catalog-a))))
  (check-true (odra-federated-package-resolution? result))
  (check-eq? (odra-federated-package-resolution-pin-origin result)
             'organization)
  (check-equal?
   (odra-federated-package-resolution-effective-catalog-pin result) catalog-a))

(test-case "source policy cannot suppress an integrity conflict"
  (define first
    (release "org.example.package" "1.0.0" (digest #\3) (digest #\4)))
  (define second
    (release "org.example.package" "1.0.0" (digest #\5) (digest #\6)))
  (define result
    (resolve
     (list
      (federated-source
       catalog-a "catalog-a" 20 'current
       (list (assertion catalog-a (digest #\7) first)))
      (federated-source
       catalog-b "catalog-b" 10 'current
       (list (assertion catalog-b (digest #\8) second))))
     (request "org.example.package")
     #:pins (list (odra-package-source-pin "org.example.package" catalog-a))))
  (check-true (odra-federated-package-resolution-failure? result))
  (check-eq? (odra-federated-package-resolution-failure-code result)
             'artifact-identity-conflict)
  (check-equal?
   (odra-federated-package-resolution-failure-catalog-ids result)
   (list catalog-a catalog-b))
  (check-equal?
   (odra-federated-package-resolution-failure-effective-catalog-pin result)
   catalog-a))

(test-case "trusted advisory policy blocks the selected exact artifact"
  (define artifact-digest (digest #\4))
  (define selected
    (release "org.example.package" "1.0.0" (digest #\3) artifact-digest))
  (define advisory
    (odra-security-advisory
     1 "odra-2026-001" "official-security" catalog-a 1 'active 'malicious
     'critical 'confirmed '() '() (list artifact-digest)
     '(block-acquisition warn) "Confirmed malicious artifact." 20 #f
     (list
      (odra-package-catalog-signature
       'ed25519 (digest #\1) package-catalog-advisory-signature-domain
       (make-string 128 #\2)))))
  (define result
    (resolve
     (list
      (federated-source
       catalog-a "catalog-a" 20 'offline
       (list (assertion catalog-a (digest #\5) selected))))
     (request "org.example.package") #:advisories (list advisory)))
  (check-true (odra-federated-package-resolution-failure? result))
  (check-eq? (odra-federated-package-resolution-failure-code result)
             'advisory-blocked)
  (check-equal?
   (odra-security-advisory-response-actions
    (odra-federated-package-resolution-failure-advisory-response result))
   '(block-acquisition warn)))

(test-case "disabled or stale registrations cannot become resolution sources"
  (define selected
    (release "org.example.package" "1.0.0" (digest #\3) (digest #\4)))
  (for ([enabled? '(#f #t)] [state '(current stale)])
    (check-exn
     exn:fail:contract?
     (lambda ()
       (define snapshot-id (digest #\9))
       (odra-federated-package-source
        (odra-package-catalog-registration
         1 "catalog-a" 1 catalog-a 'user (digest #\8) '("origin") 10
         'enforce enabled? state)
        (odra-package-catalog-confirmed-snapshot-reference
         1 catalog-a snapshot-id 1 (digest #\7) "catalog/snapshot.rktd" 20)
        (odra-package-curated-source
         catalog-a snapshot-id 10
         (list (assertion catalog-a (digest #\5) selected))))))))
