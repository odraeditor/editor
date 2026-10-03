#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "model.rkt")

(define (sample workload elapsed [external-wait 0])
  (latency-sample
   workload
   'input
   elapsed
   external-wait
   (hash 'input elapsed 'external-wait external-wait)))

(test-case "valid samples admit bounded public measurement fields"
  (check-true (latency-sample-valid? (sample "small-text" 100 10)))
  (check-false
   (latency-sample-valid?
    (latency-sample "/private/path" 'input 100 0 (hash 'input 100))))
  (check-false
   (latency-sample-valid?
    (latency-sample "small-text" 'unknown 100 0 (hash 'input 100))))
  (check-false
   (latency-sample-valid?
    (latency-sample "small-text" 'input 100 101 (hash 'input 100)))))

(test-case "summary uses deterministic nearest-rank percentiles"
  (define summary
    (summarize-latency-samples
     (for/list ([elapsed (in-range 1 101)])
       (sample "small-text" elapsed))))
  (check-equal? (latency-summary-workload-id summary) "small-text")
  (check-equal? (latency-summary-samples summary) 100)
  (check-equal? (latency-summary-p50-ns summary) 50)
  (check-equal? (latency-summary-p95-ns summary) 95)
  (check-equal? (latency-summary-p99-ns summary) 99)
  (check-equal? (latency-summary-maximum-ns summary) 100))

(test-case "summary rejects mixed workloads and empty input"
  (check-exn
   exn:fail:contract?
   (lambda ()
     (summarize-latency-samples
      (list (sample "small-text" 10) (sample "stress-text" 20)))))
  (check-exn
   exn:fail:contract?
   (lambda () (summarize-latency-samples '()))))
