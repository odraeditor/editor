#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require ffi/unsafe
         racket/file
         racket/list
         racket/runtime-path)

(define-runtime-path probe-module "probe.rkt")

(define (benchmark-payload byte-count warmup-count sample-count gate-ns)
  (define source (make-bytes byte-count))
  (define allocated-before (current-memory-use 'cumulative))
  (define latencies
    (measure warmup-count
             sample-count
             (lambda ()
               (unless (= (native-fill source byte-count) 1)
                 (error 'racket-host-benchmark "native fill failed"))
               (let ([transformed (probe-transform source)])
                 (unless (= (native-accept transformed byte-count) 1)
                   (error 'racket-host-benchmark "native accept failed"))))))
  (define allocated-after (current-memory-use 'cumulative))
  (printf "candidate=racket-host metric=payload-allocation bytes=~a allocated_bytes_per_call=~a\n"
          byte-count
          (quotient (- allocated-after allocated-before)
                    (+ warmup-count sample-count)))
  (report-latency (format "payload-~a" byte-count) latencies gate-ns))

(define (measure warmup-count sample-count operation)
  (for ([index (in-range warmup-count)])
    (operation))
  (for/list ([index (in-range sample-count)])
    (define started (current-inexact-monotonic-milliseconds))
    (operation)
    (milliseconds->nanoseconds
     (- (current-inexact-monotonic-milliseconds) started))))

(define (report-latency metric latencies gate-ns)
  (define sorted (sort latencies <))
  (define p50 (percentile-nearest-rank sorted 50))
  (define p95 (percentile-nearest-rank sorted 95))
  (define p99 (percentile-nearest-rank sorted 99))
  (define passed? (<= p99 gate-ns))
  (printf "candidate=racket-host metric=~a samples=~a p50_ns=~a p95_ns=~a p99_ns=~a max_ns=~a gate_ns=~a passed=~a\n"
          metric
          (length sorted)
          p50
          p95
          p99
          (last sorted)
          gate-ns
          passed?)
  passed?)

(define (percentile-nearest-rank sorted-values percentile)
  (list-ref sorted-values
            (sub1 (quotient (+ (* (length sorted-values) percentile) 99) 100))))

(define (milliseconds->nanoseconds milliseconds)
  (inexact->exact (round (* milliseconds 1000000))))

(define (current-rss-kib)
  (define status (file->string "/proc/self/status"))
  (define match (regexp-match #px"(?m:^VmRSS:\\s+([0-9]+)\\s+kB$)" status))
  (unless match
    (error 'racket-host-benchmark "VmRSS is unavailable"))
  (string->number (cadr match)))

(define arguments (current-command-line-arguments))
(unless (= (vector-length arguments) 2)
  (raise-user-error 'racket-host-benchmark
                    "expected: <--cold|--benchmark> <native-library>"))

(define mode (vector-ref arguments 0))
(define native-path (vector-ref arguments 1))
(define native-custodian (make-custodian))
(define baseline-rss-kib (current-rss-kib))
(define boot-start (current-inexact-monotonic-milliseconds))
(define-values (native-round-trip native-fill native-accept)
  (parameterize ([current-custodian native-custodian])
    (define native-library (ffi-lib native-path))
    (values
     (get-ffi-obj "odra_racket_host_probe_round_trip"
                  native-library
                  (_fun _int64 -> _int64))
     (get-ffi-obj "odra_racket_host_probe_fill"
                  native-library
                  (_fun _bytes _uint64 -> _int32))
     (get-ffi-obj "odra_racket_host_probe_accept"
                  native-library
                  (_fun _bytes _uint64 -> _int32)))))
(define probe-dispatch (dynamic-require probe-module 'probe-dispatch))
(define probe-force-collection (dynamic-require probe-module 'probe-force-collection))
(define probe-transform (dynamic-require probe-module 'probe-transform))
(unless (= (native-round-trip 41) 42)
  (error 'racket-host-benchmark "initial scalar call failed"))
(define boot-module-ns (milliseconds->nanoseconds
                        (- (current-inexact-monotonic-milliseconds) boot-start)))

(probe-force-collection)
(define rss-kib (current-rss-kib))

(cond
  [(string=? mode "--cold")
   (define shutdown-start (current-inexact-monotonic-milliseconds))
   (custodian-shutdown-all native-custodian)
   (printf "candidate=racket-host metric=cold boot_module_ns=~a rss_kib=~a shutdown_ns=~a\n"
           boot-module-ns
           rss-kib
           (milliseconds->nanoseconds
            (- (current-inexact-monotonic-milliseconds) shutdown-start)))]
  [(string=? mode "--benchmark")
   (define rss-increase-kib (max 0 (- rss-kib baseline-rss-kib)))
   (define idle-memory-passed? (<= rss-increase-kib (* 256 1024)))
   (printf "candidate=racket-host metric=boot-module elapsed_ns=~a gate_ns=1000000000 passed=~a\n"
           boot-module-ns
           (<= boot-module-ns 1000000000))
   (printf "candidate=racket-host metric=idle-memory rss_kib=~a increase_kib=~a gate_kib=~a passed=~a\n"
           rss-kib
           rss-increase-kib
           (* 256 1024)
           idle-memory-passed?)
   (define scalar-passed?
     (report-latency "scalar"
                     (measure 100 10000 (lambda () (native-round-trip 41)))
                     1000000))
   (define exception-passed?
     (report-latency "exception"
                     (measure 32 1000 (lambda () (probe-dispatch 3 41)))
                     10000000))
   (define payload-4k-passed? (benchmark-payload 4096 32 256 5000000))
   (define payload-1m-passed?
     (benchmark-payload (* 1024 1024) 4 40 100000000))
   (probe-force-collection)
   (define repeated-rss-kib (current-rss-kib))
   (define repeated-passed? (<= repeated-rss-kib (+ rss-kib (* 16 1024))))
   (printf "candidate=racket-host metric=repeated crossings=10000 rss_kib=~a growth_gate_kib=16384 passed=~a\n"
           repeated-rss-kib
           repeated-passed?)
   (define shutdown-start (current-inexact-monotonic-milliseconds))
   (custodian-shutdown-all native-custodian)
   (define shutdown-ns
     (milliseconds->nanoseconds
      (- (current-inexact-monotonic-milliseconds) shutdown-start)))
   (define shutdown-passed? (<= shutdown-ns 1000000000))
   (printf "candidate=racket-host metric=shutdown elapsed_ns=~a gate_ns=1000000000 passed=~a\n"
           shutdown-ns
           shutdown-passed?)
   (unless (and (<= boot-module-ns 1000000000)
                idle-memory-passed?
                scalar-passed?
                exception-passed?
                payload-4k-passed?
                payload-1m-passed?
                repeated-passed?
                shutdown-passed?)
     (exit 1))]
  [else
   (raise-user-error 'racket-host-benchmark "unknown mode: ~a" mode)])
