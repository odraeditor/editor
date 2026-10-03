#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         net/url
         "../language_bundle/acquisition.rkt"
         "../language_bundle/advisory-response.rkt"
         "../package_catalog/curation-records.rkt"
         "../package_catalog/curation-resolution.rkt"
         "credential-provider.rkt"
         "manifest-contracts.rkt"
         "resolution.rkt")

(provide
 (struct-out odra-package-content-handle)
 (struct-out odra-package-acquisition)
 (struct-out odra-package-acquisition-failure)
 (struct-out odra-package-installation-acquisition-failure)
 (contract-out
  [package-content-path (-> path-string? string? path?)]
  [acquire-package-candidate
   (->* (path-string? odra-package-installation-candidate?)
        (#:offline? boolean?
         #:location-resolver procedure?
         #:credential-provider odra-package-credential-provider?
         #:credential-bindings (listof odra-package-artifact-credential-binding?)
         #:advisory-evaluator procedure?
         #:cancelled? procedure?
         #:deadline-milliseconds exact-positive-integer?
         #:redirect-limit exact-nonnegative-integer?
         #:retry-limit exact-nonnegative-integer?)
        (or/c odra-package-acquisition? odra-package-acquisition-failure?))]
  [acquire-curated-package-resolution
   (->* (path-string? odra-package-resolution?)
        (#:offline? boolean?
         #:location-resolver procedure?
         #:credential-provider odra-package-credential-provider?
         #:credential-bindings (listof odra-package-artifact-credential-binding?))
        (or/c (list/c odra-package-installation-candidate?
                      odra-package-acquisition?)
              odra-package-installation-acquisition-failure?))]))

(define digest-pattern #px"^[0-9a-f]{64}$")

(define (digest? value)
  (and (string? value) (regexp-match? digest-pattern value)))

(define (copied value)
  (if (string? value) (string->immutable-string value) value))

(struct odra-package-content-handle (path digest size kind executable?)
  #:transparent
  #:guard
  (lambda (path digest size kind executable? _)
    (unless (and (path-string? path) (absolute-path? path)
                 (digest? digest) (exact-nonnegative-integer? size)
                 (symbol? kind) (boolean? executable?))
      (raise-arguments-error 'odra-package-content-handle
                             "invalid immutable package content handle"))
    (values (copied path) (copied digest) size kind executable?)))

(struct odra-package-acquisition
  (package-id version manifest-digest archive-digest archive-path content
              downloaded-bytes offline? reused-digests)
  #:transparent)

(struct odra-package-acquisition-failure (code message location)
  #:transparent)

(struct odra-package-installation-acquisition-failure (code detail)
  #:transparent)

(define (package-content-path root digest)
  (unless (digest? digest)
    (raise-argument-error 'package-content-path "SHA-256 digest" digest))
  (build-path (path->complete-path root) "packages" "content" "sha256"
              (substring digest 0 2) digest))

(define (target-artifact? artifact platform architecture)
  (define target (odra-package-artifact-target artifact))
  (or (not target)
      (and (eq? platform (odra-package-target-platform target))
           (eq? architecture (odra-package-target-architecture target)))))

(define (candidate-request candidate location-resolver)
  (define manifest (odra-package-installation-candidate-manifest candidate))
  (define release (odra-package-installation-candidate-release candidate))
  (define archive (odra-package-installation-candidate-artifact candidate))
  (define platform (odra-package-artifact-reference-platform archive))
  (define architecture (odra-package-artifact-reference-architecture archive))
  (define members
    (cons
     (odra-bundle-archive-member
      "odra-package.rktd"
      (odra-package-installation-candidate-manifest-digest candidate)
      (bytes-length (package-manifest->canonical-bytes manifest))
      'manifest #f)
     (for/list ([artifact (in-list (odra-package-manifest-artifacts manifest))]
                #:when (target-artifact? artifact platform architecture))
       (odra-bundle-archive-member
        (odra-package-artifact-path artifact)
        (odra-package-artifact-digest artifact)
        (odra-package-artifact-size artifact)
        (odra-package-artifact-kind artifact)
        (odra-package-artifact-executable? artifact)))))
  (odra-bundle-archive-request
   (format "~a-~a"
           (odra-package-release-reference-package-id release)
           (odra-package-release-reference-version release))
   (sort
    (remove-duplicates
     (map location-resolver
          (odra-package-artifact-reference-uri-set archive))
     string=?)
    string<?)
   (odra-package-artifact-reference-digest archive)
   (odra-package-artifact-reference-size archive)
   members
   (length members)
   (for/sum ([member (in-list members)])
     (odra-bundle-archive-member-size member))))

(define (https-origin location)
  (and (regexp-match? #px"^https://" location)
       (let ([parsed (string->url location)])
         (format "https://~a~a"
                 (string-downcase (url-host parsed))
                 (if (url-port parsed)
                     (format ":~a" (url-port parsed))
                     "")))))

(define (binding-for-location bindings location)
  (define origin (https-origin location))
  (and origin
       (for/first
           ([binding (in-list bindings)]
            #:when
            (and (odra-package-artifact-credential-binding-enabled? binding)
                 (string=?
                  origin
                  (string-downcase
                   (odra-package-artifact-credential-binding-origin binding)))))
         binding)))

(define (credential-request-headers provider bindings location)
  (define binding (binding-for-location bindings location))
  (cond
    [(not binding) (hash)]
    [(or
      (not
       (string=?
        (odra-package-artifact-credential-binding-provider-id binding)
        (odra-package-credential-provider-id provider)))
      (not
       (=
        (odra-package-artifact-credential-binding-provider-generation binding)
        (odra-package-credential-provider-generation provider))))
     #f]
    [else
     (define resolved
       (resolve-package-credential
        provider
        (odra-package-artifact-credential-binding-credential-reference binding)))
     (and
      (odra-package-credential-resolution? resolved)
      (let ([headers (package-credential-resolution-headers resolved)]
            [policy
             (odra-package-artifact-credential-binding-header-policy binding)])
        (and
         (for/and ([name (in-hash-keys headers)])
           (member (string-downcase name) policy string=?))
         headers)))]))

(define (acquire-package-candidate
         root candidate
         #:offline? [offline? #f]
         #:location-resolver [location-resolver values]
         #:credential-provider
         [credential-provider (current-package-credential-provider)]
         #:credential-bindings [credential-bindings '()]
         #:advisory-evaluator
         [advisory-evaluator
          (lambda (_phase _package-id _release-id _artifact-digests
                          _installed? _active?)
            (odra-security-advisory-response '() '() '()))]
         #:cancelled? [cancelled? (lambda () #f)]
         #:deadline-milliseconds [deadline-milliseconds 60000]
         #:redirect-limit [redirect-limit 4]
         #:retry-limit [retry-limit 2])
  (define request (candidate-request candidate location-resolver))
  (define acquired
    (acquire-language-bundle
     root request
     #:offline? offline?
     #:storage-directory "packages"
     #:request-headers
     (lambda (location)
       (credential-request-headers
        credential-provider credential-bindings location))
     #:advisory-evaluator advisory-evaluator
     #:cancelled? cancelled?
     #:deadline-milliseconds deadline-milliseconds
     #:redirect-limit redirect-limit
     #:retry-limit retry-limit))
  (cond
    [(odra-bundle-acquisition-failure? acquired)
     (odra-package-acquisition-failure
      (odra-bundle-acquisition-failure-code acquired)
      (odra-bundle-acquisition-failure-message acquired)
      (odra-bundle-acquisition-failure-location acquired))]
    [else
     (define release (odra-package-installation-candidate-release candidate))
     (define archive (odra-package-installation-candidate-artifact candidate))
     (odra-package-acquisition
      (odra-package-release-reference-package-id release)
      (odra-package-release-reference-version release)
      (odra-package-installation-candidate-manifest-digest candidate)
      (odra-package-artifact-reference-digest archive)
      (odra-bundle-acquisition-archive-path acquired)
      (for/list ([handle (in-list (odra-bundle-acquisition-content acquired))])
        (odra-package-content-handle
         (odra-bundle-content-handle-path handle)
         (odra-bundle-content-handle-digest handle)
         (odra-bundle-content-handle-size handle)
         (odra-bundle-content-handle-kind handle)
         (odra-bundle-content-handle-executable? handle)))
      (odra-bundle-acquisition-downloaded-bytes acquired)
      (odra-bundle-acquisition-offline? acquired)
      (odra-bundle-acquisition-reused-digests acquired))]))

(define (installation-acquisition-failure code detail)
  (odra-package-installation-acquisition-failure code detail))

(define (acquire-curated-package-resolution
         root resolution
         #:offline? [offline? #f]
         #:location-resolver [location-resolver values]
         #:credential-provider
         [credential-provider (current-package-credential-provider)]
         #:credential-bindings [credential-bindings '()])
  (define release (odra-package-resolution-release resolution))
  (define artifact (odra-package-resolution-artifact resolution))
  (define package-id (odra-package-release-reference-package-id release))
  (define version (odra-package-release-reference-version release))
  (define locations
    (sort
     (remove-duplicates
      (map location-resolver
           (odra-package-artifact-reference-uri-set artifact))
      string=?)
     string<?))
  (define bootstrapped
    (acquire-language-bundle-bootstrap-member
     root (format "~a.~a.bootstrap" package-id version)
     locations
     (odra-package-artifact-reference-digest artifact)
     (odra-package-artifact-reference-size artifact)
     "odra-package.rktd"
     (odra-package-release-reference-manifest-digest release)
     #:offline? offline?
     #:storage-directory "packages"
     #:request-headers
     (lambda (location)
       (credential-request-headers
        credential-provider credential-bindings location))))
  (cond
    [(odra-bundle-acquisition-failure? bootstrapped)
     (installation-acquisition-failure
      (odra-bundle-acquisition-failure-code bootstrapped)
      (odra-bundle-acquisition-failure-message bootstrapped))]
    [else
     (define manifest
       (package-manifest-module-load
        (odra-bundle-content-handle-path
         (odra-bundle-bootstrap-acquisition-member bootstrapped))))
     (cond
       [(not (odra-package-manifest? manifest))
        (installation-acquisition-failure
         'manifest "The package manifest is invalid")]
       [else
        (define candidate
          (prepare-curated-package-installation
           manifest resolution
           (odra-package-artifact-reference-platform artifact)
           (odra-package-artifact-reference-architecture artifact)))
        (cond
          [(odra-package-resolution-rejection? candidate)
           (installation-acquisition-failure
            (odra-package-resolution-rejection-code candidate)
            (format "The package manifest conflicts with catalog field ~a"
                    (odra-package-resolution-rejection-field candidate)))]
          [else
           (define acquired
             (acquire-package-candidate
              root candidate
              #:offline? offline?
              #:location-resolver location-resolver
              #:credential-provider credential-provider
              #:credential-bindings credential-bindings))
           (if (odra-package-acquisition-failure? acquired)
               (installation-acquisition-failure
                (odra-package-acquisition-failure-code acquired)
                (odra-package-acquisition-failure-message acquired))
               (list candidate acquired))])])]))
