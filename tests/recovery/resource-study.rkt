#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         racket/format
         "../../src/command/recovery.rkt")

(struct profile (name buffers payload-bytes records-per-buffer) #:transparent)

(define profiles
  (list
   (profile 'ordinary 16 (* 1 1024 1024) 4)
   (profile 'demanding 64 (* 4 1024 1024) 4)
   (profile 'stress 128 (* 16 1024 1024) 8)))

(define storage (odra-recovery-policy-storage factory-recovery-policy))
(define retention (odra-recovery-policy-retention factory-recovery-policy))
(define store-limit
  (odra-recovery-storage-limits-store-storage-bytes storage))
(define total-record-limit
  (odra-recovery-retention-total-records retention))
(define cleanup-limit
  (odra-recovery-storage-limits-cleanup-records storage))

(define (ceiling-quotient numerator denominator)
  (quotient (+ numerator (sub1 denominator)) denominator))

(for ([candidate (in-list profiles)])
  (define requested-records
    (* (profile-buffers candidate) (profile-records-per-buffer candidate)))
  (define requested-bytes
    (* requested-records (profile-payload-bytes candidate)))
  (define byte-limited-records
    (quotient store-limit (profile-payload-bytes candidate)))
  (define admitted-records
    (min requested-records total-record-limit byte-limited-records))
  (define cleanup-records (- requested-records admitted-records))
  (define cleanup-turns
    (if (zero? cleanup-records)
        0
        (ceiling-quotient cleanup-records cleanup-limit)))
  (check-true
   (<= (profile-payload-bytes candidate)
       (odra-recovery-storage-limits-record-payload-bytes storage)))
  (check-true (<= admitted-records total-record-limit))
  (check-true
   (<= (* admitted-records (profile-payload-bytes candidate)) store-limit))
  (printf
   (string-append
    "study=recovery profile=~a buffers=~a payload_bytes=~a "
    "requested_records=~a requested_bytes=~a admitted_records=~a "
    "cleanup_records=~a cleanup_turns=~a store_limit_bytes=~a "
    "record_limit=~a cleanup_limit=~a valid=true\n")
   (profile-name candidate)
   (profile-buffers candidate)
   (profile-payload-bytes candidate)
   requested-records
   requested-bytes
   admitted-records
   cleanup-records
   cleanup-turns
   store-limit
   total-record-limit
   cleanup-limit))
