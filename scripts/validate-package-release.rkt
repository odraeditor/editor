#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/cmdline
         racket/contract/base
         racket/file
         "../src/package/acquisition.rkt"
         "../src/package/installation.rkt"
         "../src/package/manifest-contracts.rkt"
         "../src/package/resolution.rkt"
         "../src/package/runtime.rkt"
         "../src/package/state-records.rkt"
         "../src/package_catalog/curation-records.rkt"
         "../src/storage/record-codec.rkt")

(provide
 (contract-out
  [validate-package-release
   (-> path-string? path-string? symbol? symbol? void?)]))

(define (sha256-file path)
  (call-with-input-file path
    (lambda (input) (bytes->hex-string (sha256-bytes input)))
    #:mode 'binary))

(define (manifest-or-fail path)
  (define manifest (package-manifest-module-load path))
  (when (odra-record-diagnostic? manifest)
    (raise-user-error
     'validate-package-release
     "manifest rejected: ~a"
     (odra-record-diagnostic-message manifest)))
  (unless (bytes=? (file->bytes path)
                   (package-manifest->canonical-bytes manifest))
    (raise-user-error 'validate-package-release
                      "manifest is not canonically encoded"))
  manifest)

(define (release-candidate manifest archive platform architecture)
  (define manifest-digest (package-manifest-digest manifest))
  (define archive-digest (sha256-file archive))
  (define artifact
    (odra-package-artifact-reference
     platform architecture '("artifact.tar.zst") archive-digest
     (file-size archive) "local-validator" #f 'reproduced))
  (define release
    (odra-package-release-reference
     1
     (odra-package-manifest-package-id manifest)
     manifest-digest
     (odra-package-manifest-version manifest)
     (odra-package-manifest-publisher-id manifest)
     "https://forge.adrianpk.com/odra/packages"
     (odra-package-manifest-source-revision manifest)
     #f
     manifest-digest
     (list artifact)
     manifest-digest manifest-digest manifest-digest manifest-digest))
  (odra-package-installation-candidate
   manifest manifest-digest release artifact
   (odra-package-provenance
    'manual #f archive-digest manifest-digest
    (odra-package-manifest-publisher-id manifest)
    (odra-package-manifest-source-revision manifest))
   'manual-uncurated))

(define (validate-runtime root candidate acquisition)
  (define installed-result
    (install-package-candidate!
     root #f candidate acquisition #:operation-id "validate-package-release"))
  (unless (odra-package-installation-result? installed-result)
    (raise-user-error 'validate-package-release
                      "inactive package installation failed: ~s"
                      installed-result))
  (define installed
    (odra-package-installation-result-package installed-result))
  (define manifest
    (odra-package-installation-candidate-manifest candidate))
  (define grant
    (odra-package-authority-grant
     (odra-package-manifest-package-id manifest)
     (odra-package-manifest-version manifest)
     1
     (odra-package-manifest-authorities manifest)
     "Focused package release validation"))
  (define runtime-candidate
    (prepare-package-runtime root installed manifest grant 1))
  (unless (odra-package-runtime-candidate? runtime-candidate)
    (raise-user-error 'validate-package-release
                      "restricted package runtime rejected: ~s"
                      runtime-candidate))
  (define command-names
    (package-runtime-candidate-command-names runtime-candidate))
  (define declared-command-names
    (for/list
        ([contribution
          (in-list (odra-package-manifest-contributions manifest))]
         #:when (eq? (odra-package-contribution-facet contribution) 'command))
      (odra-package-contribution-id contribution)))
  (unless (equal? (sort command-names string<?)
                  (sort declared-command-names string<?))
    (discard-package-runtime-candidate! runtime-candidate)
    (raise-user-error 'validate-package-release
                      "unexpected package commands: ~s"
                      command-names))
  (discard-package-runtime-candidate! runtime-candidate))

(define (validate-package-release manifest-path archive-path platform architecture)
  (define manifest (manifest-or-fail manifest-path))
  (define candidate
    (release-candidate manifest archive-path platform architecture))
  (define root (make-temporary-file "odra-package-validation-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind
    void
    (lambda ()
      (define acquisition
        (acquire-package-candidate
         root candidate
         #:location-resolver (lambda (_location) archive-path)))
      (unless (odra-package-acquisition? acquisition)
        (raise-user-error 'validate-package-release
                          "archive acquisition rejected: ~s"
                          acquisition))
      (validate-runtime root candidate acquisition)
      (printf
       "package-release: valid package=~a version=~a manifest=~a archive=~a commands=~a\n"
       (odra-package-manifest-package-id manifest)
       (odra-package-manifest-version manifest)
       (package-manifest-digest manifest)
       (sha256-file archive-path)
       (length (odra-package-manifest-contributions manifest))))
    (lambda () (delete-directory/files root))))

(module+ main
  (define manifest-path #f)
  (define archive-path #f)
  (define platform 'linux)
  (define architecture 'x86-64)
  (command-line
   #:program "validate-package-release.rkt"
   #:once-each
   [("--manifest") path "Canonical odra-package.rktd path"
    (set! manifest-path path)]
   [("--archive") path "Deterministic package archive path"
    (set! archive-path path)]
   [("--platform") value "Target platform"
    (set! platform (string->symbol value))]
   [("--architecture") value "Target architecture"
    (set! architecture (string->symbol value))]
   #:args () (void))
  (unless (and manifest-path archive-path)
    (raise-user-error 'validate-package-release
                      "--manifest and --archive are required"))
  (validate-package-release manifest-path archive-path platform architecture))
