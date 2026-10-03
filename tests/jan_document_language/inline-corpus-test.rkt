#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/runtime-path
         racket/string
         rackunit
         "inline-corpus.rkt")

(define-runtime-path manifest-path "manifest.rktd")

(define manifest
  (call-with-input-file manifest-path read))

(define expected-inline-families
  (for/list ([entry (in-list (hash-ref manifest 'entries))]
             #:when (eq? (hash-ref entry 'layer) 'inline))
    (hash-ref entry 'family)))

(test-case "inline corpus covers every Slice 3 family"
  (check-equal? (length inline-fixtures) 38)
  (check-equal? (sort (map inline-fixture-family inline-fixtures) symbol<?)
                (sort expected-inline-families symbol<?)))

(test-case "every inline family carries contextual evidence"
  (for ([fixture (in-list inline-fixtures)])
    (define cases (inline-fixture-cases fixture))
    (check-equal? (sort (hash-keys cases) symbol<?)
                  (sort inline-evidence-kinds symbol<?))
    (check-true (string? (hash-ref cases 'positive)))
    (check-true (symbol? (hash-ref cases 'index)))
    (check-equal? (hash-ref (hash-ref cases 'availability) '.org)
                  (hash-ref (hash-ref cases 'availability) '.jan))))

(test-case "inline preservation and range evidence use identical bytes"
  (for ([fixture (in-list inline-fixtures)])
    (define cases (inline-fixture-cases fixture))
    (check-equal? (hash-ref cases 'range) (hash-ref cases 'preservation))
    (check-true (string-prefix? (hash-ref cases 'escape) "\\"))))
