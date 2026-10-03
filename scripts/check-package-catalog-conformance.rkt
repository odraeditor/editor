#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/cmdline
         racket/contract/base
         racket/file
         racket/list
         "package-catalog-curator-support.rkt"
         "../src/command/package-catalogs.rkt"
         "../src/package_catalog/contracts.rkt"
         "../src/package_catalog/curation-records.rkt"
         "../src/package_catalog/manual-records.rkt"
         "../src/package_catalog/official-bootstrap.rkt"
         "../src/package_catalog/security-advisories.rkt"
         "../src/package_catalog/snapshot-reconciliation.rkt"
         "../src/package_catalog/snapshot-records.rkt")

(provide
 (contract-out
  [run-package-catalog-conformance
   (-> path-string? (listof symbol?))]))

(define required-exports
  '(official-bootstrap independent-profile fork-profile mirror-profile
    mirror-publisher-keys mirror-snapshot external-language-release
    external-language-assertion external-language-manual-acquisition advisory
    root-rotation-request))

(define (load-fixture path)
  (define module-path (path->complete-path path))
  (for/hash ([name (in-list required-exports)])
    (values name (dynamic-require module-path name))))

(define (ensure condition message)
  (unless condition
    (raise-user-error 'package-catalog-conformance message)))

(define (identity profile)
  (odra-package-catalog-profile-identity profile))

(define (official-impersonation-rejected? catalog-id)
  (with-handlers ([exn:fail? (lambda (_) #t)])
    (package-catalog-trust-reference
     #:id (make-string 64 #\a) #:catalog-id catalog-id
     #:designation 'official)
    #f))

(define (exact-mirror-check snapshot)
  (define root (make-temporary-file "package-catalog-conformance-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define origin (build-path root "origin.rktd"))
      (define mirror (build-path root "mirror.rktd"))
      (call-with-output-file origin
        (lambda (output)
          (write-bytes (package-catalog-snapshot->module-bytes snapshot) output)))
      (copy-file origin mirror)
      (ensure (validate-package-catalog-exact-mirror origin mirror)
              "exact mirror validation failed"))
    (lambda () (delete-directory/files root))))

(define (run-package-catalog-conformance fixture-path)
  (define fixture (load-fixture fixture-path))
  (define bootstrap (hash-ref fixture 'official-bootstrap))
  (define official
    (odra-package-catalog-bootstrap-profile bootstrap))
  (define independent (hash-ref fixture 'independent-profile))
  (define fork (hash-ref fixture 'fork-profile))
  (define mirror-profile (hash-ref fixture 'mirror-profile))
  (define mirror-keys (hash-ref fixture 'mirror-publisher-keys))
  (define snapshot (hash-ref fixture 'mirror-snapshot))
  (define release (hash-ref fixture 'external-language-release))
  (define assertion (hash-ref fixture 'external-language-assertion))
  (define manual (hash-ref fixture 'external-language-manual-acquisition))
  (define advisory (hash-ref fixture 'advisory))
  (define rotation (hash-ref fixture 'root-rotation-request))

  (ensure (package-catalog-bootstrap-valid? bootstrap)
          "official bootstrap is invalid")
  (ensure (and (not (string=? (identity official) (identity independent)))
               (not (string=? (identity official) (identity fork)))
               (not (string=? (identity independent) (identity fork))))
          "official, independent, and fork identities are not distinct")
  (ensure
   (string=? (odra-package-catalog-profile-display-name independent)
             (odra-package-catalog-profile-display-name fork))
   "fork fixture must prove that copied presentation does not grant identity")
  (ensure (official-impersonation-rejected? (identity fork))
          "fork acquired official designation")
  (exact-mirror-check snapshot)
  (define offline
    (reconcile-package-catalog-snapshots
     mirror-profile mirror-keys snapshot '() 120))
  (ensure (eq? (odra-package-catalog-snapshot-reconciliation-mode offline)
               'offline)
          "confirmed snapshot was not retained offline")
  (ensure
   (equal? release
           (odra-package-curation-assertion-release assertion))
   "curated language bundle release changed identity")
  (ensure
   (equal? release (odra-manual-package-acquisition-release manual))
   "manual language bundle release changed identity")
  (ensure (eq? (odra-manual-package-acquisition-curation-state manual)
               'manual-uncurated)
          "manual acquisition fabricated curation")
  (ensure
   (member "org.example.language"
           (odra-security-advisory-affected-package-ids advisory) string=?)
   "advisory does not select the external language bundle")
  (ensure
   (string=?
    (odra-package-catalog-offline-signing-request-catalog-id rotation)
    (identity independent))
   "root rotation changed catalog identity")
  '(official independent fork exact-mirror manual hostile advisory rotation
    offline language-bundle))

(module+ main
  (define fixture-path #f)
  (command-line
   #:program "check-package-catalog-conformance.rkt"
   #:once-each
   [("--fixture") path "Conformance fixture module"
                     (set! fixture-path path)]
   #:args () (void))
  (unless fixture-path
    (raise-user-error 'package-catalog-conformance "--fixture is required"))
  (define cases (run-package-catalog-conformance fixture-path))
  (printf "package-catalog-conformance: pass cases=~a\n" (length cases)))

(module+ test
  (require racket/runtime-path
           rackunit)
  (define-runtime-path fixture
    "../tests/package_catalog_conformance/fixture.rkt")
  (check-equal?
   (run-package-catalog-conformance fixture)
   '(official independent fork exact-mirror manual hostile advisory rotation
     offline language-bundle)))
