#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         (only-in "../command/gutter-provider.rkt"
                  odra-gutter-provider?
                  odra-gutter-provider-name
                  odra-gutter-provider-package
                  odra-gutter-provider-generation
                  odra-gutter-provider-marker-generation
                  odra-gutter-provider-complete?
                  odra-gutter-provider-lanes
                  odra-gutter-provider-markers
                  odra-gutter-lane-identity
                  odra-gutter-lane-side
                  odra-gutter-lane-order
                  odra-gutter-lane-width
                  odra-gutter-lane-minimum-cells
                  odra-gutter-lane-maximum-cells
                  odra-gutter-lane-alignment
                  odra-gutter-lane-visibility
                  odra-gutter-lane-collision
                  odra-gutter-lane-priority
                  odra-gutter-lane-style
                  odra-gutter-lane-separator
                  odra-gutter-lane-separator-fallback
                  odra-gutter-marker-identity
                  odra-gutter-marker-lane
                  odra-gutter-marker-line
                  odra-gutter-marker-value
                  odra-gutter-marker-fallback
                  odra-gutter-marker-style
                  odra-gutter-marker-priority
                  odra-gutter-marker-aggregation
                  odra-gutter-marker-detail
                  odra-gutter-marker-actions
                  odra-gutter-marker-stale?))

(provide
 (struct-out gutter-provider-startup-result)
 (contract-out
  [load-gutter-provider-startup-value (-> any/c gutter-provider-startup-result?)]
  [encode-gutter-provider (-> odra-gutter-provider? bytes?)]))

(define schema-version 1)
(define header-bytes 96)
(define lane-record-bytes 152)
(define marker-record-bytes 224)
(define maximum-proposal-bytes (+ header-bytes lane-record-bytes
                                  (* 256 marker-record-bytes) (* 128 1024)))

