#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         racket/match)

(provide computation-configuration-limits
         admit-computation-configuration)

;; Configuration limits remain subordinate to the stable computation ceilings.
(define computation-configuration-limits
  '#hasheq((adapters . 256)
           (policies . 1024)
           (configuration-bytes . 16777216)
           (identity-bytes . 96)
           (version-bytes . 128)))

(define stable-limits
  '#hasheq((table-cells . 65536)
           (formula-dependencies . 16384)
           (graph-depth . 1024)
           (executable-targets . 4096)
           (active-sessions . 64)
           (child-processes . 32)
           (output-bytes . 67108864)
           (retained-output-bytes . 268435456)
           (generated-files . 4096)
           (result-rows . 16384)
           (cache-bytes . 268435456)))

(define mandatory-limits '(elapsed-milliseconds cpu-milliseconds rss-bytes environment-entries))
(define known-effects '(read-resource write-resource network child-process environment credential))

(define (bounded-text? value maximum)
  (and (string? value)
       (positive? (string-length value))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(define (unique-by? values key)
  (= (length values) (length (remove-duplicates (map key values)))))

(define (copy-text value)
  (string->immutable-string value))

(define (normalize-limits limits)
  (and (hash? limits)
       (for/and ([(key ceiling) (in-hash stable-limits)])
         (define value (hash-ref limits key #f))
         (and (exact-positive-integer? value) (<= value ceiling)))
       (for/and ([key (in-list mandatory-limits)])
         (exact-positive-integer? (hash-ref limits key #f)))
       (for/hasheq ([(key value) (in-hash limits)]) (values key value))))

(define (normalize-adapter candidate)
  (match candidate
    [(hash-table ('identity identity)
                 ('language language)
                 ('version version)
                 ('class (and class (or 'factory-adapter 'configured-provider)))
                 ('in-process? (? boolean? in-process?))
                 ('runtime-required? (? boolean? runtime-required?))
                 ('limits limits))
     (define normalized-limits (normalize-limits limits))
     (and (bounded-text? identity 96)
          (bounded-text? language 96)
          (bounded-text? version 128)
          normalized-limits
          (hasheq 'identity (copy-text identity)
                  'language (copy-text language)
                  'version (copy-text version)
                  'class class
                  'in-process? in-process?
                  'runtime-required? runtime-required?
                  'limits normalized-limits))]
    [_ #f]))

(define (normalize-policy candidate)
  (and (hash? candidate)
       (let ([identity (hash-ref candidate 'identity #f)]
             [adapter (hash-ref candidate 'adapter "")]
             [language (hash-ref candidate 'language #f)]
             [origin (hash-ref candidate 'origin #f)]
             [interactive (hash-ref candidate 'interactive #f)]
             [batch (hash-ref candidate 'batch #f)]
             [effects (hash-ref candidate 'effects #f)])
         (and (bounded-text? identity 96)
              (or (equal? adapter "") (bounded-text? adapter 96))
              (bounded-text? language 96)
              (memq origin '(factory user workspace project document external))
              (memq interactive '(deny confirm allow))
              (memq batch '(deny allow))
              (list? effects)
              (andmap (lambda (effect) (memq effect known-effects)) effects)
              (= (length effects) (length (remove-duplicates effects)))
              (hasheq 'identity (copy-text identity)
                      'adapter (copy-text adapter)
                      'language (copy-text language)
                      'origin origin
                      'interactive interactive
                      'batch batch
                      'effects effects)))))

(define (configuration-text-bytes value)
  (cond
    [(string? value) (bytes-length (string->bytes/utf-8 value))]
    [(hash? value) (for/sum ([(key item) (in-hash value)])
                     (+ (configuration-text-bytes key) (configuration-text-bytes item)))]
    [(list? value) (for/sum ([item (in-list value)]) (configuration-text-bytes item))]
    [else 0]))

;; Admission validates and copies one complete adapter and policy generation.
(define (admit-computation-configuration candidate
                                          [confirmed-generation 0]
                                          [confirmed-adapter-generation 0]
                                          [confirmed-policy-generation 0])
  (and (hash? candidate)
       (let ([generation (hash-ref candidate 'generation #f)]
             [adapter-generation (hash-ref candidate 'adapter-generation #f)]
             [policy-generation (hash-ref candidate 'policy-generation #f)]
             [adapters (hash-ref candidate 'adapters #f)]
             [policies (hash-ref candidate 'policies #f)])
         (and (exact-positive-integer? generation)
              (> generation confirmed-generation)
              (exact-positive-integer? adapter-generation)
              (> adapter-generation confirmed-adapter-generation)
              (exact-positive-integer? policy-generation)
              (> policy-generation confirmed-policy-generation)
              (list? adapters)
              (pair? adapters)
              (list? policies)
              (pair? policies)
              (<= (length adapters) (hash-ref computation-configuration-limits 'adapters))
              (<= (length policies) (hash-ref computation-configuration-limits 'policies))
              (let ([normalized-adapters (map normalize-adapter adapters)]
                    [normalized-policies (map normalize-policy policies)])
                (and (andmap values normalized-adapters)
                     (andmap values normalized-policies)
                     (unique-by? normalized-adapters (lambda (item) (hash-ref item 'identity)))
                     (unique-by? normalized-adapters (lambda (item) (hash-ref item 'language)))
                     (unique-by? normalized-policies (lambda (item) (hash-ref item 'identity)))
                     (let ([result
                            (hasheq 'generation generation
                                    'adapter-generation adapter-generation
                                    'policy-generation policy-generation
                                    'adapters normalized-adapters
                                    'policies normalized-policies)])
                       (and (<= (configuration-text-bytes result)
                                (hash-ref computation-configuration-limits 'configuration-bytes))
                            result))))))))
