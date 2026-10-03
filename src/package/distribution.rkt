#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/contract/base
         racket/file
         racket/list
         racket/path
         racket/string
         "../package_catalog/curation-records.rkt"
         "acquisition.rkt"
         "distribution-records.rkt"
         "lifecycle.rkt"
         "manifest-contracts.rkt"
         "resolution.rkt"
         "state-records.rkt")

(provide
 (struct-out odra-package-distribution-failure)
 (struct-out odra-package-distribution-result)
 (contract-out
  [activate-package-distribution!
   (-> odra-package-lifecycle-manager? path-string?
       odra-package-distribution? symbol? symbol?
       odra-package-distribution-result?)]))

(struct odra-package-distribution-failure (package-id code detail)
  #:transparent)

(struct odra-package-distribution-result
  (status activated unchanged failures)
  #:transparent)

(struct prepared-bundled-package
  (declaration manifest candidate archive-path))

(define (file-digest path)
  (call-with-input-file path
    (lambda (input) (bytes->hex-string (sha256-bytes input)))
    #:mode 'binary))

(define (path-below-root? root candidate)
  (define root-parts (explode-path root))
  (define candidate-parts (explode-path candidate))
  (and (<= (length root-parts) (length candidate-parts))
       (equal? root-parts (take candidate-parts (length root-parts)))))

(define (distribution-file root relative-path)
  (define lexical
    (simplify-path
     (path->complete-path (string->path relative-path) root)))
  (and (path-below-root? root lexical)
       (file-exists? lexical)
       (not (link-exists? lexical))
       (let ([resolved (simplify-path lexical #t)])
         (and (path-below-root? root resolved) resolved))))

(define (failure declaration code detail)
  (odra-package-distribution-failure
   (odra-package-release-reference-package-id
    (odra-bundled-package-release declaration))
   code detail))

(define (prepare-bundled-package root distribution declaration platform architecture)
  (define manifest-path
    (distribution-file root (odra-bundled-package-manifest-path declaration)))
  (define archive-path
    (distribution-file root (odra-bundled-package-archive-path declaration)))
  (cond
    [(not manifest-path)
     (failure declaration 'missing-manifest
              "The bundled package manifest is absent or outside the distribution")]
    [(not archive-path)
     (failure declaration 'missing-archive
              "The bundled package archive is absent or outside the distribution")]
    [else
     (define manifest (package-manifest-module-load manifest-path))
     (define release (odra-bundled-package-release declaration))
     (define artifact
       (package-release-artifact release platform architecture))
     (cond
       [(not (odra-package-manifest? manifest))
        (failure declaration 'invalid-manifest
                 "The bundled package manifest is invalid")]
       [(not (package-manifest-api-compatible?
              manifest
              (odra-package-distribution-runtime-api-version distribution)))
        (failure declaration 'incompatible-api
                 "The bundled package is incompatible with the distribution runtime API")]
       [(not artifact)
        (failure declaration 'unsupported-target
                 "The bundled package has no artifact for this target")]
       [(not (= (file-size archive-path)
                (odra-package-artifact-reference-size artifact)))
        (failure declaration 'archive-size
                 "The bundled package archive size differs from the release record")]
       [(not (string=? (file-digest archive-path)
                       (odra-package-artifact-reference-digest artifact)))
        (failure declaration 'archive-digest
                 "The bundled package archive digest differs from the release record")]
       [else
        (define candidate
          (prepare-bundled-package-installation
           manifest release platform architecture
           (odra-package-distribution-id distribution)))
        (if (odra-package-resolution-rejection? candidate)
            (failure declaration 'release-mismatch
                     (format "Bundled release field ~a does not match its manifest"
                             (odra-package-resolution-rejection-field candidate)))
            (prepared-bundled-package
             declaration manifest candidate archive-path))])]))

(define (installed-content-matches? package prepared)
  (define candidate (prepared-bundled-package-candidate prepared))
  (define artifact (odra-package-installation-candidate-artifact candidate))
  (and (string=?
        (odra-installed-package-manifest package)
        (odra-package-installation-candidate-manifest-digest candidate))
       (equal?
        (odra-installed-package-archive package)
        (odra-package-artifact-reference-digest artifact))))

(define (activate-prepared! manager distribution prepared)
  (define declaration (prepared-bundled-package-declaration prepared))
  (define candidate (prepared-bundled-package-candidate prepared))
  (define manifest (prepared-bundled-package-manifest prepared))
  (define release (odra-bundled-package-release declaration))
  (define package-id (odra-package-release-reference-package-id release))
  (define version (odra-package-release-reference-version release))
  (define existing
    (package-state-find (package-lifecycle-state manager) package-id version))
  (cond
    [(and existing (not (installed-content-matches? existing prepared)))
     (failure declaration 'identity-conflict
              "The bundled package identity names different installed content")]
    [else
     (define installed
       (cond
         [existing
          (package-lifecycle-register-manifest! manager manifest)
          existing]
         [else
          (define acquired
            (acquire-package-candidate
             (package-lifecycle-root manager)
             candidate
             #:location-resolver
             (lambda (_location)
               (path->string (prepared-bundled-package-archive-path prepared)))))
          (if (odra-package-acquisition-failure? acquired)
              acquired
              (package-lifecycle-install! manager candidate acquired))]))
     (cond
       [(odra-package-acquisition-failure? installed)
        (failure declaration 'acquisition
                 (odra-package-acquisition-failure-message installed))]
       [(odra-package-lifecycle-result? installed)
        (define package (odra-package-lifecycle-result-package installed))
        (if (not (odra-installed-package? package))
            (failure declaration 'installation
                     (odra-package-lifecycle-result-detail installed))
            (activate-installed! manager distribution declaration package))]
       [else
        (activate-installed! manager distribution declaration installed)])]))

(define (activate-installed! manager distribution declaration package)
  (cond
    [(not (odra-bundled-package-enabled? declaration)) 'unchanged]
    [(eq? (odra-installed-package-lifecycle package) 'active-confirmed) 'unchanged]
    [(eq? (odra-installed-package-lifecycle package) 'installed-disabled)
     (define enabled
       (package-lifecycle-enable!
        manager
        (odra-installed-package-id package)
        (odra-installed-package-version package)
        (format "Bundled by the ~a distribution"
                (odra-package-distribution-id distribution))))
     (if (eq? (odra-package-lifecycle-result-status enabled) 'enabled)
         'activated
         (failure declaration 'activation
                  (odra-package-lifecycle-result-detail enabled)))]
    [else
     (failure declaration 'lifecycle
              "The bundled package is not in an activatable lifecycle state")]))

(define (activate-package-distribution!
         manager distribution-root distribution platform architecture)
  (define root
    (simplify-path (path->complete-path distribution-root) #t))
  (define prepared
    (for/list ([declaration
                (in-list (odra-package-distribution-packages distribution))])
      (prepare-bundled-package
       root distribution declaration platform architecture)))
  (define preflight-failures
    (filter odra-package-distribution-failure? prepared))
  (cond
    [(pair? preflight-failures)
     (odra-package-distribution-result
      'rejected '() '() preflight-failures)]
    [else
     (define activated '())
     (define unchanged '())
     (define failures '())
     (for ([candidate (in-list prepared)])
       (define package-id
         (odra-package-release-reference-package-id
          (odra-bundled-package-release
           (prepared-bundled-package-declaration candidate))))
       (define result (activate-prepared! manager distribution candidate))
       (cond
         [(eq? result 'activated) (set! activated (cons package-id activated))]
         [(eq? result 'unchanged) (set! unchanged (cons package-id unchanged))]
         [else (set! failures (cons result failures))]))
     (odra-package-distribution-result
      (if (null? failures) 'confirmed 'degraded)
      (reverse activated) (reverse unchanged) (reverse failures))]))