(struct gutter-provider-startup-result (status provider bytes diagnostic) #:transparent)

(define (word value)
  (integer->integer-bytes value 8 #f #f))

(define (words values)
  (apply bytes-append (map word values)))

(define (symbol-code value table who)
  (define found (assq value table))
  (unless found (error who "unsupported value: ~a" value))
  (cdr found))

(define side-codes '((left . 1) (right . 2)))
(define width-codes '((fixed . 1) (automatic . 2) (bounded-automatic . 3)
                      (content-presence . 4)))
(define alignment-codes '((left . 1) (center . 2) (right . 3)))
(define visibility-codes '((always . 1) (when-content . 2) (configured . 3)))
(define collision-codes '((highest-priority . 1) (stack . 2) (aggregate . 3)
                          (primary-with-details . 4)))
(define style-codes
  '((ordinary . 1) (background . 2) (separator . 3)
    (diagnostic-error . 6) (diagnostic-warning . 7)
    (diagnostic-information . 8) (diagnostic-hint . 9)
    (continuation . 10) (clipping . 11) (stale . 12)
    (aggregate . 13) (unavailable . 14)))

(define (load-gutter-provider-startup-value value)
  (with-handlers ([exn:fail?
                   (lambda (failure)
                     (gutter-provider-startup-result 'rejected #f #"" (exn-message failure)))])
    (cond
      [(not value) (gutter-provider-startup-result 'confirmed #f #"" #f)]
      [(odra-gutter-provider? value)
       (gutter-provider-startup-result 'confirmed value (encode-gutter-provider value) #f)]
      [else
       (raise-arguments-error 'load-gutter-provider-startup-value
                              "expected one programmable Gutter provider or #f"
                              "value" value)])))

(define (encode-gutter-provider provider)
  (define lanes (odra-gutter-provider-lanes provider))
  (define markers (odra-gutter-provider-markers provider))
  (define text-start (+ header-bytes (* lane-record-bytes (length lanes))
                        (* marker-record-bytes (length markers))))
  (define cursor text-start)
  (define trailing '())
  (define (append-text value)
    (define bytes (string->bytes/utf-8 value))
    (define range (list cursor (bytes-length bytes)))
    (set! cursor (+ cursor (bytes-length bytes)))
    (set! trailing (cons bytes trailing))
    range)
  (define name-range (append-text (odra-gutter-provider-name provider)))
  (define package-range (append-text (symbol->string (odra-gutter-provider-package provider))))
  (define lane-ranges
    (for/list ([lane (in-list lanes)])
      (list (append-text (symbol->string (odra-gutter-lane-identity lane)))
            (append-text (odra-gutter-lane-separator lane))
            (append-text (odra-gutter-lane-separator-fallback lane)))))
  (define marker-ranges
    (for/list ([marker (in-list markers)])
      (list (append-text (symbol->string (odra-gutter-marker-identity marker)))
            (append-text (odra-gutter-marker-value marker))
            (append-text (odra-gutter-marker-fallback marker))
            (append-text (odra-gutter-marker-aggregation marker))
            (append-text (odra-gutter-marker-detail marker))
            (for/list ([action (in-list (odra-gutter-marker-actions marker))])
              (append-text action)))))
  (define text-bytes (- cursor text-start))
  (when (> cursor maximum-proposal-bytes)
    (error 'encode-gutter-provider "programmable Gutter proposal exceeds copied storage"))
  (define lane-index
    (for/hash ([lane (in-list lanes)] [index (in-naturals)])
      (values (odra-gutter-lane-identity lane) index)))
  (define lane-records
    (for/list ([lane (in-list lanes)] [ranges (in-list lane-ranges)] [index (in-naturals)])
      (define identity-range (list-ref ranges 0))
      (define separator-range (list-ref ranges 1))
      (define fallback-range (list-ref ranges 2))
      (words
       (list (odra-gutter-provider-generation provider)
             index
             (symbol-code (odra-gutter-lane-side lane) side-codes 'encode-gutter-provider)
             (+ 32768 (odra-gutter-lane-order lane))
             1
             (symbol-code (odra-gutter-lane-width lane) width-codes 'encode-gutter-provider)
             (odra-gutter-lane-minimum-cells lane)
             (odra-gutter-lane-maximum-cells lane)
             (symbol-code (odra-gutter-lane-alignment lane) alignment-codes
                          'encode-gutter-provider)
             (symbol-code (odra-gutter-lane-visibility lane) visibility-codes
                          'encode-gutter-provider)
             (symbol-code (odra-gutter-lane-collision lane) collision-codes
                          'encode-gutter-provider)
             (odra-gutter-lane-priority lane)
             (symbol-code (odra-gutter-lane-style lane) style-codes 'encode-gutter-provider)
             (car identity-range) (cadr identity-range)
             (car separator-range) (cadr separator-range)
             (car fallback-range) (cadr fallback-range)))))
  (define marker-records
    (for/list ([marker (in-list markers)] [ranges (in-list marker-ranges)] [index (in-naturals)])
      (define action-ranges (list-ref ranges 5))
      (define padded-actions
        (append action-ranges (make-list (- 4 (length action-ranges)) '(0 0))))
      (words
       (append
        (list (odra-gutter-provider-generation provider)
              (odra-gutter-provider-marker-generation provider)
              index
              (hash-ref lane-index (odra-gutter-marker-lane marker))
              (sub1 (odra-gutter-marker-line marker))
              (symbol-code (odra-gutter-marker-style marker) style-codes
                           'encode-gutter-provider)
              (odra-gutter-marker-priority marker)
              2
              (if (odra-gutter-marker-stale? marker) 1 0)
              (car (list-ref ranges 0)) (cadr (list-ref ranges 0))
              (car (list-ref ranges 1)) (cadr (list-ref ranges 1))
              (car (list-ref ranges 2)) (cadr (list-ref ranges 2))
              (car (list-ref ranges 3)) (cadr (list-ref ranges 3))
              (car (list-ref ranges 4)) (cadr (list-ref ranges 4))
              (length action-ranges))
        (append-map (lambda (range) range) padded-actions)))))
  (bytes-append
   (words
    (list schema-version
          (odra-gutter-provider-generation provider)
          (odra-gutter-provider-marker-generation provider)
          (length lanes)
          (length markers)
          (if (odra-gutter-provider-complete? provider) 1 0)
          (car name-range) (cadr name-range)
          (car package-range) (cadr package-range)
          text-bytes cursor))
   (apply bytes-append lane-records)
   (apply bytes-append marker-records)
   (apply bytes-append (reverse trailing))))

(module+ test
  (require rackunit
           (only-in "../command/gutter-provider.rkt"
                    gutter-lane gutter-marker gutter-provider))

  (define provider
    (gutter-provider
     "Personal Notes" 'personal-notes
     (list (gutter-lane 'notes))
     (list (gutter-marker 'review 'notes 5 "◆" #:fallback "*"
                          #:style 'diagnostic-information
                          #:detail "Review this line"
                          #:actions '(gutter-inspect-markers)))))
  (define encoded (encode-gutter-provider provider))
  (define (read-word offset)
    (integer-bytes->integer encoded #f #f offset (+ offset 8)))
  (check-equal? (read-word 0) schema-version)
  (check-equal? (read-word 24) 1)
  (check-equal? (read-word 32) 1)
  (check-equal? (read-word 88) (bytes-length encoded))
  (check-equal? (bytes-length encoded)
                (+ header-bytes lane-record-bytes marker-record-bytes (read-word 80)))
  (check-eq? (gutter-provider-startup-result-status
              (load-gutter-provider-startup-value provider))
             'confirmed)
  (check-eq? (gutter-provider-startup-result-status
              (load-gutter-provider-startup-value 'invalid))
             'rejected))
