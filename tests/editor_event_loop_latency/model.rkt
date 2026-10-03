#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list)

(provide (struct-out latency-sample)
         latency-sample-valid?
         (struct-out latency-summary)
         summarize-latency-samples)

(define maximum-samples 4096)
(define maximum-workload-id-length 64)
(define admitted-turn-kinds '(input command racket projection render maintenance))
(define admitted-phases '(input dispatch racket projection render external-wait))

(struct latency-sample
  (workload-id turn-kind elapsed-ns external-wait-ns phase-durations)
  #:transparent)

(struct latency-summary
  (workload-id samples p50-ns p95-ns p99-ns maximum-ns external-wait-maximum-ns)
  #:transparent)

(define (bounded-identifier? value)
  (and (string? value)
       (positive? (string-length value))
       (<= (string-length value) maximum-workload-id-length)
       (regexp-match? #px"^[a-z0-9][a-z0-9-]*$" value)))

(define (phase-durations-valid? durations elapsed-ns external-wait-ns)
  (and (hash? durations)
       (immutable? durations)
       (<= (hash-count durations) (length admitted-phases))
       (for/and ([(phase duration) (in-hash durations)])
         (and (memq phase admitted-phases)
              (exact-nonnegative-integer? duration)
              (<= duration elapsed-ns)))
       (<= external-wait-ns elapsed-ns)))

;; Validates one sanitized measurement without accepting content or path fields.
(define (latency-sample-valid? sample)
  (and (latency-sample? sample)
       (bounded-identifier? (latency-sample-workload-id sample))
       (memq (latency-sample-turn-kind sample) admitted-turn-kinds)
       (exact-positive-integer? (latency-sample-elapsed-ns sample))
       (exact-nonnegative-integer? (latency-sample-external-wait-ns sample))
       (phase-durations-valid?
        (latency-sample-phase-durations sample)
        (latency-sample-elapsed-ns sample)
        (latency-sample-external-wait-ns sample))))

(define (nearest-rank sorted-values percentile)
  (define count (length sorted-values))
  (define rank (max 1 (ceiling (* (/ percentile 100) count))))
  (list-ref sorted-values (sub1 rank)))

;; Summarizes one bounded workload and rejects mixed or malformed samples.
(define (summarize-latency-samples samples)
  (unless (and (list? samples)
               (pair? samples)
               (<= (length samples) maximum-samples)
               (andmap latency-sample-valid? samples))
    (raise-argument-error
     'summarize-latency-samples
     "a non-empty bounded list of valid latency samples"
     samples))
  (define workload-id (latency-sample-workload-id (car samples)))
  (unless (andmap
           (lambda (sample)
             (string=? workload-id (latency-sample-workload-id sample)))
           samples)
    (raise-argument-error
     'summarize-latency-samples
     "samples for one workload"
     samples))
  (define elapsed-values
    (sort (map latency-sample-elapsed-ns samples) <))
  (latency-summary
   workload-id
   (length samples)
   (nearest-rank elapsed-values 50)
   (nearest-rank elapsed-values 95)
   (nearest-rank elapsed-values 99)
   (last elapsed-values)
   (apply max (map latency-sample-external-wait-ns samples))))
