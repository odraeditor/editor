#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         rackunit
         "model.rkt")

(define key-a (make-string 64 #\a))
(define key-b (make-string 64 #\b))
(define catalog-id (make-string 64 #\c))

(define roots
  (list (catalog-root-key key-a 1 'ed25519 key-a 1 100)
        (catalog-root-key key-b 2 'ed25519 key-b 101 #f)))

(define policies
  (list
   (catalog-policy "official-policy-v1" 1 1 "eligible-v1" "authority-v1"
                   "assessment-v1" "decision-v1" "retention-v1")
   (catalog-policy "official-policy-v2" 2 20 "eligible-v2" "authority-v2"
                   "assessment-v2" "decision-v2" "retention-v2")))

(define curators
  (list
   (curator-authorization "curator-primary" "person-primary" 'human 1 #f
                          '("official-policy-v1" "official-policy-v2"))))

(define publishers
  (list (publisher-authorization "snapshot-publisher" (list key-a key-b) 1 1 #f)))

(define endpoints
  (list
   (catalog-endpoint "origin" catalog-id "https://packages.example/catalog"
                     'https 'origin 0 #t)
   (catalog-endpoint "mirror" catalog-id "https://mirror.example/catalog"
                     'https 'mirror 1 #t)))

(define (fixture
         #:identity [identity catalog-id]
         #:display-name [display-name "Example Catalog"]
         #:roots [selected-roots roots]
         #:curators [selected-curators curators]
         #:publishers [selected-publishers publishers]
         #:policies [selected-policies policies]
         #:endpoints [selected-endpoints endpoints])
  (catalog-profile 1 identity display-name selected-roots selected-curators
                   selected-publishers selected-policies selected-endpoints))

(test-case "catalog identity ignores endpoint order and location"
  (define-values (confirmed rejection) (confirm-catalog-profile (fixture)))
  (check-false rejection)
  (define-values (moved moved-rejection)
    (confirm-catalog-profile
     (fixture
      #:endpoints
      (list
       (catalog-endpoint "mirror" catalog-id "https://new-mirror.example/catalog"
                         'https 'mirror 0 #t)
       (catalog-endpoint "origin" catalog-id "https://new-origin.example/catalog"
                         'https 'origin 1 #t)))))
  (check-false moved-rejection)
  (check-true (same-catalog-identity? confirmed moved)))

(test-case "profile collections normalize independently from declaration order"
  (define-values (expected expected-rejection) (confirm-catalog-profile (fixture)))
  (define-values (permuted permuted-rejection)
    (confirm-catalog-profile
     (fixture #:roots (reverse roots)
              #:policies (reverse policies)
              #:endpoints (reverse endpoints))))
  (check-false expected-rejection)
  (check-false permuted-rejection)
  (check-equal? permuted expected))

(test-case "root and policy generations must be unique and increasing"
  (define duplicate-root
    (catalog-root-key (make-string 64 #\d) 1 'ed25519 (make-string 64 #\d) 1 #f))
  (define-values (_ root-rejection)
    (confirm-catalog-profile (fixture #:roots (cons duplicate-root roots))))
  (check-eq? (catalog-identity-rejection-code root-rejection)
             'duplicate-identity)
  (check-eq? (catalog-identity-rejection-field root-rejection)
             'root-generations)
  (define stale-policies
    (list (struct-copy catalog-policy (car policies) [effective-from 20])
          (struct-copy catalog-policy (cadr policies) [effective-from 10])))
  (define-values (_2 policy-rejection)
    (confirm-catalog-profile (fixture #:policies stale-policies)))
  (check-eq? (catalog-identity-rejection-code policy-rejection)
             'stale-generation))

(test-case "curation authority admits accountable humans only"
  (for ([class '(ai-assisted deterministic-tool isolated-runtime)])
    (define invalid
      (curator-authorization "curator-primary" "assessor" class 1 #f
                             '("official-policy-v1")))
    (define-values (_ rejection)
      (confirm-catalog-profile (fixture #:curators (list invalid))))
    (check-eq? (catalog-identity-rejection-code rejection) 'invalid-authority)
    (check-eq? (catalog-identity-rejection-field rejection) 'curators)))

(test-case "curator authorization is policy and interval specific"
  (define authorization (car curators))
  (check-true
   (curator-authorization-active? authorization 50 "official-policy-v2"))
  (check-false
   (curator-authorization-active? authorization 50 "unrelated-policy"))
  (define expired (struct-copy curator-authorization authorization [valid-until 40]))
  (check-false
   (curator-authorization-active? expired 50 "official-policy-v1")))

(test-case "publisher thresholds count distinct authorized keys"
  (define authorization (publisher-authorization "threshold" (list key-a key-b) 2 1 100))
  (check-true
   (publisher-authorization-active? authorization 50 (list key-a key-b)))
  (check-false
   (publisher-authorization-active? authorization 50 (list key-a key-a)))
  (check-false
   (publisher-authorization-active? authorization 101 (list key-a key-b))))

(test-case "endpoint identity and transport constraints reject"
  (for ([endpoint
         (in-list
          (list
           (catalog-endpoint "wrong-catalog" (make-string 64 #\d)
                             "https://packages.example/catalog"
                             'https 'origin 0 #t)
           (catalog-endpoint "local-over-network" catalog-id
                             "https://packages.example/catalog"
                             'https 'local 0 #t)
           (catalog-endpoint "credentials" catalog-id
                             "https://user@packages.example/catalog"
                             'https 'origin 0 #t)))])
    (define-values (_ rejection)
      (confirm-catalog-profile (fixture #:endpoints (list endpoint))))
    (check-eq? (catalog-identity-rejection-code rejection) 'invalid-field)
    (check-eq? (catalog-identity-rejection-field rejection) 'endpoints)))

(test-case "ordinary demanding and boundary profiles fit selected limits"
  (for ([profile (in-list catalog-identity-resource-profiles)])
    (check-true (validate-catalog-identity-resource-profile profile))))

(test-case "each count ceiling rejects a one-unit overflow"
  (define boundary (last catalog-identity-resource-profiles))
  (for ([field (in-list '(root-keys curator-authorizations
                                    publisher-authorizations policies
                                    endpoints signatures))])
    (check-false
     (validate-catalog-identity-resource-profile
      (hash-set boundary field
                (add1 (hash-ref catalog-identity-limits field)))))))
