#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/cmdline
         racket/file
         racket/string
         "../src/command/package-catalogs.rkt"
         "../src/package_catalog/official-bootstrap.rkt"
         "../src/package_catalog/runtime-service.rkt")

(define endpoint-uri #f)
(define credential-reference #f)
(define package-id #f)
(define expected-versions '())

(command-line
 #:program "validate-package-catalog-remote.rkt"
 #:once-each
 [("--endpoint") uri "Private HTTPS snapshot endpoint"
                    (set! endpoint-uri uri)]
 [("--credential-reference") reference "Credential provider reference"
                                  (set! credential-reference reference)]
 [("--package") identity "Expected package identity"
                         (set! package-id identity)]
 #:multi
 [("--expect-version") version "Expected admitted release version"
                              (set! expected-versions
                                    (cons version expected-versions))]
 #:args () (void))

(unless endpoint-uri
  (raise-user-error 'package-catalog-remote "--endpoint is required"))
(unless credential-reference
  (raise-user-error 'package-catalog-remote
                    "--credential-reference is required"))
(unless package-id
  (raise-user-error 'package-catalog-remote "--package is required"))
(when (null? expected-versions)
  (raise-user-error 'package-catalog-remote
                    "at least one --expect-version is required"))

(define registration-id "odra-official")
(define registration
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
     #:credential-reference credential-reference))))
(define configuration
  (package-catalog-configuration #:registrations (list registration)))
(define state-root
  (make-temporary-file "odra-private-catalog-validation~a" 'directory))
(file-or-directory-permissions state-root #o700)

(dynamic-wind
  void
  (lambda ()
    (define refreshed
      (package-catalog-runtime-refresh state-root configuration registration-id))
    (unless (eq? (odra-package-catalog-runtime-result-status refreshed) 'success)
      (raise-user-error
       'package-catalog-remote
       "refresh failed: ~a"
       (odra-package-catalog-runtime-result-detail refreshed)))
    (define searched
      (package-catalog-runtime-search state-root configuration package-id))
    (define detail (odra-package-catalog-runtime-result-detail searched))
    (unless (= (odra-package-catalog-runtime-result-item-count searched)
               (length expected-versions))
      (raise-user-error
       'package-catalog-remote
       "expected ~a admitted releases, received ~a"
       (length expected-versions)
       (odra-package-catalog-runtime-result-item-count searched)))
    (for ([version (in-list expected-versions)])
      (unless (string-contains? detail (format "~a@~a" package-id version))
        (raise-user-error
         'package-catalog-remote
         "expected release is absent: ~a@~a" package-id version)))
    (printf
     "package-catalog-remote: catalog=~a package=~a releases=~a\n"
     official-package-catalog-identity
     package-id
     (string-join (sort expected-versions string<?) ",")))
  (lambda ()
    (delete-directory/files state-root)))
