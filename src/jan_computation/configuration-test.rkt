#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "configuration.rkt")

(define bounded-limits
  '#hasheq((table-cells . 4096)
           (formula-dependencies . 2048)
           (graph-depth . 256)
           (executable-targets . 256)
           (active-sessions . 8)
           (child-processes . 4)
           (output-bytes . 1048576)
           (retained-output-bytes . 8388608)
           (generated-files . 256)
           (result-rows . 4096)
           (cache-bytes . 16777216)
           (elapsed-milliseconds . 30000)
           (cpu-milliseconds . 30000)
           (rss-bytes . 536870912)
           (environment-entries . 128)))

(define valid-candidate
  (hasheq
   'generation 2
   'adapter-generation 4
   'policy-generation 6
   'adapters
   (list (hasheq 'identity "racket"
                 'language "racket"
                 'version "factory-1"
                 'class 'factory-adapter
                 'in-process? #t
                 'runtime-required? #f
                 'limits bounded-limits))
   'policies
   (list (hasheq 'identity "racket-project"
                 'language "racket"
                 'origin 'project
                 'interactive 'confirm
                 'batch 'deny
                 'effects '(read-resource child-process)))))

(test-case "computation configuration copies one Racket generation"
  (define language (string-copy "racket"))
  (define adapter (hash-set (car (hash-ref valid-candidate 'adapters)) 'language language))
  (define candidate (hash-set valid-candidate 'adapters (list adapter)))
  (define admitted (admit-computation-configuration candidate 1 3 5))
  (string-set! language 0 #\b)
  (check-equal? (hash-ref admitted 'generation) 2)
  (check-equal? (hash-ref admitted 'adapter-generation) 4)
  (check-equal? (hash-ref (car (hash-ref admitted 'adapters)) 'language) "racket")
  (check-equal? (hash-ref (car (hash-ref admitted 'policies)) 'batch) 'deny))

(test-case "stale and duplicate adapter generations reject wholly"
  (check-false (admit-computation-configuration valid-candidate 2 3 5))
  (define adapter (car (hash-ref valid-candidate 'adapters)))
  (define duplicate (hash-set adapter 'identity "replacement"))
  (check-false
   (admit-computation-configuration
    (hash-set valid-candidate 'adapters (list adapter duplicate))
    1 3 5)))

(test-case "execution limits and batch policy remain bounded"
  (define adapter (car (hash-ref valid-candidate 'adapters)))
  (define invalid-limits (hash-set bounded-limits 'output-bytes 67108865))
  (check-false
   (admit-computation-configuration
    (hash-set valid-candidate 'adapters (list (hash-set adapter 'limits invalid-limits)))
    1 3 5))
  (define policy (car (hash-ref valid-candidate 'policies)))
  (check-false
   (admit-computation-configuration
    (hash-set valid-candidate 'policies (list (hash-set policy 'batch 'confirm)))
    1 3 5)))
