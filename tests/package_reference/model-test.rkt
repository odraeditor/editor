#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         rackunit
         "../../src/package/manifest-contracts.rkt"
         "../../src/package/state-records.rkt")

(define digest-a (make-string 64 #\a))
(define digest-b (make-string 64 #\b))
(define digest-c (make-string 64 #\c))
(define revision (make-string 40 #\d))
(define linux-x86 (odra-package-target 'linux 'x86-64))
(define linux-arm (odra-package-target 'linux 'aarch64))
(define no-managed-state
  (odra-package-state-compatibility #f #f #f 'none))

(define (artifact role kind path digest authority)
  (odra-package-artifact
   role kind path digest 128 #f #f authority '()))

(define license
  (artifact "license" 'license "LICENSE" digest-a #f))
(define entrypoint
  (artifact "entrypoint" 'racket-module "main.rkt" digest-b
            'racket-extension))
(define grammar
  (artifact "grammar" 'grammar "grammar.so" digest-c 'native-grammar))

(define (proposal id kind artifacts authorities contributions entrypoint-record)
  (odra-package-manifest-proposal
   1 id kind id "1.0.0" "Deterministic package model fixture" "MIT"
   "LICENSE" "example.publisher" revision "1.0.0" "2.0.0"
   (list linux-x86 linux-arm) '() authorities artifacts entrypoint-record
   contributions '() no-managed-state))

(define command
  (odra-package-contribution
   "example-command" 'command '(active-buffer) '(buffer view)))
(define extension-proposal
  (proposal
   "org.example.extension" 'extension (list entrypoint license)
   '(racket-extension) (list command)
   (odra-package-entrypoint "main.rkt" 'odra-package-contributions)))
(define language-proposal
  (proposal
   "org.example.language" 'language-support (list grammar license)
   '(native-grammar) '() #f))

(test-case "ordinary and language-support packages share one manifest owner"
  (define-values (extension extension-rejection)
    (confirm-package-manifest extension-proposal))
  (define-values (language language-rejection)
    (confirm-package-manifest language-proposal))
  (check-false extension-rejection)
  (check-false language-rejection)
  (check-eq? (odra-package-manifest-kind extension) 'extension)
  (check-eq? (odra-package-manifest-kind language) 'language-support)
  (check-equal? (odra-package-manifest-format-version extension)
                (odra-package-manifest-format-version language)))

(test-case "manifest confirmation is independent from declaration order"
  (define permuted
    (struct-copy odra-package-manifest-proposal extension-proposal
                 [targets (reverse
                           (odra-package-manifest-proposal-targets
                            extension-proposal))]
                 [authorities
                  (reverse
                   (odra-package-manifest-proposal-authorities
                    extension-proposal))]
                 [artifacts
                  (reverse
                   (odra-package-manifest-proposal-artifacts
                    extension-proposal))]))
  (define-values (expected expected-rejection)
    (confirm-package-manifest extension-proposal))
  (define-values (observed observed-rejection)
    (confirm-package-manifest permuted))
  (check-false expected-rejection)
  (check-false observed-rejection)
  (check-equal? observed expected))

(test-case "installed state identity does not derive from list position"
  (define provenance
    (odra-package-provenance
     'catalog digest-a digest-b digest-c
     "example.publisher" revision))
  (define (installed id kind manifest artifact)
    (odra-installed-package
     id kind "1.0.0" 1 manifest #f (list artifact) '() provenance
     'linux 'x86-64 '() '() "" 'installed-disabled 0 #f #f #t #f ""))
  (define extension
    (installed "org.example.extension" 'extension digest-a digest-b))
  (define language
    (installed "org.example.language" 'language-support digest-b digest-c))
  (define state
    (package-state-with-checksum
     (odra-package-state
      1 "default" 1 0 (list extension language) #f #f '() '()
      (odra-package-accounting 2 2 256 256 0) #f (make-string 64 #\0))))
  (check-equal? (odra-installed-package-id
                 (package-state-find state "org.example.extension" "1.0.0"))
                "org.example.extension")
  (check-equal? (odra-installed-package-id
                 (package-state-find state "org.example.language" "1.0.0"))
                "org.example.language"))

(test-case "removed unpinned content becomes collectible"
  (define provenance
    (odra-package-provenance
     'catalog digest-a digest-b digest-c
     "example.publisher" revision))
  (define removed
    (odra-installed-package
     "org.example.removed" 'extension "1.0.0" 1 digest-a #f
     (list digest-b) '() provenance 'linux 'x86-64 '() '() "" 'removed
     0 #f #f #f #f ""))
  (define state
    (package-state-with-checksum
     (odra-package-state
      1 "default" 1 0 (list removed) #f #f '() '()
      (odra-package-accounting 1 1 128 128 0) #f (make-string 64 #\0))))
  (check-equal? (package-state-reachable-content state) '())
  (check-equal? (package-state-garbage-collection-plan
                 state (list digest-a digest-b))
                (list digest-a digest-b)))
