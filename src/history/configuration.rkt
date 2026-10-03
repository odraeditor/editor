#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list)

(define unsigned-64/c
  (and/c exact-nonnegative-integer? (<=/c (sub1 (expt 2 64)))))
(define immutable-hash/c (and/c hash? immutable?))

(provide
 (contract-out
  [history-policy? (-> any/c boolean?)]
  [history-policy-inspect (-> history-policy? immutable-hash/c)]
  [history-policy-replace
   (-> history-policy? immutable-hash/c history-policy?)]
  [reload-history-policy! (-> (-> history-policy? history-policy?) void?)]
  [reset-history-policy! (-> void?)]
  [runtime-history-policy-exchange
   (-> exact-positive-integer? (listof unsigned-64/c) list?)]))

(define history-policy-field-names
  '(global-retained-bytes
    buffer-retained-bytes
    global-nodes
    buffer-nodes
    guaranteed-recent-units
    retained-depth
    sibling-branches
    records-per-unit
    payload-bytes-per-unit
    multibuffer-participants
    selective-operations
    inspection-nodes
    pruning-operations))
(define history-policy-field-count (length history-policy-field-names))

(struct history-policy (fields) #:transparent)

;; history-policy-inspect returns all fields as immutable configuration data.
(define (history-policy-inspect policy)
  (history-policy-fields policy))

;; history-policy-replace copies one policy with the named fields replaced.
(define (history-policy-replace policy replacements)
  (history-policy
   (for/fold ([fields (history-policy-fields policy)])
             ([(field value) (in-hash replacements)])
     (unless (memq field history-policy-field-names)
       (raise-arguments-error
        'history-policy-replace
        "unknown history policy field"
        "field" field))
     (unless (and (exact-nonnegative-integer? value)
                  (<= value (sub1 (expt 2 64))))
       (raise-argument-error
        'history-policy-replace
        "an unsigned 64-bit integer field value"
        value))
     (hash-set fields field value))))

(define configured-history-policy (lambda (current) current))

;; reload-history-policy! atomically replaces the live Racket configuration function.
(define (reload-history-policy! configure)
  (set! configured-history-policy configure))

;; reset-history-policy! restores the identity configuration used by built-in defaults.
(define (reset-history-policy!)
  (set! configured-history-policy (lambda (current) current)))

(define (fields->history-policy fields)
  (unless (= (length fields) history-policy-field-count)
    (raise-argument-error
     'runtime-history-policy-exchange
     "a complete 13-field history policy"
     fields))
  (history-policy
   (for/hasheq ([field (in-list history-policy-field-names)]
                [value (in-list fields)])
     (values field value))))

(define (history-policy->fields policy)
  (for/list ([field (in-list history-policy-field-names)])
    (hash-ref (history-policy-fields policy) field)))

;; runtime-history-policy-exchange applies the configured production policy.
(define (runtime-history-policy-exchange generation fields)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f 0 '()
                           (string->bytes/utf-8 (exn-message failure))))])
    (define candidate
      (configured-history-policy (fields->history-policy fields)))
    (unless (history-policy? candidate)
      (raise-result-error
       'runtime-history-policy-exchange "a history policy" candidate))
    (list #t generation (history-policy->fields candidate) #"")))

(module+ test-support
  (provide fields->history-policy history-policy->fields configured-history-policy))

(module+ test
  (require rackunit)

  (define default-fields
    (list (* 512 1024 1024)
          (* 256 1024 1024)
          250000
          100000
          256
          65536
          1024
          100000
          (* 256 1024 1024)
          1000
          1000000
          256
          4096))
  (define initial (fields->history-policy default-fields))
  (check-equal? (hash-ref (history-policy-inspect initial) 'inspection-nodes) 256)
  (check-equal?
   (hash-ref
    (history-policy-inspect
     (history-policy-replace initial (hasheq 'inspection-nodes 512)))
    'inspection-nodes)
   512)
  (check-exn exn:fail:contract?
             (lambda ()
               (history-policy-replace initial (hasheq 'unknown-field 1))))
  (check-exn exn:fail:contract?
             (lambda ()
               (history-policy-replace initial (hasheq 'inspection-nodes -1))))

  (reload-history-policy!
   (lambda (current)
     (history-policy-replace current (hasheq 'inspection-nodes 512))))
  (check-equal? (list-ref (runtime-history-policy-exchange 7 default-fields) 2)
                (append (take default-fields 11) '(512 4096)))
  (reload-history-policy!
   (lambda (current)
     (history-policy-replace current (hasheq 'inspection-nodes 128))))
  (check-equal? (list-ref (runtime-history-policy-exchange 7 default-fields) 2)
                (append (take default-fields 11) '(128 4096)))
  (reset-history-policy!)
  (check-equal? (runtime-history-policy-exchange 7 default-fields)
                (list #t 7 default-fields #"")))
