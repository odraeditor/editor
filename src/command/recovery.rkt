#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base)

(provide
 minimum-recovery-debounce-milliseconds
 maximum-recovery-debounce-milliseconds
 minimum-recovery-maximum-interval-milliseconds
 maximum-recovery-maximum-interval-milliseconds
 minimum-recovery-retention-seconds
 maximum-recovery-retention-seconds
 minimum-recovery-records-per-buffer
 maximum-recovery-records-per-buffer
 minimum-recovery-total-records
 maximum-recovery-total-records
 minimum-recovery-record-payload-bytes
 maximum-recovery-record-payload-bytes
 minimum-recovery-buffer-storage-bytes
 maximum-recovery-buffer-storage-bytes
 minimum-recovery-store-storage-bytes
 maximum-recovery-store-storage-bytes
 minimum-recovery-cleanup-records
 maximum-recovery-cleanup-records
 factory-recovery-retention
 factory-recovery-storage-limits
 factory-recovery-policy
 recovery-strategy?
 recovery-startup-policy?
 recovery-source-autosave-policy?
 (struct-out odra-recovery-retention)
 (struct-out odra-recovery-storage-limits)
 (struct-out odra-recovery-policy)
 (contract-out
  [recovery-retention
   (->* ()
        (#:maximum-age-seconds exact-positive-integer?
         #:records-per-buffer exact-positive-integer?
         #:total-records exact-positive-integer?)
        odra-recovery-retention?)]
  [recovery-storage-limits
   (->* ()
        (#:record-payload-bytes exact-positive-integer?
         #:buffer-storage-bytes exact-positive-integer?
         #:store-storage-bytes exact-positive-integer?
         #:cleanup-records exact-positive-integer?)
        odra-recovery-storage-limits?)]
  [recovery-policy
   (->* ()
        (#:enabled? boolean?
         #:strategy recovery-strategy?
         #:debounce-milliseconds exact-positive-integer?
         #:maximum-interval-milliseconds exact-positive-integer?
         #:retention odra-recovery-retention?
         #:storage odra-recovery-storage-limits?
         #:startup recovery-startup-policy?
         #:source-autosave recovery-source-autosave-policy?)
        odra-recovery-policy?)]))

(define kibibyte 1024)
(define mebibyte (* 1024 kibibyte))
(define gibibyte (* 1024 mebibyte))

(define minimum-recovery-debounce-milliseconds 50)
(define maximum-recovery-debounce-milliseconds 5000)
(define minimum-recovery-maximum-interval-milliseconds 1000)
(define maximum-recovery-maximum-interval-milliseconds 60000)
(define minimum-recovery-retention-seconds 3600)
(define maximum-recovery-retention-seconds (* 30 24 3600))
(define minimum-recovery-records-per-buffer 1)
(define maximum-recovery-records-per-buffer 64)
(define minimum-recovery-total-records 16)
(define maximum-recovery-total-records 16384)
(define minimum-recovery-record-payload-bytes (* 64 kibibyte))
(define maximum-recovery-record-payload-bytes gibibyte)
(define minimum-recovery-buffer-storage-bytes mebibyte)
(define maximum-recovery-buffer-storage-bytes (* 4 gibibyte))
(define minimum-recovery-store-storage-bytes (* 64 mebibyte))
(define maximum-recovery-store-storage-bytes (* 32 gibibyte))
(define minimum-recovery-cleanup-records 8)
(define maximum-recovery-cleanup-records 4096)

(define recovery-strategies '(transaction-debounced interval hybrid))
(define recovery-startup-policies '(ask inspect restore-matching))
(define recovery-source-autosave-policies '(disabled after-checkpoint))

(define (recovery-strategy? value)
  (and (memq value recovery-strategies) #t))

(define (recovery-startup-policy? value)
  (and (memq value recovery-startup-policies) #t))

(define (recovery-source-autosave-policy? value)
  (and (memq value recovery-source-autosave-policies) #t))

(struct odra-recovery-retention
  (maximum-age-seconds records-per-buffer total-records)
  #:transparent
  #:guard
  (lambda (maximum-age-seconds records-per-buffer total-records _)
    (unless (and (<= minimum-recovery-retention-seconds
                     maximum-age-seconds
                     maximum-recovery-retention-seconds)
                 (<= minimum-recovery-records-per-buffer
                     records-per-buffer
                     maximum-recovery-records-per-buffer)
                 (<= minimum-recovery-total-records
                     total-records
                     maximum-recovery-total-records)
                 (<= records-per-buffer total-records))
      (raise-arguments-error 'odra-recovery-retention
                             "recovery retention exceeds immutable bounds"))
    (values maximum-age-seconds records-per-buffer total-records)))

(define factory-recovery-retention
  (odra-recovery-retention (* 7 24 3600) 8 512))

(struct odra-recovery-storage-limits
  (record-payload-bytes buffer-storage-bytes store-storage-bytes cleanup-records)
  #:transparent
  #:guard
  (lambda (record-payload-bytes buffer-storage-bytes store-storage-bytes
                                cleanup-records _)
    (unless (and (<= minimum-recovery-record-payload-bytes
                     record-payload-bytes
                     maximum-recovery-record-payload-bytes)
                 (<= minimum-recovery-buffer-storage-bytes
                     buffer-storage-bytes
                     maximum-recovery-buffer-storage-bytes)
                 (<= minimum-recovery-store-storage-bytes
                     store-storage-bytes
                     maximum-recovery-store-storage-bytes)
                 (<= minimum-recovery-cleanup-records
                     cleanup-records
                     maximum-recovery-cleanup-records)
                 (<= record-payload-bytes buffer-storage-bytes)
                 (<= buffer-storage-bytes store-storage-bytes))
      (raise-arguments-error 'odra-recovery-storage-limits
                             "recovery storage limits exceed immutable bounds"))
    (values record-payload-bytes buffer-storage-bytes store-storage-bytes
            cleanup-records)))

(define factory-recovery-storage-limits
  (odra-recovery-storage-limits
   (* 128 mebibyte) (* 512 mebibyte) (* 2 gibibyte) 128))

(struct odra-recovery-policy
  (enabled? strategy debounce-milliseconds maximum-interval-milliseconds
            retention storage startup source-autosave)
  #:transparent
  #:guard
  (lambda (enabled? strategy debounce-milliseconds maximum-interval-milliseconds
                    retention storage startup source-autosave _)
    (unless (and (boolean? enabled?)
                 (recovery-strategy? strategy)
                 (<= minimum-recovery-debounce-milliseconds
                     debounce-milliseconds
                     maximum-recovery-debounce-milliseconds)
                 (<= minimum-recovery-maximum-interval-milliseconds
                     maximum-interval-milliseconds
                     maximum-recovery-maximum-interval-milliseconds)
                 (<= debounce-milliseconds maximum-interval-milliseconds)
                 (odra-recovery-retention? retention)
                 (odra-recovery-storage-limits? storage)
                 (recovery-startup-policy? startup)
                 (recovery-source-autosave-policy? source-autosave))
      (raise-arguments-error 'odra-recovery-policy
                             "invalid unsaved-work recovery policy"))
    (values enabled? strategy debounce-milliseconds maximum-interval-milliseconds
            retention storage startup source-autosave)))

(define factory-recovery-policy
  (odra-recovery-policy
   #t 'hybrid 300 5000
   factory-recovery-retention
   factory-recovery-storage-limits
   'ask
   'disabled))

(define (recovery-retention
         #:maximum-age-seconds [maximum-age-seconds (* 7 24 3600)]
         #:records-per-buffer [records-per-buffer 8]
         #:total-records [total-records 512])
  (odra-recovery-retention
   maximum-age-seconds records-per-buffer total-records))

(define (recovery-storage-limits
         #:record-payload-bytes [record-payload-bytes (* 128 mebibyte)]
         #:buffer-storage-bytes [buffer-storage-bytes (* 512 mebibyte)]
         #:store-storage-bytes [store-storage-bytes (* 2 gibibyte)]
         #:cleanup-records [cleanup-records 128])
  (odra-recovery-storage-limits
   record-payload-bytes buffer-storage-bytes store-storage-bytes cleanup-records))

(define (recovery-policy
         #:enabled? [enabled? #t]
         #:strategy [strategy 'hybrid]
         #:debounce-milliseconds [debounce-milliseconds 300]
         #:maximum-interval-milliseconds [maximum-interval-milliseconds 5000]
         #:retention [retention factory-recovery-retention]
         #:storage [storage factory-recovery-storage-limits]
         #:startup [startup 'ask]
         #:source-autosave [source-autosave 'disabled])
  (odra-recovery-policy
   enabled? strategy debounce-milliseconds maximum-interval-milliseconds
   retention storage startup source-autosave))

(module+ test
  (require rackunit)

  (check-true (odra-recovery-policy-enabled? factory-recovery-policy))
  (check-eq? (odra-recovery-policy-strategy factory-recovery-policy) 'hybrid)
  (check-eq? (odra-recovery-policy-source-autosave factory-recovery-policy)
             'disabled)
  (check-exn exn:fail?
             (lambda () (recovery-policy #:debounce-milliseconds 49)))
  (check-exn exn:fail?
             (lambda ()
               (recovery-policy #:debounce-milliseconds 5000
                                #:maximum-interval-milliseconds 1000)))
  (check-exn exn:fail?
             (lambda ()
               (recovery-storage-limits
                #:record-payload-bytes (* 2 gibibyte)))))
