#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         "ksawery-annotation.rkt"
         "ksawery-extension.rkt")

(provide
 (struct-out ksawery-operation-executable)
 (struct-out ksawery-operation-verifier)
 (struct-out ksawery-operation-limits)
 (struct-out ksawery-operation-plan)
 default-ksawery-operation-limits
 (contract-out
  [make-ksawery-operation-git (-> ksawery-operation-executable?)]
  [make-ksawery-operation-executable
   (-> (or/c symbol? string?) string? ksawery-operation-executable?)]
  [make-ksawery-operation-verifier
   (->* (symbol?)
        (#:observation (or/c #f symbol?)
         #:target (or/c #f ksawery-annotation-target-value?)
         #:operation (or/c #f symbol?))
        ksawery-operation-verifier?)]
  [make-ksawery-operation-limits
   (->* ()
        (#:output-bytes exact-positive-integer?
         #:diagnostic-bytes exact-positive-integer?
         #:deadline-milliseconds exact-positive-integer?
         #:cancellation-grace-milliseconds exact-positive-integer?)
        ksawery-operation-limits?)]
  [make-ksawery-operation-plan
   (->* (ksawery-contributor? exact-positive-integer? exact-positive-integer?
                              (or/c symbol? string?) string? exact-positive-integer?
                              ksawery-operation-executable? (listof string?) symbol?
                              (listof symbol?) ksawery-operation-verifier?)
        (#:diagnostic-policy symbol? #:limits ksawery-operation-limits?)
        ksawery-operation-plan?)]
  [encode-ksawery-operation-plan (-> ksawery-operation-plan? bytes?)]))

(define schema-version 1)
(define header-bytes 192)
(define limits-bytes 32)
(define verifier-bytes 56)
(define argument-record-bytes 16)
(define maximum-arguments 64)
(define maximum-argument-bytes 512)
(define maximum-vector-bytes (* 8 1024 1024))
(define maximum-executable-bytes (* 4 1024))
(define maximum-output-bytes (* 8 1024 1024))
(define maximum-diagnostic-bytes (* 64 1024))
(define maximum-deadline-milliseconds (* 10 60 1000))
(define maximum-cancellation-grace-milliseconds 5000)
(define maximum-copy-bytes (* 8 1024 1024))
(define maximum-identity-bytes 96)
(define maximum-label-bytes 128)
(define observations '(status history refs sequence conflict process))
(define effects '(read-only repository-mutating externally-mutating))
(define diagnostic-policies '(suppressed bounded-public))
(define verifier-kinds
  '(none observation-available target-present target-absent operation-state))
(define operation-states
  '(unknown normal merging rebasing cherry-picking reverting bisecting
            applying-patches other-sequence))
(define target-families
  '(path diff-unit revision revision-range ref remote conflict sequence process))
(define effect-codes
  '((read-only . 1) (repository-mutating . 2) (externally-mutating . 3)))
(define diagnostic-policy-codes '((suppressed . 1) (bounded-public . 2)))
(define verifier-kind-codes
  '((none . 0) (observation-available . 1) (target-present . 2)
               (target-absent . 3) (operation-state . 4)))
(define operation-state-codes
  '((unknown . 0) (normal . 1) (merging . 2) (rebasing . 3)
              (cherry-picking . 4) (reverting . 5) (bisecting . 6)
              (applying-patches . 7) (other-sequence . 8)))

(struct ksawery-operation-executable (kind identity path) #:transparent)
(struct ksawery-operation-verifier (kind observation target operation) #:transparent)
(struct ksawery-operation-limits
  (output-bytes diagnostic-bytes deadline-milliseconds
                cancellation-grace-milliseconds)
  #:transparent)
(struct ksawery-operation-plan
  (contributor-identity contributor-generation contribution id generation
                        identity purpose executable arguments effect refresh
                        verifier environment diagnostic-policy limits)
  #:transparent)

(define default-ksawery-operation-limits
  (ksawery-operation-limits (* 1024 1024) (* 4 1024) 30000 250))

;; make-ksawery-operation-git selects the core-owned Git executable role.
(define (make-ksawery-operation-git)
  (ksawery-operation-executable 'built-in-git "git" #f))

;; make-ksawery-operation-executable copies one personal-configuration path.
(define (make-ksawery-operation-executable identity executable-path)
  (define copied-identity
    (validated-identity 'make-ksawery-operation-executable identity))
  (define copied-path
    (validated-text 'make-ksawery-operation-executable 'path executable-path
                    maximum-executable-bytes #f))
  (unless (and (positive? (string-length copied-path))
               (char=? (string-ref copied-path 0) #\/))
    (raise-arguments-error 'make-ksawery-operation-executable
                           "configured executable path must be absolute"))
  (ksawery-operation-executable 'configured-absolute-path copied-identity copied-path))

;; make-ksawery-operation-verifier constructs one closed refreshed condition.
(define (make-ksawery-operation-verifier kind
                                          #:observation [observation #f]
                                          #:target [target #f]
                                          #:operation [operation #f])
  (check-member 'make-ksawery-operation-verifier 'kind kind verifier-kinds)
  (when observation
    (check-member 'make-ksawery-operation-verifier 'observation observation observations))
  (when operation
    (check-member 'make-ksawery-operation-verifier 'operation operation operation-states))
  (unless
      (case kind
        [(none) (and (not observation) (not target) (not operation))]
        [(observation-available) (and observation (not target) (not operation))]
        [(target-present target-absent)
         (and observation target (not operation)
              (target-supports-observation?
               (ksawery-annotation-target-value-family target) observation))]
        [(operation-state)
         (and (memq observation '(status sequence conflict))
              (memq operation (cdr operation-states)) (not target))])
    (raise-arguments-error 'make-ksawery-operation-verifier
                           "verifier fields are inconsistent"))
  (ksawery-operation-verifier kind observation target operation))

;; make-ksawery-operation-limits validates one bounded child policy.
(define (make-ksawery-operation-limits
         #:output-bytes [output-bytes (* 1024 1024)]
         #:diagnostic-bytes [diagnostic-bytes (* 4 1024)]
         #:deadline-milliseconds [deadline-milliseconds 30000]
         #:cancellation-grace-milliseconds [cancellation-grace-milliseconds 250])
  (unless (and (<= output-bytes maximum-output-bytes)
               (<= diagnostic-bytes maximum-diagnostic-bytes)
               (<= 100 deadline-milliseconds maximum-deadline-milliseconds)
               (<= cancellation-grace-milliseconds
                   maximum-cancellation-grace-milliseconds)
               (< cancellation-grace-milliseconds deadline-milliseconds))
    (raise-arguments-error 'make-ksawery-operation-limits
                           "external operation limits exceed immutable policy"))
  (ksawery-operation-limits output-bytes diagnostic-bytes deadline-milliseconds
                            cancellation-grace-milliseconds))

;; make-ksawery-operation-plan constructs one inert declared argument vector.
(define (make-ksawery-operation-plan contributor contribution id identity purpose generation
                                     executable arguments effect refresh verifier
                                     #:diagnostic-policy [diagnostic-policy 'bounded-public]
                                     #:limits [limits default-ksawery-operation-limits])
  (check-member 'make-ksawery-operation-plan 'effect effect effects)
  (check-member 'make-ksawery-operation-plan 'diagnostic-policy
                diagnostic-policy diagnostic-policies)
  (validated-symbol-list 'make-ksawery-operation-plan 'refresh refresh observations #f)
  (unless (<= (length arguments) maximum-arguments)
    (raise-arguments-error 'make-ksawery-operation-plan
                           "argument count exceeds immutable policy"))
  (define copied-arguments
    (for/list ([argument (in-list arguments)])
      (validated-text 'make-ksawery-operation-plan 'argument argument
                      maximum-argument-bytes #f)))
  (unless (<= (for/sum ([argument (in-list copied-arguments)])
                (bytes-length (string->bytes/utf-8 argument)))
              maximum-vector-bytes)
    (raise-arguments-error 'make-ksawery-operation-plan
                           "argument vector exceeds immutable policy"))
  (define contributor-data (ksawery-contributor->datum contributor))
  (define declaration
    (for/first ([entry (in-list (hash-ref contributor-data 'contributions))]
                #:when (= (hash-ref entry 'id) contribution)) entry))
  (unless (and declaration
               (eq? (hash-ref declaration 'kind) 'external-operation)
               (memq 'submit-external-operation (hash-ref declaration 'authorities))
               (andmap (lambda (entry)
                         (memq entry (hash-ref declaration 'observations)))
                       refresh))
    (raise-arguments-error 'make-ksawery-operation-plan
                           "contribution does not admit this external operation"))
  (unless (and (exact-positive-integer? id) (exact-positive-integer? generation))
    (raise-arguments-error 'make-ksawery-operation-plan
                           "plan identity and generation must be positive"))
  (unless (and (ksawery-operation-executable? executable)
               (ksawery-operation-verifier? verifier)
               (or (eq? (ksawery-operation-verifier-kind verifier) 'none)
                   (memq (ksawery-operation-verifier-observation verifier) refresh)))
    (raise-arguments-error 'make-ksawery-operation-plan
                           "executable or verifier is not admitted"))
  (define plan
    (ksawery-operation-plan
     (hash-ref contributor-data 'identity) (hash-ref contributor-data 'generation)
     contribution id generation
     (validated-identity 'make-ksawery-operation-plan identity)
     (validated-text 'make-ksawery-operation-plan 'purpose purpose maximum-label-bytes #f)
     executable copied-arguments effect (map values refresh) verifier
     'core-repository diagnostic-policy limits))
  (encode-ksawery-operation-plan plan)
  plan)

;; encode-ksawery-operation-plan emits fixed records followed by copied UTF-8.
(define (encode-ksawery-operation-plan plan)
  (define executable (ksawery-operation-plan-executable plan))
  (define verifier (ksawery-operation-plan-verifier plan))
  (define target (ksawery-operation-verifier-target verifier))
  (define leading-parts
    (map string->bytes/utf-8
         (list (ksawery-operation-plan-contributor-identity plan)
               (ksawery-operation-plan-identity plan)
               (ksawery-operation-plan-purpose plan)
               (ksawery-operation-executable-identity executable))))
  (define executable-path-parts
    (if (ksawery-operation-executable-path executable)
        (list (string->bytes/utf-8
               (ksawery-operation-executable-path executable)))
        '()))
  (define target-parts
    (if target
        (list (ksawery-annotation-target-value-identity target))
        '()))
  (define argument-parts
    (map string->bytes/utf-8 (ksawery-operation-plan-arguments plan)))
  (define text-parts
    (append
     leading-parts executable-path-parts target-parts argument-parts))
  (define offsets
    (let loop ([parts text-parts] [offset 0] [result '()])
      (if (null? parts)
          (reverse result)
          (loop (cdr parts) (+ offset (bytes-length (car parts)))
                (cons offset result)))))
  (define text (apply bytes-append text-parts))
  (define arguments (ksawery-operation-plan-arguments plan))
  (define executable-path-index
    (and (pair? executable-path-parts) 4))
  (define target-index
    (and target (+ 4 (length executable-path-parts))))
  (define argument-start
    (+ 4 (length executable-path-parts) (length target-parts)))
  (define argument-records
    (for/list ([argument (in-list arguments)] [index (in-naturals argument-start)])
      (words (list-ref offsets index) (bytes-length (list-ref text-parts index)))))
  (define record-bytes
    (+ header-bytes limits-bytes verifier-bytes
       (* argument-record-bytes (length arguments)) (bytes-length text)))
  (when (> record-bytes maximum-copy-bytes)
    (raise-arguments-error 'encode-ksawery-operation-plan
                           "encoded plan exceeds immutable byte policy"))
  (define limits (ksawery-operation-plan-limits plan))
  (bytes-append
   (words
    schema-version record-bytes
    (ksawery-operation-plan-contributor-generation plan)
    (ksawery-operation-plan-contribution plan)
    (ksawery-operation-plan-id plan)
    (ksawery-operation-plan-generation plan)
    (symbol-code (ksawery-operation-plan-effect plan) effect-codes)
    (symbol-set-code (ksawery-operation-plan-refresh plan) observations)
    1
    (symbol-code (ksawery-operation-plan-diagnostic-policy plan)
                 diagnostic-policy-codes)
    (if (eq? (ksawery-operation-executable-kind executable) 'built-in-git) 1 2)
    (length arguments)
    (list-ref offsets 0) (bytes-length (list-ref text-parts 0))
    (list-ref offsets 1) (bytes-length (list-ref text-parts 1))
    (list-ref offsets 2) (bytes-length (list-ref text-parts 2))
    (list-ref offsets 3) (bytes-length (list-ref text-parts 3))
    (if executable-path-index (list-ref offsets executable-path-index) 0)
    (if executable-path-index
        (bytes-length (list-ref text-parts executable-path-index)) 0)
    (bytes-length text) 0)
   (words
    (ksawery-operation-limits-output-bytes limits)
    (ksawery-operation-limits-diagnostic-bytes limits)
    (* 1000000 (ksawery-operation-limits-deadline-milliseconds limits))
    (* 1000000 (ksawery-operation-limits-cancellation-grace-milliseconds limits)))
   (words
    (symbol-code (ksawery-operation-verifier-kind verifier) verifier-kind-codes)
    (if (ksawery-operation-verifier-observation verifier)
        (index-of observations (ksawery-operation-verifier-observation verifier)) 0)
    (if (ksawery-operation-verifier-operation verifier)
        (symbol-code (ksawery-operation-verifier-operation verifier)
                     operation-state-codes) 0)
    (if target (add1 (index-of target-families
                               (ksawery-annotation-target-value-family target))) 0)
    (if target (ksawery-annotation-target-value-generation target) 0)
    (if target (list-ref offsets target-index) 0)
    (if target (bytes-length (list-ref text-parts target-index)) 0))
   (apply bytes-append argument-records)
   text))

(define (target-supports-observation? target observation)
  (case target
    [(path diff-unit) (eq? observation 'status)]
    [(revision revision-range) (eq? observation 'history)]
    [(ref remote) (eq? observation 'refs)]
    [(conflict) (memq observation '(conflict sequence))]
    [(sequence) (eq? observation 'sequence)]
    [(process) (eq? observation 'process)]))

(define (validated-identity who value)
  (define copied (if (symbol? value) (symbol->string value) value))
  (validated-text who 'identity copied maximum-identity-bytes #f))

(define (validated-text who field value limit allow-empty?)
  (define copied (string->immutable-string value))
  (unless (and (or allow-empty? (positive? (string-length copied)))
               (<= (bytes-length (string->bytes/utf-8 copied)) limit)
               (not (regexp-match? #rx"\u0000" copied)))
    (raise-arguments-error who "text exceeds immutable policy"
                           (symbol->string field) value))
  copied)

(define (check-member who field value accepted)
  (unless (memq value accepted)
    (raise-arguments-error who "value is outside the closed vocabulary"
                           (symbol->string field) value)))

(define (validated-symbol-list who field entries accepted allow-empty?)
  (unless (and (list? entries) (or allow-empty? (pair? entries))
               (andmap (lambda (entry) (memq entry accepted)) entries)
               (= (length entries) (length (remove-duplicates entries))))
    (raise-arguments-error who "symbol list is invalid"
                           (symbol->string field) entries))
  (map values entries))

(define (symbol-code value table)
  (define entry (assq value table))
  (unless entry (raise-arguments-error 'encode-ksawery-operation-plan
                                       "symbol has no native code" "value" value))
  (cdr entry))

(define (symbol-set-code values vocabulary)
  (for/fold ([result 0]) ([value (in-list values)])
    (bitwise-ior result (arithmetic-shift 1 (index-of vocabulary value)))))

(define (words . values)
  (apply bytes-append
         (map (lambda (value) (integer->integer-bytes value 8 #f #f)) values)))
