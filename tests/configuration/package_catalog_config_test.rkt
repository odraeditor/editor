#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         rackunit
         "../../src/command/package-catalogs.rkt"
         "../../src/configuration/personal.rkt"
         "../../src/package_catalog/federated-resolution.rkt")

(define catalog-id (make-string 64 #\a))
(define trust-id (make-string 64 #\b))

(define (write-init root content)
  (call-with-output-file (build-path root "init.rkt")
    (lambda (output) (display content output))
    #:exists 'truncate/replace))

(test-case "personal configuration admits checked catalog forms"
  (define root (make-temporary-file "odra-package-config-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (write-init
       root
       (format
        #<<RACKET
#lang racket/base
(require odra/package-catalogs)
(provide odra-package-catalogs)
(define catalog-id ~s)
(define trust
  (package-catalog-trust-reference
   #:id ~s #:catalog-id catalog-id))
(define endpoint
  (package-catalog-endpoint
   #:id "private" #:catalog-id catalog-id
   #:uri "https://catalog.example/private/snapshot.rktd"
   #:credential-reference "credential.catalog.private"))
(define registration
  (package-catalog-registration
   #:id "private" #:kind 'private #:trust trust
   #:endpoints (list endpoint) #:precedence 40))
(define odra-package-catalogs
  (package-catalog-configuration
   #:registrations (list registration)
   #:source-pins
   (list (package-source-pin "org.example.package" catalog-id))
   #:organization-overrides
   (list (package-organization-override "org.example" catalog-id))))
RACKET
        catalog-id trust-id))
      (define observation
        (personal-config-load (personal-config-source root)))
      (check-eq? (odra-personal-config-observation-state observation)
                 'confirmed (format "~s" observation))
      (define configured
        (personal-config-observation-export
         observation 'odra-package-catalogs))
      (check-true (odra-package-catalog-configuration? configured))
      (check-equal?
       (length (odra-package-catalog-configuration-registrations configured))
       1))
    (lambda () (delete-directory/files root))))

(test-case "catalog configuration rejects duplicate trust identities"
  (define trust
    (package-catalog-trust-reference
     #:id trust-id #:catalog-id catalog-id))
  (define endpoint
    (package-catalog-endpoint
     #:id "local" #:catalog-id catalog-id
     #:uri "file:///tmp/catalog.rktd" #:role 'local))
  (check-exn
   exn:fail?
   (lambda ()
     (package-catalog-configuration
      #:registrations
      (list
       (package-catalog-registration
        #:id "first" #:kind 'local #:trust trust
        #:endpoints (list endpoint))
       (package-catalog-registration
        #:id "second" #:kind 'local #:trust trust
        #:endpoints (list endpoint)))))))
