#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/file
         racket/path
         rackunit
         "../../src/package/archive-production.rkt"
         "../../src/package/distribution-records.rkt"
         "../../src/package/distribution.rkt"
         "../../src/package/lifecycle.rkt"
         "../../src/package/manifest-contracts.rkt"
         "../../src/package/runtime.rkt"
         "../../src/package/state-records.rkt"
         "../../src/package_catalog/curation-records.rkt"
         "../../src/storage/record-codec.rkt")

(define (digest character) (make-string 64 character))

(define (sha256 bytes)
  (bytes->hex-string (sha256-bytes (open-input-bytes bytes))))

(define (write-bytes-file path bytes)
  (make-parent-directory* path)
  (call-with-output-file path
    (lambda (output) (write-bytes bytes output))
    #:exists 'truncate/replace #:mode 'binary))

(define (make-fixture root
                      #:api-minimum [api-minimum "1.0.0"]
                      #:api-maximum [api-maximum "2.0.0"])
  (define source-root (build-path root "source"))
  (define distribution-root (build-path root "distribution"))
  (define release-root
    (build-path distribution-root "packages" "odra.fixture" "1.0.0"))
  (make-directory* source-root)
  (make-directory* release-root)
  (define module-bytes
    (string->bytes/utf-8
     (string-append
      "#lang racket/base\n"
      "(require odra/commands)\n"
      "(provide odra-package-contributions)\n"
      "(define odra-package-contributions\n"
      "  (list (make-command 'fixture-command\n"
      "                      (lambda (_context) 'bundled)\n"
      "                      #:requirements '(active-buffer)\n"
      "                      #:effects '(buffer))))\n")))
  (define module-artifact
    (odra-package-artifact
     "entrypoint" 'racket-module "entrypoint.rkt" (sha256 module-bytes)
     (bytes-length module-bytes) #f #f 'racket-extension '()))
  (define-values (manifest rejection)
    (confirm-package-manifest
     (odra-package-manifest-proposal
      1 "odra.fixture" 'extension "Fixture" "1.0.0"
      "Bundled package fixture" "GPL-3.0-only" #f "odra.publisher"
      (make-string 40 #\a) api-minimum api-maximum
      (list (odra-package-target 'linux 'x86-64)) '()
      '(racket-extension) (list module-artifact)
      (odra-package-entrypoint "entrypoint.rkt" 'odra-package-contributions)
      (list (odra-package-contribution
             "fixture-command" 'command '(active-buffer) '(buffer)))
      '() (odra-package-state-compatibility #f #f #f 'none))))
  (check-false rejection)
  (write-bytes-file (build-path source-root "entrypoint.rkt") module-bytes)
  (write-bytes-file
   (build-path source-root "odra-package.rktd")
   (package-manifest->canonical-bytes manifest))
  (define archive-path (build-path release-root "odra.fixture-1.0.0.tar.zst"))
  (define produced
    (produce-package-archive
     manifest source-root archive-path 'linux 'x86-64))
  (check-true (odra-package-archive-production? produced) (format "~s" produced))
  (define manifest-relative "packages/odra.fixture/1.0.0/odra-package.rktd")
  (define archive-relative
    "packages/odra.fixture/1.0.0/odra.fixture-1.0.0.tar.zst")
  (write-bytes-file
   (build-path distribution-root manifest-relative)
   (package-manifest->canonical-bytes manifest))
  (define archive-reference
    (odra-package-artifact-reference
     'linux 'x86-64 (list archive-relative)
     (odra-package-archive-production-digest produced)
     (odra-package-archive-production-size produced)
     "odra-builder" #f 'reproduced))
  (define release
    (odra-package-release-reference
     1 "odra.fixture" (digest #\b) "1.0.0" "odra.publisher"
     "https://forge.example/odra/packages" (make-string 40 #\a) #f
     (package-manifest-digest manifest) (list archive-reference)
     (digest #\c) (digest #\d) (digest #\e) (digest #\f)))
  (values
   distribution-root
   (odra-package-distribution
    1 "odra.standard" "1.0.0"
    (list
     (odra-bundled-package
      release manifest-relative archive-relative #t)))))

(test-case "distribution records round-trip through the closed module grammar"
  (define root (make-temporary-file "package-distribution-record-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define-values (_distribution-root distribution) (make-fixture root))
      (define bytes (package-distribution->module-bytes distribution))
      (define parsed
        (package-distribution-module-parse bytes "odra-distribution.rktd"))
      (check-equal? parsed distribution)
      (check-exn
       exn:fail?
       (lambda ()
         (odra-package-distribution
          1 "odra.standard" "1.0.0"
          (append (odra-package-distribution-packages distribution)
                  (odra-package-distribution-packages distribution)))))
      (check-true
       (odra-record-diagnostic?
        (package-distribution-module-parse
         #"#lang racket/base\n(displayln 'unsafe)\n"
         "unsafe.rktd"))))
    (lambda () (delete-directory/files root))))

(test-case "bundled packages activate locally through the generic lifecycle"
  (define root (make-temporary-file "package-distribution-activation-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define-values (distribution-root distribution) (make-fixture root))
      (define data-root (build-path root "data"))
      (define manager
        (make-package-lifecycle-manager data-root))
      (define activated
        (activate-package-distribution!
         manager distribution-root distribution 'linux 'x86-64))
      (check-eq? (odra-package-distribution-result-status activated) 'confirmed
                 (format "~s" activated))
      (check-equal? (odra-package-distribution-result-activated activated)
                    '("odra.fixture"))
      (define installed
        (package-state-find
         (package-lifecycle-state manager) "odra.fixture" "1.0.0"))
      (check-eq? (odra-installed-package-lifecycle installed) 'active-confirmed)
      (check-eq?
       (odra-package-provenance-kind
        (odra-installed-package-provenance installed))
       'bundled)
      (check-equal?
       (package-runtime-call
        (package-lifecycle-runtime manager) "odra.fixture"
        (odra-installed-package-contribution-generation installed)
        "fixture-command" #f)
       'bundled)
      (package-runtime-close! (package-lifecycle-runtime manager))
      (define restarted (make-package-lifecycle-manager data-root))
      (define restored (package-lifecycle-restore! restarted))
      (check-eq? (odra-package-lifecycle-result-status restored) 'restored)
      (check-equal? (odra-package-lifecycle-result-values restored)
                    '("odra.fixture"))
      (define repeated
        (activate-package-distribution!
         restarted distribution-root distribution 'linux 'x86-64))
      (check-eq? (odra-package-distribution-result-status repeated) 'confirmed)
      (check-equal? (odra-package-distribution-result-unchanged repeated)
                    '("odra.fixture"))
      (package-runtime-close! (package-lifecycle-runtime restarted)))
    (lambda () (delete-directory/files root))))

(test-case "distribution preflight rejects corrupted local archives"
  (define root (make-temporary-file "package-distribution-integrity-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define-values (distribution-root distribution) (make-fixture root))
      (define declaration (car (odra-package-distribution-packages distribution)))
      (define archive-path
        (build-path distribution-root
                    (odra-bundled-package-archive-path declaration)))
      (define corrupted (bytes-copy (file->bytes archive-path)))
      (bytes-set! corrupted 0 (bitwise-xor #xff (bytes-ref corrupted 0)))
      (write-bytes-file archive-path corrupted)
      (define manager
        (make-package-lifecycle-manager (build-path root "data")))
      (define rejected
        (activate-package-distribution!
         manager distribution-root distribution 'linux 'x86-64))
      (check-eq? (odra-package-distribution-result-status rejected) 'rejected)
      (check-eq?
       (odra-package-distribution-failure-code
        (car (odra-package-distribution-result-failures rejected)))
       'archive-digest)
      (check-equal?
       (odra-package-state-packages (package-lifecycle-state manager)) '())
      (package-runtime-close! (package-lifecycle-runtime manager)))
    (lambda () (delete-directory/files root))))

(test-case "distribution preflight rejects invalid content before installation"
  (define root (make-temporary-file "package-distribution-rejection-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define-values (distribution-root distribution)
        (make-fixture root #:api-maximum "1.0.0"))
      (define incompatible
        (struct-copy odra-package-distribution distribution
                     [runtime-api-version "2.0.0"]))
      (define manager
        (make-package-lifecycle-manager (build-path root "data")))
      (define rejected
        (activate-package-distribution!
         manager distribution-root incompatible 'linux 'x86-64))
      (check-eq? (odra-package-distribution-result-status rejected) 'rejected)
      (check-eq?
       (odra-package-distribution-failure-code
        (car (odra-package-distribution-result-failures rejected)))
       'incompatible-api)
      (check-equal?
       (odra-package-state-packages (package-lifecycle-state manager)) '())
      (package-runtime-close! (package-lifecycle-runtime manager)))
    (lambda () (delete-directory/files root))))
