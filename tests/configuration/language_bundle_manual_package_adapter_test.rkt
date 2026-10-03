#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/file
         rackunit
         "../../src/command/language-bundles.rkt"
         "../../src/language_bundle/activation-candidate.rkt"
         "../../src/language_bundle/lifecycle.rkt"
         "../../src/language_bundle/manual-package-adapter.rkt"
         "../../src/language_bundle/state-records.rkt"
         "../../src/package_catalog/curation-records.rkt"
         "../../src/package_catalog/curation-resolution.rkt"
         "../../src/package_catalog/manual-persistence.rkt"
         "../../src/package_catalog/manual-records.rkt"
         "../../src/package_catalog/manual-resolution.rkt")

(define (digest character) (make-string 64 character))
(define manifest-bytes #"checked manual manifest")
(define manifest-digest
  (bytes->hex-string (sha256-bytes (open-input-bytes manifest-bytes))))
(define artifact-bytes (make-bytes 2048 65))
(define artifact-digest
  (bytes->hex-string (sha256-bytes (open-input-bytes artifact-bytes))))
(define catalog-a (digest #\b))
(define catalog-b (digest #\c))

(define value
  (language-support-bundle
   #:id 'org.example.manual #:display-name "Manual Language"
   #:version "1.0.0" #:api-min "1.0.0" #:api-max "2.0.0"
   #:description "Manual package adapter fixture."
   #:publisher 'org.example.publisher #:source 'manual.local
   #:targets '((linux x86-64))))

(define input
  (odra-bundle-preparation-input
   value 'personal "manual" '() (hasheq) (hasheq) 0))

(define fixture-root
  (make-temporary-file "odra-manual-adapter-source-~a" 'directory))
(file-or-directory-permissions fixture-root #o700)
(define fixture-artifact (build-path fixture-root "manual.tar.zst"))
(void
 (call-with-output-file fixture-artifact
   (lambda (output) (write-bytes artifact-bytes output))
   #:exists 'error #:mode 'binary))
(define resolved
  (resolve-manual-package-source
   fixture-root
   (odra-manual-package-source-request
    1 'local-artifact (path->string fixture-artifact) #f #f)))
(unless (odra-manual-package-resolved-source? resolved)
  (error 'manual-package-adapter-fixture "manual source resolution failed"))

(define release
  (odra-package-release-reference
   1 "org.example.manual" (digest #\d) "1.0.0" "org.example.publisher"
   (string-append "file://" (path->string fixture-artifact))
   (make-string 40 #\e) #f manifest-digest
   (list
    (odra-package-artifact-reference
     'linux 'x86-64 '("manual.tar.zst") artifact-digest
     (bytes-length artifact-bytes) #f #f
     'unverified))
   (digest #\f) (digest #\1) (digest #\2) (digest #\3)))

(define (assertion catalog id candidate [status 'admitted])
  (odra-package-curation-assertion
   1 id catalog 1 candidate "decision-1" "policy-v1" status
   (if (eq? status 'admitted) "" "deprecated") '() 1 1))

(define (source catalog precedence assertions)
  (odra-package-curated-source catalog (digest #\9) precedence assertions))

(define (prepare [sources '()] [candidate-release release] [candidate-input input]
                 [bytes manifest-bytes])
  (prepare-manual-language-bundle-installation
   resolved candidate-release sources candidate-input bytes
   'linux 'x86-64 "manual user grant"))

(test-case "manual candidate stays visibly uncurated without an exact assertion"
  (define candidate (prepare))
  (check-true (odra-manual-language-bundle-candidate? candidate))
  (check-eq?
   (odra-manual-package-acquisition-curation-state
    (odra-manual-language-bundle-candidate-acquisition candidate))
   'manual-uncurated)
  (check-equal?
   (odra-manual-language-bundle-candidate-matching-assertions candidate) '()))

(test-case "all exact curator assertions remain attributable"
  (define first (assertion catalog-a (digest #\5) release))
  (define second (assertion catalog-b (digest #\6) release 'deprecated))
  (define candidate
    (prepare
     (list (source catalog-b 10 (list second))
           (source catalog-a 20 (list first)))))
  (define acquisition
    (odra-manual-language-bundle-candidate-acquisition candidate))
  (check-eq? (odra-manual-package-acquisition-curation-state acquisition)
             'matches-curated-release)
  (check-equal? (odra-manual-package-acquisition-matching-assertion-ids acquisition)
                (list (digest #\5) (digest #\6))))

(test-case "nearby but nonidentical curated release does not create curation"
  (define other
    (struct-copy odra-package-release-reference release
                 [release-id (digest #\7)]
                 [dependency-set-digest (digest #\8)]))
  (define candidate
    (prepare (list (source catalog-a 10
                           (list (assertion catalog-a (digest #\5) other))))))
  (check-eq?
   (odra-manual-package-acquisition-curation-state
    (odra-manual-language-bundle-candidate-acquisition candidate))
   'manual-uncurated))

(test-case "manifest and artifact mismatches reject before installation"
  (define manifest-failure (prepare '() release input #"changed manifest"))
  (check-eq? (odra-manual-language-bundle-failure-code manifest-failure)
             'manifest-mismatch)
  (define artifact-failure
    (prepare
     '()
     (struct-copy
      odra-package-release-reference release
      [artifact-set
       (list
        (struct-copy odra-package-artifact-reference
                     (car (odra-package-release-reference-artifact-set release))
                     [digest (digest #\8)]))])))
  (check-eq? (odra-manual-language-bundle-failure-code artifact-failure)
             'artifact-mismatch))

(test-case "manual preparation source cannot impersonate a catalog package"
  (define catalog-input
    (struct-copy odra-bundle-preparation-input input [source 'package]))
  (define result (prepare '() release catalog-input))
  (check-eq? (odra-manual-language-bundle-failure-code result)
             'source-mismatch))

(test-case "manual release retains the exact resolved source reference"
  (define result
    (prepare
     '()
     (struct-copy odra-package-release-reference release
                  [source-uri "file:///tmp/different.tar.zst"])))
  (check-eq? (odra-manual-language-bundle-failure-code result)
             'source-mismatch)
  (check-eq? (odra-manual-language-bundle-failure-field result)
             'source-uri))

(define (record-state manager)
  (odra-installed-bundle-lifecycle
   (car
    (odra-language-bundle-state-bundles
     (bundle-lifecycle-state manager)))))

(test-case "manual installation is inactive until a separate enable action"
  (define root (make-temporary-file "odra-manual-install-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind
    void
    (lambda ()
      (define manager (make-bundle-lifecycle-manager root))
      (define candidate (prepare))
      (define installed (install-manual-language-bundle! root manager candidate))
      (check-eq? (odra-bundle-lifecycle-result-state installed) 'installed)
      (check-eq? (record-state manager) 'installed-disabled)
      (define acquisition
        (odra-manual-language-bundle-candidate-acquisition candidate))
      (check-equal?
       (manual-package-acquisition-module-load
        (manual-package-acquisition-path
         root (odra-manual-package-acquisition-id acquisition)))
       acquisition)
      (define restarted
        (make-bundle-lifecycle-manager
         root
         #:inputs
         (list
          (odra-manual-language-bundle-candidate-install-request candidate))))
      (check-eq? (record-state restarted) 'installed-disabled)
      (check-eq?
       (odra-bundle-lifecycle-result-state
        (bundle-lifecycle-enable! manager "org.example.manual" "1.0.0"))
       'enable)
      (check-eq? (record-state manager) 'active-confirmed))
    (lambda () (delete-directory/files root))))

(test-case "manual dependency remains missing instead of adding a source"
  (define dependent-value
    (struct-copy
     odra-language-support-bundle value
     [dependencies
      (list
       (language-bundle-dependency
        #:id 'org.example.runtime #:minimum "1.0.0" #:maximum "2.0.0"))]))
  (define dependent-input
    (struct-copy odra-bundle-preparation-input input [bundle dependent-value]))
  (define candidate (prepare '() release dependent-input))
  (define root (make-temporary-file "odra-manual-dependency-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind
    void
    (lambda ()
      (define manager (make-bundle-lifecycle-manager root))
      (check-eq?
       (odra-bundle-lifecycle-result-state
        (install-manual-language-bundle! root manager candidate))
       'installed)
      (define enabled
        (bundle-lifecycle-enable! manager "org.example.manual" "1.0.0"))
      (check-eq? (odra-bundle-lifecycle-result-state enabled) 'rejected)
      (check-eq? (record-state manager) 'installed-disabled))
    (lambda () (delete-directory/files root))))

(delete-directory/files fixture-root)
