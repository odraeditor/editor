#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         rackunit
         "../../src/language_bundle/catalog-contracts.rkt"
         "../../src/language_bundle/catalog-integrity.rkt"
         "../../src/language_bundle/catalog-resolution.rkt"
         (submod "../../src/language_bundle/catalog-integrity.rkt" test-support))

(define (digest character) (make-string 64 character))
(define public-key
  "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
(define key-digest
  "21fe31dfa154a261626bf854046fd2271b7bed4b6abe45aa58877ef47f9721b9")
(define signing-key (odra-catalog-signing-key key-digest 'ed25519 public-key))
(define secret-key
  (string-append
   "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
   public-key))
(define signature-value (make-string 128 #\b))
(define policy (odra-catalog-refresh-policy 'manual 0 86400))
(define limits
  (odra-catalog-resource-limits
   maximum-catalog-snapshot-bytes maximum-catalog-entries
   maximum-catalog-artifact-descriptors 60000 4 2))
(define signature
  (odra-catalog-signature
   'ed25519 key-digest "odra-language-catalog-v1" signature-value))
(define fresh-expiry (odra-catalog-expiry 10 1000 20))

(define (make-source id precedence)
  (odra-catalog-source
   id 'https (format "https://~a.example/catalog.rktd" id)
   precedence policy (list signing-key) 'direct #f limits))

(define (make-dependency id minimum maximum #:optional? [optional? #f])
  (odra-catalog-dependency-summary
   id minimum maximum optional? '(language)))

(define (make-entry id version manifest
                    #:dependencies [dependencies '()]
                    #:authorities [authorities '()]
                    #:replacement [replacement #f]
                    #:platform [platform 'linux]
                    #:architecture [architecture 'x86-64])
  (odra-catalog-entry
   id version "1.0.0" "2.0.0"
   (list (odra-catalog-target platform architecture))
   manifest (list (format "manifests/~a-~a.rktd" id version))
   id "" '(language) authorities dependencies 1 1024 #f replacement))

(define (make-snapshot source-id sequence _snapshot-digest entries
                       #:expiry [expiry fresh-expiry])
  (define ordered
    (sort entries string<?
          #:key (lambda (entry)
                  (format "~a@~a" (odra-catalog-entry-bundle-id entry)
                          (odra-catalog-entry-version entry)))))
  (define unsigned
    (odra-catalog-snapshot
     1 source-id sequence (make-string 64 #\0) expiry
     (catalog-entries-digest ordered) key-digest signature ordered 4096))
  (define detached
    (odra-catalog-signature
     'ed25519 key-digest "odra-language-catalog-v1"
     (sign-for-test (catalog-snapshot-signature-message unsigned) secret-key)))
  (define signed
    (struct-copy odra-catalog-snapshot unsigned [signature detached]))
  (struct-copy odra-catalog-snapshot signed
               [snapshot-digest (catalog-snapshot-content-digest signed)]))

(define (request id [minimum "0.0.0"] [maximum "99.0.0"])
  (odra-catalog-resolution-request id minimum maximum '(language)))

(define (resolve sources snapshots requests
                 #:granted [granted '()]
                 #:replacements [replacements (hash)])
  (resolve-catalog-candidates
   sources snapshots requests 'linux 'x86-64 "1.0.0" 100
   #:granted-authorities granted
   #:replacement-policy replacements))

(test-case "source precedence and resolution are independent from input order"
  (define primary (make-source "primary" 20))
  (define secondary (make-source "secondary" 10))
  (define primary-snapshot
    (make-snapshot "primary" 1 (digest #\1)
                   (list (make-entry "org.example.app" "1.0.0" (digest #\2)))))
  (define secondary-snapshot
    (make-snapshot "secondary" 1 (digest #\3)
                   (list (make-entry "org.example.app" "2.0.0" (digest #\4)))))
  (define expected
    (resolve (list primary secondary)
             (list primary-snapshot secondary-snapshot)
             (list (request "org.example.app"))))
  (check-true (odra-catalog-resolution? expected))
  (check-equal? (odra-catalog-resolved-bundle-version
                 (car (odra-catalog-resolution-bundles expected)))
                "1.0.0")
  (check-equal? (odra-catalog-resolution-snapshot-digests expected)
                (list (odra-catalog-snapshot-snapshot-digest primary-snapshot)))
  (check-equal?
   (resolve (reverse (list primary secondary))
            (reverse (list primary-snapshot secondary-snapshot))
            (list (request "org.example.app")))
   expected))

(test-case "highest compatible semantic version wins within one source"
  (define source (make-source "primary" 10))
  (define snapshot
    (make-snapshot
     "primary" 1 (digest #\1)
     (list (make-entry "org.example.app" "1.9.0" (digest #\2))
           (make-entry "org.example.app" "2.0.0-rc.1" (digest #\3))
           (make-entry "org.example.app" "2.0.0" (digest #\4)))))
  (define result
    (resolve (list source) (list snapshot)
             (list (request "org.example.app" "1.0.0" "2.0.0"))))
  (check-equal? (odra-catalog-resolved-bundle-version
                 (car (odra-catalog-resolution-bundles result)))
                "2.0.0"))

(test-case "required dependencies precede consumers and optional absence is inert"
  (define source (make-source "primary" 10))
  (define app
    (make-entry
     "org.example.app" "1.0.0" (digest #\2)
     #:dependencies
     (list (make-dependency "org.example.optional" "1.0.0" "1.0.0"
                            #:optional? #t)
           (make-dependency "org.example.runtime" "1.0.0" "2.0.0"))))
  (define runtime
    (make-entry "org.example.runtime" "1.5.0" (digest #\3)))
  (define result
    (resolve (list source)
             (list (make-snapshot "primary" 1 (digest #\1)
                                  (list app runtime)))
             (list (request "org.example.app"))))
  (check-true (odra-catalog-resolution? result))
  (check-equal? (odra-catalog-resolution-activation-order result)
                '("org.example.runtime" "org.example.app"))
  (check-equal? (odra-catalog-resolved-bundle-dependencies
                 (second (odra-catalog-resolution-bundles result)))
                '("org.example.runtime@1.5.0")))

(test-case "platform and architecture are exact candidate constraints"
  (define source (make-source "primary" 10))
  (define snapshot
    (make-snapshot
     "primary" 1 (digest #\1)
     (list (make-entry "org.example.app" "1.0.0" (digest #\2)
                       #:platform 'windows))))
  (define result
    (resolve (list source) (list snapshot) (list (request "org.example.app"))))
  (check-true (odra-catalog-resolution-failure? result))
  (check-eq? (odra-catalog-resolution-failure-code result) 'no-candidate))

(test-case "equal-precedence manifest disagreement rejects symmetrically"
  (define first (make-source "first" 10))
  (define second (make-source "second" 10))
  (define first-snapshot
    (make-snapshot "first" 1 (digest #\1)
                   (list (make-entry "org.example.app" "1.0.0" (digest #\2)))))
  (define second-snapshot
    (make-snapshot "second" 1 (digest #\3)
                   (list (make-entry "org.example.app" "1.0.0" (digest #\4)))))
  (for ([sources (in-list (list (list first second) (list second first)))]
        [snapshots
         (in-list (list (list first-snapshot second-snapshot)
                        (list second-snapshot first-snapshot)))])
    (define result
      (resolve sources snapshots (list (request "org.example.app"))))
    (check-true (odra-catalog-resolution-failure? result))
    (check-eq? (odra-catalog-resolution-failure-code result)
               'catalog-conflict)))

(test-case "authority delta excludes already granted authorities"
  (define source (make-source "primary" 10))
  (define snapshot
    (make-snapshot
     "primary" 1 (digest #\1)
     (list (make-entry "org.example.app" "1.0.0" (digest #\2)
                       #:authorities '(native-grammar project-read)))))
  (define result
    (resolve (list source) (list snapshot)
             (list (request "org.example.app"))
             #:granted '(project-read)))
  (check-equal? (odra-catalog-resolution-authority-delta result)
                '(native-grammar)))

(test-case "replacement requires manifest declaration and matching user policy"
  (define source (make-source "primary" 10))
  (define snapshot
    (make-snapshot
     "primary" 1 (digest #\1)
     (list (make-entry "org.example.new" "1.0.0" (digest #\2)
                       #:replacement "org.example.old")
           (make-entry "org.example.old" "1.0.0" (digest #\3)))))
  (define requests
    (list (request "org.example.new") (request "org.example.old")))
  (define denied (resolve (list source) (list snapshot) requests))
  (check-eq? (odra-catalog-resolution-failure-code denied) 'replacement-denied)
  (define admitted
    (resolve (list source) (list snapshot) requests
             #:replacements (hash "org.example.new" '("org.example.old"))))
  (check-true (odra-catalog-resolution? admitted))
  (check-equal? (odra-catalog-resolution-activation-order admitted)
                '("org.example.new"))
  (check-equal? (odra-catalog-resolution-replacements admitted)
                (list (odra-catalog-replacement
                       "org.example.new" "org.example.old"))))

(test-case "required dependency cycles reject the complete candidate graph"
  (define source (make-source "primary" 10))
  (define first
    (make-entry "org.example.a" "1.0.0" (digest #\2)
                #:dependencies
                (list (make-dependency "org.example.b" "1.0.0" "1.0.0"))))
  (define second
    (make-entry "org.example.b" "1.0.0" (digest #\3)
                #:dependencies
                (list (make-dependency "org.example.a" "1.0.0" "1.0.0"))))
  (define result
    (resolve (list source)
             (list (make-snapshot "primary" 1 (digest #\1)
                                  (list first second)))
             (list (request "org.example.a"))))
  (check-true (odra-catalog-resolution-failure? result))
  (check-eq? (odra-catalog-resolution-failure-code result) 'cycle))

(test-case "expired and untrusted snapshots cannot contribute candidates"
  (define source (make-source "primary" 10))
  (define expired
    (make-snapshot
     "primary" 1 (digest #\1)
     (list (make-entry "org.example.app" "1.0.0" (digest #\2)))
     #:expiry (odra-catalog-expiry 1 50 2)))
  (define unavailable
    (resolve (list source) (list expired) (list (request "org.example.app"))))
  (check-eq? (odra-catalog-resolution-failure-code unavailable) 'no-candidate)
  (define untrusted-source
    (struct-copy odra-catalog-source source
                 [trusted-keys
                  (list
                   (odra-catalog-signing-key
                    "39f713d0a644253f04529421b9f51b9b08979d08295959c4f3990ee617f5139f"
                    'ed25519
                    "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"))]))
  (define current
    (make-snapshot "primary" 2 (digest #\3)
                   (list (make-entry "org.example.app" "1.0.0" (digest #\2)))))
  (define untrusted
    (resolve (list untrusted-source) (list current)
             (list (request "org.example.app"))))
  (check-eq? (odra-catalog-resolution-failure-code untrusted)
             'untrusted-snapshot))
