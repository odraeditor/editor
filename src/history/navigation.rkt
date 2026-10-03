#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list)

(define unsigned-64/c
  (and/c exact-nonnegative-integer? (<=/c (sub1 (expt 2 64)))))
(define positive-64/c
  (and/c exact-positive-integer? (<=/c (sub1 (expt 2 64)))))
(define immutable-hash/c (and/c hash? immutable?))

(provide
 (contract-out
  [history-node-id? (-> any/c boolean?)]
  [history-inspection? (-> any/c boolean?)]
  [history-request? (-> any/c boolean?)]
  [history-inspection-view (-> history-inspection? immutable-hash/c)]
  [history-branch-request
   (-> history-inspection? history-node-id? positive-64/c history-request?)]
  [history-selective-undo-request
   (->* (history-inspection? positive-64/c positive-64/c)
        (#:range (or/c #f (list/c unsigned-64/c unsigned-64/c)))
        history-request?)]
  [runtime-history-inspection
   (-> list? (or/c #f list?) (or/c #f list?) list? positive-64/c history-inspection?)]
  [runtime-history-request-fields (-> history-request? list?)]))

(struct history-node-id (history slot generation))
(struct history-inspection (active parent preferred children generation))
(struct history-request (operation active target unit generation operations range))

(define (raw->node-id who raw)
  (unless (and (= (length raw) 3)
               (andmap exact-positive-integer? raw)
               (andmap (lambda (value) (<= value (sub1 (expt 2 64)))) raw))
    (raise-argument-error who "a three-field nonzero native node identity" raw))
  (apply history-node-id raw))

(define (raw->projection raw)
  (unless (and (= (length raw) 10)
               (list? (list-ref raw 3))
               (bytes? (list-ref raw 5)))
    (raise-argument-error 'runtime-history-inspection "a native node projection" raw))
  (hasheq 'id (raw->node-id 'runtime-history-inspection (take raw 3))
          'unit (list-ref raw 4)
          'parent (and (pair? (list-ref raw 3))
                       (raw->node-id 'runtime-history-inspection (list-ref raw 3)))
          'command (bytes->string/utf-8 (list-ref raw 5))
          'creation-order (list-ref raw 6)
          'retained-bytes (list-ref raw 7)
          'payload-bytes (list-ref raw 8)
          'child-count (list-ref raw 9)))

;; runtime-history-inspection is the sole decoder for copied native projections.
(define (runtime-history-inspection active parent preferred children generation)
  (history-inspection
   (raw->projection active)
   (and parent (raw->projection parent))
   (and preferred (raw->projection preferred))
   (map raw->projection children)
   generation))

;; history-inspection-view exposes immutable data while node identities stay opaque.
(define (history-inspection-view inspection)
  (hasheq 'active (history-inspection-active inspection)
          'parent (history-inspection-parent inspection)
          'preferred-child (history-inspection-preferred inspection)
          'children (history-inspection-children inspection)
          'policy-generation (history-inspection-generation inspection)))

(define (projection-id projection)
  (hash-ref projection 'id))

;; history-branch-request retains only an identity that came from a native projection.
(define (history-branch-request inspection target operations)
  (history-request
   'select-branch
   (projection-id (history-inspection-active inspection))
   target
   0
   (history-inspection-generation inspection)
   operations
   #f))

;; history-selective-undo-request names one retained unit and optional admitted range.
(define (history-selective-undo-request inspection unit operations #:range [range #f])
  (when (and range (> (car range) (cadr range)))
    (raise-arguments-error
     'history-selective-undo-request
     "range start exceeds range end"
     "range" range))
  (history-request
   'selective-undo
   (projection-id (history-inspection-active inspection))
   #f
   unit
   (history-inspection-generation inspection)
   operations
   range))

(define (node-id->raw identity)
  (and identity
       (list (history-node-id-history identity)
             (history-node-id-slot identity)
             (history-node-id-generation identity))))

;; runtime-history-request-fields encodes one immutable request for checked native validation.
(define (runtime-history-request-fields request)
  (list (history-request-operation request)
        (node-id->raw (history-request-active request))
        (node-id->raw (history-request-target request))
        (history-request-unit request)
        (history-request-generation request)
        (history-request-operations request)
        (history-request-range request)))

(module+ test
  (require rackunit)

  (define active '(1 2 1 (1 1 1) 7 #"edit" 2 512 8 2))
  (define child '(1 3 1 (1 2 1) 8 #"alternate" 3 256 4 0))
  (define inspection
    (runtime-history-inspection active #f child (list child) 4))
  (define view (history-inspection-view inspection))
  (check-true (immutable? view))
  (check-equal? (hash-ref (hash-ref view 'active) 'command) "edit")
  (define target (hash-ref (car (hash-ref view 'children)) 'id))
  (check-true (history-node-id? target))
  (check-equal?
   (car (runtime-history-request-fields
         (history-branch-request inspection target 32)))
   'select-branch)
  (check-equal?
   (last (runtime-history-request-fields
          (history-selective-undo-request inspection 7 64 #:range '(2 5))))
   '(2 5))
  (check-exn exn:fail:contract?
             (lambda ()
               (history-selective-undo-request inspection 7 64 #:range '(5 2)))))
