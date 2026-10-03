#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         racket/match
         racket/set)

(provide output-limits
         output-resource-profiles
         resolve-export-setting
         validate-include-graph
         expand-macros
         normalize-output-tree
         construct-publication-manifest
         incremental-output-current?
         admit-protocol-request
         reconcile-synchronization
         order-extensions
         plan-output-resource
         transition-output-lifecycle
         validate-output-resource-profile
         estimate-output-retained-bytes
         estimate-output-temporary-bytes)

(define output-limits
  '#hasheq((included-resources . 1024)
           (include-depth . 128)
           (macro-expansions . 4096)
           (normalized-nodes . 1048576)
           (output-bytes . 268435456)
           (diagnostics . 65536)
           (manifest-entries . 65536)
           (links . 16384)
           (publication-targets . 4096)
           (provider-operations . 128)
           (cache-bytes . 536870912)
           (protocol-payload-bytes . 1048576)
           (settings . 4096)
           (filters . 256)))

(define output-resource-profiles
  (list
   '#hasheq((name . ordinary) (included-resources . 8) (include-depth . 8)
            (macro-expansions . 64) (normalized-nodes . 4096)
            (output-bytes . 1048576) (diagnostics . 128) (manifest-entries . 256)
            (links . 128) (publication-targets . 8) (provider-operations . 2)
            (cache-bytes . 8388608) (protocol-payload-bytes . 65536)
            (settings . 64) (filters . 8))
   '#hasheq((name . demanding) (included-resources . 768) (include-depth . 96)
            (macro-expansions . 3072) (normalized-nodes . 786432)
            (output-bytes . 201326592) (diagnostics . 49152) (manifest-entries . 49152)
            (links . 12288) (publication-targets . 3072) (provider-operations . 96)
            (cache-bytes . 402653184) (protocol-payload-bytes . 786432)
            (settings . 3072) (filters . 192))
   '#hasheq((name . boundary) (included-resources . 1024) (include-depth . 128)
            (macro-expansions . 4096) (normalized-nodes . 1048576)
            (output-bytes . 268435456) (diagnostics . 65536) (manifest-entries . 65536)
            (links . 16384) (publication-targets . 4096) (provider-operations . 128)
            (cache-bytes . 536870912) (protocol-payload-bytes . 1048576)
            (settings . 4096) (filters . 256))))

