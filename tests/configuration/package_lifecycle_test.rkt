#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/file
         racket/list
         racket/path
         racket/string
         rackunit
         "../../src/package/acquisition.rkt"
         "../../src/package/lifecycle.rkt"
         "../../src/package/lifecycle-service.rkt"
         (submod "../../src/package/lifecycle-service.rkt" test-support)
         "../../src/package/manifest-contracts.rkt"
         "../../src/package/resolution.rkt"
         "../../src/package/runtime.rkt"
         "../../src/package/state-records.rkt"
         "../../src/package_catalog/curation-records.rkt")

(define (digest character) (make-string 64 character))

(define (sha256 value)
  (bytes->hex-string (sha256-bytes (open-input-bytes value))))

(define (write-content root content)
  (define content-digest (sha256 content))
  (define path (package-content-path root content-digest))
  (make-parent-directory* path)
  (for ([directory
         (in-list
          (list root
                (build-path root "packages")
                (build-path root "packages" "content")
                (build-path root "packages" "content" "sha256")
                (path-only path)))])
    (file-or-directory-permissions directory #o700))
  (call-with-output-file path
    (lambda (output) (write-bytes content output))
    #:mode 'binary #:permissions #o600)
  (values content-digest path))

(define (fixture root version response revision-character)
  (file-or-directory-permissions root #o700)
  (define source
    (string->bytes/utf-8
     (string-append
      "#lang racket/base\n"
      "(require odra/commands)\n"
      "(provide odra-package-contributions)\n"
      "(define odra-package-contributions\n"
      "  (list (make-command 'fixture-command (lambda (_context) '"
      response
      ") #:requirements '(active-buffer) #:effects '(buffer))))\n")))
  (define-values (module-digest module-path) (write-content root source))
  (define-values (manifest rejection)
    (confirm-package-manifest
     (odra-package-manifest-proposal
      1 "odra.fixture" 'extension "Fixture" version "" "MIT" #f
      "odra.publisher" (make-string 40 revision-character) "1.0.0" "2.0.0"
      (list (odra-package-target 'linux 'x86-64)) '() '(racket-extension)
      (list
       (odra-package-artifact
        "entrypoint" 'racket-module "main.rkt" module-digest
        (bytes-length source) #f #f 'racket-extension '()))
      (odra-package-entrypoint "main.rkt" 'odra-package-contributions)
      (list
       (odra-package-contribution
        "fixture-command" 'command '(active-buffer) '(buffer)))
      '() (odra-package-state-compatibility #f #f #f 'none))))
  (check-false rejection)
  (define manifest-bytes (package-manifest->canonical-bytes manifest))
  (define archive-bytes (string->bytes/utf-8 (string-append "archive-" version)))
  (define-values (manifest-digest manifest-path)
    (write-content root manifest-bytes))
  (define-values (archive-digest archive-path)
    (write-content root archive-bytes))
  (define archive
    (odra-package-artifact-reference
     'linux 'x86-64 (list (string-append "https://packages.example/" version))
     archive-digest (bytes-length archive-bytes) "odra-builder" #f 'reproduced))
  (define release
    (odra-package-release-reference
     1 "odra.fixture" (digest revision-character) version "odra.publisher"
     "https://forge.example/odra/fixture"
     (make-string 40 revision-character) #f manifest-digest (list archive)
     (digest #\c) (digest #\d) (digest #\e) (digest #\f)))
  (values
   (odra-package-installation-candidate
    manifest manifest-digest release archive
    (odra-package-provenance
     'catalog (digest #\1) (digest #\2) (digest #\3)
     "odra.publisher" (make-string 40 revision-character))
    'admitted)
   (odra-package-acquisition
    "odra.fixture" version manifest-digest archive-digest archive-path
    (list
     (odra-package-content-handle
      manifest-path manifest-digest (bytes-length manifest-bytes) 'manifest #f)
     (odra-package-content-handle
      module-path module-digest (bytes-length source) 'racket-module #f))
    (bytes-length archive-bytes) #f '())))

(test-case "generic lifecycle installs inactive and activates only after authority confirmation"
  (define root (make-temporary-file "package-lifecycle-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define manager (make-package-lifecycle-manager root))
      (define-values (candidate acquisition) (fixture root "1.0.0" "initial" #\a))
      (define installed (package-lifecycle-install! manager candidate acquisition))
      (check-eq? (odra-package-lifecycle-result-status installed) 'installed
                 (format "~s" installed))
      (check-eq? (odra-installed-package-lifecycle
                  (odra-package-lifecycle-result-package installed))
                 'installed-disabled)
      (check-false
       (package-runtime-active-generation
        (package-lifecycle-runtime manager) "odra.fixture"))
      (define enabled
        (package-lifecycle-enable! manager "odra.fixture" "1.0.0"
                                   "confirmed in package workflow"))
      (check-eq? (odra-package-lifecycle-result-status enabled) 'enabled)
      (check-equal?
       (package-runtime-call
        (package-lifecycle-runtime manager) "odra.fixture"
        (odra-installed-package-contribution-generation
         (odra-package-lifecycle-result-package enabled))
        "fixture-command" #f)
       'initial)
      (define inspection
        (car (package-lifecycle-inspect manager "odra.fixture" #f)))
      (check-eq? (odra-package-lifecycle-inspection-lifecycle inspection)
                 'active-confirmed)
      (check-equal?
       (odra-package-lifecycle-inspection-granted-authorities inspection)
       '(racket-extension)))
    (lambda () (delete-directory/files root))))

(test-case "update rollback disable and remove preserve exact human release identity"
  (define root (make-temporary-file "package-lifecycle-update-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define manager (make-package-lifecycle-manager root))
      (define-values (first-candidate first-acquisition)
        (fixture root "1.0.0" "initial" #\a))
      (define-values (second-candidate second-acquisition)
        (fixture root "1.1.0" "updated" #\b))
      (package-lifecycle-install! manager first-candidate first-acquisition)
      (package-lifecycle-enable! manager "odra.fixture" "1.0.0" "initial grant")
      (package-lifecycle-install! manager second-candidate second-acquisition)
      (define updated
        (package-lifecycle-update! manager "odra.fixture" "1.1.0" "update grant"))
      (check-eq? (odra-package-lifecycle-result-status updated) 'updated
                 (format "~s" updated))
      (check-equal? (odra-installed-package-predecessor
                     (odra-package-lifecycle-result-package updated))
                    "1.0.0")
      (define rolled-back
        (package-lifecycle-rollback! manager "odra.fixture" "rollback grant"))
      (check-eq? (odra-package-lifecycle-result-status rolled-back) 'rolled-back)
      (check-equal? (odra-installed-package-version
                     (odra-package-lifecycle-result-package rolled-back))
                    "1.0.0")
      (check-eq? (odra-package-lifecycle-result-status
                  (package-lifecycle-disable! manager "odra.fixture"))
                 'disabled)
      (check-eq? (odra-package-lifecycle-result-status
                  (package-lifecycle-remove! manager "odra.fixture" "1.1.0"))
                 'removed))
    (lambda () (delete-directory/files root))))

(test-case "cleanup removes only unreachable package content"
  (define root (make-temporary-file "package-lifecycle-cleanup-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define manager (make-package-lifecycle-manager root))
      (define-values (candidate acquisition) (fixture root "1.0.0" "initial" #\a))
      (define installed (package-lifecycle-install! manager candidate acquisition))
      (define package (odra-package-lifecycle-result-package installed))
      (package-lifecycle-remove! manager "odra.fixture" "1.0.0")
      (define known
        (append
         (list (odra-installed-package-manifest package)
               (odra-installed-package-archive package))
         (odra-installed-package-artifacts package)))
      (define deleted '())
      (define cleaned
        (package-lifecycle-cleanup!
         manager known
         (lambda (content-digest)
           (set! deleted (cons content-digest deleted))
           #t)))
      (check-eq? (odra-package-lifecycle-result-status cleaned) 'cleaned)
      (check-equal? (sort deleted string<?) (sort known string<?))
      (check-equal? (package-lifecycle-list manager) '()))
    (lambda () (delete-directory/files root))))

(test-case "restart restores active packages from verified content"
  (define root (make-temporary-file "package-lifecycle-restart-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define first (make-package-lifecycle-manager root))
      (define-values (candidate acquisition) (fixture root "1.0.0" "initial" #\a))
      (package-lifecycle-install! first candidate acquisition)
      (package-lifecycle-enable! first "odra.fixture" "1.0.0" "restart grant")
      (define restarted (make-package-lifecycle-manager root))
      (check-eq? (odra-package-lifecycle-result-status
                  (package-lifecycle-doctor restarted))
                 'healthy)
      (define restored (package-lifecycle-restore! restarted))
      (check-eq? (odra-package-lifecycle-result-status restored) 'restored)
      (check-equal? (odra-package-lifecycle-result-values restored)
                    '("odra.fixture"))
      (check-eq? (odra-package-lifecycle-result-status
                  (package-lifecycle-doctor restarted))
                 'healthy))
    (lambda () (delete-directory/files root))))

(test-case "user-facing runtime service uses package names and exact releases"
  (define root (make-temporary-file "package-lifecycle-service-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define-values (candidate acquisition) (fixture root "1.0.0" "initial" #\a))
      (check-equal?
       (odra-package-lifecycle-runtime-result-detail
        (package-lifecycle-runtime-list root))
       "No packages are installed")
      (define installed
        (parameterize
            ([current-package-lifecycle-installer
              (lambda (_root id version)
                (if (and (string=? id "odra.fixture")
                         (string=? version "1.0.0"))
                    (list candidate acquisition)
                    "Release not found"))])
          (package-lifecycle-runtime-install root "odra.fixture@1.0.0")))
      (check-eq? (odra-package-lifecycle-runtime-result-status installed)
                 'success)
      (check-regexp-match
       #rx"requested authorities: racket-extension"
       (odra-package-lifecycle-runtime-result-detail installed))
      (check-regexp-match
       #rx"installed-disabled"
       (odra-package-lifecycle-runtime-result-detail
        (package-lifecycle-runtime-describe root "odra.fixture")))
      (check-regexp-match
       #rx"requested authorities racket-extension [|] granted authorities none"
       (odra-package-lifecycle-runtime-result-detail
        (package-lifecycle-runtime-describe root "odra.fixture")))
      (check-eq?
       (odra-package-lifecycle-runtime-result-status
        (package-lifecycle-runtime-enable root "odra.fixture@1.0.0"))
       'success)
      (check-regexp-match
       #rx"active-confirmed"
       (odra-package-lifecycle-runtime-result-detail
        (package-lifecycle-runtime-describe root "odra.fixture@1.0.0")))
      (check-eq?
       (odra-package-lifecycle-runtime-result-status
        (package-lifecycle-runtime-doctor root))
       'success)
      (check-eq?
       (odra-package-lifecycle-runtime-result-status
        (package-lifecycle-runtime-install root "opaque-id"))
       'failure))
    (lambda ()
      (reset-package-lifecycle-runtime!)
      (delete-directory/files root))))
