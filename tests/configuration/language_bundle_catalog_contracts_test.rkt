#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/language_bundle/catalog-contracts.rkt")

(define digest-a (make-string 64 #\a))
(define digest-b (make-string 64 #\b))
(define digest-c (make-string 64 #\c))
(define signature-a (make-string 128 #\a))
(define public-key
  "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
(define key-id
  "21fe31dfa154a261626bf854046fd2271b7bed4b6abe45aa58877ef47f9721b9")
(define signing-key (odra-catalog-signing-key key-id 'ed25519 public-key))
(define linux-x86 (odra-catalog-target 'linux 'x86-64))
(define policy (odra-catalog-refresh-policy 'interval 3600 86400))
(define limits
  (odra-catalog-resource-limits
   maximum-catalog-snapshot-bytes maximum-catalog-entries
   maximum-catalog-artifact-descriptors 60000 4 2))
(define signature
  (odra-catalog-signature
   'ed25519 key-id "odra-language-catalog-v1" signature-a))
(define expiry (odra-catalog-expiry 100 200 120))
(define dependency
  (odra-catalog-dependency-summary
   "org.example.runtime" "1.0.0" "2.0.0" #f '(language)))
(define entry
  (odra-catalog-entry
   "org.example.language" "1.0.0" "1.0.0" "2.0.0"
   (list linux-x86) digest-b '("manifests/language.rktd")
   "Example Language" "Example catalog fixture"
   '(language syntax-provider) '(native-grammar) (list dependency)
   3 4096 #f #f))

(test-case "local catalog source is offline and contains no credential"
  (define source
    (odra-catalog-source
     "local-fixture" 'local-file "/tmp/catalog.rktd" 10 policy
     (list signing-key) 'offline #f limits))
  (check-eq? (odra-catalog-source-transport source) 'local-file)
  (check-false (odra-catalog-source-credential-reference source))
  (check-true (immutable? (odra-catalog-source-endpoint source)))
  (check-exn
   exn:fail?
   (lambda ()
     (odra-catalog-source
      "local-fixture" 'local-file "/tmp/catalog.rktd" 10 policy
      (list signing-key) 'direct #f limits))))

(test-case "HTTPS source admits only a bounded credential reference"
  (define credential
    (odra-catalog-credential-reference 'secret-service "language-catalog"))
  (define source
    (odra-catalog-source
     "public-catalog" 'https "https://catalog.example/odra/index.rktd"
     20 policy (list signing-key) 'direct credential limits))
  (check-equal? (odra-catalog-source-credential-reference source) credential)
  (for ([endpoint
         '("http://catalog.example/index.rktd"
           "https://user:secret@catalog.example/index.rktd"
           "https://catalog.example/index.rktd?token=secret")])
    (check-exn
     exn:fail?
     (lambda ()
       (odra-catalog-source
        "public-catalog" 'https endpoint 20 policy
        (list signing-key) 'direct credential limits)))))

(test-case "catalog resource limits cannot raise native maxima"
  (check-equal? (odra-catalog-resource-limits-entries limits)
                maximum-catalog-entries)
  (check-exn
   exn:fail?
   (lambda ()
     (odra-catalog-resource-limits
      (add1 maximum-catalog-snapshot-bytes) maximum-catalog-entries
      maximum-catalog-artifact-descriptors 60000 4 2))))

(test-case "catalog entries retain exact targets and dependency summaries"
  (check-equal? (odra-catalog-entry-targets entry) (list linux-x86))
  (check-equal? (odra-catalog-entry-dependencies entry) (list dependency))
  (check-exn
   exn:fail?
   (lambda ()
     (struct-copy odra-catalog-entry entry
                  [dependencies
                   (list
                    (odra-catalog-dependency-summary
                     "org.example.language" "1.0.0" "2.0.0" #f '(language)))]))))

(test-case "signed snapshot binds source, digest, key, expiry, and canonical entries"
  (define snapshot
    (odra-catalog-snapshot
     1 "public-catalog" 9 digest-c expiry digest-c key-id signature
     (list entry) 4096))
  (check-equal? (odra-catalog-snapshot-entries snapshot) (list entry))
  (check-exn
   exn:fail?
   (lambda ()
     (struct-copy odra-catalog-snapshot snapshot [signing-key-id digest-b]))))

(test-case "expiry is deterministic at both boundaries"
  (check-eq? (catalog-expiry-status expiry 99) 'not-yet-valid)
  (check-eq? (catalog-expiry-status expiry 100) 'fresh)
  (check-eq? (catalog-expiry-status expiry 200) 'fresh)
  (check-eq? (catalog-expiry-status expiry 201) 'expired))

(test-case "cache record retains confirmed and predecessor snapshot identities"
  (define cache
    (odra-catalog-cache-record
     1 "public-catalog" 3 digest-c digest-b
     "/tmp/odra/catalog/snapshot.rktd" "/tmp/odra/catalog/index.rktd"
     expiry ""))
  (check-equal? (odra-catalog-cache-record-confirmed-snapshot-digest cache)
                digest-c)
  (check-exn
   exn:fail?
   (lambda ()
     (struct-copy odra-catalog-cache-record cache
                  [previous-snapshot-digest digest-c]))))

(test-case "search index is a canonical rebuildable projection"
  (define index-entry
    (odra-catalog-index-entry
     "org.example.language" "1.0.0" "Example Language"
     '("example") '(language syntax-provider) (list linux-x86)))
  (define index (odra-catalog-search-index digest-c (list index-entry)))
  (check-equal? (odra-catalog-search-index-entries index) (list index-entry))
  (check-exn
   exn:fail?
   (lambda ()
     (odra-catalog-search-index digest-c (list index-entry index-entry)))))
