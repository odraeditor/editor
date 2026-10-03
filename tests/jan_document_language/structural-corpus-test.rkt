#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/runtime-path
         rackunit
         "structural-corpus.rkt")

(define-runtime-path manifest-path "manifest.rktd")

(define manifest
  (call-with-input-file manifest-path read))

(define expected-structural-families
  (for/list ([entry (in-list (hash-ref manifest 'entries))]
             #:when (eq? (hash-ref entry 'layer) 'structural))
    (hash-ref entry 'family)))

(test-case "structural corpus covers every Slice 2 family"
  (check-equal? (length structural-fixtures) 34)
  (check-equal? (sort (map structural-fixture-family structural-fixtures) symbol<?)
                (sort expected-structural-families symbol<?)))

(test-case "every structural family carries the complete evidence matrix"
  (for ([fixture (in-list structural-fixtures)])
    (define cases (structural-fixture-cases fixture))
    (check-equal? (sort (hash-keys cases) symbol<?)
                  (sort structural-evidence-kinds symbol<?))
    (check-true (string? (hash-ref cases 'positive)))
    (check-equal? (hash-ref (hash-ref cases 'availability) '.org)
                  (hash-ref (hash-ref cases 'availability) '.jan))))

(test-case "corpus sources retain explicit range and line-ending evidence"
  (for ([fixture (in-list structural-fixtures)])
    (define cases (structural-fixture-cases fixture))
    (check-equal? (hash-ref cases 'range) (hash-ref cases 'preservation))
    (define without-crlf
      (regexp-replace* #rx"\r\n" (hash-ref cases 'line-ending) ""))
    (check-false (regexp-match? #rx"[\r\n]" without-crlf))))
