#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/language_bundle/catalog-contracts.rkt"
         "../../src/language_bundle/catalog-integrity.rkt"
         (submod "../../src/language_bundle/catalog-integrity.rkt" test-support))

(define public-key
  "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
(define secret-key
  (string-append
   "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
   public-key))
(define key-id
  "21fe31dfa154a261626bf854046fd2271b7bed4b6abe45aa58877ef47f9721b9")
(define signing-key (odra-catalog-signing-key key-id 'ed25519 public-key))
(define source
  (odra-catalog-source
   "local-fixture" 'local-file "/tmp/signed-catalog.rktd" 10
   (odra-catalog-refresh-policy 'manual 0 86400)
   (list signing-key) 'offline #f
   (odra-catalog-resource-limits
    maximum-catalog-snapshot-bytes maximum-catalog-entries
    maximum-catalog-artifact-descriptors 60000 0 0)))
(define entry
  (odra-catalog-entry
   "org.example.fixture" "1.0.0" "1.0.0" "2.0.0"
   (list (odra-catalog-target 'linux 'x86-64))
   (make-string 64 #\a) '("manifest.rktd") "Fixture" "Signed local fixture"
   '(language) '() '() 1 1024 #f #f))
(define placeholder-signature
  (odra-catalog-signature
   'ed25519 key-id "odra-language-catalog-v1" (make-string 128 #\0)))

(define unsigned
  (odra-catalog-snapshot
   1 "local-fixture" 1 (make-string 64 #\0)
   (odra-catalog-expiry 10 1000 20)
   (catalog-entries-digest (list entry)) key-id placeholder-signature
   (list entry) 4096))
(define detached
  (odra-catalog-signature
   'ed25519 key-id "odra-language-catalog-v1"
   (sign-for-test (catalog-snapshot-signature-message unsigned) secret-key)))
(define signed-without-digest
  (struct-copy odra-catalog-snapshot unsigned [signature detached]))
(define signed
  (struct-copy odra-catalog-snapshot signed-without-digest
               [snapshot-digest
                (catalog-snapshot-content-digest signed-without-digest)]))

(test-case "signed local catalog verifies against its configured Ed25519 trust root"
  (check-true (verify-catalog-snapshot source signed)))

(test-case "tampered entry bytes reject before signature admission"
  (define tampered-entry
    (struct-copy odra-catalog-entry entry [summary "tampered"]))
  (define tampered
    (struct-copy odra-catalog-snapshot signed [entries (list tampered-entry)]))
  (define failure (verify-catalog-snapshot source tampered))
  (check-true (odra-catalog-integrity-failure? failure))
  (check-eq? (odra-catalog-integrity-failure-code failure) 'entries-digest))

(test-case "tampered detached signature rejects even with a matching snapshot digest"
  (define invalid-signature
    (struct-copy odra-catalog-signature detached
                 [value (string-append "0" (substring
                                             (odra-catalog-signature-value detached) 1))]))
  (define invalid-without-digest
    (struct-copy odra-catalog-snapshot signed [signature invalid-signature]))
  (define invalid
    (struct-copy odra-catalog-snapshot invalid-without-digest
                 [snapshot-digest
                  (catalog-snapshot-content-digest invalid-without-digest)]))
  (define failure (verify-catalog-snapshot source invalid))
  (check-true (odra-catalog-integrity-failure? failure))
  (check-eq? (odra-catalog-integrity-failure-code failure) 'signature))
