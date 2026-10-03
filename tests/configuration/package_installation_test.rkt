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
         rackunit
         "../../src/package/acquisition.rkt"
         "../../src/package/installation.rkt"
         (submod "../../src/package/installation.rkt" test-support)
         "../../src/package/manifest-contracts.rkt"
         "../../src/package/resolution.rkt"
         "../../src/package/state-persistence.rkt"
         "../../src/package/state-records.rkt"
         "../../src/package_catalog/curation-records.rkt")

(define (digest character) (make-string 64 character))
(define (sha256 value)
  (bytes->hex-string (sha256-bytes (open-input-bytes value))))

(define (write-content root bytes)
  (define digest (sha256 bytes))
  (define path (package-content-path root digest))
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
    (lambda (output) (write-bytes bytes output))
    #:mode 'binary #:permissions #o600)
  (values digest (path->string path)))

(define (fixture root)
  (define entrypoint-bytes
    #"#lang racket/base\n(error 'entrypoint \"must remain inert\")\n")
  (define entrypoint-digest (sha256 entrypoint-bytes))
  (define-values (manifest rejection)
    (confirm-package-manifest
     (odra-package-manifest-proposal
      1 "odra.fixture" 'extension "Fixture" "1.0.0" "" "MIT" #f
      "odra.publisher" (make-string 40 #\a) "1.0.0" "2.0.0"
      (list (odra-package-target 'linux 'x86-64)) '() '(racket-extension)
      (list
       (odra-package-artifact
        "entrypoint" 'racket-module "main.rkt" entrypoint-digest
        (bytes-length entrypoint-bytes) #f #f 'racket-extension '()))
      (odra-package-entrypoint "main.rkt" 'odra-package-contributions)
      (list (odra-package-contribution
             "fixture-command" 'command '(active-buffer) '(buffer)))
      '() (odra-package-state-compatibility #f #f #f 'none))))
  (check-false rejection)
  (define manifest-bytes (package-manifest->canonical-bytes manifest))
  (define archive-bytes #"verified archive bytes")
  (define-values (manifest-digest manifest-path)
    (write-content root manifest-bytes))
  (define-values (_entrypoint-digest entrypoint-path)
    (write-content root entrypoint-bytes))
  (define-values (archive-digest archive-path)
    (write-content root archive-bytes))
  (define archive-reference
    (odra-package-artifact-reference
     'linux 'x86-64 '("fixture.tar.zst") archive-digest
     (bytes-length archive-bytes) "odra-builder" #f 'reproduced))
  (define release
    (odra-package-release-reference
     1 "odra.fixture" (digest #\b) "1.0.0" "odra.publisher"
     "https://forge.example/odra/fixture" (make-string 40 #\a) #f
     manifest-digest (list archive-reference)
     (digest #\c) (digest #\d) (digest #\e) (digest #\f)))
  (define candidate
    (odra-package-installation-candidate
     manifest manifest-digest release archive-reference
     (odra-package-provenance
      'catalog (digest #\1) (digest #\2) (digest #\3)
      "odra.publisher" (make-string 40 #\a))
     'admitted))
  (define acquisition
    (odra-package-acquisition
     "odra.fixture" "1.0.0" manifest-digest archive-digest archive-path
     (list
      (odra-package-content-handle
       manifest-path manifest-digest (bytes-length manifest-bytes) 'manifest #f)
      (odra-package-content-handle
       entrypoint-path entrypoint-digest (bytes-length entrypoint-bytes)
       'racket-module #f))
     (bytes-length archive-bytes) #f '()))
  (values candidate acquisition))

(test-case "verified installation commits only installed-disabled state"
  (define root (make-temporary-file "package-installation-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define-values (candidate acquisition) (fixture root))
      (define result
        (install-package-candidate!
         root #f candidate acquisition #:operation-id "install-fixture"))
      (check-true (odra-package-installation-result? result) (format "~s" result))
      (define state (odra-package-installation-result-state result))
      (define installed (odra-package-installation-result-package result))
      (check-equal? (odra-package-state-generation state) 2)
      (check-eq? (odra-installed-package-lifecycle installed) 'installed-disabled)
      (check-equal? (odra-installed-package-granted-authorities installed) '())
      (check-equal? (odra-installed-package-contribution-generation installed) 0)
      (check-equal? (odra-package-state-operations state) '())
      (define startup (package-state-startup root))
      (check-eq? (odra-package-startup-mode startup) 'confirmed)
      (define repeated
        (install-package-candidate! root state candidate acquisition))
      (check-true (odra-package-installation-result-idempotent? repeated))
      (check-equal? (odra-package-state-generation
                     (odra-package-installation-result-state repeated))
                    2))
    (lambda () (delete-directory/files root))))

(test-case "interrupted final publication leaves a recoverable operation journal"
  (define root (make-temporary-file "package-installation-recovery-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define-values (candidate acquisition) (fixture root))
      (define writes 0)
      (define result
        (parameterize
            ([current-package-installation-persist
              (lambda (data-root state)
                (set! writes (add1 writes))
                (if (= writes 2)
                    'injected-publication-failure
                    (package-state-persist data-root state)))])
          (install-package-candidate!
           root #f candidate acquisition #:operation-id "install-interrupted")))
      (check-true (odra-package-installation-failure? result) (format "~s" result))
      (define startup (package-state-startup root))
      (check-eq? (odra-package-startup-mode startup) 'resume-operation)
      (define recovered
        (recover-package-installations! root (odra-package-startup-state startup)))
      (check-true (odra-package-installation-result-recovered? recovered))
      (check-equal? (odra-package-state-operations
                     (odra-package-installation-result-state recovered))
                    '())
      (check-equal? (odra-package-state-packages
                     (odra-package-installation-result-state recovered))
                    '()))
    (lambda () (delete-directory/files root))))

(test-case "changed verified content is quarantined before installation"
  (define root (make-temporary-file "package-installation-quarantine-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define-values (candidate acquisition) (fixture root))
      (define content (last (odra-package-acquisition-content acquisition)))
      (call-with-output-file (odra-package-content-handle-path content)
        (lambda (output) (write-bytes #"changed" output))
        #:exists 'truncate/replace #:mode 'binary)
      (define result
        (install-package-candidate! root #f candidate acquisition))
      (check-true (odra-package-installation-failure? result) (format "~s" result))
      (check-eq? (odra-package-installation-failure-code result) 'verification)
      (check-equal? (odra-package-state-packages
                     (odra-package-installation-failure-state result))
                    '())
      (check-not-false
       (member (odra-package-content-handle-digest content)
               (odra-package-state-quarantine
                (odra-package-installation-failure-state result)))))
    (lambda () (delete-directory/files root))))
