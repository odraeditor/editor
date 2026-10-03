#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         "../../../src/layout/display-policy-configuration.rkt"
         (submod "../../../src/layout/display-policy-configuration.rkt" test-support))

(provide runtime-display-policy-exchange-probe)

(define (runtime-display-policy-exchange-probe scenario generation fields)
  (cond
    [(= scenario 0) (runtime-display-policy-exchange generation fields)]
    [(= scenario 2) (list #t 'wrong-result fields #"")]
    [else
     (with-handlers ([exn?
                      (lambda (failure)
                        (list #f 0 '()
                              (string->bytes/utf-8 (exn-message failure))))])
       (define current (fields->display-policy fields))
       (define selected
         (case scenario
           [(1)
            (error 'runtime-display-policy-exchange-probe
                   "requested display policy failure")]
           [(3)
            (collect-garbage)
            (display-policy->fields (configured-display-policy current))]
           [(4) (display-policy->fields (configured-display-policy current))]
           [(5)
            (display-policy->fields
             (display-policy-replace
              current
              (hasheq 'actions '(reuse-least-recent split-right)
                      'split-height-threshold 16
                      'split-width-threshold 60)))]
           [(6) (list-set (display-policy->fields current) 1 99)]
           [(7) (list-set (display-policy->fields current) 33 0)]
           [(8) (list-set (display-policy->fields current) 0 33)]
           [else
            (raise-argument-error
             'runtime-display-policy-exchange-probe
             "an integer from 0 through 8"
             scenario)]))
       (list #t (if (= scenario 4) (add1 generation) generation) selected #""))]))

(module+ test
  (require rackunit)
  (define fields (append '(4 1 2 3 4) (make-list 28 0) '(12 40)))
  (check-false (car (runtime-display-policy-exchange-probe 1 7 fields)))
  (check-equal?
   (cadr (runtime-display-policy-exchange-probe 2 7 fields))
   'wrong-result))
