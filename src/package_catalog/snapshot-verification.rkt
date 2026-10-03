#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         "contracts.rkt"
         "integrity.rkt"
         "snapshot-records.rkt")

(provide
 (struct-out odra-package-catalog-snapshot-failure)
 (contract-out
  [verify-package-catalog-snapshot
   (->* (odra-package-catalog-profile?
         (listof odra-package-catalog-publisher-key?)
         (or/c #f odra-package-catalog-snapshot?)
         exact-nonnegative-integer?
         exact-positive-integer?
         odra-package-catalog-snapshot?)
        (#:allow-bootstrap-latest? boolean?)
        (or/c #t odra-package-catalog-snapshot-failure?))]))

(struct odra-package-catalog-snapshot-failure (code field expected actual)
  #:transparent
  #:guard
  (lambda (code field expected actual _)
    (unless (and (memq code '(catalog-identity expiry history metadata-size
                                               not-yet-valid policy
                                               publisher-authorization
                                               sequence signature
                                               snapshot-digest))
                 (symbol? field))
      (raise-arguments-error 'odra-package-catalog-snapshot-failure
                             "invalid snapshot verification failure"))
    (values code field expected actual)))

(define (failure code field [expected #f] [actual #f])
  (odra-package-catalog-snapshot-failure code field expected actual))

(define (find-policy profile policy-id sequence)
  (for/first ([policy (in-list (odra-package-catalog-profile-policies profile))]
              #:when
              (and (string=? policy-id (odra-package-catalog-policy-id policy))
                   (<= (odra-package-catalog-policy-effective-from policy)
                       sequence)))
    policy))

(define (find-publisher profile publisher-id)
  (for/first
      ([authorization
        (in-list (odra-package-catalog-profile-publishers profile))]
       #:when
       (string=? publisher-id
                 (odra-package-catalog-publisher-authorization-id authorization)))
    authorization))

(define (history-failure previous snapshot allow-bootstrap-latest?)
  (cond
    [(not previous)
     (and (not allow-bootstrap-latest?)
          (or (not (= (odra-package-catalog-snapshot-sequence snapshot) 1))
              (odra-package-catalog-snapshot-previous-snapshot-digest snapshot))
          (failure 'history 'bootstrap 1
                   (odra-package-catalog-snapshot-sequence snapshot)))]
    [(not (string=?
           (odra-package-catalog-snapshot-catalog-id previous)
           (odra-package-catalog-snapshot-catalog-id snapshot)))
     (failure 'catalog-identity 'previous-snapshot
              (odra-package-catalog-snapshot-catalog-id snapshot)
              (odra-package-catalog-snapshot-catalog-id previous))]
    [(not (= (odra-package-catalog-snapshot-sequence snapshot)
             (add1 (odra-package-catalog-snapshot-sequence previous))))
     (failure 'sequence 'sequence
              (add1 (odra-package-catalog-snapshot-sequence previous))
              (odra-package-catalog-snapshot-sequence snapshot))]
    [(not (string=?
           (odra-package-catalog-snapshot-previous-snapshot-digest snapshot)
           (odra-package-catalog-snapshot-id previous)))
     (failure 'history 'previous-snapshot-digest
              (odra-package-catalog-snapshot-id previous)
              (odra-package-catalog-snapshot-previous-snapshot-digest snapshot))]
    [else #f]))

(define (verify-package-catalog-snapshot
         profile publisher-keys previous now observed-metadata-size snapshot
         #:allow-bootstrap-latest? [allow-bootstrap-latest? #f])
  (define profile-integrity
    (verify-package-catalog-profile-identity profile))
  (define expected-digest
    (package-catalog-snapshot-content-digest snapshot))
  (define history-rejection
    (history-failure previous snapshot allow-bootstrap-latest?))
  (define policy
    (find-policy profile
                 (odra-package-catalog-snapshot-policy-id snapshot)
                 (odra-package-catalog-snapshot-sequence snapshot)))
  (define publisher
    (find-publisher
     profile
     (odra-package-catalog-snapshot-publisher-authorization-id snapshot)))
  (cond
    [(odra-package-catalog-integrity-failure? profile-integrity)
     (failure 'catalog-identity 'profile #f
              (odra-package-catalog-integrity-failure-code profile-integrity))]
    [(not (string=? (odra-package-catalog-profile-identity profile)
                    (odra-package-catalog-snapshot-catalog-id snapshot)))
     (failure 'catalog-identity 'catalog-id
              (odra-package-catalog-profile-identity profile)
              (odra-package-catalog-snapshot-catalog-id snapshot))]
    [(not (string=? expected-digest
                    (odra-package-catalog-snapshot-id snapshot)))
     (failure 'snapshot-digest 'id expected-digest
              (odra-package-catalog-snapshot-id snapshot))]
    [history-rejection history-rejection]
    [(not policy)
     (failure 'policy 'policy-id #f
              (odra-package-catalog-snapshot-policy-id snapshot))]
    [(> (odra-package-catalog-snapshot-issued-at snapshot) now)
     (failure 'not-yet-valid 'issued-at now
              (odra-package-catalog-snapshot-issued-at snapshot))]
    [(>= now (odra-package-catalog-snapshot-expires-at snapshot))
     (failure 'expiry 'expires-at
              (odra-package-catalog-snapshot-expires-at snapshot) now)]
    [(not (= observed-metadata-size
             (odra-package-catalog-snapshot-metadata-size snapshot)))
     (failure 'metadata-size 'metadata-size
              (odra-package-catalog-snapshot-metadata-size snapshot)
              observed-metadata-size)]
    [(not publisher)
     (failure 'publisher-authorization 'publisher-authorization-id #f
              (odra-package-catalog-snapshot-publisher-authorization-id snapshot))]
    [else
     (define signature-result
       (verify-package-catalog-publisher-signatures
        publisher publisher-keys
        (odra-package-catalog-snapshot-signatures snapshot)
        (odra-package-catalog-snapshot-issued-at snapshot)
        (package-catalog-snapshot-signing-payload snapshot)))
     (if (odra-package-catalog-integrity-failure? signature-result)
         (failure
          (if (eq? (odra-package-catalog-integrity-failure-code signature-result)
                   'publisher-authorization)
              'publisher-authorization
              'signature)
          'signatures #f
          (odra-package-catalog-integrity-failure-code signature-result))
         #t)]))
