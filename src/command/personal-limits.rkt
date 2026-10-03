#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         "native-contracts.rkt")

(provide
 default-personal-command-limits
 maximum-personal-diagnostic-bytes
 (contract-out
  [personal-command-limits? (-> any/c boolean?)]
  [personal-command-limits-deadline-milliseconds
   (-> personal-command-limits? exact-positive-integer?)]
  [personal-command-limits-custodian-memory-bytes
   (-> personal-command-limits? exact-positive-integer?)]
  [personal-command-limits-inspection-bytes
   (-> personal-command-limits? exact-positive-integer?)]
  [personal-command-limits-replacement-bytes
   (-> personal-command-limits? exact-positive-integer?)]
  [personal-command-limits-splices
   (-> personal-command-limits? exact-positive-integer?)]
  [personal-command-limits-temporary-native-bytes
   (-> personal-command-limits? exact-positive-integer?)]
  [personal-command-limits-nested-operations
   (-> personal-command-limits? exact-positive-integer?)]
  [personal-command-limits-diagnostic-bytes
   (-> personal-command-limits? exact-positive-integer?)]
  [make-personal-command-limits
   (->* ()
        (#:deadline-milliseconds exact-positive-integer?
         #:custodian-memory-bytes exact-positive-integer?
         #:inspection-bytes exact-positive-integer?
         #:replacement-bytes exact-positive-integer?
         #:splices exact-positive-integer?
         #:temporary-native-bytes exact-positive-integer?
         #:nested-operations exact-positive-integer?
         #:diagnostic-bytes exact-positive-integer?)
        personal-command-limits?)]))

(define native-maximum-inspection-bytes
  (native-contract-value 'transaction 'maximum-inspection-bytes))
(define native-maximum-splices
  (native-contract-value 'transaction 'maximum-batch-splices))
(define native-maximum-replacement-bytes
  (native-contract-value 'transaction 'maximum-text-bytes))
(define native-maximum-nested-operations
  (native-contract-value 'transaction 'maximum-nested-depth))

;; These defaults admit demanding interactive text transformations while
;; remaining substantially below the native transaction hard maxima.
(define default-personal-deadline-milliseconds 2000)
(define maximum-personal-deadline-milliseconds 10000)
(define maximum-personal-custodian-memory-bytes (* 128 1024 1024))
(define maximum-personal-inspection-bytes (* 8 1024 1024))
(define maximum-personal-replacement-bytes (* 8 1024 1024))
(define maximum-personal-splices 4096)
(define maximum-personal-temporary-native-bytes (* 32 1024 1024))
(define maximum-personal-nested-operations 8)
(define maximum-personal-diagnostic-bytes 4096)

(struct personal-command-limits
  (deadline-milliseconds custodian-memory-bytes inspection-bytes
                         replacement-bytes splices temporary-native-bytes
                         nested-operations diagnostic-bytes)
  #:transparent)

(define (make-personal-command-limits
         #:deadline-milliseconds
         [deadline-milliseconds default-personal-deadline-milliseconds]
         #:custodian-memory-bytes
         [custodian-memory-bytes maximum-personal-custodian-memory-bytes]
         #:inspection-bytes
         [inspection-bytes maximum-personal-inspection-bytes]
         #:replacement-bytes
         [replacement-bytes maximum-personal-replacement-bytes]
         #:splices [splices maximum-personal-splices]
         #:temporary-native-bytes
         [temporary-native-bytes maximum-personal-temporary-native-bytes]
         #:nested-operations
         [nested-operations maximum-personal-nested-operations]
         #:diagnostic-bytes
         [diagnostic-bytes maximum-personal-diagnostic-bytes])
  (check-limit 'deadline-milliseconds deadline-milliseconds
               maximum-personal-deadline-milliseconds)
  (check-limit 'custodian-memory-bytes custodian-memory-bytes
               maximum-personal-custodian-memory-bytes)
  (check-limit 'inspection-bytes inspection-bytes
               (min maximum-personal-inspection-bytes
                    native-maximum-inspection-bytes))
  (check-limit 'replacement-bytes replacement-bytes
               (min maximum-personal-replacement-bytes
                    native-maximum-replacement-bytes))
  (check-limit 'splices splices
               (min maximum-personal-splices native-maximum-splices))
  (check-limit 'temporary-native-bytes temporary-native-bytes
               maximum-personal-temporary-native-bytes)
  (check-limit 'nested-operations nested-operations
               (min maximum-personal-nested-operations
                    native-maximum-nested-operations))
  (check-limit 'diagnostic-bytes diagnostic-bytes
               maximum-personal-diagnostic-bytes)
  (personal-command-limits
   deadline-milliseconds custodian-memory-bytes inspection-bytes
   replacement-bytes splices temporary-native-bytes nested-operations
   diagnostic-bytes))

(define (check-limit name value maximum)
  (when (> value maximum)
    (raise-arguments-error
     'make-personal-command-limits
     "requested limit exceeds the personal command maximum"
     "limit" name "requested" value "maximum" maximum)))

(define default-personal-command-limits (make-personal-command-limits))

(module+ test
  (require rackunit)

  (check-true (personal-command-limits? default-personal-command-limits))
  (check-equal?
   (personal-command-limits-inspection-bytes default-personal-command-limits)
   (* 8 1024 1024))
  (check-equal?
   (personal-command-limits-deadline-milliseconds
    default-personal-command-limits)
   2000)
  (check-equal?
   (personal-command-limits-deadline-milliseconds
    (make-personal-command-limits #:deadline-milliseconds 10000))
   10000)
  (check-equal?
   (personal-command-limits-deadline-milliseconds
    (make-personal-command-limits #:deadline-milliseconds 250))
   250)
  (check-exn
   #rx"exceeds the personal command maximum"
   (lambda ()
     (make-personal-command-limits
      #:inspection-bytes (add1 maximum-personal-inspection-bytes)))))
