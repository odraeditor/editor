#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         "../command/native-contracts.rkt"
         (prefix-in cap: "scoped-capability.rkt"))

(provide
 (struct-out layout-handle)
 (struct-out pane-handle)
 (struct-out layout-rect)
 (struct-out layout-pane-geometry)
 (struct-out layout-node)
 (struct-out layout-scope)
 (struct-out layout-snapshot)
 (struct-out layout-outcome)
 (struct-out layout-failure)
 (contract-out
  [layout-control? (-> any/c boolean?)]
  [call-with-layout-control
   (-> exact-positive-integer? exact-positive-integer?
       (-> layout-control? any/c) any/c)]
  [layout-inspect (-> layout-control? (or/c layout-snapshot? layout-failure?))]
  [layout-split-below
   (-> layout-control? pane-handle? (or/c layout-outcome? layout-failure?))]
  [layout-split-right
   (-> layout-control? pane-handle? (or/c layout-outcome? layout-failure?))]
  [layout-focus
   (-> layout-control? pane-handle? (or/c layout-outcome? layout-failure?))]
  [layout-close
   (-> layout-control? pane-handle? (or/c layout-outcome? layout-failure?))]
  [layout-keep-only
   (-> layout-control? pane-handle? (or/c layout-outcome? layout-failure?))]
  [layout-resize
   (-> layout-control? pane-handle? exact-positive-integer? (or/c -1 1)
       (or/c layout-outcome? layout-failure?))]
  [layout-balance-dimensions
   (-> layout-control? (or/c layout-outcome? layout-failure?))]
  [layout-balance-areas
   (-> layout-control? (or/c layout-outcome? layout-failure?))]
  [layout-dedication
   (-> layout-control? pane-handle? (or/c layout-outcome? layout-failure?))]
  [layout-set-dedication
   (-> layout-control? pane-handle? exact-nonnegative-integer?
       (or/c layout-outcome? layout-failure?))]
  [native-layout-turn
   (-> exact-positive-integer? exact-positive-integer? list?)]))

