#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/cmdline
         racket/file
         racket/list
         racket/string
         "../src/command/catalog.rkt"
         "../src/command/package-catalogs.rkt"
         "../src/package/acquisition.rkt"
         "../src/package/lifecycle.rkt"
         "../src/package/lifecycle-service.rkt"
         "../src/package/runtime.rkt"
         "../src/package_catalog/official-bootstrap.rkt"
         "../src/package_catalog/runtime-service.rkt")

(define endpoint-uri #f)
(define credential-reference #f)
(define package-id #f)
(define initial-version #f)
(define update-version #f)

(command-line
 #:program "validate-private-package-lifecycle.rkt"
 #:once-each
 [("--endpoint") uri "Private HTTPS snapshot endpoint"
                    (set! endpoint-uri uri)]
 [("--credential-reference") reference "Credential provider reference"
                                  (set! credential-reference reference)]
 [("--package") identity "Package identity" (set! package-id identity)]
 [("--initial-version") version "Initial exact release"
                          (set! initial-version version)]
 [("--update-version") version "Compatible update release"
                         (set! update-version version)]
 #:args () (void))

(unless (and endpoint-uri credential-reference package-id initial-version
             update-version)
  (raise-user-error
   'private-package-lifecycle
   "--endpoint, --credential-reference, --package, --initial-version, and --update-version are required"))

(define registration-id "odra-official")
(define configuration
  (package-catalog-configuration
   #:registrations
   (list
    (package-catalog-registration
     #:id registration-id
     #:kind 'official
     #:configuration-origin 'built-in
     #:trust
     (package-catalog-trust-reference
      #:id official-package-catalog-root-key-id
      #:catalog-id official-package-catalog-identity
      #:designation 'official)
     #:endpoints
     (list
      (package-catalog-endpoint
       #:id "odra-official-origin"
       #:catalog-id official-package-catalog-identity
       #:uri endpoint-uri
       #:credential-reference credential-reference))))))

(define root
  (make-temporary-file "odra-private-package-lifecycle-~a" 'directory))
(file-or-directory-permissions root #o700)

(define (ensure-success operation result)
  (unless (eq? (odra-package-lifecycle-runtime-result-status result) 'success)
    (raise-user-error
     'private-package-lifecycle "~a failed: ~a" operation
     (odra-package-lifecycle-runtime-result-detail result))))

(define (installer installation-root selected-id selected-version)
  (define prepared
    (package-catalog-runtime-prepare-installation
     installation-root configuration selected-id selected-version))
  (if (odra-package-installation-acquisition-failure? prepared)
      (odra-package-installation-acquisition-failure-detail prepared)
      prepared))

(define (release version)
  (format "~a@~a" package-id version))

(dynamic-wind
  void
  (lambda ()
    (define refreshed
      (package-catalog-runtime-refresh root configuration registration-id))
    (unless (eq? (odra-package-catalog-runtime-result-status refreshed) 'success)
      (raise-user-error
       'private-package-lifecycle "refresh failed: ~a"
       (odra-package-catalog-runtime-result-detail refreshed)))
    (for ([version (in-list (list initial-version update-version))])
      (ensure-success
       (format "install ~a" version)
       (package-lifecycle-runtime-install
        root (release version) #:installer installer)))
    (ensure-success
     "enable initial release"
     (package-lifecycle-runtime-enable root (release initial-version)))
    (unless
        (member
         "rot13-region"
         (map odra-command-definition-name
              (odra-command-catalog-definitions
               (package-lifecycle-runtime-catalog root)))
         string=?)
      (raise-user-error
       'private-package-lifecycle
       "enabled package command is absent from the runtime catalog"))
    (ensure-success
     "update"
     (package-lifecycle-runtime-update root (release update-version)))
    (ensure-success
     "rollback"
     (package-lifecycle-runtime-rollback root package-id))

    ;; A separate manager proves restart and offline activation from verified
    ;; installed content without contacting the catalog or artifact endpoint.
    (define restarted (make-package-lifecycle-manager root))
    (define restored (package-lifecycle-restore! restarted))
    (unless (and (eq? (odra-package-lifecycle-result-status restored) 'restored)
                 (member package-id
                         (odra-package-lifecycle-result-values restored)
                         string=?))
      (raise-user-error
       'private-package-lifecycle "restart did not restore the active package"))
    (package-runtime-close! (package-lifecycle-runtime restarted))

    (ensure-success
     "disable"
     (package-lifecycle-runtime-disable root package-id))
    (for ([version (in-list (list initial-version update-version))])
      (ensure-success
       (format "remove ~a" version)
       (package-lifecycle-runtime-remove root (release version))))
    (ensure-success "cleanup" (package-lifecycle-runtime-cleanup root))
    (unless (null? (package-lifecycle-list (make-package-lifecycle-manager root)))
      (raise-user-error
       'private-package-lifecycle "removed package state remains installed"))
    (printf
     "private-package-lifecycle: package=~a releases=~a,~a command=rot13-region status=complete\n"
     package-id initial-version update-version))
  (lambda ()
    (delete-directory/files root)))
