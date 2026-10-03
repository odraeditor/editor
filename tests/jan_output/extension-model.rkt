#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         racket/match
         racket/string)

(provide extension-families
         admit-extension-generation
         plan-extension-invocation
         extension-result-valid?
         inspect-extension-catalog
         extension-conformance-complete?)

(define extension-families
  '(hook package property-reader property-writer tree-mapper agenda-source
         agenda-view capture-template capture-value custom-link export-backend derived-backend
         export-filter citation-processor table-translator dynamic-block
         execution-adapter publishing-provider synchronization-provider))

(define family-operations
  '#hasheq((hook . (run-hook))
           (package . (compose-package))
           (property-reader . (read-property))
           (property-writer . (write-property))
           (tree-mapper . (map-tree))
           (agenda-source . (supply-agenda search-agenda))
           (agenda-view . (render-agenda enrich-agenda))
           (capture-template . (supply-capture-template))
           (capture-value . (supply-capture-value))
           (custom-link . (parse-link complete-link follow-link store-link export-link preview-link))
           (export-backend . (render-backend))
           (derived-backend . (render-backend))
           (export-filter . (filter-output))
           (citation-processor . (resolve-citation))
           (table-translator . (translate-table))
           (dynamic-block . (write-dynamic-block))
           (execution-adapter . (execute-source))
           (publishing-provider . (publish))
           (synchronization-provider . (synchronize))))

(define family-boundaries
  '#hasheq((hook . (read-only document-candidate))
           (package . (read-only result-value))
           (property-reader . (read-only result-value))
           (property-writer . (document-candidate))
           (tree-mapper . (read-only result-value))
           (agenda-source . (read-only result-value))
           (agenda-view . (read-only result-value))
           (capture-template . (read-only result-value))
           (capture-value . (read-only result-value))
           (custom-link . (result-value document-candidate resource-candidate))
           (export-backend . (result-value resource-candidate))
           (derived-backend . (result-value resource-candidate))
           (export-filter . (result-value resource-candidate))
           (citation-processor . (result-value resource-candidate))
           (table-translator . (result-value resource-candidate))
           (dynamic-block . (document-candidate))
           (execution-adapter . (result-value document-candidate resource-candidate))
           (publishing-provider . (result-value resource-candidate))
           (synchronization-provider . (result-value document-candidate resource-candidate))))

(define extension-authorities
  '(inspect document-read resource-read propose-document-edit propose-resource
            process network credential))
