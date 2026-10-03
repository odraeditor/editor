#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         rackunit
         "../../src/package/manifest-contracts.rkt"
         "../../src/package/resolution.rkt"
         "../../src/package/state-records.rkt"
         "../../src/package_catalog/curation-records.rkt"
         "../../src/package_catalog/curation-resolution.rkt"
         "../../src/package_catalog/manual-resolution.rkt")

(define (digest character) (make-string 64 character))
(define revision (make-string 40 #\d))
(define catalog-id (digest #\a))
(define snapshot-id (digest #\b))
(define assertion-id (digest #\c))
(define archive-digest (digest #\e))
(define member-digest (digest #\f))
(define target (odra-package-target 'linux 'x86-64))
(define entrypoint
  (odra-package-artifact
   "entrypoint" 'racket-module "main.rkt" member-digest 128 #f #f
   'racket-extension '()))

(define-values (manifest manifest-rejection)
  (confirm-package-manifest
   (odra-package-manifest-proposal
    1 "org.example.package" 'extension "Example Package" "1.0.0"
    "Exact package resolution fixture" "MIT" #f "org.example.publisher"
    revision "1.0.0" "2.0.0" (list target) '() '(racket-extension)
    (list entrypoint)
    (odra-package-entrypoint "main.rkt" 'odra-package-contributions)
    (list (odra-package-contribution
           "example-command" 'command '(active-buffer) '(buffer)))
    '() (odra-package-state-compatibility #f #f #f 'none))))
(check-false manifest-rejection)

(define artifact
  (odra-package-artifact-reference
   'linux 'x86-64 '("https://packages.example/package.tar.zst")
   archive-digest 1024 #f #f 'reproduced))
(define release
  (odra-package-release-reference
   1 "org.example.package" (digest #\1) "1.0.0" "org.example.publisher"
   "https://forge.example/org/package" revision #f
   (package-manifest-digest manifest) (list artifact)
   (digest #\2) (digest #\3) (digest #\4) (digest #\5)))
(define assertion
  (odra-package-curation-assertion
   1 assertion-id catalog-id 1 release "decision-1" "policy-v1"
   'admitted "" '() 1 1))
(define source
  (odra-package-curated-source catalog-id snapshot-id 10 (list assertion)))
(define resolution
  (resolve-curated-package
   (list source)
   (odra-package-resolution-request
    "org.example.package" "1.0.0" "1.0.0" 'linux 'x86-64 #f)))

(test-case "catalog resolution binds a confirmed generic manifest to exact provenance"
  (define candidate
    (prepare-curated-package-installation manifest resolution 'linux 'x86-64))
  (check-true (odra-package-installation-candidate? candidate))
  (check-equal? (odra-package-installation-candidate-manifest-digest candidate)
                (package-manifest-digest manifest))
  (define provenance (odra-package-installation-candidate-provenance candidate))
  (check-eq? (odra-package-provenance-kind provenance) 'catalog)
  (check-equal? (odra-package-provenance-catalog-id provenance) catalog-id)
  (check-equal? (odra-package-provenance-snapshot-digest provenance) snapshot-id)
  (check-equal? (odra-package-provenance-assertion-id provenance) assertion-id))

(test-case "manifest mismatch rejects before artifact acquisition"
  (define changed-release
    (struct-copy odra-package-release-reference release
                 [manifest-digest (digest #\9)]))
  (define changed-assertion
    (struct-copy odra-package-curation-assertion assertion
                 [release changed-release]))
  (define changed-resolution
    (resolve-curated-package
     (list (odra-package-curated-source
            catalog-id snapshot-id 10 (list changed-assertion)))
     (odra-package-resolution-request
      "org.example.package" "1.0.0" "1.0.0" 'linux 'x86-64 #f)))
  (define rejected
    (prepare-curated-package-installation
     manifest changed-resolution 'linux 'x86-64))
  (check-true (odra-package-resolution-rejection? rejected))
  (check-eq? (odra-package-resolution-rejection-code rejected)
             'manifest-mismatch))

(test-case "manual resolution uses the same exact manifest and release boundary"
  (define fixture-root (make-temporary-file "package-resolution-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define source-root (build-path fixture-root "source"))
      (make-directory source-root)
      (call-with-output-file (build-path source-root "odra-package.rktd")
        (lambda (output)
          (write-bytes (package-manifest->canonical-bytes manifest) output))
        #:mode 'binary)
      (call-with-output-file (build-path source-root "main.rkt")
        (lambda (output) (write-bytes (make-bytes 128 65) output))
        #:mode 'binary)
      (define resolved
        (resolve-manual-package-source
         (build-path fixture-root "data")
         (odra-manual-package-source-request
          1 'development-directory (path->string source-root) #f
          "odra-package.rktd")))
      (check-true (odra-manual-package-resolved-source? resolved))
      (define manual-artifact
        (struct-copy odra-package-artifact-reference artifact
                     [digest
                      (odra-manual-package-resolved-source-artifact-digest resolved)]
                     [size
                      (odra-manual-package-resolved-source-content-bytes resolved)]))
      (define manual-release
        (struct-copy odra-package-release-reference release
                     [source-uri
                      (string-append "file://" (path->string source-root))]
                     [artifact-set (list manual-artifact)]))
      (define candidate
        (prepare-manual-package-installation
         manifest resolved manual-release '() 'linux 'x86-64))
      (check-true (odra-package-installation-candidate? candidate))
      (check-eq? (odra-package-installation-candidate-curation-status candidate)
                 'manual-uncurated)
      (check-eq? (odra-package-provenance-kind
                  (odra-package-installation-candidate-provenance candidate))
                 'manual))
    (lambda () (delete-directory/files fixture-root))))
