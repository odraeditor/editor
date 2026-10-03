#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list)

(define unsigned-64/c
  (and/c exact-nonnegative-integer? (<=/c (sub1 (expt 2 64)))))
(define immutable-hash/c (and/c hash? immutable?))

(provide
 (contract-out
  [display-policy? (-> any/c boolean?)]
  [display-policy-inspect (-> display-policy? immutable-hash/c)]
  [display-policy-replace (-> display-policy? immutable-hash/c display-policy?)]
  [reload-display-policy! (-> (-> display-policy? display-policy?) void?)]
  [reset-display-policy! (-> void?)]
  [runtime-display-policy-exchange
   (-> exact-positive-integer? (listof unsigned-64/c) list?)]))

(define display-action-symbols
  '(reuse-same-buffer
    split-below
    split-right
    reuse-least-recent
    reuse-most-recent))
(define display-action-capacity 32)
(define display-policy-field-count (+ 1 display-action-capacity 2))

(struct display-policy (actions split-height-threshold split-width-threshold)
  #:transparent)

(define (display-action->code action)
  (define position (index-of display-action-symbols action eq?))
  (unless position
    (raise-argument-error 'display-policy-replace "a display action symbol" action))
  (add1 position))

(define (display-code->action code)
  (unless (and (exact-positive-integer? code)
               (<= code (length display-action-symbols)))
    (raise-argument-error
     'runtime-display-policy-exchange
     "a known display action code"
     code))
  (list-ref display-action-symbols (sub1 code)))

;; display-policy-inspect returns the complete strategy as immutable configuration data.
(define (display-policy-inspect policy)
  (hasheq 'actions (display-policy-actions policy)
          'split-height-threshold (display-policy-split-height-threshold policy)
          'split-width-threshold (display-policy-split-width-threshold policy)))

;; display-policy-replace copies one policy with the named fields replaced.
(define (display-policy-replace policy replacements)
  (for ([field (in-hash-keys replacements)])
    (unless (memq field '(actions split-height-threshold split-width-threshold))
      (raise-arguments-error
       'display-policy-replace
       "unknown display policy field"
       "field" field)))
  (define actions (hash-ref replacements 'actions (display-policy-actions policy)))
  (unless (and (list? actions)
               (pair? actions)
               (<= (length actions) display-action-capacity)
               (= (length actions) (length (remove-duplicates actions eq?)))
               (andmap (lambda (action) (memq action display-action-symbols)) actions))
    (raise-argument-error
     'display-policy-replace
     "a nonempty unique list of at most 32 display actions"
     actions))
  (define height
    (hash-ref replacements
              'split-height-threshold
              (display-policy-split-height-threshold policy)))
  (define width
    (hash-ref replacements
              'split-width-threshold
              (display-policy-split-width-threshold policy)))
  (for ([field '(split-height-threshold split-width-threshold)]
        [value (list height width)])
    (unless (and (exact-positive-integer? value)
                 (<= value (sub1 (expt 2 64))))
      (raise-argument-error 'display-policy-replace "a positive 64-bit threshold" value)))
  (display-policy actions height width))

(define configured-display-policy (lambda (current) current))

;; reload-display-policy! atomically replaces the live Racket configuration function.
(define (reload-display-policy! configure)
  (set! configured-display-policy configure))

;; reset-display-policy! restores the identity configuration used by built-in defaults.
(define (reset-display-policy!)
  (set! configured-display-policy (lambda (current) current)))

(define (fields->display-policy fields)
  (unless (= (length fields) display-policy-field-count)
    (raise-argument-error
     'runtime-display-policy-exchange
     "a complete 35-field display policy"
     fields))
  (define action-count (car fields))
  (unless (and (exact-positive-integer? action-count)
               (<= action-count display-action-capacity))
    (raise-argument-error
     'runtime-display-policy-exchange
     "a bounded positive display action count"
     action-count))
  (define action-fields (take (cdr fields) display-action-capacity))
  (display-policy
   (map display-code->action (take action-fields action-count))
   (list-ref fields 33)
   (list-ref fields 34)))

(define (display-policy->fields policy)
  (define action-codes (map display-action->code (display-policy-actions policy)))
  (append (list (length action-codes))
          action-codes
          (make-list (- display-action-capacity (length action-codes)) 0)
          (list (display-policy-split-height-threshold policy)
                (display-policy-split-width-threshold policy))))

;; runtime-display-policy-exchange applies the configured production policy.
(define (runtime-display-policy-exchange generation fields)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f 0 '()
                           (string->bytes/utf-8 (exn-message failure))))])
    (define current (fields->display-policy fields))
    (list #t generation
          (display-policy->fields (configured-display-policy current))
          #"")))

(module+ test-support
  (provide fields->display-policy display-policy->fields configured-display-policy))

(module+ test
  (require rackunit)

  (define default-actions '(1 2 3 4))
  (define default-fields
    (append '(4) default-actions (make-list 28 0) '(12 40)))
  (define initial (fields->display-policy default-fields))
  (check-equal? (hash-ref (display-policy-inspect initial) 'actions)
                '(reuse-same-buffer split-below split-right reuse-least-recent))
  (check-equal?
   (hash-ref
    (display-policy-inspect
     (display-policy-replace initial (hasheq 'split-width-threshold 80)))
    'split-width-threshold)
   80)
  (check-exn exn:fail:contract?
             (lambda () (display-policy-replace initial (hasheq 'unknown-field 1))))
  (check-exn exn:fail:contract?
             (lambda () (display-policy-replace initial (hasheq 'actions '(split-below split-below)))))

  (reload-display-policy!
   (lambda (current)
     (display-policy-replace
      current
      (hasheq 'actions '(reuse-most-recent split-right)
              'split-width-threshold 80))))
  (check-equal? (take (list-ref (runtime-display-policy-exchange 7 default-fields) 2) 3)
                '(2 5 3))
  (reset-display-policy!)
  (check-equal? (runtime-display-policy-exchange 7 default-fields)
                (list #t 7 default-fields #"")))
