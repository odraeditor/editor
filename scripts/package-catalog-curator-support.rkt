#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/contract/base
         racket/file
         racket/match
         racket/runtime-path
         "../src/package_catalog/contracts.rkt"
         "../src/package_catalog/curation-publication.rkt"
         "../src/package_catalog/integrity.rkt"
         "../src/package_catalog/snapshot-records.rkt"
         "../src/package_catalog/snapshot-verification.rkt"
         "../src/storage/record-codec.rkt"
         "package-catalog-publication-support.rkt")

(provide
 (struct-out odra-package-catalog-offline-signing-request)
 (struct-out odra-package-catalog-curator-workflow-failure)
 (struct-out odra-package-catalog-publication-dry-run)
 (contract-out
  [bootstrap-independent-package-catalog
   (-> path-string? path?)]
  [prepare-package-catalog-root-rotation
   (-> string? string? string? exact-positive-integer?
       odra-package-catalog-offline-signing-request?)]
  [prepare-package-catalog-publisher-rotation
   (-> string? string? string? string? exact-nonnegative-integer?
       odra-package-catalog-offline-signing-request?)]
  [prepare-package-catalog-snapshot-signing
   (-> odra-package-catalog-snapshot? string?
       odra-package-catalog-offline-signing-request?)]
  [package-catalog-offline-signing-request->module-bytes
   (-> odra-package-catalog-offline-signing-request? immutable-bytes?)]
  [write-package-catalog-offline-signing-request
   (-> path-string? odra-package-catalog-offline-signing-request?
       (values path? path?))]
  [load-package-catalog-offline-signing-request
   (-> path-string?
       (or/c odra-package-catalog-offline-signing-request?
             odra-record-diagnostic?))]
  [verify-package-catalog-offline-signature
   (-> odra-package-catalog-offline-signing-request? string? string?
       (or/c #t odra-package-catalog-integrity-failure?))]
  [verify-package-catalog-snapshot-file
   (-> path-string? path-string? exact-nonnegative-integer?
       (or/c #t odra-package-catalog-snapshot-failure? odra-record-diagnostic?))]
  [validate-package-catalog-exact-mirror
   (-> path-string? path-string?
       (or/c #t odra-package-catalog-curator-workflow-failure?
             odra-record-diagnostic?))]
  [dry-run-package-catalog-publication
   (-> path-string? odra-package-catalog-publication-dry-run?)]))

(define current-offline-signing-request-format-version 1)
(define digest-pattern #px"^[0-9a-f]{64}$")
(define signature-pattern #px"^[0-9a-f]{128}$")

(define-runtime-path curator-kit
  "../assets/package-catalog/curator-kit")

(define (digest? value)
  (and (string? value) (regexp-match? digest-pattern value)))

(define (immutable-bytes? value)
  (and (bytes? value) (immutable? value)))

(define (sha256-hex bytes)
  (bytes->hex-string (sha256-bytes (open-input-bytes bytes))))

(struct odra-package-catalog-offline-signing-request
  (format-version purpose catalog-id signing-key-id domain payload message digest)
  #:transparent
  #:guard
  (lambda (format-version purpose catalog-id signing-key-id domain payload message
                          digest _)
    (define expected-message
      (and (list? payload)
           (package-catalog-signature-message domain payload)))
    (unless
        (and (= format-version current-offline-signing-request-format-version)
             (memq purpose '(publisher-rotation root-rotation snapshot))
             (digest? catalog-id)
             (digest? signing-key-id)
             (if (eq? purpose 'snapshot)
                 (string=? domain package-catalog-publisher-signature-domain)
                 (string=? domain package-catalog-root-signature-domain))
             (immutable-bytes? message)
             expected-message
             (bytes=? message expected-message)
             (digest? digest)
             (string=? digest (sha256-hex message)))
      (raise-arguments-error
       'odra-package-catalog-offline-signing-request
       "invalid deterministic offline signing request"))
    (values format-version purpose (string->immutable-string catalog-id)
            (string->immutable-string signing-key-id)
            (string->immutable-string domain) payload message
            (string->immutable-string digest))))

(struct odra-package-catalog-curator-workflow-failure (code field expected actual)
  #:transparent)

(struct odra-package-catalog-publication-dry-run
  (catalog-id sequence snapshot-id assertion-count snapshot-bytes assertion-bytes)
  #:transparent)

(define (make-request purpose catalog-id signing-key-id domain payload)
  (define message (package-catalog-signature-message domain payload))
  (odra-package-catalog-offline-signing-request
   current-offline-signing-request-format-version purpose catalog-id
   signing-key-id domain payload message (sha256-hex message)))

(define (bootstrap-independent-package-catalog target)
  (define destination (path->complete-path target))
  (when (or (file-exists? destination) (directory-exists? destination)
            (link-exists? destination))
    (raise-user-error 'package-catalog-curator
                      "bootstrap target already exists"))
  (copy-directory/files curator-kit destination)
  destination)

(define (prepare-package-catalog-root-rotation
         catalog-id current-root-key-id new-root-public-key generation)
  (define new-key-id (package-catalog-public-key-id new-root-public-key))
  (define new-root
    (odra-package-catalog-root-key
     new-key-id generation 'ed25519 new-root-public-key generation #f))
  (make-request
   'root-rotation catalog-id current-root-key-id
   package-catalog-root-signature-domain
   (list 'package-catalog-root-rotation catalog-id generation
         current-root-key-id
         (list (odra-package-catalog-root-key-id new-root)
               (odra-package-catalog-root-key-generation new-root)
               (odra-package-catalog-root-key-algorithm new-root)
               (odra-package-catalog-root-key-public-key new-root)
               (odra-package-catalog-root-key-valid-from new-root)
               (odra-package-catalog-root-key-valid-until new-root)))))

(define (prepare-package-catalog-publisher-rotation
         catalog-id current-root-key-id authorization-id new-public-key
         effective-from)
  (define new-key-id (package-catalog-public-key-id new-public-key))
  (define key
    (odra-package-catalog-publisher-key new-key-id 'ed25519 new-public-key))
  (make-request
   'publisher-rotation catalog-id current-root-key-id
   package-catalog-root-signature-domain
   (list 'package-catalog-publisher-rotation catalog-id authorization-id
         effective-from
         (list (odra-package-catalog-publisher-key-id key)
               (odra-package-catalog-publisher-key-algorithm key)
               (odra-package-catalog-publisher-key-public-key key)))))

(define (prepare-package-catalog-snapshot-signing snapshot signing-key-id)
  (make-request
   'snapshot
   (odra-package-catalog-snapshot-catalog-id snapshot)
   signing-key-id
   package-catalog-publisher-signature-domain
   (package-catalog-snapshot-signing-payload snapshot)))

(define (request->datum request)
  (list 'package-catalog-offline-signing-request
        '#:format-version
        (odra-package-catalog-offline-signing-request-format-version request)
        '#:purpose
        (odra-package-catalog-offline-signing-request-purpose request)
        '#:catalog-id
        (odra-package-catalog-offline-signing-request-catalog-id request)
        '#:signing-key-id
        (odra-package-catalog-offline-signing-request-signing-key-id request)
        '#:domain
        (odra-package-catalog-offline-signing-request-domain request)
        '#:payload
        (odra-package-catalog-offline-signing-request-payload request)
        '#:message-digest
        (odra-package-catalog-offline-signing-request-digest request)))

(define (package-catalog-offline-signing-request->module-bytes request)
  (record-datum->module-bytes (request->datum request)))

(define (write-package-catalog-offline-signing-request prefix request)
  (define absolute-prefix (path->complete-path prefix))
  (define metadata-path
    (string->path (string-append (path->string absolute-prefix) ".rktd")))
  (define message-path
    (string->path (string-append (path->string absolute-prefix) ".bin")))
  (make-parent-directory* metadata-path)
  (call-with-output-file metadata-path
    (lambda (output)
      (write-bytes
       (package-catalog-offline-signing-request->module-bytes request)
       output))
    #:exists 'error)
  (call-with-output-file message-path
    (lambda (output)
      (write-bytes
       (odra-package-catalog-offline-signing-request-message request)
       output))
    #:exists 'error)
  (values metadata-path message-path))

(define (decode-request datum)
  (match datum
    [(list 'package-catalog-offline-signing-request
           '#:format-version format-version
           '#:purpose purpose
           '#:catalog-id catalog-id
           '#:signing-key-id signing-key-id
           '#:domain domain
           '#:payload payload
           '#:message-digest digest)
     (define message (package-catalog-signature-message domain payload))
     (odra-package-catalog-offline-signing-request
      format-version purpose catalog-id signing-key-id domain payload message
      digest)]
    [_
     (raise-arguments-error 'package-catalog-offline-signing-request
                            "unsupported signing request schema")]))

(define (load-package-catalog-offline-signing-request path)
  (record-module-load path decode-request))

(define (verify-package-catalog-offline-signature request public-key signature)
  (unless (and (string? signature) (regexp-match? signature-pattern signature))
    (raise-argument-error 'verify-package-catalog-offline-signature
                          "128-character lowercase hexadecimal signature"
                          signature))
  (unless
      (string=?
       (package-catalog-public-key-id public-key)
       (odra-package-catalog-offline-signing-request-signing-key-id request))
    (raise-arguments-error 'verify-package-catalog-offline-signature
                           "public key does not match the signing request"))
  (verify-package-catalog-signature
   public-key
   (odra-package-catalog-signature
    'ed25519
    (odra-package-catalog-offline-signing-request-signing-key-id request)
    (odra-package-catalog-offline-signing-request-domain request)
    signature)
   (odra-package-catalog-offline-signing-request-domain request)
   (odra-package-catalog-offline-signing-request-payload request)))

(define (require-export module-path export)
  (dynamic-require (path->complete-path module-path) export))

(define (verify-package-catalog-snapshot-file repository-module snapshot-path now)
  (define snapshot (package-catalog-snapshot-module-load snapshot-path))
  (if (odra-record-diagnostic? snapshot)
      snapshot
      (verify-package-catalog-snapshot
       (require-export repository-module 'profile)
       (require-export repository-module 'publisher-keys)
       (require-export repository-module 'previous-snapshot)
       now
       (odra-package-catalog-snapshot-metadata-size snapshot)
       snapshot)))

(define (validate-package-catalog-exact-mirror origin-path mirror-path)
  (define origin (package-catalog-snapshot-module-load origin-path))
  (cond
    [(odra-record-diagnostic? origin) origin]
    [else
     (define mirror (package-catalog-snapshot-module-load mirror-path))
     (cond
       [(odra-record-diagnostic? mirror) mirror]
       [(not (bytes=? (file->bytes origin-path) (file->bytes mirror-path)))
        (odra-package-catalog-curator-workflow-failure
         'mirror-divergence 'bytes
         (odra-package-catalog-snapshot-id origin)
         (odra-package-catalog-snapshot-id mirror))]
       [(not (equal? origin mirror))
        (odra-package-catalog-curator-workflow-failure
         'mirror-divergence 'snapshot origin mirror)]
       [else #t])]))

(define (dry-run-package-catalog-publication repository-path)
  (define repository
    (load-package-catalog-publication-repository repository-path))
  (define publication
    (validate-package-catalog-publication-repository repository))
  (define snapshot (odra-package-catalog-publication-snapshot publication))
  (odra-package-catalog-publication-dry-run
   (odra-package-catalog-snapshot-catalog-id snapshot)
   (odra-package-catalog-snapshot-sequence snapshot)
   (odra-package-catalog-snapshot-id snapshot)
   (length (odra-package-catalog-publication-assertions publication))
   (odra-package-catalog-publication-snapshot-bytes publication)
   (odra-package-catalog-publication-assertion-set-bytes publication)))
