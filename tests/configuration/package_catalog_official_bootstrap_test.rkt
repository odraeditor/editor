#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         rackunit
         "../../src/command/package-catalogs.rkt"
         "../../src/package_catalog/contracts.rkt"
         "../../src/package_catalog/integrity.rkt"
         "../../src/package_catalog/official-bootstrap.rkt")

(test-case "compiled official bootstrap is internally consistent"
  (define profile
    (odra-package-catalog-bootstrap-profile official-package-catalog-bootstrap))
  (check-true
   (package-catalog-bootstrap-valid? official-package-catalog-bootstrap))
  (check-equal? (odra-package-catalog-profile-identity profile)
                official-package-catalog-identity)
  (check-equal?
   (package-catalog-public-key-id official-package-catalog-root-public-key)
   official-package-catalog-root-key-id)
  (check-equal?
   (package-catalog-public-key-id official-package-catalog-publisher-public-key)
   official-package-catalog-publisher-key-id)
  (check-true (verify-package-catalog-profile-identity profile))
  (check-equal? (package-catalog-profile->canonical-bytes profile)
                (package-catalog-profile->canonical-bytes profile))
  (check-eq?
   (odra-package-catalog-bootstrap-lifecycle
    official-package-catalog-bootstrap)
   'public)
  (check-false
   (odra-package-catalog-bootstrap-formalization-required?
    official-package-catalog-bootstrap))
  (check-false official-package-catalog-credential-reference)
  (define endpoint
    (first (odra-package-catalog-profile-endpoints profile)))
  (check-equal? (odra-package-catalog-endpoint-id endpoint)
                "odra-official-origin")
  (check-equal?
   (odra-package-catalog-endpoint-uri endpoint)
   "https://forge.adrianpk.com/odra/kasper/raw/branch/publication/current-snapshot.rktd"))

(test-case "clean factory configuration contains exactly one official identity"
  (define registrations
    (odra-package-catalog-configuration-registrations
     factory-package-catalog-configuration))
  (check-equal? (length registrations) 1)
  (define registration (first registrations))
  (check-eq? (odra-package-catalog-config-registration-kind registration)
             'official)
  (check-eq?
   (odra-package-catalog-trust-reference-designation
    (odra-package-catalog-config-registration-trust registration))
   'official)
  (check-equal?
   (odra-package-catalog-trust-reference-catalog-id
    (odra-package-catalog-config-registration-trust registration))
   official-package-catalog-identity)
  (check-equal?
   (odra-package-catalog-trust-reference-id
    (odra-package-catalog-config-registration-trust registration))
   official-package-catalog-root-key-id))

(test-case "official designation is not derived from presentation or location"
  (define copied-name
    (odra-package-catalog-root-key
     (make-string 64 #\a) 1 'ed25519 (make-string 64 #\b) 0 #f))
  (define copied-identity (package-catalog-identity copied-name))
  (check-not-equal? copied-identity official-package-catalog-identity)
  (check-not-equal? copied-identity official-package-catalog-root-key-id)
  (check-exn
   exn:fail?
   (lambda ()
     (package-catalog-trust-reference
      #:id (make-string 64 #\a)
      #:catalog-id copied-identity
      #:designation 'official))))

(test-case "user configuration can disable or replace factory defaults"
  (define disabled (package-catalog-configuration))
  (check-equal?
   (odra-package-catalog-configuration-registrations disabled) '())
  (define independent-catalog-id (make-string 64 #\c))
  (define independent
    (package-catalog-registration
     #:id "independent"
     #:kind 'independent
     #:trust
     (package-catalog-trust-reference
      #:id (make-string 64 #\d) #:catalog-id independent-catalog-id)
     #:endpoints
     (list
      (package-catalog-endpoint
       #:id "independent-origin" #:catalog-id independent-catalog-id
       #:uri "https://catalog.example/snapshot.rktd"))))
  (define replaced
    (package-catalog-configuration #:registrations (list independent)))
  (check-equal?
   (map odra-package-catalog-config-registration-kind
        (odra-package-catalog-configuration-registrations replaced))
   '(independent)))