;; Scalar settings use explicit precedence; additive settings retain source order.
(define (resolve-export-setting key backend candidates)
  (define matching
    (filter (lambda (candidate)
              (and (equal? (hash-ref candidate 'key #f) key)
                   (or (not (hash-ref candidate 'backend #f))
                       (equal? (hash-ref candidate 'backend) backend))))
            candidates))
  (and (pair? matching)
       (let ([additive? (hash-ref (car matching) 'additive? #f)])
         (and (andmap (lambda (candidate)
                        (eq? (hash-ref candidate 'additive? #f) additive?))
                      matching)
              (if additive?
                  (sort matching < #:key (lambda (candidate) (hash-ref candidate 'order 0)))
                  (argmax
                   (lambda (candidate)
                     (+ (* 100 (hash-ref candidate 'precedence 0))
                        (if (hash-ref candidate 'backend #f) 10 0)
                        (hash-ref candidate 'order 0)))
                   matching))))))

;; Includes require exact resources, acyclic parent chains, and stable ordering.
(define (validate-include-graph includes)
  (define ids (map (lambda (include) (hash-ref include 'resource #f)) includes))
  (define table (for/hasheq ([include (in-list includes)])
                  (values (hash-ref include 'resource) include)))
  (define (visit identity visiting visited)
    (cond [(member identity visiting) #f]
          [(member identity visited) visited]
          [else
           (define include (hash-ref table identity #f))
           (and include
                (let ([parent (hash-ref include 'parent #f)])
                  (if parent
                      (let ([next (visit parent (cons identity visiting) visited)])
                        (and next (cons identity next)))
                      (cons identity visited))))]))
  (and (<= (length includes) (hash-ref output-limits 'included-resources))
       (= (length ids) (length (remove-duplicates ids)))
       (andmap exact-positive-integer? ids)
       (for/and ([include (in-list includes)])
         (and (exact-positive-integer? (hash-ref include 'revision #f))
              (<= 1 (hash-ref include 'depth 0) (hash-ref output-limits 'include-depth))))
       (for/fold ([visited '()]) ([identity (in-list ids)] #:break (not visited))
         (visit identity '() visited))))

;; Macro expansion is inert, bounded, and rejects missing or recursive values.
(define (expand-macros invocations definitions)
  (and (<= (length invocations) (hash-ref output-limits 'macro-expansions))
       (let loop ([remaining invocations] [visiting '()] [output '()] [bytes 0])
         (cond
           [(null? remaining) (hasheq 'fragments (reverse output) 'bytes bytes 'complete? #t)]
           [else
            (define invocation (car remaining))
            (define identity (hash-ref invocation 'identity #f))
            (define definition (hash-ref definitions identity #f))
            (and definition
                 (not (member identity visiting))
                 (bytes? (hash-ref definition 'expansion #f))
                 (let* ([fragment (hash-ref definition 'expansion)]
                        [next-bytes (+ bytes (bytes-length fragment))])
                   (and (<= next-bytes (hash-ref output-limits 'output-bytes))
                        (loop (cdr remaining) visiting (cons fragment output) next-bytes))))]))))

;; Normalization returns copied nodes and never retains parser objects.
(define (normalize-output-tree source nodes policy)
  (and (bytes? source)
       (list? nodes)
       (<= (length nodes) (hash-ref output-limits 'normalized-nodes))
       (for/and ([node (in-list nodes)])
         (and (symbol? (hash-ref node 'kind #f))
              (exact-nonnegative-integer? (hash-ref node 'start #f))
              (<= (hash-ref node 'start) (hash-ref node 'end #f) (bytes-length source))))
       (let ([selected
              (filter (lambda (node)
                        (and (or (hash-ref policy 'comments? #f)
                                 (not (eq? (hash-ref node 'kind) 'comment)))
                             (or (hash-ref policy 'archived? #f)
                                 (not (hash-ref node 'archived? #f)))
                             (not (set-member? (hash-ref policy 'excluded-tags (set))
                                               (hash-ref node 'tag #f)))))
                      nodes)])
         (hasheq 'nodes (map hash-copy selected)
                 'node-count (length selected)
                 'complete? #t))))

;; Publication manifests account for every checked candidate before effects.
(define (construct-publication-manifest identity scope outputs)
  (and (exact-positive-integer? identity)
       (hash? scope)
       (pair? outputs)
       (<= (length outputs) (hash-ref output-limits 'manifest-entries))
       (for/and ([output (in-list outputs)])
         (and (exact-positive-integer? (hash-ref output 'resource #f))
              (bytes? (hash-ref output 'digest #f))
              (positive? (bytes-length (hash-ref output 'digest)))))
       (hasheq 'identity identity 'scope (hash-copy scope)
               'outputs (map hash-copy outputs) 'state 'candidate 'complete? #t)))

;; Incremental reuse requires complete semantic, provider, settings, and tool equality.
(define (incremental-output-current? cached requested)
  (and (hash? cached) (hash? requested)
       (for/and ([key (in-list '(source dependencies backend filters settings tools))])
         (equal? (hash-ref cached key #f) (hash-ref requested key #f)))))

;; Protocol inputs are bounded and explicit before decoding or transport.
(define (admit-protocol-request request)
  (and (hash? request)
       (hash-ref request 'explicit? #f)
       (exact-positive-integer? (hash-ref request 'provider-generation #f))
       (bytes? (hash-ref request 'payload #f))
       (<= (bytes-length (hash-ref request 'payload))
           (hash-ref output-limits 'protocol-payload-bytes))
       (hash-copy request)))

;; Synchronization never overwrites a divergent entry without a decision.
(define (reconcile-synchronization entries)
  (and (list? entries)
       (<= (length entries) (hash-ref output-limits 'manifest-entries))
       (let ([conflicts
              (filter (lambda (entry)
                        (and (not (equal? (hash-ref entry 'base) (hash-ref entry 'local)))
                             (not (equal? (hash-ref entry 'base) (hash-ref entry 'remote)))
                             (not (equal? (hash-ref entry 'local) (hash-ref entry 'remote)))))
                      entries)])
         (hasheq 'entries (length entries) 'conflicts (length conflicts)
                 'state (if (null? conflicts) 'applied 'conflicted)))))

;; Extensions order by explicit priority and stable identity after whole-set validation.
(define (order-extensions extensions)
  (and (<= (length extensions) (hash-ref output-limits 'provider-operations))
       (= (length extensions)
          (length (remove-duplicates (map (lambda (extension) (hash-ref extension 'identity #f))
                                          extensions))))
       (andmap (lambda (extension)
                 (and (symbol? (hash-ref extension 'identity #f))
                      (exact-integer? (hash-ref extension 'priority #f))
                      (exact-positive-integer? (hash-ref extension 'generation #f))))
               extensions)
       (sort extensions
             (lambda (left right)
               (or (< (hash-ref left 'priority) (hash-ref right 'priority))
                   (and (= (hash-ref left 'priority) (hash-ref right 'priority))
                        (symbol<? (hash-ref left 'identity) (hash-ref right 'identity))))))))

;; Resource planning returns a checked candidate and performs no write.
(define (plan-output-resource destination bytes expected-revision overwrite?)
  (and (exact-positive-integer? destination)
       (bytes? bytes)
       (<= (bytes-length bytes) (hash-ref output-limits 'output-bytes))
       (exact-positive-integer? expected-revision)
       (hasheq 'resource destination 'expected-revision expected-revision
               'bytes (bytes-copy bytes) 'overwrite? overwrite? 'complete? #t)))

(define (transition-output-lifecycle state event)
  (case state
    [(prepared) (and (memq event '(confirmed cancelled failed)) event)]
    [(confirmed) (and (memq event '(active cancelled failed)) event)]
    [(active) (and (memq event '(completed cancelled failed reconciliation-required)) event)]
    [(completed cancelled failed reconciliation-required) (and (eq? event 'closed) 'closed)]
    [else #f]))

(define (validate-output-resource-profile profile)
  (and (hash? profile)
       (for/and ([(key limit) (in-hash output-limits)])
         (define value (hash-ref profile key #f))
         (and (exact-positive-integer? value) (<= value limit)))))

(define (estimate-output-retained-bytes profile)
  (+ (hash-ref profile 'cache-bytes)
     (hash-ref profile 'output-bytes)
     (* (hash-ref profile 'manifest-entries) 96)
     (* (hash-ref profile 'diagnostics) 64)))

(define (estimate-output-temporary-bytes profile)
  (+ (* (hash-ref profile 'included-resources) 128)
     (* (hash-ref profile 'macro-expansions) 96)
     (* (hash-ref profile 'normalized-nodes) 64)
     (* (hash-ref profile 'links) 80)
     (* (hash-ref profile 'publication-targets) 128)))
