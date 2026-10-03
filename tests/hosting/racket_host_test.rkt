#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require ffi/unsafe
         racket/runtime-path
         rackunit
         rackunit/text-ui
         "probe.rkt")

(define-runtime-path probe-module "probe.rkt")

(define arguments (current-command-line-arguments))
(unless (= (vector-length arguments) 1)
  (raise-user-error 'racket-host-test "expected: <native-library>"))

(define native-custodian (make-custodian))
(define native-round-trip
  (parameterize ([current-custodian native-custodian])
    (define native-library (ffi-lib (vector-ref arguments 0)))
    (get-ffi-obj "odra_racket_host_probe_round_trip"
                 native-library
                 (_fun _int64 -> _int64))))

(define hosting-tests
  (test-suite
   "Racket-hosted Odin boundary"
   (test-case "ordinary module loads"
     (check-eq? (dynamic-require probe-module 'scalar-round-trip)
                scalar-round-trip))
   (test-case "scalar call succeeds"
     (check-equal? (native-round-trip 41) 42))
   (test-case "wrong type is rejected"
     (check-exn exn:fail:contract?
                (lambda () (native-round-trip "41"))))
   (test-case "wrong arity is rejected"
     (check-exn exn:fail:contract?
                (lambda () (native-round-trip))))
   (test-case "Racket exception is contained"
     (for ([scenario (in-range 1 5)])
       (check-false (car (probe-dispatch scenario 41)))))))

(define failures (run-tests hosting-tests))
(custodian-shutdown-all native-custodian)
(unless (zero? failures)
  (exit 1))
