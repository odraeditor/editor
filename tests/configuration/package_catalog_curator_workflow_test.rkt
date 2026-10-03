#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/path
         racket/runtime-path
         rackunit
         "../../scripts/package-catalog-curator-support.rkt"
         "../../scripts/package-catalog-publication-support.rkt"
         "../../src/package_catalog/curation-publication.rkt"
         "../../src/package_catalog/integrity.rkt"
         "../../src/package_catalog/snapshot-records.rkt"
         (submod "../../src/package_catalog/integrity.rkt" test-support))

(define-runtime-path publication-repository
  "../package_catalog_publication_fixture/repository.rkt")

(define root-public-key
  "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
(define root-secret-key
  (string-append
   "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
   root-public-key))
(define root-key-id (package-catalog-public-key-id root-public-key))
(define catalog-id (make-string 64 #\a))

(test-case "independent bootstrap copies the complete neutral kit"
  (define parent (make-temporary-file "catalog-bootstrap-~a" 'directory))
  (define target (build-path parent "catalog"))
  (dynamic-wind
    void
    (lambda ()
      (check-equal? (bootstrap-independent-package-catalog target)
                    (path->complete-path target))
      (check-true (file-exists? (build-path target "README.md")))
      (check-true (file-exists? (build-path target "template" "catalog.rkt")))
      (check-true
       (file-exists? (build-path target "policy" "authority.md"))))
    (lambda () (delete-directory/files parent))))

(test-case "rotation requests support deterministic offline signing exchange"
  (define request
    (prepare-package-catalog-root-rotation
     catalog-id root-key-id (make-string 64 #\3) 2))
  (define repeated
    (prepare-package-catalog-root-rotation
     catalog-id root-key-id (make-string 64 #\3) 2))
  (check-equal? request repeated)
  (define signature
    (sign-for-test
     (odra-package-catalog-offline-signing-request-message request)
     root-secret-key))
  (check-true
   (verify-package-catalog-offline-signature
    request root-public-key signature))
  (define prefix
    (build-path (make-temporary-file "signing-request-~a" 'directory)
                "root-rotation"))
  (define root (path-only prefix))
  (dynamic-wind
    void
    (lambda ()
      (define-values (metadata message)
        (write-package-catalog-offline-signing-request prefix request))
      (check-equal? (load-package-catalog-offline-signing-request metadata)
                    request)
      (check-equal? (file->bytes message)
                    (odra-package-catalog-offline-signing-request-message
                     request)))
    (lambda () (delete-directory/files root))))

(test-case "publisher rotation request is root-authorized"
  (define request
    (prepare-package-catalog-publisher-rotation
     catalog-id root-key-id "snapshot-publisher" (make-string 64 #\4) 2))
  (check-eq?
   (odra-package-catalog-offline-signing-request-purpose request)
   'publisher-rotation)
  (check-equal?
   (odra-package-catalog-offline-signing-request-domain request)
   package-catalog-root-signature-domain))

(test-case "snapshot verification, exact mirrors, and dry-run remain deterministic"
  (define repository
    (load-package-catalog-publication-repository publication-repository))
  (define publication
    (validate-package-catalog-publication-repository repository))
  (define snapshot (odra-package-catalog-publication-snapshot publication))
  (define signing-request
    (prepare-package-catalog-snapshot-signing
     snapshot
     (odra-package-catalog-signature-key-id
      (car (odra-package-catalog-snapshot-signatures snapshot)))))
  (check-eq?
   (odra-package-catalog-offline-signing-request-purpose signing-request)
   'snapshot)
  (check-equal?
   (odra-package-catalog-offline-signing-request-domain signing-request)
   package-catalog-publisher-signature-domain)
  (define root (make-temporary-file "catalog-mirror-~a" 'directory))
  (define origin (build-path root "origin.rktd"))
  (define mirror (build-path root "mirror.rktd"))
  (dynamic-wind
    void
    (lambda ()
      (call-with-output-file origin
        (lambda (output)
          (write-bytes (package-catalog-snapshot->module-bytes snapshot) output)))
      (copy-file origin mirror)
      (check-true
       (verify-package-catalog-snapshot-file
        publication-repository origin 120))
      (check-true (validate-package-catalog-exact-mirror origin mirror))
      (define first
        (dry-run-package-catalog-publication publication-repository))
      (define second
        (dry-run-package-catalog-publication publication-repository))
      (check-equal? first second))
    (lambda () (delete-directory/files root))))
