#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         racket/match)

(provide planning-configuration-limits
         admit-planning-configuration)

;; Configuration limits are subordinate to the stable operation resource limits.
(define planning-configuration-limits
  '#hasheq((workflows . 64)
           (workflow-states . 256)
           (source-sets . 64)
           (sources . 1024)
           (captures . 256)
           (agendas . 256)
           (configuration-bytes . 16777216)))

(define (bounded-text? value maximum)
  (and (string? value)
       (positive? (string-length value))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(define (unique-by? values key)
  (= (length values) (length (remove-duplicates (map key values)))))

(define (copy-text value)
  (string->immutable-string value))

(define (normalize-workflow-state state)
  (match state
    [(hash-table ('name name)
                 ('finished? (? boolean? finished?))
                 ('key key)
                 ('presentation presentation)
                 ('log log))
     (and (bounded-text? name 96)
          (or (not key) (char? key))
          (memq presentation '(todo active waiting done cancelled))
          (memq log '(none state note time))
          (hasheq 'name (copy-text name)
                  'finished? finished?
                  'key key
                  'presentation presentation
                  'log log))]
    [_ #f]))

(define (normalize-workflow candidate)
  (match candidate
    [(hash-table ('identity (? symbol? identity)) ('states states))
     (and (list? states)
          (pair? states)
          (<= (length states) (hash-ref planning-configuration-limits 'workflow-states))
          (let ([normalized (map normalize-workflow-state states)])
            (and (andmap values normalized)
                 (unique-by? normalized (lambda (state) (hash-ref state 'name)))
                 (ormap (lambda (state) (not (hash-ref state 'finished?))) normalized)
                 (ormap (lambda (state) (hash-ref state 'finished?)) normalized)
                 (hasheq 'identity identity 'states normalized))))]
    [_ #f]))

(define (normalize-source source)
  (match source
    [(hash-table ('identity (? symbol? identity))
                 ('kind (and kind (or 'file 'directory 'project 'workspace 'provider)))
                 ('resource resource)
                 ('depth (? exact-nonnegative-integer? depth))
                 ('document-limit (? exact-positive-integer? document-limit)))
     (and (bounded-text? resource 4096)
          (<= depth 64)
          (<= document-limit 1024)
          (hasheq 'identity identity
                  'kind kind
                  'resource (copy-text resource)
                  'depth depth
                  'document-limit document-limit))]
    [_ #f]))

(define (normalize-source-set candidate)
  (match candidate
    [(hash-table ('identity (? symbol? identity)) ('sources sources))
     (and (list? sources)
          (<= (length sources) (hash-ref planning-configuration-limits 'sources))
          (let ([normalized (map normalize-source sources)])
            (and (andmap values normalized)
                 (unique-by? normalized (lambda (source) (hash-ref source 'identity)))
                 (hasheq 'identity identity 'sources normalized))))]
    [_ #f]))

(define (normalize-capture candidate)
  (match candidate
    [(hash-table ('key (? char? key))
                 ('label label)
                 ('entry-type (or 'heading 'task 'item 'plain))
                 ('target target)
                 ('template template)
                 ('immediate-finish? (? boolean? immediate-finish?)))
     (and (bounded-text? label 128)
          (bounded-text? target 4096)
          (bounded-text? template 65536)
          (hasheq 'key key
                  'label (copy-text label)
                  'entry-type (hash-ref candidate 'entry-type)
                  'target (copy-text target)
                  'template (copy-text template)
                  'immediate-finish? immediate-finish?))]
    [_ #f]))

(define (normalize-agenda candidate)
  (match candidate
    [(hash-table ('key (? char? key))
                 ('label label)
                 ('query query)
                 ('span (or 'day 'week 'all))
                 ('result-limit (? exact-positive-integer? result-limit)))
     (and (bounded-text? label 128)
          (bounded-text? query 4096)
          (<= result-limit 65536)
          (hasheq 'key key
                  'label (copy-text label)
                  'query (copy-text query)
                  'span (hash-ref candidate 'span)
                  'result-limit result-limit))]
    [_ #f]))

(define (configuration-text-bytes value)
  (cond
    [(string? value) (bytes-length (string->bytes/utf-8 value))]
    [(hash? value) (for/sum ([(key item) (in-hash value)])
                     (+ (configuration-text-bytes key)
                        (configuration-text-bytes item)))]
    [(list? value) (for/sum ([item (in-list value)]) (configuration-text-bytes item))]
    [else 0]))

;; Admission validates and copies one complete generation before returning it.
(define (admit-planning-configuration candidate [confirmed-generation 0])
  (and (hash? candidate)
       (let ([generation (hash-ref candidate 'generation #f)]
             [provider-generation (hash-ref candidate 'provider-generation #f)]
             [workflows (hash-ref candidate 'workflows #f)]
             [source-sets (hash-ref candidate 'source-sets #f)]
             [captures (hash-ref candidate 'captures #f)]
             [agendas (hash-ref candidate 'agendas #f)])
         (and (exact-positive-integer? generation)
              (> generation confirmed-generation)
              (exact-positive-integer? provider-generation)
              (list? workflows)
              (pair? workflows)
              (list? source-sets)
              (list? captures)
              (list? agendas)
              (<= (length workflows) (hash-ref planning-configuration-limits 'workflows))
              (<= (length source-sets) (hash-ref planning-configuration-limits 'source-sets))
              (<= (length captures) (hash-ref planning-configuration-limits 'captures))
              (<= (length agendas) (hash-ref planning-configuration-limits 'agendas))
              (unique-by? workflows (lambda (item) (hash-ref item 'identity #f)))
              (unique-by? source-sets (lambda (item) (hash-ref item 'identity #f)))
              (unique-by? captures (lambda (item) (hash-ref item 'key #f)))
              (unique-by? agendas (lambda (item) (hash-ref item 'key #f)))
              (let ([normalized-workflows (map normalize-workflow workflows)]
                    [normalized-source-sets (map normalize-source-set source-sets)]
                    [normalized-captures (map normalize-capture captures)]
                    [normalized-agendas (map normalize-agenda agendas)])
                (and (andmap values normalized-workflows)
                     (andmap values normalized-source-sets)
                     (andmap values normalized-captures)
                     (andmap values normalized-agendas)
                     (<= (for/sum ([workflow (in-list normalized-workflows)])
                           (length (hash-ref workflow 'states)))
                         (hash-ref planning-configuration-limits 'workflow-states))
                     (<= (for/sum ([source-set (in-list normalized-source-sets)])
                           (length (hash-ref source-set 'sources)))
                         (hash-ref planning-configuration-limits 'sources))
                     (let ([result
                            (hasheq 'generation generation
                                    'provider-generation provider-generation
                                    'workflows normalized-workflows
                                    'source-sets normalized-source-sets
                                    'captures normalized-captures
                                    'agendas normalized-agendas)])
                       (and (<= (configuration-text-bytes result)
                                (hash-ref planning-configuration-limits
                                          'configuration-bytes))
                            result))))))))
