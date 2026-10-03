#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/string
         rackunit
         "../package_catalog_runtime_fixture.rkt"
         "../../src/command/package-catalogs.rkt"
         "../../src/package/credential-provider.rkt"
         "../../src/package_catalog/contracts.rkt"
         "../../src/package_catalog/curation-publication.rkt"
         "../../src/package_catalog/publication-metadata.rkt"
         "../../src/package_catalog/runtime-service.rkt"
         "../../src/package_catalog/snapshot-records.rkt"
         (submod "../../src/package_catalog/endpoint-transport.rkt"
                 test-support))

(define configuration (package-catalog-configuration))

(test-case "local publication works through durable runtime catalog state"
  (define root (make-temporary-file "odra-package-catalog-runtime-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind
    void
    (lambda ()
      (define publication-root
        (make-package-catalog-runtime-publication root))
      (define preview
        (package-catalog-runtime-preview-add
         root configuration publication-root))
      (check-eq? (odra-package-catalog-runtime-result-status preview)
                 'confirmation)
      (define registration-id
        (odra-package-catalog-runtime-result-identity preview))
      (check-regexp-match #px"^local-[0-9a-f]{12}$" registration-id)

      (define added
        (package-catalog-runtime-add root configuration publication-root))
      (check-eq? (odra-package-catalog-runtime-result-status added) 'success
                 (odra-package-catalog-runtime-result-detail added))
      (check-equal? (odra-package-catalog-runtime-result-item-count added) 1)

      (define listed (package-catalog-runtime-list root configuration))
      (check-equal? (odra-package-catalog-runtime-result-item-count listed) 1)
      (check-regexp-match
       (regexp-quote registration-id)
       (odra-package-catalog-runtime-result-detail listed))

      (define searched
        (package-catalog-runtime-search root configuration "org.example"))
      (check-equal? (odra-package-catalog-runtime-result-item-count searched) 1)
      (check-regexp-match
       #px"org[.]example[.]package@1[.]0[.]0"
       (odra-package-catalog-runtime-result-detail searched))

      (define described
        (package-catalog-runtime-describe root configuration registration-id))
      (check-regexp-match
       #px"Designation: independent"
       (odra-package-catalog-runtime-result-detail described))

      (define doctor (package-catalog-runtime-doctor root configuration))
      (check-regexp-match
       #px"Confirmed snapshots: 1"
       (odra-package-catalog-runtime-result-detail doctor))

      (delete-directory/files publication-root)
      (define failed-refresh
        (package-catalog-runtime-refresh root configuration registration-id))
      (check-eq? (odra-package-catalog-runtime-result-status failed-refresh)
                 'failure)
      (define retained
        (package-catalog-runtime-search root configuration "org.example"))
      (check-equal? (odra-package-catalog-runtime-result-item-count retained) 1)

      (define disabled
        (package-catalog-runtime-set-enabled
         root configuration registration-id #f))
      (check-eq? (odra-package-catalog-runtime-result-status disabled) 'success)
      (check-equal?
       (odra-package-catalog-runtime-result-item-count
        (package-catalog-runtime-search root configuration "org.example"))
       0)

      (define removed
        (package-catalog-runtime-remove root configuration registration-id))
      (check-eq? (odra-package-catalog-runtime-result-status removed) 'success)
      (check-equal?
       (odra-package-catalog-runtime-result-item-count
        (package-catalog-runtime-list root configuration))
       0))
    (lambda () (delete-directory/files root))))

(test-case "HTTPS refresh fetches the content-addressed assertion artifact"
  (define root (make-temporary-file "odra-package-catalog-remote-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind
    void
    (lambda ()
      (define profile package-catalog-runtime-fixture-profile)
      (define catalog-id (odra-package-catalog-profile-identity profile))
      (define root-id
        (odra-package-catalog-root-key-id
         (car (odra-package-catalog-profile-roots profile))))
      (define endpoint-uri
        "https://catalog.example/preview/current-snapshot.rktd")
      (define credential-reference "ODRA_CATALOG_TEST_TOKEN")
      (define registration
        (package-catalog-registration
         #:id "fixture-remote"
         #:kind 'independent
         #:configuration-origin 'user
         #:trust
         (package-catalog-trust-reference
          #:id root-id #:catalog-id catalog-id)
         #:endpoints
         (list
          (package-catalog-endpoint
           #:id "fixture-origin"
           #:catalog-id catalog-id
           #:uri endpoint-uri
           #:credential-reference credential-reference))))
      (define remote-configuration
        (package-catalog-configuration #:registrations (list registration)))
      (define legacy-registration
        (package-catalog-registration
         #:id "fixture-remote"
         #:kind 'independent
         #:configuration-origin 'user
         #:trust
         (package-catalog-trust-reference
          #:id root-id #:catalog-id catalog-id)
         #:endpoints
         (list
          (package-catalog-endpoint
           #:id "fixture-origin"
           #:catalog-id catalog-id
           #:uri endpoint-uri))))
      (define legacy-configuration
        (package-catalog-configuration
         #:registrations (list legacy-registration)))
      (define metadata-directory
        (build-path root "package-catalog" "metadata"))
      (make-directory* metadata-directory)
      (file-or-directory-permissions (build-path root "package-catalog") #o700)
      (file-or-directory-permissions metadata-directory #o700)
      (call-with-output-file
       (build-path metadata-directory (string-append catalog-id ".rktd"))
       (lambda (output)
         (write-bytes
          (package-catalog-publication-metadata->module-bytes
           (odra-package-catalog-publication-metadata
            1 profile package-catalog-runtime-fixture-publisher-keys))
          output))
       #:exists 'truncate/replace
       #:mode 'binary)
      (define snapshot (make-package-catalog-runtime-fixture-snapshot))
      (define snapshot-bytes (package-catalog-snapshot->module-bytes snapshot))
      (define assertion-bytes
        (package-curation-assertion-set->module-bytes
         package-catalog-runtime-fixture-assertions))
      (define valid-assertions? #t)
      (define requested '())
      (define credential-available? #t)
      (define provider
        (make-package-credential-provider
         #:id "runtime-test" #:generation 1
         #:lookup
         (lambda (reference)
           (check-equal? reference credential-reference)
           (and credential-available?
                (make-package-credential
                 #:headers
                 (hash "authorization" "Bearer runtime-private"))))))
      (check-equal?
       (odra-package-catalog-runtime-result-item-count
        (package-catalog-runtime-list root legacy-configuration))
       1)
      (parameterize
          ([current-package-credential-provider provider]
           [current-catalog-transport-open
            (lambda (uri headers _proxy-policy)
              (check-equal?
               (hash-ref headers "authorization") "Bearer runtime-private")
              (set! requested (cons uri requested))
              (transport-response
               200 (hash)
               (open-input-bytes
                (if (string=? uri endpoint-uri)
                    snapshot-bytes
                    (if valid-assertions?
                        assertion-bytes
                        (package-curation-assertion-set->module-bytes '()))))))])
        (define discovered
          (package-catalog-runtime-discover
           root remote-configuration "org.example.package"))
        (check-eq? (odra-package-catalog-runtime-result-status discovered)
                   'success
                   (odra-package-catalog-runtime-result-detail discovered))
        (check-equal? (odra-package-catalog-runtime-result-item-count discovered)
                      1)
        (define refreshed
          (package-catalog-runtime-refresh
           root remote-configuration "fixture-remote"))
        (check-eq? (odra-package-catalog-runtime-result-status refreshed)
                   'success
                   (odra-package-catalog-runtime-result-detail refreshed))
        (check-equal? (odra-package-catalog-runtime-result-item-count refreshed)
                      1)
        (check-true
         (for/or ([uri (in-list requested)])
           (string-contains?
            uri
            (string-append
             "/assertions/"
             (odra-package-catalog-snapshot-assertion-set-digest snapshot)
             ".rktd"))))
        (define searched
          (package-catalog-runtime-search
           root remote-configuration "org.example.package"))
        (check-equal?
         (odra-package-catalog-runtime-result-item-count searched)
         1)
        (check-equal?
         (odra-package-catalog-runtime-result-item-count
          (package-catalog-runtime-search
           root remote-configuration ""))
         1)
        (set! credential-available? #f)
        (define offline
          (package-catalog-runtime-refresh
           root remote-configuration "fixture-remote"))
        (check-eq? (odra-package-catalog-runtime-result-status offline)
                   'failure)
        (check-false
         (regexp-match?
          #px"runtime-private"
          (odra-package-catalog-runtime-result-detail offline)))
        (check-equal?
         (odra-package-catalog-runtime-result-item-count
          (package-catalog-runtime-search
           root remote-configuration "org.example.package"))
         1)
        (set! credential-available? #t)
        (set! valid-assertions? #f)
        (define rejected
          (package-catalog-runtime-refresh
           root remote-configuration "fixture-remote"))
        (check-eq? (odra-package-catalog-runtime-result-status rejected)
                   'failure)
        (check-regexp-match
         #px"digest does not match"
         (odra-package-catalog-runtime-result-detail rejected))
        (check-regexp-match
         #px"fixture-remote [|] enabled [|] failed"
         (odra-package-catalog-runtime-result-detail
          (package-catalog-runtime-list root remote-configuration)))
        (check-equal?
         (odra-package-catalog-runtime-result-item-count
          (package-catalog-runtime-search
           root remote-configuration "org.example.package"))
         0)))
    (lambda () (delete-directory/files root))))
