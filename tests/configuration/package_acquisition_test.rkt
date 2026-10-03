#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/file
         rackunit
         "../../src/package/acquisition.rkt"
         "../../src/package/archive-production.rkt"
         "../../src/package/installation.rkt"
         "../../src/package/manifest-contracts.rkt"
         "../../src/package/resolution.rkt"
         "../../src/package/state-records.rkt"
         "../../src/package_catalog/curation-records.rkt"
         "../../src/package_catalog/curation-resolution.rkt")

(define (digest character) (make-string 64 character))
(define (sha256 value)
  (bytes->hex-string (sha256-bytes (open-input-bytes value))))

(test-case "deterministic archive acquisition publishes verified inert package content"
  (define fixture-root (make-temporary-file "package-acquisition-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define source-root (build-path fixture-root "source"))
      (define data-root (build-path fixture-root "data"))
      (make-directory source-root)
      (define marker (build-path fixture-root "entrypoint-evaluated"))
      (define module-bytes
        (string->bytes/utf-8
         (format "#lang racket/base\n(call-with-output-file ~s void)\n"
                 (path->string marker))))
      (define module-artifact
        (odra-package-artifact
         "entrypoint" 'racket-module "main.rkt" (sha256 module-bytes)
         (bytes-length module-bytes) #f #f 'racket-extension '()))
      (define-values (manifest rejection)
        (confirm-package-manifest
         (odra-package-manifest-proposal
          1 "odra.fixture" 'extension "Fixture" "1.0.0"
          "Verified acquisition fixture" "MIT" #f "odra.publisher"
          (make-string 40 #\a) "1.0.0" "2.0.0"
          (list (odra-package-target 'linux 'x86-64)) '()
          '(racket-extension) (list module-artifact)
          (odra-package-entrypoint "main.rkt" 'odra-package-contributions)
          (list (odra-package-contribution
                 "fixture-command" 'command '(active-buffer) '(buffer)))
          '() (odra-package-state-compatibility #f #f #f 'none))))
      (check-false rejection)
      (call-with-output-file (build-path source-root "main.rkt")
        (lambda (output) (write-bytes module-bytes output))
        #:mode 'binary)
      (call-with-output-file (build-path source-root "odra-package.rktd")
        (lambda (output)
          (write-bytes (package-manifest->canonical-bytes manifest) output))
        #:mode 'binary)
      (define first-path (build-path fixture-root "first.tar.zst"))
      (define second-path (build-path fixture-root "second.tar.zst"))
      (define first
        (produce-package-archive
         manifest source-root first-path 'linux 'x86-64))
      (define second
        (produce-package-archive
         manifest source-root second-path 'linux 'x86-64))
      (check-true (odra-package-archive-production? first))
      (check-true (odra-package-archive-production? second))
      (check-equal? (odra-package-archive-production-digest first)
                    (odra-package-archive-production-digest second))
      (check-equal? (file->bytes first-path) (file->bytes second-path))
      (define archive-reference
        (odra-package-artifact-reference
         'linux 'x86-64 '("fixture.tar.zst")
         (odra-package-archive-production-digest first)
         (odra-package-archive-production-size first)
         "odra-builder" #f 'reproduced))
      (define release
        (odra-package-release-reference
         1 "odra.fixture" (digest #\b) "1.0.0" "odra.publisher"
         "https://forge.example/odra/fixture" (make-string 40 #\a) #f
         (package-manifest-digest manifest) (list archive-reference)
         (digest #\c) (digest #\d) (digest #\e) (digest #\f)))
      (define catalog-id (digest #\1))
      (define assertion
        (odra-package-curation-assertion
         1 (digest #\2) catalog-id 1 release "decision-1" "policy-v1"
         'admitted "" '() 1 1))
      (define resolution
        (resolve-curated-package
         (list (odra-package-curated-source
                catalog-id (digest #\3) 10 (list assertion)))
         (odra-package-resolution-request
          "odra.fixture" "1.0.0" "1.0.0" 'linux 'x86-64 #f)))
      (define prepared
        (acquire-curated-package-resolution
         data-root resolution
         #:location-resolver (lambda (_) (path->string first-path))))
      (check-true (list? prepared) (format "~s" prepared))
      (define candidate (car prepared))
      (define acquired (cadr prepared))
      (check-true (odra-package-acquisition? acquired))
      (check-equal? (odra-package-acquisition-downloaded-bytes acquired) 0)
      (check-equal? (length (odra-package-acquisition-content acquired)) 2)
      (check-true
       (file-exists?
        (package-content-path
         data-root (odra-package-archive-production-digest first))))
      (define installed
        (install-package-candidate!
         data-root #f candidate acquired #:operation-id "install-fixture"))
      (check-true (odra-package-installation-result? installed))
      (check-eq?
       (odra-installed-package-lifecycle
        (odra-package-installation-result-package installed))
       'installed-disabled)
      (check-false (file-exists? marker)))
    (lambda () (delete-directory/files fixture-root))))

(test-case "archive production rejects undeclared source files"
  (define fixture-root (make-temporary-file "package-shape-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define payload #"fixture")
      (define artifact
        (odra-package-artifact
         "payload" 'data "payload.txt" (sha256 payload) (bytes-length payload)
         #f #f #f '()))
      (define-values (manifest rejection)
        (confirm-package-manifest
         (odra-package-manifest-proposal
          1 "odra.shape" 'extension "Shape" "1.0.0" "" "MIT" #f
          "odra.publisher" (make-string 40 #\a) "1.0.0" "2.0.0"
          (list (odra-package-target 'linux 'x86-64)) '() '() (list artifact)
          #f '() '() (odra-package-state-compatibility #f #f #f 'none))))
      (check-false rejection)
      (call-with-output-file (build-path fixture-root "odra-package.rktd")
        (lambda (output)
          (write-bytes (package-manifest->canonical-bytes manifest) output))
        #:mode 'binary)
      (call-with-output-file (build-path fixture-root "payload.txt")
        (lambda (output) (write-bytes payload output)) #:mode 'binary)
      (call-with-output-file (build-path fixture-root "undeclared.txt")
        (lambda (output) (write-bytes #"extra" output)) #:mode 'binary)
      (define result
        (produce-package-archive
         manifest fixture-root (build-path fixture-root "result.tar.zst")
         'linux 'x86-64))
      (check-true (odra-package-archive-production-failure? result))
      (check-eq? (odra-package-archive-production-failure-code result)
                 'archive-shape))
    (lambda () (delete-directory/files fixture-root))))
