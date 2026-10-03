#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/file
         racket/path
         racket/string
         rackunit
         "../../src/language_bundle/acquisition.rkt"
         (submod "../../src/language_bundle/acquisition.rkt" test-support)
         "../../src/package/acquisition.rkt"
         "../../src/package/credential-provider.rkt"
         "../../src/package/manifest-contracts.rkt"
         "../../src/package/resolution.rkt"
         "../../src/package/state-records.rkt"
         "../../src/package_catalog/curation-records.rkt")

(define (digest character) (make-string 64 character))
(define (sha256 value)
  (bytes->hex-string (sha256-bytes (open-input-bytes value))))

(define (put-field! target offset value)
  (bytes-copy! target offset value))

(define (octal-field value width)
  (define digits (number->string value 8))
  (bytes-append
   (string->bytes/utf-8
    (string-append (make-string (- width 1 (string-length digits)) #\0) digits))
   #"\0"))

(define (tar-member path content [type #\0])
  (define header (make-bytes 512 0))
  (put-field! header 0 (string->bytes/utf-8 path))
  (put-field! header 100 #"0000600\0")
  (put-field! header 108 #"0000000\0")
  (put-field! header 116 #"0000000\0")
  (put-field! header 124 (octal-field (bytes-length content) 12))
  (put-field! header 136 (octal-field 0 12))
  (put-field! header 148 #"        ")
  (bytes-set! header 156 (char->integer type))
  (put-field! header 257 #"ustar\0")
  (put-field! header 263 #"00")
  (define checksum (for/sum ([byte (in-bytes header)]) byte))
  (define digits (number->string checksum 8))
  (put-field!
   header 148
   (bytes-append
    (string->bytes/utf-8
     (string-append (make-string (- 6 (string-length digits)) #\0) digits))
    #"\0 "))
  (define padding (modulo (- 512 (modulo (bytes-length content) 512)) 512))
  (bytes-append header content (make-bytes padding 0)))

(define module-bytes #"#lang racket/base\n(provide odra-package-contributions)\n")
(define module-digest (sha256 module-bytes))
(define-values (manifest manifest-rejection)
  (confirm-package-manifest
   (odra-package-manifest-proposal
    1 "odra.failure" 'extension "Failure Fixture" "1.0.0" "" "MIT" #f
    "odra.publisher" (make-string 40 #\a) "1.0.0" "2.0.0"
    (list (odra-package-target 'linux 'x86-64)) '() '(racket-extension)
    (list
     (odra-package-artifact
      "entrypoint" 'racket-module "main.rkt" module-digest
      (bytes-length module-bytes) #f #f 'racket-extension '()))
    (odra-package-entrypoint "main.rkt" 'odra-package-contributions)
    (list (odra-package-contribution
           "failure-command" 'command '(active-buffer) '(buffer)))
    '() (odra-package-state-compatibility #f #f #f 'none))))
(check-false manifest-rejection)
(define manifest-bytes (package-manifest->canonical-bytes manifest))
(define valid-archive
  (bytes-append
   (tar-member "odra-package.rktd" manifest-bytes)
   (tar-member "main.rkt" module-bytes)
   (make-bytes 1024 0)))

(define (candidate archive [archive-digest (sha256 archive)]
                   [archive-size (bytes-length archive)]
                   [location "https://packages.example/failure.tar.zst"])
  (define reference
    (odra-package-artifact-reference
     'linux 'x86-64 (list location)
     archive-digest archive-size "odra-builder" #f 'reproduced))
  (define release
    (odra-package-release-reference
     1 "odra.failure" (digest #\b) "1.0.0" "odra.publisher"
     "https://forge.example/odra/failure" (make-string 40 #\a) #f
     (package-manifest-digest manifest) (list reference)
     (digest #\c) (digest #\d) (digest #\e) (digest #\f)))
  (odra-package-installation-candidate
   manifest (package-manifest-digest manifest) release reference
   (odra-package-provenance
    'catalog (digest #\1) (digest #\2) (digest #\3)
    "odra.publisher" (make-string 40 #\a))
   'admitted))

(define (raw-open path)
  (values (open-input-file path #:mode 'binary) (lambda (_) #t)))

(define (acquire root archive candidate-value #:cancelled? [cancelled? (lambda () #f)])
  (parameterize
      ([current-acquisition-transport-open
        (lambda (_)
          (acquisition-response 200 (hash) (open-input-bytes archive)))]
       [current-acquisition-archive-open raw-open])
    (acquire-package-candidate root candidate-value #:cancelled? cancelled?)))

(define (with-root action)
  (define root (make-temporary-file "package-acquisition-failure-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind void (lambda () (action root))
                (lambda () (delete-directory/files root))))

(test-case "generic acquisition cancellation cleans private staging"
  (with-root
   (lambda (root)
     (define result
       (acquire root valid-archive (candidate valid-archive)
                #:cancelled? (lambda () #t)))
     (check-true (odra-package-acquisition-failure? result))
     (check-eq? (odra-package-acquisition-failure-code result) 'cancelled)
     (check-false
      (directory-exists?
       (build-path root "packages" "staging" "odra.failure-1.0.0"))))))

(test-case "private artifact authentication follows only same-origin redirects"
  (with-root
   (lambda (root)
     (define provider
       (make-package-credential-provider
        #:id "test-provider" #:generation 3
        #:lookup
        (lambda (_)
          (make-package-credential
           #:headers (hash "authorization" "Bearer package-private")))))
     (define binding
       (package-artifact-credential-binding
        #:endpoint-id "package-origin"
        #:origin "https://packages.example"
        #:credential-reference "package.private"
        #:provider-id "test-provider"
        #:provider-generation 3))
     (define requests '())
     (define result
       (parameterize
           ([current-acquisition-transport-open
             (lambda (location headers)
               (check-equal?
                (hash-ref headers "authorization") "Bearer package-private")
               (set! requests (cons location requests))
               (if (string-suffix? location "failure.tar.zst")
                   (acquisition-response
                    302
                    (hash "location"
                          "https://packages.example/private/archive.tar.zst")
                    (open-input-bytes #""))
                   (acquisition-response
                    200 (hash) (open-input-bytes valid-archive))))]
            [current-acquisition-archive-open raw-open])
         (acquire-package-candidate
          root (candidate valid-archive)
          #:credential-provider provider
          #:credential-bindings (list binding))))
     (check-true (odra-package-acquisition? result))
     (check-equal?
      (reverse requests)
      '("https://packages.example/failure.tar.zst"
        "https://packages.example/private/archive.tar.zst")))))

(test-case "private artifact credentials reject cross-origin redirects"
  (with-root
   (lambda (root)
     (define provider
       (make-package-credential-provider
        #:id "test-provider" #:generation 3
        #:lookup
        (lambda (_)
          (make-package-credential
           #:headers (hash "authorization" "Bearer redirect-secret")))))
     (define binding
       (package-artifact-credential-binding
        #:endpoint-id "package-origin"
        #:origin "https://packages.example"
        #:credential-reference "package.private"
        #:provider-id "test-provider"
        #:provider-generation 3))
     (define result
       (parameterize
           ([current-acquisition-transport-open
             (lambda (_location _headers)
               (acquisition-response
                302
                (hash "location" "https://other.example/archive.tar.zst")
                (open-input-bytes #"")))]
            [current-acquisition-archive-open raw-open])
         (acquire-package-candidate
          root (candidate valid-archive)
          #:credential-provider provider
          #:credential-bindings (list binding)
          #:retry-limit 0)))
     (check-eq? (odra-package-acquisition-failure-code result) 'redirect)
     (check-false (regexp-match? #px"redirect-secret" (format "~s" result))))))

(test-case "missing private artifact credentials fail before transport"
  (with-root
   (lambda (root)
     (define provider
       (make-package-credential-provider
        #:id "test-provider" #:generation 3 #:lookup (lambda (_) #f)))
     (define binding
       (package-artifact-credential-binding
        #:endpoint-id "package-origin"
        #:origin "https://packages.example"
        #:credential-reference "package.private"
        #:provider-id "test-provider"
        #:provider-generation 3))
     (define opened? #f)
     (define result
       (parameterize
           ([current-acquisition-transport-open
             (lambda (_location _headers)
               (set! opened? #t)
               (acquisition-response
                200 (hash) (open-input-bytes valid-archive)))]
            [current-acquisition-archive-open raw-open])
         (acquire-package-candidate
          root (candidate valid-archive)
          #:credential-provider provider
          #:credential-bindings (list binding)
          #:retry-limit 0)))
     (check-eq? (odra-package-acquisition-failure-code result) 'credential)
     (check-false opened?))))

(test-case "archive digest and byte ceilings reject before extraction"
  (with-root
   (lambda (root)
     (define digest-result
       (acquire root valid-archive (candidate valid-archive (digest #\9))))
     (check-eq? (odra-package-acquisition-failure-code digest-result) 'digest)))
  (with-root
   (lambda (root)
     (define size-result
       (acquire root valid-archive
                (candidate valid-archive (sha256 valid-archive)
                           (sub1 (bytes-length valid-archive)))))
     (check-eq? (odra-package-acquisition-failure-code size-result) 'limit))))

(test-case "archive traversal rejects before immutable publication"
  (with-root
   (lambda (root)
     (define traversal
       (bytes-append
        (tar-member "../escape" manifest-bytes)
        (tar-member "main.rkt" module-bytes)
        (make-bytes 1024 0)))
     (define result (acquire root traversal (candidate traversal)))
     (check-eq? (odra-package-acquisition-failure-code result) 'archive-path)
     (check-false (file-exists? (build-path root "escape"))))))

(test-case "immutable content collisions reject without replacement"
  (with-root
   (lambda (root)
     (define selected (candidate valid-archive))
     (define manifest-path
       (package-content-path root (package-manifest-digest manifest)))
     (make-parent-directory* manifest-path)
     (for ([directory
            (in-list
             (list (build-path root "packages")
                   (build-path root "packages" "content")
                   (build-path root "packages" "content" "sha256")
                   (path-only manifest-path)))])
       (file-or-directory-permissions directory #o700))
     (call-with-output-file manifest-path
       (lambda (output)
         (write-bytes (make-bytes (bytes-length manifest-bytes) 88) output))
       #:mode 'binary #:permissions #o600)
     (define result (acquire root valid-archive selected))
     (check-eq? (odra-package-acquisition-failure-code result) 'publication)
     (check-not-equal? (file->bytes manifest-path) manifest-bytes))))
