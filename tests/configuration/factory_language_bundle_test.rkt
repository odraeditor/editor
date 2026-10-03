#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/file
         racket/runtime-path
         rackunit
         (prefix-in bundle: "../../src/command/language-bundles.rkt")
         "../../src/language_bundle/factory-bundles.rkt")

(define-runtime-path repository-root "../..")

(define (artifact-path artifact)
  (build-path repository-root
              (bundle:odra-language-bundle-artifact-path artifact)))

(define (file-sha256 path)
  (call-with-input-file path
    (lambda (input)
      (bytes->hex-string (sha256-bytes input)))))

(define (check-artifact-fidelity artifact)
  (define path (artifact-path artifact))
  (check-true (file-exists? path)
              (format "missing Factory artifact: ~a" path))
  (check-equal? (file-size path)
                (bundle:odra-language-bundle-artifact-size artifact)
                (format "Factory artifact size mismatch: ~a" path))
  (check-equal? (file-sha256 path)
                (bundle:odra-language-bundle-artifact-sha256 artifact)
                (format "Factory artifact digest mismatch: ~a" path)))

(test-case "Factory bundle artifacts match their declared immutable sources"
  (for* ([factory (in-list (factory-language-bundles))]
         [artifact
          (in-list
           (bundle:odra-language-support-bundle-artifacts factory))])
    (check-artifact-fidelity artifact)))

(test-case "Factory bundle discovery exposes one record per maintained identity"
  (check-equal?
   (map bundle:odra-language-support-bundle-id
        (factory-language-bundles))
   '(org.odra.jan org.odra.odin org.odra.racket org.odra.go org.odra.rust
                  org.odra.javascript org.odra.typescript org.odra.html
                  org.odra.css))
  (check-eq? (factory-language-bundle-find 'org.odra.jan)
             factory-jan-language-bundle)
  (check-eq? (factory-language-bundle-find 'org.odra.odin)
             factory-odin-language-bundle)
  (check-eq? (factory-language-bundle-find 'org.odra.racket)
             factory-racket-language-bundle)
  (check-eq? (factory-language-bundle-find 'org.odra.go)
             factory-go-language-bundle)
  (check-eq? (factory-language-bundle-find 'org.odra.rust)
             factory-rust-language-bundle)
  (check-eq? (factory-language-bundle-find 'org.odra.javascript)
             factory-javascript-language-bundle)
  (check-eq? (factory-language-bundle-find 'org.odra.typescript)
             factory-typescript-language-bundle)
  (check-eq? (factory-language-bundle-find 'org.odra.html)
             factory-html-language-bundle)
  (check-eq? (factory-language-bundle-find 'org.odra.css)
             factory-css-language-bundle)
  (check-false (factory-language-bundle-find 'org.odra.unknown)))
