#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require "../../../src/history/configuration.rkt"
         (submod "../../../src/history/configuration.rkt" test-support))

(provide runtime-history-policy-exchange-probe)

(define (runtime-history-policy-exchange-probe scenario generation fields)
  (cond
    [(= scenario 0) (runtime-history-policy-exchange generation fields)]
    [(= scenario 2) (list #t 'wrong-result fields #"")]
    [else
     (with-handlers ([exn?
                      (lambda (failure)
                        (list #f 0 '()
                              (string->bytes/utf-8 (exn-message failure))))])
       (define current (fields->history-policy fields))
       (define candidate
         (case scenario
           [(1) (error 'runtime-history-policy-exchange-probe "requested policy failure")]
           [(3) (collect-garbage) (configured-history-policy current)]
           [(4) (configured-history-policy current)]
           [(5)
            (define inspected (history-policy-inspect current))
            (history-policy-replace
             current
             (hasheq 'inspection-nodes
                     (add1 (hash-ref inspected 'inspection-nodes))))]
           [(6) (history-policy-replace current (hasheq 'inspection-nodes 8))]
           [(7) (history-policy-replace current (hasheq 'global-retained-bytes 0))]
           [(8)
            (history-policy-replace
             current
             (hasheq 'global-retained-bytes (* 16 1024 1024)
                     'buffer-retained-bytes (* 32 1024 1024)))]
           [else
            (raise-argument-error
             'runtime-history-policy-exchange-probe
             "an integer from 0 through 8"
             scenario)]))
       (list #t
             (if (= scenario 4) (add1 generation) generation)
             (history-policy->fields candidate)
             #""))]))

(module+ test
  (require rackunit)
  (define fields
    (list (* 512 1024 1024) (* 256 1024 1024) 250000 100000 256 65536
          1024 100000 (* 256 1024 1024) 1000 1000000 256 4096))
  (check-false (car (runtime-history-policy-exchange-probe 1 7 fields)))
  (check-equal?
   (cadr (runtime-history-policy-exchange-probe 2 7 fields))
   'wrong-result))
