#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         rackunit
         "model.rkt")

(define factory-definitions
  (list
   (language-definition "odin" "Odin" 'factory "" 1 '() '(".odin") "Odra factory")
   (language-definition "jan" "Jan" 'factory "" 1 '() '(".org" ".jan") "Odra factory")
   (language-definition "racket" "Racket" 'factory "" 1 '("info.rkt") '(".rkt") "Odra factory")))

(define (confirmed definitions [generation 1])
  (define-values (result accepted? failure)
    (confirm-catalog #f generation definitions))
  (check-true accepted?)
  (check-false failure)
  result)

;; A complete candidate publishes all maintained identities in canonical order.
(test-case "catalog confirmation is independent from definition order"
  (define baseline (confirmed factory-definitions))
  (for ([permutation (in-list (permutations factory-definitions))])
    (check-equal? (confirmed permutation) baseline)))

;; Exact filename selection outranks suffix matching within one source and scope.
(test-case "exact filename outranks suffix"
  (define definitions
    (list
     (language-definition "racket" "Racket" 'factory "" 1
                          '("info.rkt") '(".rkt") "Odra factory")
     (language-definition "metadata" "Metadata" 'factory "" 1
                          '("info.rkt.meta") '(".info.rkt") "fixture")))
  (define catalog (confirmed definitions))
  (define-values (selected failure) (resolve-language catalog "/work/info.rkt"))
  (check-false failure)
  (check-equal? (association-identity selected) "racket")
  (check-equal? (association-selector-kind selected) 'exact-filename))

;; The longest matching suffix wins without depending on declaration order.
(test-case "longest suffix wins"
  (define definitions
    (list
     (language-definition "generic" "Generic" 'factory "" 1 '() '(".gz") "fixture")
     (language-definition "tar" "Tar" 'factory "" 1 '() '(".tar.gz") "fixture")))
  (for ([candidate (in-list (list definitions (reverse definitions)))])
    (define-values (selected failure)
      (resolve-language (confirmed candidate) "/work/archive.tar.gz"))
    (check-false failure)
    (check-equal? (association-identity selected) "tar")
    (check-equal? (association-selector selected) ".tar.gz")))

;; Contribution source precedence wins across otherwise valid selectors.
(test-case "higher source shadows lower source"
  (define definitions
    (append factory-definitions
            (list (language-definition "scheme" "Scheme" 'personal "" 4
                                       '() '(".rkt") "personal init.rkt"))))
  (define-values (selected failure)
    (resolve-language (confirmed definitions) "/work/main.rkt"))
  (check-false failure)
  (check-equal? (association-identity selected) "scheme")
  (check-equal? (association-source selected) 'personal)
  (check-equal? (association-shadowed selected) '("racket")))

;; Explicit selection uses a confirmed identity and outranks filename matching.
(test-case "explicit confirmed identity outranks filename"
  (define-values (selected failure)
    (resolve-language (confirmed factory-definitions) "/work/main.rkt" #:explicit "odin"))
  (check-false failure)
  (check-equal? (association-identity selected) "odin")
  (check-equal? (association-selector-kind selected) 'explicit))

;; Equal selector specificity for different identities rejects the whole candidate.
(test-case "same-scope selector ambiguity rejects candidate"
  (define conflicting
    (append factory-definitions
            (list (language-definition "scheme" "Scheme" 'factory "" 1
                                       '() '(".rkt") "fixture"))))
  (define-values (result accepted? failure) (confirm-catalog #f 1 conflicting))
  (check-false accepted?)
  (check-equal? (rejection-code failure) 'ambiguous-selector)
  (check-equal? (catalog-generation result) 0))

;; Identity and selector comparisons are deliberately case-sensitive.
(test-case "identity and suffix matching are case-sensitive"
  (define catalog (confirmed factory-definitions))
  (define-values (upper-suffix upper-suffix-failure)
    (resolve-language catalog "/work/main.RKT"))
  (define-values (upper-identity upper-identity-failure)
    (resolve-language catalog "/work/main.rkt" #:explicit "Racket"))
  (check-false upper-suffix)
  (check-equal? (rejection-code upper-suffix-failure) 'no-match)
  (check-false upper-identity)
  (check-equal? (rejection-code upper-identity-failure) 'invalid-explicit))

;; Failed or stale candidates preserve the last confirmed generation exactly.
(test-case "rejected generation preserves last confirmed catalog"
  (define current (confirmed factory-definitions 7))
  (define-values (stale accepted? failure)
    (confirm-catalog current 7 (reverse factory-definitions)))
  (check-false accepted?)
  (check-equal? (rejection-code failure) 'stale-generation)
  (check-equal? (catalog-generation stale) 7)
  (check-equal? (catalog-definitions stale) (catalog-definitions current)))

;; Fixed catalog limits admit measured profiles and reject a one-unit overflow.
(test-case "resource profiles select bounded catalog capacities"
  (for ([profile (in-list catalog-resource-profiles)])
    (check-true (validate-resource-profile profile)))
  (define boundary (last catalog-resource-profiles))
  (check-false
   (validate-resource-profile
    (hash-set boundary 'selectors (add1 (hash-ref catalog-limits 'selectors-total))))))
