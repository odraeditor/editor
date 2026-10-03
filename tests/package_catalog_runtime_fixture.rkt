#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/cmdline
         racket/file
         (prefix-in fixture:
                    "package_catalog_publication_fixture/repository.rkt")
         "../src/package_catalog/contracts.rkt"
         "../src/package_catalog/curation-publication.rkt"
         "../src/package_catalog/integrity.rkt"
         "../src/package_catalog/publication-metadata.rkt"
         "../src/package_catalog/snapshot-records.rkt"
         (submod "../src/package_catalog/integrity.rkt" test-support))

(provide make-package-catalog-runtime-publication
         package-catalog-runtime-fixture-profile
         package-catalog-runtime-fixture-publisher-keys
         package-catalog-runtime-fixture-assertions
         make-package-catalog-runtime-fixture-snapshot)

(define publisher-public-key
  "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c")
(define publisher-secret-key
  (string-append
   "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
   publisher-public-key))
(define publisher-key-id (package-catalog-public-key-id publisher-public-key))
(define assertions
  (odra-package-catalog-publication-assertions fixture:publication))
(define package-catalog-runtime-fixture-profile fixture:profile)
(define package-catalog-runtime-fixture-publisher-keys fixture:publisher-keys)
(define package-catalog-runtime-fixture-assertions assertions)

(define (current-snapshot)
  (define issued-at (- (current-seconds) 10))
  (define expires-at (+ (current-seconds) 3600))
  (let loop ([metadata-size 1])
    (define draft
      (odra-package-catalog-snapshot
       1 (make-string 64 #\0)
       (odra-package-catalog-profile-identity fixture:profile)
       1 #f "policy-v1" issued-at expires-at
       (package-curation-assertion-set-digest assertions)
       (make-string 64 #\5) metadata-size "snapshot-publisher" '()))
    (define identified
      (struct-copy
       odra-package-catalog-snapshot draft
       [id (package-catalog-snapshot-content-digest draft)]))
    (define payload (package-catalog-snapshot-signing-payload identified))
    (define message
      (package-catalog-signature-message
       package-catalog-publisher-signature-domain payload))
    (define signed
      (struct-copy
       odra-package-catalog-snapshot identified
       [signatures
        (list
         (odra-package-catalog-signature
          'ed25519 publisher-key-id package-catalog-publisher-signature-domain
          (sign-for-test message publisher-secret-key)))]))
    (define actual
      (bytes-length (package-catalog-snapshot->module-bytes signed)))
    (if (= actual metadata-size) signed (loop actual))))

(define (make-package-catalog-runtime-fixture-snapshot)
  (current-snapshot))

(define (write-bytes-file path bytes)
  (call-with-output-file path
    (lambda (output) (write-bytes bytes output))
    #:exists 'truncate/replace
    #:mode 'binary))

(define (make-package-catalog-runtime-publication root)
  (define publication-root (build-path root "publication"))
  (when (directory-exists? publication-root)
    (delete-directory/files publication-root))
  (make-directory* publication-root)
  (define snapshot (current-snapshot))
  (write-bytes-file
   (build-path publication-root "catalog.rktd")
   (package-catalog-publication-metadata->module-bytes
    (odra-package-catalog-publication-metadata
     1 fixture:profile fixture:publisher-keys)))
  (write-bytes-file
   (build-path publication-root "snapshot.rktd")
   (package-catalog-snapshot->module-bytes snapshot))
  (write-bytes-file
   (build-path publication-root "assertions.rktd")
   (package-curation-assertion-set->module-bytes assertions))
  publication-root)

(module+ main
  (command-line
   #:program "package-catalog-runtime-fixture"
   #:args (root)
   (displayln
    (path->string
     (make-package-catalog-runtime-publication
      (path->complete-path root))))))
