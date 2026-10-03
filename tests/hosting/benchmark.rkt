#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         racket/port
         racket/runtime-path
         racket/system)

(define-runtime-path racket-host-benchmark "racket_host_benchmark.rkt")

(define (measure-process executable . process-arguments)
  (define started (current-inexact-monotonic-milliseconds))
  (parameterize ([current-output-port (open-output-nowhere)]
                 [current-error-port (open-output-nowhere)])
    (apply run-process executable process-arguments))
  (milliseconds->nanoseconds
   (- (current-inexact-monotonic-milliseconds) started)))

(define (run-process executable . process-arguments)
  (define exit-code (apply system*/exit-code executable process-arguments))
  (unless (zero? exit-code)
    (error 'hosting-benchmark
           "candidate process failed: ~a ~a"
           executable
           process-arguments)))

(define (report-cold candidate samples)
  (define sorted (sort samples <))
  (define p95 (percentile-nearest-rank sorted 95))
  (define passed? (<= p95 1000000000))
  (printf "candidate=~a metric=cold-process samples=~a p95_ns=~a max_ns=~a gate_ns=1000000000 passed=~a\n"
          candidate
          (length sorted)
          p95
          (last sorted)
          passed?)
  (flush-output)
  passed?)

(define (percentile-nearest-rank sorted-values percentile)
  (list-ref sorted-values
            (sub1 (quotient (+ (* (length sorted-values) percentile) 99) 100))))

(define (milliseconds->nanoseconds milliseconds)
  (inexact->exact (round (* milliseconds 1000000))))

(define arguments (current-command-line-arguments))
(unless (= (vector-length arguments) 2)
  (raise-user-error 'hosting-benchmark
                    "expected: <odin-host-executable> <racket-host-library>"))

(define odin-host (vector-ref arguments 0))
(define racket-host-library (vector-ref arguments 1))
(define racket-executable (find-executable-path "racket"))
(unless racket-executable
  (raise-user-error 'hosting-benchmark "racket executable is unavailable"))

(define cold-samples 20)
(define odin-cold-passed?
  (report-cold
   "odin-host"
   (for/list ([sample (in-range cold-samples)])
     (measure-process odin-host "--cold"))))
(define racket-cold-passed?
  (report-cold
   "racket-host"
   (for/list ([sample (in-range cold-samples)])
     (measure-process racket-executable
                      (path->string racket-host-benchmark)
                      "--cold"
                      racket-host-library))))

(run-process odin-host "--benchmark")
(run-process racket-executable
             (path->string racket-host-benchmark)
             "--benchmark"
             racket-host-library)

(unless (and odin-cold-passed? racket-cold-passed?)
  (exit 1))
