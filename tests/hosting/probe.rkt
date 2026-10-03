#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require ffi/unsafe)

(provide probe-dispatch
         probe-cumulative-memory-use
         probe-force-collection
         probe-transform
         scalar-round-trip)

;; scalar-round-trip returns the successor of one exact integer.
(define (scalar-round-trip value)
  (add1 value))

;; probe-transform returns a distinct byte string with the same contents.
(define (probe-transform value)
  (bytes-copy value))

;; probe-force-collection completes one full collection for RSS sampling.
(define (probe-force-collection)
  (collect-garbage))

;; probe-cumulative-memory-use reports total Racket allocation since startup.
(define (probe-cumulative-memory-use)
  (current-memory-use 'cumulative))

;; probe-dispatch contains probe failures before they cross into native code.
(define (probe-dispatch scenario value)
  (with-handlers ([exn:fail?
                   (lambda (failure)
                     (list #f (exn-message failure)))])
    (list #t
          (case scenario
            [(0) (scalar-round-trip value)]
            [(1) (scalar-round-trip "wrong type")]
            [(2) (scalar-round-trip)]
            [(3) (error 'probe-dispatch "requested failure")]
            [(4) (dynamic-require ''odra-missing-probe 'missing)]
            [else (raise-argument-error 'probe-dispatch
                                        "an integer from 0 through 4"
                                        scenario)]))))

(module+ test
  (require rackunit)

  (check-equal? (probe-dispatch 0 41) '(#t 42))
  (define source #"odra")
  (define transformed (probe-transform source))
  (check-equal? transformed source)
  (check-false (eq? transformed source))
  (for ([scenario (in-range 1 5)])
    (define result (probe-dispatch scenario 41))
    (check-false (car result))
    (check-pred (lambda (value)
                  (and (string? value)
                       (positive? (string-length value))))
                (cadr result))))

(module+ main
  (define arguments (current-command-line-arguments))
  (unless (= (vector-length arguments) 2)
    (raise-user-error 'racket-host-probe "expected: <native-library> <integer>"))

  (define native-library (ffi-lib (vector-ref arguments 0)))
  (define native-round-trip
    (get-ffi-obj "odra_racket_host_probe_round_trip"
                 native-library
                 (_fun _int64 -> _int64)))
  (define input (string->number (vector-ref arguments 1)))
  (unless (exact-integer? input)
    (raise-user-error 'racket-host-probe "input must be an exact integer"))

  (define result (native-round-trip input))
  (unless (= result (scalar-round-trip input))
    (error 'racket-host-probe "native result disagrees with the Racket reference"))
  (printf "racket-host: ~a\n" result))
