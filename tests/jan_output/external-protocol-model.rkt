#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         racket/match
         racket/string)

(provide plan-link-operation
         admit-external-protocol
         dispatch-result-valid?)

(define protocol-schema-version 1)
(define payload-limit 1048576)
(define output-limit 268435456)
(define result-limit 16384)
(define validity-window 900)
(define value-kinds '(url title body selection annotation))

(define action-capability
  '#hasheq((follow . follow-link)
           (store . store-link)
           (search . search-links)
           (preview . preview-link)
           (media-intake . intake-media)
           (store-link . store-link)
           (start-capture . start-capture)
           (open-source . open-source)))

(define (bounded-text? value maximum)
  (and (string? value)
       (positive? (string-length value))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(define (select-provider request providers)
  (define identity (hash-ref request 'provider #f))
  (define generation (hash-ref request 'provider-generation #f))
  (define matches
    (filter (lambda (provider)
              (and (eq? (hash-ref provider 'identity #f) identity)
                   (equal? (hash-ref provider 'generation #f) generation)))
            providers))
  (and (= (length matches) 1)
       (let ([provider (car matches)]
             [capability (hash-ref action-capability (hash-ref request 'action #f) #f)])
         (and capability
              (hash-ref provider 'admitted? #f)
              (eq? (hash-ref provider 'state #f) 'available)
              (member capability (hash-ref provider 'capabilities '()))
              (= (hash-ref request 'authentication-generation 0)
                 (hash-ref provider 'authentication-generation -1))
              provider))))

(define (link-shape-valid? request)
  (define action (hash-ref request 'action #f))
  (define locator (hash-ref request 'locator #f))
  (define query (hash-ref request 'query #f))
  (define source (hash-ref request 'source #f))
  (define source-revision (hash-ref request 'source-revision #f))
  (define destination (hash-ref request 'destination #f))
  (define destination-revision (hash-ref request 'destination-revision #f))
  (define bytes (hash-ref request 'byte-limit 0))
  (define results (hash-ref request 'result-limit 0))
  (and (exact-positive-integer? bytes) (<= bytes output-limit)
       (exact-positive-integer? results) (<= results result-limit)
       (case action
         [(follow preview) (and (bounded-text? locator 4096) (not query)
                                (not source) (not destination))]
         [(store) (and (exact-positive-integer? source)
                       (exact-positive-integer? source-revision)
                       (not locator) (not query) (not destination))]
         [(search) (and (bounded-text? query 4096) (not locator)
                        (not source) (not destination))]
         [(media-intake) (and (bounded-text? locator 4096) (not query) (not source)
                              (exact-positive-integer? destination)
                              (exact-positive-integer? destination-revision))]
         [else #f])))

(define (plan-link-operation request providers)
  (define provider (select-provider request providers))
  (and provider
       (hash-ref request 'explicit? #f)
       (not (hash-ref request 'cancelled? #f))
       (hash-ref request 'authenticated? #f)
       (link-shape-valid? request)
       (let ([action (hash-ref request 'action)])
         (hasheq 'operation (hash-ref request 'operation)
                 'action action
                 'provider (hash-ref provider 'identity)
                 'provider-generation (hash-ref provider 'generation)
                 'resource-read? #t
                 'resource-write? (eq? action 'media-intake)
                 'navigation? (eq? action 'follow)
                 'preview? (eq? action 'preview)
                 'byte-limit (hash-ref request 'byte-limit)
                 'result-limit (hash-ref request 'result-limit)))))

(define (values-valid? values payload-bytes)
  (and (list? values)
       (<= (length values) 256)
       (= (length values) (length (remove-duplicates (map (lambda (value) (hash-ref value 'kind #f)) values))))
       (andmap (lambda (value)
                 (and (memq (hash-ref value 'kind #f) value-kinds)
                      (bounded-text? (hash-ref value 'value #f) 65536)
                      (boolean? (hash-ref value 'sensitive? #f))))
               values)
       (<= (for/sum ([value (in-list values)])
             (bytes-length (string->bytes/utf-8 (hash-ref value 'value))))
           payload-bytes)))

(define (external-shape-valid? request)
  (define action (hash-ref request 'action #f))
  (define values (hash-ref request 'values #f))
  (and (values-valid? values (hash-ref request 'payload-bytes 0))
       (case action
         [(store-link)
          (and (bounded-text? (hash-ref request 'locator #f) 4096)
               (andmap (lambda (value) (memq (hash-ref value 'kind) '(title annotation))) values))]
         [(start-capture)
          (and (symbol? (hash-ref request 'template #f))
               (exact-positive-integer? (hash-ref request 'template-generation #f)))]
         [(open-source)
          (and (exact-positive-integer? (hash-ref request 'target #f))
               (exact-positive-integer? (hash-ref request 'target-revision #f))
               (memq (hash-ref request 'location-kind #f) '(source-block structural-node))
               (bounded-text? (hash-ref request 'location #f) 4096)
               (null? values))]
         [else #f])))

(define (admit-external-protocol request providers replay-records)
  (define issued (hash-ref request 'issued-at 0))
  (define expires (hash-ref request 'expires-at 0))
  (define observed (hash-ref request 'observed-at 0))
  (define provider (select-provider request providers))
  (define replayed?
    (for/or ([record (in-list replay-records)])
      (and (eq? (hash-ref record 'caller #f) (hash-ref request 'caller #f))
           (= (hash-ref record 'caller-generation 0) (hash-ref request 'caller-generation -1))
           (or (= (hash-ref record 'operation 0) (hash-ref request 'operation -1))
               (equal? (hash-ref record 'nonce #f) (hash-ref request 'nonce #f))))))
  (and (= (hash-ref request 'schema 0) protocol-schema-version)
       (exact-positive-integer? (hash-ref request 'operation #f))
       (exact-positive-integer? (hash-ref request 'provider-generation #f))
       (exact-positive-integer? (hash-ref request 'caller-generation #f))
       (exact-positive-integer? (hash-ref request 'authentication-generation #f))
       (hash-ref request 'authenticated? #f)
       (hash-ref request 'explicit? #f)
       (not (hash-ref request 'cancelled? #f))
       (bounded-text? (hash-ref request 'caller-instance #f) 4096)
       (bytes? (hash-ref request 'nonce #f)) (positive? (bytes-length (hash-ref request 'nonce)))
       (bytes? (hash-ref request 'payload-digest #f))
       (positive? (bytes-length (hash-ref request 'payload-digest)))
       (exact-positive-integer? (hash-ref request 'payload-bytes #f))
       (<= (hash-ref request 'payload-bytes) payload-limit)
       (<= issued observed expires) (<= (- expires issued) validity-window)
       provider (not replayed?) (external-shape-valid? request)
       (let* ([action (hash-ref request 'action)]
              [values (hash-ref request 'values)]
              [plan (hasheq 'operation (hash-ref request 'operation)
                            'action action
                            'provider (hash-ref provider 'identity)
                            'provider-generation (hash-ref provider 'generation)
                            'schema protocol-schema-version
                            'caller (hash-ref request 'caller)
                            'caller-instance (hash-ref request 'caller-instance)
                            'caller-generation (hash-ref request 'caller-generation)
                            'authentication-generation (hash-ref request 'authentication-generation)
                            'nonce (hash-ref request 'nonce)
                            'payload-digest (hash-ref request 'payload-digest)
                            'value-count (length values)
                            'sensitive-value-count
                            (count (lambda (value) (hash-ref value 'sensitive?)) values)
                            'link-state-change? (eq? action 'store-link)
                            'document-change? (eq? action 'start-capture)
                            'navigation? (eq? action 'open-source))]
              [replay (hasheq 'caller (hash-ref request 'caller)
                              'caller-generation (hash-ref request 'caller-generation)
                              'operation (hash-ref request 'operation)
                              'nonce (hash-ref request 'nonce)
                              'expires-at expires
                              'state 'reserved)])
         (hasheq 'plan plan 'replay replay))))

(define (dispatch-result-valid? plan result)
  (and (= (hash-ref plan 'operation) (hash-ref result 'operation -1))
       (eq? (hash-ref plan 'provider) (hash-ref result 'provider #f))
       (= (hash-ref plan 'provider-generation) (hash-ref result 'provider-generation -1))
       (case (hash-ref result 'state #f)
         [(failed cancelled)
          (and (not (hash-ref result 'complete? #f))
               (not (hash-ref result 'link-state-changed? #f))
               (not (hash-ref result 'document-changed? #f))
               (not (hash-ref result 'navigation-changed? #f)))]
         [(completed)
          (and (hash-ref result 'complete? #f)
               (equal? (hash-ref plan 'link-state-change?) (hash-ref result 'link-state-changed? #f))
               (equal? (hash-ref plan 'document-change?) (hash-ref result 'document-changed? #f))
               (equal? (hash-ref plan 'navigation?) (hash-ref result 'navigation-changed? #f)))]
         [else #f])))
