#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require "../../../src/hosting/runtime.rkt")

(provide runtime-call-probe)

;; runtime-call-probe drives scalar failure and forced-collection turns.
(define (runtime-call-probe scenario value)
  (case scenario
    [(0) (runtime-call value)]
    [(2) (list #t 'wrong-result #"")]
    [else
     (with-handlers ([exn?
                      (lambda (failure)
                        (list #f 0 (string->bytes/utf-8 (exn-message failure))))])
       (define result
         (case scenario
           [(1) (error 'runtime-call-probe "requested Racket failure")]
           [(3) (collect-garbage) value]
           [else
            (raise-argument-error
             'runtime-call-probe "an integer from 0 through 3" scenario)]))
       (list #t result #""))]))

(module+ test
  (require rackunit)
  (check-equal? (runtime-call-probe 0 41) '(#t 42 #""))
  (check-false (car (runtime-call-probe 1 41)))
  (check-equal? (runtime-call-probe 2 41) '(#t wrong-result #""))
  (check-equal? (runtime-call-probe 3 41) '(#t 41 #"")))