(define extension-sources '(factory package user workspace project))
(define extension-states '(declared available unavailable))
(define failure-policies '(continue abort-operation disable-provider))

(define (bounded-symbol? value [maximum 96])
  (and (symbol? value)
       (positive? (string-length (symbol->string value)))
       (<= (bytes-length (string->bytes/utf-8 (symbol->string value))) maximum)))

(define (unique? values)
  (= (length values) (length (remove-duplicates values))))

(define (symbol-list-subset? requested available)
  (and (list? requested) (andmap (lambda (value) (memq value available)) requested)))

(define (source-rank source)
  (or (index-of extension-sources source) +inf.0))

(define (provider<? left right)
  (define left-family (index-of extension-families (hash-ref left 'family)))
  (define right-family (index-of extension-families (hash-ref right 'family)))
  (cond
    [(< left-family right-family) #t]
    [(> left-family right-family) #f]
    [(< (hash-ref left 'order) (hash-ref right 'order)) #t]
    [(> (hash-ref left 'order) (hash-ref right 'order)) #f]
    [(< (source-rank (hash-ref left 'source)) (source-rank (hash-ref right 'source))) #t]
    [(> (source-rank (hash-ref left 'source)) (source-rank (hash-ref right 'source))) #f]
    [else (symbol<? (hash-ref left 'identity) (hash-ref right 'identity))]))

(define (normalize-provider candidate)
  (and (hash? candidate)
       (let* ([identity (hash-ref candidate 'identity #f)]
              [generation (hash-ref candidate 'generation #f)]
              [family (hash-ref candidate 'family #f)]
              [source (hash-ref candidate 'source #f)]
              [order (hash-ref candidate 'order #f)]
              [api-version (hash-ref candidate 'api-version #f)]
              [operations (hash-ref candidate 'operations #f)]
              [authorities (hash-ref candidate 'authorities #f)]
              [boundary (hash-ref candidate 'boundary #f)]
              [failure-policy (hash-ref candidate 'failure-policy #f)]
              [parent (hash-ref candidate 'parent #f)]
              [parent-generation (hash-ref candidate 'parent-generation 0)]
              [input-limit (hash-ref candidate 'input-limit #f)]
              [input-bytes (hash-ref candidate 'input-bytes #f)]
              [result-limit (hash-ref candidate 'result-limit #f)]
              [output-bytes (hash-ref candidate 'output-bytes #f)]
              [temporary-limit (hash-ref candidate 'temporary-limit #f)]
              [state (hash-ref candidate 'state #f)]
              [admitted? (hash-ref candidate 'admitted? #f)])
         (and (bounded-symbol? identity)
              (exact-positive-integer? generation)
              (memq family extension-families)
              (memq source extension-sources)
              (exact-integer? order)
              (equal? api-version 1)
              (list? operations) (pair? operations) (unique? operations)
              (symbol-list-subset? operations (hash-ref family-operations family))
              (list? authorities) (pair? authorities) (unique? authorities)
              (symbol-list-subset? authorities extension-authorities)
              (memq 'inspect authorities)
              (memq boundary (hash-ref family-boundaries family))
              (eq? (eq? boundary 'document-candidate)
                   (and (memq 'propose-document-edit authorities) #t))
              (eq? (eq? boundary 'resource-candidate)
                   (and (memq 'propose-resource authorities) #t))
              (memq failure-policy failure-policies)
              (or (and (eq? family 'derived-backend)
                       (bounded-symbol? parent)
                       (not (eq? parent identity))
                       (exact-positive-integer? parent-generation))
                  (and (not (eq? family 'derived-backend))
                       (not parent) (zero? parent-generation)))
              (exact-positive-integer? input-limit) (<= input-limit 4096)
              (exact-positive-integer? input-bytes) (<= input-bytes (* 16 1024 1024))
              (exact-positive-integer? result-limit) (<= result-limit 4096)
              (exact-positive-integer? output-bytes) (<= output-bytes (* 16 1024 1024))
              (exact-nonnegative-integer? temporary-limit) (<= temporary-limit 256)
              (memq state extension-states)
              (boolean? admitted?)
              (hasheq 'identity identity 'generation generation 'family family
                      'source source 'order order 'api-version api-version
                      'operations (append operations '())
                      'authorities (append authorities '())
                      'boundary boundary 'failure-policy failure-policy
                      'parent parent 'parent-generation parent-generation
                      'input-limit input-limit 'input-bytes input-bytes
                      'result-limit result-limit
                      'output-bytes output-bytes 'temporary-limit temporary-limit
                      'state state 'admitted? admitted?)))))

(define (derived-chain-valid? provider providers)
  (let loop ([current provider] [seen '()])
    (case (hash-ref current 'family)
      [(export-backend) #t]
      [(derived-backend)
       (define identity (hash-ref current 'identity))
       (define parent-identity (hash-ref current 'parent))
       (define parent-generation (hash-ref current 'parent-generation))
       (and (not (memq identity seen))
            (let ([matches
                   (filter (lambda (candidate)
                             (and (eq? (hash-ref candidate 'identity) parent-identity)
                                  (= (hash-ref candidate 'generation) parent-generation)))
                           providers)])
              (and (= (length matches) 1)
                   (loop (car matches) (cons identity seen)))))]
      [else #f])))

;; admit-extension-generation validates, copies, and deterministically orders one generation.
(define (admit-extension-generation candidate [confirmed-generation 0])
  (and (hash? candidate)
       (let ([generation (hash-ref candidate 'generation #f)]
             [replaces (hash-ref candidate 'replaces-generation #f)]
             [configuration-generation (hash-ref candidate 'configuration-generation #f)]
             [providers (hash-ref candidate 'providers #f)])
         (and (exact-positive-integer? generation) (> generation confirmed-generation)
              (exact-nonnegative-integer? replaces) (= replaces confirmed-generation)
              (exact-positive-integer? configuration-generation)
              (list? providers) (pair? providers) (<= (length providers) 128)
              (let ([normalized (map normalize-provider providers)])
                (and (andmap values normalized)
                     (unique? (map (lambda (provider) (hash-ref provider 'identity)) normalized))
                     (andmap (lambda (provider)
                               (or (not (eq? (hash-ref provider 'family) 'derived-backend))
                                   (derived-chain-valid? provider normalized)))
                             normalized)
                     (hasheq 'generation generation
                             'configuration-generation configuration-generation
                             'providers (sort normalized provider<?))))))))

;; plan-extension-invocation selects one exact provider without granting undeclared authority.
(define (plan-extension-invocation request catalog)
  (and (hash? request) (hash? catalog)
       (= (hash-ref request 'catalog-generation 0) (hash-ref catalog 'generation -1))
       (= (hash-ref request 'configuration-generation 0)
          (hash-ref catalog 'configuration-generation -1))
       (hash-ref request 'explicit? #f)
       (not (hash-ref request 'cancelled? #t))
       (let* ([identity (hash-ref request 'provider #f)]
              [matches (filter (lambda (provider) (eq? (hash-ref provider 'identity) identity))
                               (hash-ref catalog 'providers '()))])
         (and (= (length matches) 1)
              (let ([provider (car matches)]
                    [operation (hash-ref request 'operation #f)]
                    [granted (hash-ref request 'authorities #f)]
                    [input-count (hash-ref request 'input-count #f)]
                    [input-bytes (hash-ref request 'input-bytes #f)]
                    [result-limit (hash-ref request 'result-limit #f)]
                    [output-bytes (hash-ref request 'output-bytes #f)]
                    [temporary-limit (hash-ref request 'temporary-limit #f)])
                (and (= (hash-ref request 'provider-generation 0)
                        (hash-ref provider 'generation))
                     (eq? (hash-ref request 'family #f) (hash-ref provider 'family))
                     (eq? (hash-ref provider 'state) 'available)
                     (hash-ref provider 'admitted? #f)
                     (memq operation (hash-ref provider 'operations))
                     (list? granted) (pair? granted) (unique? granted)
                     (memq 'inspect granted)
                     (symbol-list-subset? granted (hash-ref provider 'authorities))
                     (exact-positive-integer? (hash-ref request 'resource #f))
                     (exact-positive-integer? (hash-ref request 'revision #f))
                     (exact-positive-integer? input-count)
                     (<= input-count (hash-ref provider 'input-limit))
                     (exact-positive-integer? input-bytes)
                     (<= input-bytes (hash-ref provider 'input-bytes))
                     (exact-positive-integer? result-limit)
                     (<= result-limit (hash-ref provider 'result-limit))
                     (exact-positive-integer? output-bytes)
                     (<= output-bytes (hash-ref provider 'output-bytes))
                     (exact-nonnegative-integer? temporary-limit)
                     (<= temporary-limit (hash-ref provider 'temporary-limit))
                     (hasheq 'operation (hash-ref request 'operation-id)
                             'catalog-generation (hash-ref catalog 'generation)
                             'configuration-generation
                             (hash-ref catalog 'configuration-generation)
                             'provider identity
                             'provider-generation (hash-ref provider 'generation)
                             'family (hash-ref provider 'family)
                             'entrypoint operation
                             'resource (hash-ref request 'resource)
                             'revision (hash-ref request 'revision)
                             'authorities (append granted '())
                             'boundary (hash-ref provider 'boundary)
                             'failure-policy (hash-ref provider 'failure-policy)
                             'input-count input-count 'input-bytes input-bytes
                             'result-limit result-limit
                             'output-bytes output-bytes
                             'temporary-limit temporary-limit)))))))

;; extension-result-valid? accepts only values or unapplied candidates with complete cleanup.
(define (extension-result-valid? plan result)
  (and (hash? plan) (hash? result)
       (= (hash-ref result 'operation 0) (hash-ref plan 'operation -1))
       (eq? (hash-ref result 'provider #f) (hash-ref plan 'provider))
       (= (hash-ref result 'provider-generation 0) (hash-ref plan 'provider-generation))
       (not (hash-ref result 'mutated-directly? #t))
       (= (hash-ref result 'temporary-created -1) (hash-ref result 'temporary-cleaned -2))
       (<= (hash-ref result 'temporary-created +inf.0) (hash-ref plan 'temporary-limit))
       (zero? (hash-ref result 'retained-native-bytes -1))
       (case (hash-ref result 'state #f)
         [(failed cancelled unavailable)
          (and (not (hash-ref result 'complete? #t))
               (zero? (hash-ref result 'result-count -1))
               (zero? (hash-ref result 'result-bytes -1))
               (eq? (hash-ref result 'candidate #f) 'none))]
         [(completed)
          (and (hash-ref result 'complete? #f)
               (exact-positive-integer? (hash-ref result 'result-count #f))
               (<= (hash-ref result 'result-count) (hash-ref plan 'result-limit))
               (exact-nonnegative-integer? (hash-ref result 'result-bytes #f))
               (<= (hash-ref result 'result-bytes) (hash-ref plan 'output-bytes))
               (case (hash-ref plan 'boundary)
                 [(read-only result-value) (eq? (hash-ref result 'candidate #f) 'none)]
                 [(document-candidate resource-candidate)
                  (and (eq? (hash-ref result 'candidate)
                            (if (eq? (hash-ref plan 'boundary) 'document-candidate)
                                'document 'resource))
                       (exact-positive-integer? (hash-ref result 'candidate-id #f))
                       (= (hash-ref result 'expected-revision 0)
                          (hash-ref plan 'revision)))]
                 [else #f]))]
         [else #f])))

;; inspect-extension-catalog returns stable declaration-only provider records.
(define (inspect-extension-catalog catalog)
  (for/list ([provider (in-list (hash-ref catalog 'providers))])
    (hasheq 'catalog-generation (hash-ref catalog 'generation)
            'identity (hash-ref provider 'identity)
            'generation (hash-ref provider 'generation)
            'family (hash-ref provider 'family)
            'source (hash-ref provider 'source)
            'order (hash-ref provider 'order)
            'operations (hash-ref provider 'operations)
            'authorities (hash-ref provider 'authorities)
            'boundary (hash-ref provider 'boundary)
            'failure-policy (hash-ref provider 'failure-policy)
            'state (hash-ref provider 'state)
            'active? (and (hash-ref provider 'admitted?)
                          (eq? (hash-ref provider 'state) 'available)))))

;; extension-conformance-complete? checks all families and cross-cutting safety evidence.
(define (extension-conformance-complete? catalog evidence)
  (and (equal? (sort (remove-duplicates
                      (map (lambda (provider) (hash-ref provider 'family))
                           (hash-ref catalog 'providers)))
                     symbol<?)
               (sort extension-families symbol<?))
       (for/and ([field (in-list '(copied-values? deterministic-order? stale-rejection?
                                  authority-constrained? mutation-candidate-only?
                                  failure-contained? limits-enforced? cleanup-complete?
                                  inspection-complete?))])
         (hash-ref evidence field #f))))
