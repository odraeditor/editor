#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         rackunit
         "model.rkt")

(define v1 (bundle-version 1 0 0 #f))
(define v2 (bundle-version 2 0 0 #f))
(define digest-a (make-string 64 #\a))
(define digest-b (make-string 64 #\b))
(define all-targets
  (list (bundle-target 'linux 'x86-64)
        (bundle-target 'darwin 'aarch64)
        (bundle-target 'windows 'x86-64)))

(define dependencies
  (list
   (bundle-dependency "org.example.runtime" v1 v2 #f '(service))
   (bundle-dependency "org.example.theme" v1 v2 #t '())))

(define artifacts
  (list
   (bundle-artifact "grammar" 'tree-sitter-grammar "lib/language.so"
                    digest-a 4096
                    (list (bundle-target 'linux 'x86-64)
                          (bundle-target 'darwin 'aarch64))
                    'native-grammar)
   (bundle-artifact "queries" 'query "queries/highlights.scm"
                    digest-b 512 all-targets #f)))

(define contributions
  (list
   (bundle-contribution 'language "example" '("example") '() '() '())
   (bundle-contribution 'syntax-provider "example-tree-sitter" '("example")
                        '("grammar" "queries") '()
                        '(native-grammar))))

(define (fixture
         #:dependencies [selected-dependencies dependencies]
         #:authorities [authorities '(native-grammar)]
         #:contributions [selected-contributions contributions]
         #:artifacts [selected-artifacts artifacts]
         #:entrypoint [entrypoint #f])
  (bundle-manifest
   1 "org.example.language" "Example Language" v1
   (bundle-api-range v1 v2)
   "Example language support bundle."
   "org.example" "catalog.example"
   all-targets
   selected-dependencies authorities selected-contributions selected-artifacts
   entrypoint))

;; Canonical bytes are independent from declaration order for every set-like field.
(test-case "manifest encoding is canonical"
  (define expected (bundle-manifest->canonical-bytes (fixture)))
  (define permuted
    (fixture
     #:dependencies (reverse dependencies)
     #:authorities '(native-grammar)
     #:contributions (reverse contributions)
     #:artifacts (reverse artifacts)))
  (define target-permuted
    (struct-copy bundle-manifest permuted
                 [targets (reverse all-targets)]
                 [artifacts
                  (for/list ([artifact (in-list (bundle-manifest-artifacts permuted))])
                    (struct-copy bundle-artifact artifact
                                 [targets (reverse (bundle-artifact-targets artifact))]))]))
  (check-equal? (bundle-manifest->canonical-bytes target-permuted) expected))

;; A valid manifest confirms as a bounded immutable byte representation.
(test-case "valid manifest confirms"
  (define-values (encoded rejection) (confirm-bundle-manifest (fixture)))
  (check-false rejection)
  (check-true (bytes? encoded))
  (check-true (immutable? encoded))
  (check-true (positive? (bytes-length encoded))))

;; Duplicate semantic identities reject instead of depending on list order.
(test-case "duplicate contribution identity rejects"
  (define duplicated
    (fixture #:contributions
             (append contributions
                     (list (bundle-contribution 'language "example"
                                                '("example") '() '() '())))))
  (define-values (encoded rejection) (confirm-bundle-manifest duplicated))
  (check-false encoded)
  (check-equal? (bundle-rejection-code rejection) 'duplicate-identity)
  (check-equal? (bundle-rejection-field rejection) 'contributions))

;; Contribution references must resolve within the complete candidate.
(test-case "unknown artifact and authority references reject"
  (for ([candidate
         (in-list
          (list
           (fixture
            #:contributions
            (list (bundle-contribution 'syntax-provider "invalid" '("example")
                                       '("missing") '() '(native-grammar))))
           (fixture
            #:authorities '()
            #:contributions
            (list (bundle-contribution 'syntax-provider "invalid" '("example")
                                       '("grammar") '() '(native-grammar))))))])
    (define-values (encoded rejection) (confirm-bundle-manifest candidate))
    (check-false encoded)
    (check-equal? (bundle-rejection-code rejection) 'unknown-reference)))

;; Dependencies cannot point to the owning bundle or carry inverted ranges.
(test-case "dependency constraints are bounded"
  (for ([dependency
         (in-list
          (list
           (bundle-dependency "org.example.language" v1 v2 #f '())
           (bundle-dependency "org.example.runtime" v2 v1 #f '())))])
    (define-values (encoded rejection)
      (confirm-bundle-manifest (fixture #:dependencies (list dependency))))
    (check-false encoded)
    (check-not-false (memq (bundle-rejection-code rejection)
                           '(self-dependency invalid-version-range)))))

;; Compatibility is inclusive and compares the complete semantic-version core.
(test-case "bundle API compatibility is explicit"
  (check-true (bundle-api-compatible? (fixture) v1))
  (check-true (bundle-api-compatible? (fixture) v2))
  (check-true
   (bundle-api-compatible? (fixture) (bundle-version 1 9 4 #f)))
  (check-false
   (bundle-api-compatible? (fixture) (bundle-version 0 9 9 #f)))
  (check-false
   (bundle-api-compatible? (fixture) (bundle-version 2 0 1 #f))))

;; Platform selection returns exactly one matching immutable artifact.
(test-case "platform selection is explicit"
  (define-values (selected rejection)
    (select-bundle-artifact (fixture) "grammar" 'linux 'x86-64))
  (check-false rejection)
  (check-equal? (bundle-artifact-path selected) "lib/language.so")
  (define-values (missing missing-rejection)
    (select-bundle-artifact (fixture) "grammar" 'windows 'x86-64))
  (check-false missing)
  (check-equal? (bundle-rejection-code missing-rejection)
                'unavailable-platform))

;; Relative paths and SHA-256 text are structural admission boundaries.
(test-case "artifact paths and digests reject malformed values"
  (for ([artifact
         (in-list
          (list
           (struct-copy bundle-artifact (car artifacts) [path "../language.so"])
           (struct-copy bundle-artifact (car artifacts) [digest "abcd"])))])
    (define-values (encoded rejection)
      (confirm-bundle-manifest (fixture #:artifacts (list artifact))))
    (check-false encoded)
    (check-not-false (memq (bundle-rejection-code rejection)
                           '(invalid-path invalid-digest unknown-reference)))))

;; Entrypoints must name one declared Racket module artifact.
(test-case "entrypoint references a declared Racket module"
  (define-values (encoded rejection)
    (confirm-bundle-manifest (fixture #:entrypoint "main.rkt")))
  (check-false encoded)
  (check-equal? (bundle-rejection-code rejection) 'unknown-reference))

;; Ordinary, demanding, and boundary profiles fit each independent ceiling.
(test-case "resource profiles fit manifest limits"
  (for ([profile (in-list bundle-resource-profiles)])
    (check-true (validate-bundle-resource-profile profile))))

;; Every selected resource boundary rejects a one-unit overflow.
(test-case "resource profiles reject one-unit overflow"
  (define boundary (last bundle-resource-profiles))
  (for ([field (in-list '(dependencies artifacts contributions authorities
                                      targets manifest-bytes))])
    (check-false
     (validate-bundle-resource-profile
      (hash-set boundary field (add1 (hash-ref bundle-limits field)))))))
