#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list)

(provide snapshot-limits
         snapshot-resource-profiles
         (struct-out catalog-snapshot)
         (struct-out snapshot-observation)
         (struct-out snapshot-rejection)
         validate-snapshot-history
         reconcile-snapshot-observations
         estimate-snapshot-retained-bytes
         estimate-snapshot-temporary-bytes
         validate-snapshot-resource-profile)

(define snapshot-limits
  '#hasheq((metadata-bytes . 4194304)
           (signatures . 16)
           (observations . 64)
           (retained-snapshots . 1024)
           (retained-bytes . 67108864)
           (temporary-bytes . 16777216)))

(define snapshot-resource-profiles
  (list
   '#hasheq((name . ordinary)
            (metadata-bytes . 65536)
            (signatures . 1)
            (observations . 2)
            (retained-snapshots . 32))
   '#hasheq((name . demanding)
            (metadata-bytes . 1048576)
            (signatures . 8)
            (observations . 16)
            (retained-snapshots . 256))
   '#hasheq((name . boundary)
            (metadata-bytes . 4194304)
            (signatures . 16)
            (observations . 64)
            (retained-snapshots . 1024))))

(struct catalog-snapshot
  (id catalog-id sequence previous-digest policy-id issued-at expires-at
      assertion-digest advisory-digest metadata-size publisher-id signatures)
  #:transparent)
(struct snapshot-observation (endpoint-id role state snapshot valid?) #:transparent)
(struct snapshot-rejection (code expected actual retained) #:transparent)

(define (validate-snapshot-history previous candidate now observed-size)
  (cond
    [(not (= observed-size (catalog-snapshot-metadata-size candidate)))
     (snapshot-rejection 'metadata-size
                         (catalog-snapshot-metadata-size candidate)
                         observed-size previous)]
    [(> observed-size (hash-ref snapshot-limits 'metadata-bytes))
     (snapshot-rejection 'metadata-limit
                         (hash-ref snapshot-limits 'metadata-bytes)
                         observed-size previous)]
    [(> (length (catalog-snapshot-signatures candidate))
        (hash-ref snapshot-limits 'signatures))
     (snapshot-rejection 'signature-limit
                         (hash-ref snapshot-limits 'signatures)
                         (length (catalog-snapshot-signatures candidate))
                         previous)]
    [(> (catalog-snapshot-issued-at candidate) now)
     (snapshot-rejection 'not-yet-valid now
                         (catalog-snapshot-issued-at candidate) previous)]
    [(>= now (catalog-snapshot-expires-at candidate))
     (snapshot-rejection 'expired
                         (catalog-snapshot-expires-at candidate) now previous)]
    [(and (not previous)
          (or (not (= (catalog-snapshot-sequence candidate) 1))
              (catalog-snapshot-previous-digest candidate)))
     (snapshot-rejection 'bootstrap-history 1
                         (catalog-snapshot-sequence candidate) previous)]
    [(and previous
          (not (= (catalog-snapshot-sequence candidate)
                  (add1 (catalog-snapshot-sequence previous)))))
     (snapshot-rejection 'sequence
                         (add1 (catalog-snapshot-sequence previous))
                         (catalog-snapshot-sequence candidate) previous)]
    [(and previous
          (not (equal? (catalog-snapshot-previous-digest candidate)
                       (catalog-snapshot-id previous))))
     (snapshot-rejection 'predecessor
                         (catalog-snapshot-id previous)
                         (catalog-snapshot-previous-digest candidate) previous)]
    [else #t]))

(define (reconcile-snapshot-observations previous observations)
  (define available
    (filter (lambda (value) (eq? (snapshot-observation-state value) 'available))
            observations))
  (define valid
    (filter snapshot-observation-valid? available))
  (cond
    [(null? available)
     (if previous
         (values 'offline previous '())
         (values 'unavailable #f '()))]
    [(null? valid) (values 'rejected previous available)]
    [(> (length
         (remove-duplicates
          (map (lambda (value)
                 (catalog-snapshot-id (snapshot-observation-snapshot value)))
               valid)
          string=?))
        1)
     (values 'divergent previous valid)]
    [else
     (values 'confirmed
             (snapshot-observation-snapshot (car valid))
             (sort (map snapshot-observation-endpoint-id valid) string<?))]))

(define (estimate-snapshot-retained-bytes profile)
  (* (hash-ref profile 'retained-snapshots)
     (+ 2048 (* 256 (hash-ref profile 'signatures)))))

(define (estimate-snapshot-temporary-bytes profile)
  (+ (hash-ref profile 'metadata-bytes)
     (* 4096 (hash-ref profile 'observations))
     (* 256 (hash-ref profile 'signatures))))

(define (validate-snapshot-resource-profile profile)
  (and
   (for/and ([field '(metadata-bytes signatures observations retained-snapshots)])
     (define value (hash-ref profile field #f))
     (and (exact-nonnegative-integer? value)
          (<= value (hash-ref snapshot-limits field))))
   (<= (estimate-snapshot-retained-bytes profile)
       (hash-ref snapshot-limits 'retained-bytes))
   (<= (estimate-snapshot-temporary-bytes profile)
       (hash-ref snapshot-limits 'temporary-bytes))))