(define (contract item) (native-contract-value 'layout item))
(define scope-record-bytes (contract 'scope-record-bytes))
(define snapshot-header-bytes (contract 'snapshot-header-bytes))
(define node-record-bytes (contract 'node-record-bytes))
(define request-record-bytes (contract 'request-record-bytes))
(define outcome-record-bytes (contract 'outcome-record-bytes))
(define maximum-snapshot-nodes (contract 'maximum-snapshot-nodes))
(define maximum-snapshot-bytes
  (+ snapshot-header-bytes (* maximum-snapshot-nodes node-record-bytes)))
(define operation-scope (contract 'operation-scope))
(define operation-snapshot (contract 'operation-snapshot))
(define operation-split-below (contract 'operation-split-below))
(define operation-split-right (contract 'operation-split-right))
(define operation-focus (contract 'operation-focus))
(define operation-close (contract 'operation-close))
(define operation-keep-only (contract 'operation-keep-only))
(define operation-resize (contract 'operation-resize))
(define operation-balance-dimensions (contract 'operation-balance-dimensions))
(define operation-balance-areas (contract 'operation-balance-areas))
(define operation-inspect-dedication (contract 'operation-inspect-dedication))
(define operation-set-dedication (contract 'operation-set-dedication))

(struct layout-control (capability [scope #:mutable]))
(struct layout-handle (owner-id layout-id generation) #:transparent)
(struct pane-handle (layout pane-id slot slot-generation) #:transparent)
(struct layout-rect (row column height width) #:transparent)
(struct layout-pane-geometry (outer content status separator) #:transparent)
(struct layout-node
  (kind node-id slot-generation parent-id depth arrangement
        first-child-id second-child-id first-weight second-weight
        pane view buffer-id entry dedication history-count history-generation
        geometry active? mru-rank)
  #:transparent)
(struct layout-scope (schema-version access layout pane) #:transparent)
(struct layout-snapshot
  (scope geometry-state geometry-request root-id active-pane
         node-count pane-count partition-count geometry-work nodes)
  #:transparent)
(struct layout-outcome
  (scope primary secondary changed? partition-id arrangement delta
         first-span second-span previous-dedication current-dedication)
  #:transparent)
(struct layout-failure (code limit actual) #:transparent)

;; call-with-layout-control confines one opaque layout capability to one Racket turn.
(define (call-with-layout-control generation token command)
  (cap:call-with-scoped-capability
   'layout generation token
   (lambda (capability) (command (layout-control capability #f)))))

(define (layout-native-invoke control operation input output-capacity)
  (when (> output-capacity maximum-snapshot-bytes)
    (raise-arguments-error
     'layout-native-invoke
     "output capacity exceeds the supported maximum"
     "limit" maximum-snapshot-bytes
     "actual" output-capacity))
  (when (> (bytes-length input) request-record-bytes)
    (raise-arguments-error
     'layout-native-invoke
     "input payload exceeds the supported maximum"
     "limit" request-record-bytes
     "actual" (bytes-length input)))
  (define result
    (cap:scoped-capability-invoke
     (layout-control-capability control)
     operation 0 0 input output-capacity))
  (case (cap:scoped-capability-result-status result)
    [(0) (cap:scoped-capability-result-output result)]
    [(1)
     (layout-failure
      (cap:scoped-capability-result-failure-code result)
      (cap:scoped-capability-result-limit result)
      (cap:scoped-capability-result-actual result))]
    [else
     (error 'layout-native-invoke "native layout adapter rejected the call")]))

(define (layout-current-scope control)
  (or (layout-control-scope control)
      (let ([result (layout-native-invoke control operation-scope #"" scope-record-bytes)])
        (if (layout-failure? result)
            result
            (let ([scope (decode-scope result 0)])
              (set-layout-control-scope! control scope)
              scope)))))

;; layout-inspect returns an immutable copied snapshot of the current generation.
(define (layout-inspect control)
  (define scope (layout-current-scope control))
  (if (layout-failure? scope)
      scope
      (let ([result
             (layout-native-invoke
              control operation-snapshot (encode-scope scope) maximum-snapshot-bytes)])
        (if (layout-failure? result) result (decode-snapshot result)))))

(define (layout-split-below control pane)
  (layout-mutate control operation-split-below pane 0 0 0))

(define (layout-split-right control pane)
  (layout-mutate control operation-split-right pane 0 0 0))

(define (layout-focus control pane)
  (layout-mutate control operation-focus pane 0 0 0))

(define (layout-close control pane)
  (layout-mutate control operation-close pane 0 0 0))

(define (layout-keep-only control pane)
  (layout-mutate control operation-keep-only pane 0 0 0))

(define (layout-resize control pane arrangement delta)
  (layout-mutate control operation-resize pane arrangement delta 0))

(define (layout-balance-dimensions control)
  (define scope (layout-current-scope control))
  (if (layout-failure? scope)
      scope
      (layout-mutate
       control operation-balance-dimensions (layout-scope-pane scope) 0 0 0)))

(define (layout-balance-areas control)
  (define scope (layout-current-scope control))
  (if (layout-failure? scope)
      scope
      (layout-mutate control operation-balance-areas (layout-scope-pane scope) 0 0 0)))

(define (layout-dedication control pane)
  (layout-mutate control operation-inspect-dedication pane 0 0 0))

(define (layout-set-dedication control pane dedication)
  (layout-mutate control operation-set-dedication pane 0 0 dedication))

(define (layout-mutate control operation pane arrangement delta dedication)
  (define scope (layout-current-scope control))
  (if (layout-failure? scope)
      scope
      (let ([result
             (layout-native-invoke
              control operation
              (encode-request scope operation pane arrangement delta dedication)
              outcome-record-bytes)])
        (if (layout-failure? result)
            result
            (let ([outcome (decode-outcome result)])
              (set-layout-control-scope! control (layout-outcome-scope outcome))
              outcome)))))

;; native-layout-turn executes one production layout capability turn.
(define (native-layout-turn generation token)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #f (string->bytes/utf-8 (exn-message failure))))])
    (define result
      (call-with-layout-control generation token layout-current-scope))
    (list #t result #"")))

(define (encode-scope scope)
  (define output (make-bytes scope-record-bytes))
  (for ([value
         (in-list
          (list (layout-scope-schema-version scope)
                (layout-scope-access scope)
                (layout-handle-owner-id (layout-scope-layout scope))
                (layout-handle-layout-id (layout-scope-layout scope))
                (layout-handle-generation (layout-scope-layout scope))
                (pane-handle-pane-id (layout-scope-pane scope))
                (pane-handle-slot (layout-scope-pane scope))
                (pane-handle-slot-generation (layout-scope-pane scope))))]
        [offset (in-range 0 scope-record-bytes 8)])
    (write-u64! output offset value))
  output)

(define (encode-request scope operation pane arrangement delta dedication)
  (define output (make-bytes request-record-bytes))
  (bytes-copy! output 0 (encode-scope scope))
  (define layout (pane-handle-layout pane))
  (for ([value
         (in-list
          (list operation
                (layout-handle-owner-id layout)
                (layout-handle-layout-id layout)
                (layout-handle-generation layout)
                (pane-handle-pane-id pane)
                (pane-handle-slot pane)
                (pane-handle-slot-generation pane)
                arrangement))]
        [offset (in-range scope-record-bytes 128 8)])
    (write-u64! output offset value))
  (write-s64! output 128 delta)
  (write-u64! output 136 dedication)
  output)

(define (decode-scope input offset)
  (define layout
    (layout-handle (read-u64 input (+ offset 16))
                   (read-u64 input (+ offset 24))
                   (read-u64 input (+ offset 32))))
  (layout-scope
   (read-u64 input offset)
   (read-u64 input (+ offset 8))
   layout
   (pane-handle layout
                (read-u64 input (+ offset 40))
                (read-u64 input (+ offset 48))
                (read-u64 input (+ offset 56)))))

(define (decode-pane input offset)
  (define layout
    (layout-handle (read-u64 input offset)
                   (read-u64 input (+ offset 8))
                   (read-u64 input (+ offset 16))))
  (pane-handle layout
               (read-u64 input (+ offset 24))
               (read-u64 input (+ offset 32))
               (read-u64 input (+ offset 40))))

(define (decode-rect input offset)
  (layout-rect (read-s64 input offset)
               (read-s64 input (+ offset 8))
               (read-s64 input (+ offset 16))
               (read-s64 input (+ offset 24))))

(define (decode-snapshot input)
  (unless (>= (bytes-length input) snapshot-header-bytes)
    (error 'layout-inspect "native layout snapshot has a truncated header"))
  (define node-count (read-u64 input 160))
  (define expected (+ snapshot-header-bytes (* node-count node-record-bytes)))
  (unless (and (<= node-count maximum-snapshot-nodes)
               (= (bytes-length input) expected))
    (error 'layout-inspect "native layout snapshot has an invalid node extent"))
  (layout-snapshot
   (decode-scope input 0)
   (read-u64 input 64)
   (list (read-s64 input 72) (read-s64 input 80)
         (read-s64 input 88) (read-s64 input 96))
   (read-u64 input 104)
   (decode-pane input 112)
   node-count
   (read-u64 input 168)
   (read-u64 input 176)
   (read-u64 input 184)
   (for/list ([index (in-range node-count)])
     (decode-node input (+ snapshot-header-bytes (* index node-record-bytes))))))

(define (decode-node input offset)
  (define (u word) (read-u64 input (+ offset (* word 8))))
  (define (s word) (read-s64 input (+ offset (* word 8))))
  (define pane (decode-pane input (+ offset (* 10 8))))
  (layout-node
   (u 0) (u 1) (u 2) (u 3) (u 4) (u 5) (u 6) (u 7) (u 8) (u 9)
   pane
   (list (u 16) (u 17) (u 18))
   (u 19)
   (list (u 20) (u 21) (u 22) (u 23) (u 24) (u 25))
   (u 26) (u 27) (u 28)
   (layout-pane-geometry
    (layout-rect (s 29) (s 30) (s 31) (s 32))
    (layout-rect (s 33) (s 34) (s 35) (s 36))
    (layout-rect (s 37) (s 38) (s 39) (s 40))
    (layout-rect (s 41) (s 42) (s 43) (s 44)))
   (not (zero? (u 45)))
   (u 46)))

(define (decode-outcome input)
  (unless (= (bytes-length input) outcome-record-bytes)
    (error 'layout-request "native layout outcome has an invalid width"))
  (layout-outcome
   (decode-scope input 0)
   (decode-pane input 64)
   (decode-pane input 112)
   (not (zero? (read-u64 input 160)))
   (read-u64 input 168)
   (read-u64 input 176)
   (read-s64 input 184)
   (read-s64 input 192)
   (read-s64 input 200)
   (read-u64 input 208)
   (read-u64 input 216)))

(define (write-u64! output offset value)
  (integer->integer-bytes value 8 #f #f output offset)
  (void))

(define (write-s64! output offset value)
  (integer->integer-bytes value 8 #t #f output offset)
  (void))

(define (read-u64 input offset)
  (integer-bytes->integer input #f #f offset (+ offset 8)))

(define (read-s64 input offset)
  (integer-bytes->integer input #t #f offset (+ offset 8)))

(module+ test
  (require rackunit)

  (define escaped #f)
  (call-with-layout-control 1 1 (lambda (control) (set! escaped control)))
  (check-exn exn:fail? (lambda () (layout-inspect escaped)))
  (check-equal? (bytes-length (encode-request
                               (layout-scope 1 1 (layout-handle 1 1 1)
                                             (pane-handle (layout-handle 1 1 1) 1 0 1))
                               operation-resize
                               (pane-handle (layout-handle 1 1 1) 1 0 1)
                               2 -1 0))
                request-record-bytes))
