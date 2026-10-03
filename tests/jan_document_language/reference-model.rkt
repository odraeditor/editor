#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         racket/match
         racket/runtime-path)

(provide jan-baseline
         structural-families
         inline-families
         required-evidence
         resource-limits
         resource-profiles
         load-fixture-manifest
         validate-fixture-manifest
         validate-resource-profiles
         estimated-retained-bytes
         estimated-temporary-bytes)

(define jan-baseline "jan-org-9.8.10-v1")

(define structural-families
  '(document-root
    zeroth-section
    heading
    section
    center-block
    quote-block
    special-block
    drawer
    property-drawer
    dynamic-block
    footnote-definition
    inline-task
    list-item
    plain-list
    pipe-table
    table-provider-form
    source-block
    example-block
    export-block
    comment-block
    lesser-block
    clock
    diary-expression
    planning-line
    line-comment
    fixed-width-area
    horizontal-rule
    keyword
    affiliated-keyword
    latex-environment
    node-property
    paragraph
    table-row
    table-separator-row))

(define inline-families
  '(entity
    special-symbol
    latex-fragment
    export-snippet
    named-footnote-reference
    inline-footnote-reference
    anonymous-footnote-reference
    citation
    citation-reference
    inline-call
    inline-source
    explicit-line-break
    radio-link
    plain-link
    angle-link
    regular-link
    macro
    target
    radio-target
    percentage-cookie
    fraction-cookie
    subscript
    superscript
    table-cell
    active-timestamp
    inactive-timestamp
    diary-timestamp
    point-timestamp
    timestamp-range
    repeating-timestamp
    delayed-timestamp
    bold-markup
    italic-markup
    underline-markup
    verbatim-markup
    code-markup
    strike-through-markup
    plain-text))

(define required-evidence
  '(positive negative ambiguous nested malformed unicode line-ending casing
             indentation unknown-form boundary preservation range availability))

(define resource-limits
  '#hasheq((source-bytes . 67108864)
           (retained-bytes . 536870912)
           (temporary-bytes . 134217728)
           (nodes . 1048576)
           (structural-depth . 1024)
           (inline-depth . 256)
           (attributes-per-node . 128)
           (index-facts . 1048576)
           (diagnostics . 4096)
           (diagnostic-text-bytes . 4096)
           (incremental-edits . 16384)
           (inspection-bytes . 1048576)
           (rewrite-splices . 16384)
           (rewrite-bytes . 16777216)
           (cancellation-check-bytes . 65536)
           (initial-step-bytes . 8388608)
           (incremental-step-bytes . 2097152)
           (maintenance-step-nanoseconds . 50000000)
           (candidate-nanoseconds . 5000000000)))

(define resource-profiles
  (list
   '#hasheq((name . ordinary)
            (source-bytes . 65536)
            (nodes . 8192)
            (structural-depth . 32)
            (inline-depth . 16)
            (attributes-per-node . 32)
            (index-facts . 8192)
            (diagnostics . 64)
            (incremental-edits . 64)
            (temporary-bytes . 8388608))
   '#hasheq((name . demanding)
            (source-bytes . 8388608)
            (nodes . 524288)
            (structural-depth . 512)
            (inline-depth . 128)
            (attributes-per-node . 96)
            (index-facts . 524288)
            (diagnostics . 2048)
            (incremental-edits . 8192)
            (temporary-bytes . 100663296))
   '#hasheq((name . adversarial)
            (source-bytes . 67108864)
            (nodes . 1048576)
            (structural-depth . 1024)
            (inline-depth . 256)
            (attributes-per-node . 128)
            (index-facts . 1048576)
            (diagnostics . 4096)
            (incremental-edits . 16384)
            (temporary-bytes . 134217728))))

(define-runtime-path fixture-manifest-path "manifest.rktd")

(define (load-fixture-manifest)
  (call-with-input-file fixture-manifest-path read))

(define (validate-fixture-manifest manifest)
  (match manifest
    [(hash-table ('schema schema)
                 ('status status)
                 ('pending pending)
                 ('baseline baseline)
                 ('entries entries))
     (and (equal? schema 1)
          (eq? status 'complete)
          (null? pending)
          (equal? baseline jan-baseline)
          (list? entries)
          (equal? (length entries)
                  (+ (length structural-families) (length inline-families)))
          (let ([families (map (lambda (entry) (hash-ref entry 'family #f)) entries)])
            (and (not (check-duplicates families))
                 (equal? (sort families symbol<?)
                         (sort (append structural-families inline-families) symbol<?))))
          (for/and ([entry (in-list entries)])
            (define family (hash-ref entry 'family #f))
            (define layer (hash-ref entry 'layer #f))
            (define owner-slice (hash-ref entry 'owner-slice #f))
            (define evidence (hash-ref entry 'evidence '()))
            (and (case layer
                   [(structural) (and (memq family structural-families)
                                      (equal? owner-slice 2))]
                   [(inline) (and (memq family inline-families)
                                  (equal? owner-slice 3))]
                   [else #f])
                 (list? evidence)
                 (not (check-duplicates evidence))
                 (equal? (sort evidence symbol<?)
                         (sort required-evidence symbol<?)))))]
    [_ #f]))

(define (validate-resource-profiles profiles [limits resource-limits])
  (and (pair? profiles)
       (not (check-duplicates (map (lambda (profile) (hash-ref profile 'name #f)) profiles)))
       (for/and ([profile (in-list profiles)])
         (and (positive-exact-integer? (hash-ref profile 'source-bytes #f))
              (bounded? profile limits 'source-bytes 'source-bytes)
              (bounded? profile limits 'nodes 'nodes)
              (bounded? profile limits 'structural-depth 'structural-depth)
              (bounded? profile limits 'inline-depth 'inline-depth)
              (bounded? profile limits 'attributes-per-node 'attributes-per-node)
              (bounded? profile limits 'index-facts 'index-facts)
              (bounded? profile limits 'diagnostics 'diagnostics)
              (bounded? profile limits 'incremental-edits 'incremental-edits)
              (bounded? profile limits 'temporary-bytes 'temporary-bytes)
              (<= (estimated-retained-bytes profile limits)
                  (hash-ref limits 'retained-bytes))
              (<= (estimated-temporary-bytes profile)
                  (hash-ref limits 'temporary-bytes))))))

(define (estimated-retained-bytes profile [limits resource-limits])
  (+ (hash-ref profile 'source-bytes)
     (* (hash-ref profile 'nodes) 192)
     (* (hash-ref profile 'index-facts) 48)
     (* (hash-ref profile 'diagnostics)
        (+ 32 (hash-ref limits 'diagnostic-text-bytes)))))

(define (estimated-temporary-bytes profile)
  (hash-ref profile 'temporary-bytes))

(define (bounded? profile limits profile-key limit-key)
  (define value (hash-ref profile profile-key #f))
  (and (positive-exact-integer? value)
       (<= value (hash-ref limits limit-key))))

(define (positive-exact-integer? value)
  (and (exact-integer? value) (positive? value)))
