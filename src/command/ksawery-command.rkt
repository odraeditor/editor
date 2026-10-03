#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         "catalog.rkt"
         "ksawery-annotation.rkt"
         "ksawery-extension.rkt"
         "ksawery-operation.rkt")

(provide
 (struct-out ksawery-command-choice)
 (struct-out ksawery-command-argument)
 (struct-out ksawery-command-action)
 (struct-out ksawery-command-family)
 (struct-out ksawery-command-value)
 ksawery-command-context?
 ksawery-command-context-contributor-generation
 ksawery-command-context-repository
 ksawery-command-context-repository-generation
 ksawery-command-context-worktree-generation
 ksawery-command-context-observation
 ksawery-command-context-observation-generation
 ksawery-command-context-surface
 ksawery-command-context-surface-generation
 ksawery-command-context-selection-generation
 ksawery-command-context-target
 ksawery-command-context-operation-state
 ksawery-command-context-mutation-available?
 ksawery-command-context-capability-generation
 ksawery-command-context-observation-truncated?
 ksawery-command-context-privacy-filtered?
 (struct-out ksawery-command-submission)
 ksawery-command-outcome?
 ksawery-command-outcome-operation
 ksawery-command-family-definitions
 (contract-out
  [make-ksawery-command-choice
   (-> exact-positive-integer? (or/c symbol? string?) string? ksawery-command-choice?)]
  [make-ksawery-command-argument
   (->* (exact-positive-integer? (or/c symbol? string?) string? symbol?)
        (#:required? boolean? #:maximum-bytes exact-nonnegative-integer?
         #:choices (listof ksawery-command-choice?))
        ksawery-command-argument?)]
  [make-ksawery-command-action
   (->* (exact-positive-integer? (or/c symbol? string?) string? symbol? (listof symbol?))
        (#:targets (listof symbol?) #:operation symbol?
         #:core-operation (or/c #f symbol?)
         #:mutates-repository? boolean? #:confirmation-required? boolean?
         #:external-operation (or/c #f procedure?))
        ksawery-command-action?)]
  [make-ksawery-command-family
   (-> ksawery-contributor? exact-positive-integer? exact-positive-integer?
       (or/c symbol? string?) string? exact-positive-integer? (listof symbol?)
       (listof ksawery-command-argument?) (listof ksawery-command-action?)
       ksawery-command-family?)]
  [make-ksawery-command-boolean
   (-> exact-positive-integer? boolean? ksawery-command-value?)]
  [make-ksawery-command-choice-value
   (-> exact-positive-integer? exact-positive-integer? ksawery-command-value?)]
  [make-ksawery-command-text
   (-> exact-positive-integer? string? ksawery-command-value?)]
  [make-ksawery-command-target
   (-> exact-positive-integer? symbol? ksawery-annotation-target-value?
       ksawery-command-value?)]
  [make-ksawery-command-opaque
   (-> exact-positive-integer? bytes? ksawery-command-value?)]
  [decode-ksawery-command-context (-> bytes? ksawery-command-context?)]
  [decode-ksawery-command-submission
   (-> bytes? ksawery-command-family? ksawery-command-submission?)]
  [encode-ksawery-command-family (-> ksawery-command-family? bytes?)]
  [ksawery-command-request-action
   (->* (ksawery-command-context? ksawery-command-family?
                                  exact-positive-integer? (listof ksawery-command-value?))
        (#:confirmation (or/c #f exact-positive-integer?))
        ksawery-command-outcome?)]
  [ksawery-command-request-external-operation
   (-> ksawery-command-context? ksawery-command-family?
       exact-positive-integer? (listof ksawery-command-value?)
       ksawery-operation-plan? exact-positive-integer?
       ksawery-command-outcome?)]
  [ksawery-command-reject
   (-> ksawery-command-context? string? ksawery-command-outcome?)]
  [ksawery-command-cancel
   (-> ksawery-command-context? ksawery-command-outcome?)]))

(define schema-version 1)
(define context-header-bytes 184)
(define family-header-bytes 144)
(define argument-record-bytes 80)
(define choice-record-bytes 40)
(define action-record-bytes 96)
(define submission-header-bytes 80)
(define submission-value-record-bytes 72)
(define maximum-arguments 256)
(define maximum-choices 256)
(define maximum-actions 256)
(define maximum-identity-bytes 96)
(define maximum-label-bytes 128)
(define maximum-value-bytes (* 4 1024))
(define maximum-result-bytes (* 4 1024))
(define maximum-family-bytes (* 8 1024 1024))
(define maximum-repository-bytes 4096)
(define maximum-target-bytes 1280)
(define identity-pattern #px"^[a-z][a-z0-9]*(?:[./-][a-z0-9]+)*$")
(define argument-kinds '(boolean closed-choice text selection ref revision revision-range opaque))
(define observations '(status history refs sequence conflict process))
(define surfaces '(status history refs sequence conflict process))
(define target-families '(path diff-unit revision revision-range ref remote conflict sequence process))
(define authorities '(inspect present invoke-declared-command request-core-action
                              submit-external-operation assist-conflict))
(define operation-requirements '(any idle active sequence conflict))
(define operation-states '(idle active sequence conflict))
(define core-operations
  '(status sequence history refs revision-detail revision-range path-detail stage unstage
           discard commit amend fixup fetch push create-branch switch-branch rename-branch
           delete-branch create-tag delete-tag merge continue-merge abort-merge rebase
           continue-rebase skip-rebase abort-rebase cherry-pick continue-cherry-pick
           skip-cherry-pick abort-cherry-pick revert continue-revert skip-revert abort-revert
           bisect bisect-good bisect-bad bisect-skip bisect-reset resolve-conflict))
(define argument-kind-codes
  '((boolean . 1) (closed-choice . 2) (text . 3) (selection . 4)
                  (ref . 5) (revision . 6) (revision-range . 7) (opaque . 8)))
(define observation-codes
  '((status . 0) (history . 1) (refs . 2) (sequence . 3) (conflict . 4) (process . 5)))
(define surface-codes observation-codes)
(define target-family-codes
  '((path . 1) (diff-unit . 2) (revision . 3) (revision-range . 4)
               (ref . 5) (remote . 6) (conflict . 7) (sequence . 8) (process . 9)))
(define authority-codes
  '((inspect . 0) (present . 1) (invoke-declared-command . 2)
                  (request-core-action . 3) (submit-external-operation . 4)
                  (assist-conflict . 5)))
(define operation-requirement-codes
  '((any . 1) (idle . 2) (active . 3) (sequence . 4) (conflict . 5)))
(define operation-state-codes '((idle . 1) (active . 2) (sequence . 3) (conflict . 4)))

(struct ksawery-command-choice (id identity label) #:transparent)
(struct ksawery-command-argument
  (id identity label kind required? maximum-bytes choices) #:transparent)
(struct ksawery-command-action
  (id identity label authority observations targets operation
      core-operation mutates-repository? confirmation-required?
      external-operation) #:transparent)
(struct ksawery-command-family
  (contributor-identity contributor-generation contribution id identity label
                        generation observations arguments actions) #:transparent)
(struct ksawery-command-value (argument kind value) #:transparent)
(struct ksawery-command-context
  (contributor contributor-generation repository repository-generation
               worktree-generation observation observation-generation surface
               surface-generation selection-generation target operation-state
               mutation-available? capability-generation observation-truncated?
               privacy-filtered?)
  #:transparent)
(struct ksawery-command-submission
  (request family family-generation action confirmation context values)
  #:transparent)
(struct ksawery-command-outcome
  (kind context family action arguments confirmation diagnostic operation))

;; make-ksawery-command-choice creates one copied closed vocabulary member.
(define (make-ksawery-command-choice id identity label)
  (ksawery-command-choice id (validated-identity 'make-ksawery-command-choice identity)
                          (validated-text 'make-ksawery-command-choice label maximum-label-bytes #f)))

;; make-ksawery-command-argument declares one bounded semantic input.
(define (make-ksawery-command-argument id identity label kind
                                       #:required? [required? #f]
                                       #:maximum-bytes [maximum-bytes 0]
                                       #:choices [choices '()])
  (check-member 'make-ksawery-command-argument 'kind kind argument-kinds)
  (unless (and (exact-nonnegative-integer? maximum-bytes)
               (<= maximum-bytes maximum-value-bytes))
    (raise-arguments-error 'make-ksawery-command-argument "argument byte limit is invalid"))
  (unless (and (<= (length choices) maximum-choices)
               (= (length choices) (length (remove-duplicates (map ksawery-command-choice-id choices))))
               (= (length choices) (length (remove-duplicates (map ksawery-command-choice-identity choices)))))
    (raise-arguments-error 'make-ksawery-command-argument "choices must be bounded and unique"))
  (unless (if (eq? kind 'closed-choice)
              (and (pair? choices) (zero? maximum-bytes))
              (and (null? choices)
                   (if (memq kind '(text opaque)) (positive? maximum-bytes) (zero? maximum-bytes))))
    (raise-arguments-error 'make-ksawery-command-argument "kind, choices, and byte limit are inconsistent"))
  (ksawery-command-argument
   id (validated-identity 'make-ksawery-command-argument identity)
   (validated-text 'make-ksawery-command-argument label maximum-label-bytes #f)
   kind required? maximum-bytes (map values choices)))

;; make-ksawery-command-action declares one checked action without implementation authority.
(define (make-ksawery-command-action id identity label authority action-observations
                                     #:targets [targets '()]
                                     #:operation [operation 'any]
                                     #:core-operation [core-operation #f]
                                     #:mutates-repository? [mutates? #f]
                                     #:confirmation-required? [confirmation? #f]
                                     #:external-operation [external-operation #f])
  (check-member 'make-ksawery-command-action 'authority authority authorities)
  (validated-symbol-list 'make-ksawery-command-action 'observations action-observations observations #f)
  (validated-symbol-list 'make-ksawery-command-action 'targets targets target-families #t)
  (check-member 'make-ksawery-command-action 'operation operation operation-requirements)
  (when core-operation
    (check-member 'make-ksawery-command-action 'core-operation core-operation core-operations))
  (unless (or (not core-operation)
              (ormap (lambda (observation)
                       (core-operation-supports-observation? core-operation observation))
                     action-observations))
    (raise-arguments-error 'make-ksawery-command-action
                           "core operation does not match the admitted observations"))
  (unless (andmap (lambda (target)
                    (ormap (lambda (observation)
                             (target-supports-observation? target observation))
                           action-observations))
                  targets)
    (raise-arguments-error 'make-ksawery-command-action
                           "target families do not match the admitted observations"))
  (unless
      (case authority
        [(request-core-action)
         (and mutates? confirmation? core-operation (not external-operation))]
        [(submit-external-operation)
         (and confirmation? (not core-operation)
              (procedure? external-operation)
              (procedure-arity-includes? external-operation 2))]
        [else
         (and (memq authority '(inspect present invoke-declared-command assist-conflict))
              (not mutates?) (not confirmation?) (not core-operation)
              (not external-operation))])
    (raise-arguments-error 'make-ksawery-command-action
                           "action authority, confirmation, and implementation are inconsistent"))
  (ksawery-command-action
   id (validated-identity 'make-ksawery-command-action identity)
   (validated-text 'make-ksawery-command-action label maximum-label-bytes #f)
   authority (map values action-observations) (map values targets) operation
   core-operation mutates? confirmation? external-operation))

;; make-ksawery-command-family validates one contributor-owned immutable family generation.
(define (make-ksawery-command-family contributor contribution id identity label generation
                                     family-observations arguments actions)
  (unless (and (<= (length arguments) maximum-arguments)
               (pair? actions) (<= (length actions) maximum-actions))
    (raise-arguments-error 'make-ksawery-command-family "family members exceed immutable limits"))
  (validated-symbol-list 'make-ksawery-command-family 'observations family-observations observations #f)
  (define contributor-data (ksawery-contributor->datum contributor))
  (define declaration
    (for/first ([entry (in-list (hash-ref contributor-data 'contributions))]
                #:when (= (hash-ref entry 'id) contribution)) entry))
  (unless (and declaration (eq? (hash-ref declaration 'kind) 'command-family)
               (andmap (lambda (entry) (memq entry (hash-ref declaration 'observations)))
                       family-observations))
    (raise-arguments-error 'make-ksawery-command-family
                           "contribution does not admit this command family"))
  (for ([action (in-list actions)])
    (unless (and (andmap (lambda (entry) (memq entry family-observations))
                         (ksawery-command-action-observations action))
                 (memq (ksawery-command-action-authority action)
                       (hash-ref declaration 'authorities)))
      (raise-arguments-error 'make-ksawery-command-family
                             "action exceeds family observations or authority")))
  (check-unique 'make-ksawery-command-family arguments
                ksawery-command-argument-id ksawery-command-argument-identity)
  (check-unique 'make-ksawery-command-family actions
                ksawery-command-action-id ksawery-command-action-identity)
  (define family
    (ksawery-command-family
     (hash-ref contributor-data 'identity) (hash-ref contributor-data 'generation)
     contribution id (validated-identity 'make-ksawery-command-family identity)
     (validated-text 'make-ksawery-command-family label maximum-label-bytes #f)
     generation (map values family-observations) (map values arguments) (map values actions)))
  (encode-ksawery-command-family family)
  family)

;; ksawery-command-family-definitions composes deterministic shared-registry entries.
(define (ksawery-command-family-definitions contributor families)
  (define contributor-data (ksawery-contributor->datum contributor))
  (define provider (hash-ref contributor-data 'identity))
  (define source (hash-ref contributor-data 'provenance))
  (unless (and (list? families) (andmap ksawery-command-family? families))
    (raise-argument-error 'ksawery-command-family-definitions
                          "list of ksawery-command-family?" families))
  (for ([family (in-list families)])
    (unless (and (string=? (ksawery-command-family-contributor-identity family)
                           provider)
                 (= (ksawery-command-family-contributor-generation family)
                    (hash-ref contributor-data 'generation)))
      (raise-arguments-error
       'ksawery-command-family-definitions
       "command family belongs to another contributor generation")))
  (define definitions
    (for*/list ([family (in-list families)]
                [action (in-list (ksawery-command-family-actions family))])
      (define name
        (string-append provider "/"
                       (ksawery-command-family-identity family) "/"
                       (ksawery-command-action-identity action)))
      (make-command-definition
       name 'ksawery-extension 'ordinary 'prohibited '(lifecycle)
       (ksawery-command-action-label action)
       (lambda (_context) (error 'ksawery-extension-command
                                 "native Ksawery routing is required"))
       #:requirements '(active-buffer)
       #:provider provider
       #:source source
       #:location (ksawery-command-family-identity family))))
  (sort definitions string<? #:key odra-command-definition-name))

(define (make-ksawery-command-boolean argument value)
  (ksawery-command-value argument 'boolean value))
(define (make-ksawery-command-choice-value argument choice)
  (ksawery-command-value argument 'closed-choice choice))
(define (make-ksawery-command-text argument value)
  (validated-text 'make-ksawery-command-text value maximum-value-bytes #t)
  (ksawery-command-value argument 'text (string->immutable-string value)))
(define (make-ksawery-command-target argument kind target)
  (unless (memq kind '(selection ref revision revision-range))
    (raise-arguments-error 'make-ksawery-command-target "target argument kind is invalid"))
  (ksawery-command-value argument kind target))
(define (make-ksawery-command-opaque argument value)
  (unless (<= (bytes-length value) maximum-value-bytes)
    (raise-arguments-error 'make-ksawery-command-opaque "opaque value exceeds immutable limit"))
  (ksawery-command-value argument 'opaque (bytes->immutable-bytes value)))

;; decode-ksawery-command-context exposes only copied public repository truth.
(define (decode-ksawery-command-context input)
  (unless (>= (bytes-length input) context-header-bytes)
    (raise-arguments-error 'decode-ksawery-command-context "command context header is incomplete"))
  (define words-list (for/list ([offset (in-range 0 context-header-bytes 8)]) (input-word input offset)))
  (unless (and (= (list-ref words-list 0) schema-version)
               (= (list-ref words-list 1) (bytes-length input))
               (positive? (list-ref words-list 2)) (positive? (list-ref words-list 3))
               (positive? (list-ref words-list 4)) (positive? (list-ref words-list 5))
               (positive? (list-ref words-list 7)) (positive? (list-ref words-list 9))
               (positive? (list-ref words-list 10)) (positive? (list-ref words-list 16))
               (memq (list-ref words-list 11) '(0 1))
               (memq (list-ref words-list 15) '(0 1))
               (memq (list-ref words-list 17) '(0 1))
               (memq (list-ref words-list 18) '(0 1))
               (= (list-ref words-list 19) context-header-bytes)
               (= (list-ref words-list 21)
                  (+ context-header-bytes (list-ref words-list 20)))
               (= (list-ref words-list 1)
                  (+ (list-ref words-list 21) (list-ref words-list 22)))
               (if (= (list-ref words-list 11) 1)
                   (and (positive? (list-ref words-list 12))
                        (positive? (list-ref words-list 13))
                        (positive? (list-ref words-list 22)))
                   (and (zero? (list-ref words-list 12))
                        (zero? (list-ref words-list 13))
                        (zero? (list-ref words-list 22)))))
    (raise-arguments-error 'decode-ksawery-command-context "command context is invalid"))
  (define observation (code-symbol 'decode-ksawery-command-context (list-ref words-list 6) observation-codes))
  (define repository
    (bytes->string/utf-8
     (input-range input (list-ref words-list 19) (list-ref words-list 20)
                  context-header-bytes maximum-repository-bytes #f)))
  (define target
    (and (= (list-ref words-list 11) 1)
         (make-ksawery-annotation-target
          (code-symbol 'decode-ksawery-command-context (list-ref words-list 12) target-family-codes)
          (list-ref words-list 13)
          (input-range input (list-ref words-list 21) (list-ref words-list 22)
                       context-header-bytes maximum-target-bytes #f))))
  (when (and target
             (or (not (= (ksawery-annotation-target-value-generation target)
                         (list-ref words-list 7)))
                 (not (target-supports-observation?
                       (ksawery-annotation-target-value-family target) observation))))
    (raise-arguments-error 'decode-ksawery-command-context "command target is stale"))
  (ksawery-command-context
   (list-ref words-list 2) (list-ref words-list 3) (string->immutable-string repository)
   (list-ref words-list 4) (list-ref words-list 5) observation (list-ref words-list 7)
   (code-symbol 'decode-ksawery-command-context (list-ref words-list 8) surface-codes)
   (list-ref words-list 9) (list-ref words-list 10) target
   (code-symbol 'decode-ksawery-command-context (list-ref words-list 14) operation-state-codes)
   (= (list-ref words-list 15) 1) (list-ref words-list 16)
   (= (list-ref words-list 17) 1) (= (list-ref words-list 18) 1)))

;; decode-ksawery-command-submission validates one fixed native command request.
(define (decode-ksawery-command-submission input family)
  (unless (>= (bytes-length input) submission-header-bytes)
    (raise-arguments-error 'decode-ksawery-command-submission
                           "command submission header is incomplete"))
  (define header
    (for/list ([offset (in-range 0 submission-header-bytes 8)])
      (input-word input offset)))
  (define argument-count (list-ref header 7))
  (define context-bytes (list-ref header 8))
  (define payload-bytes (list-ref header 9))
  (define records-bytes (* argument-count submission-value-record-bytes))
  (define context-start submission-header-bytes)
  (define records-start (+ context-start context-bytes))
  (define payload-start (+ records-start records-bytes))
  (unless (and (= (list-ref header 0) schema-version)
               (= (list-ref header 1) (bytes-length input))
               (positive? (list-ref header 2))
               (= (list-ref header 3) (ksawery-command-family-id family))
               (= (list-ref header 4) (ksawery-command-family-generation family))
               (positive? (list-ref header 5))
               (<= argument-count maximum-arguments)
               (>= context-bytes context-header-bytes)
               (= (+ payload-start payload-bytes) (bytes-length input)))
    (raise-arguments-error 'decode-ksawery-command-submission
                           "command submission is invalid or stale"))
  (define context
    (decode-ksawery-command-context
     (subbytes input context-start records-start)))
  (define payload (subbytes input payload-start))
  (define values
    (for/list ([index (in-range argument-count)])
      (define base (+ records-start (* index submission-value-record-bytes)))
      (define record
        (for/list ([offset (in-range base (+ base submission-value-record-bytes) 8)])
          (input-word input offset)))
      (decode-ksawery-command-submission-value record payload)))
  (ksawery-command-submission
   (list-ref header 2) (list-ref header 3) (list-ref header 4)
   (list-ref header 5) (list-ref header 6) context values))

(define (decode-ksawery-command-submission-value record payload)
  (define argument (list-ref record 0))
  (define kind
    (code-symbol 'decode-ksawery-command-submission
                 (list-ref record 1) argument-kind-codes))
  (define scalar (list-ref record 2))
  (define content-offset (list-ref record 3))
  (define content-bytes (list-ref record 4))
  (define target-family (list-ref record 5))
  (define target-generation (list-ref record 6))
  (define target-offset (list-ref record 7))
  (define target-bytes (list-ref record 8))
  (case kind
    [(boolean)
     (unless (and (memq scalar '(0 1)) (zero? content-offset) (zero? content-bytes)
                  (zero? target-family) (zero? target-generation)
                  (zero? target-offset) (zero? target-bytes))
       (raise-arguments-error 'decode-ksawery-command-submission
                              "Boolean argument record is invalid"))
     (make-ksawery-command-boolean argument (= scalar 1))]
    [(closed-choice)
     (unless (and (positive? scalar) (zero? content-offset) (zero? content-bytes)
                  (zero? target-family) (zero? target-generation)
                  (zero? target-offset) (zero? target-bytes))
       (raise-arguments-error 'decode-ksawery-command-submission
                              "choice argument record is invalid"))
     (make-ksawery-command-choice-value argument scalar)]
    [(text opaque)
     (unless (and (zero? scalar) (positive? content-bytes)
                  (zero? target-family) (zero? target-generation)
                  (zero? target-offset) (zero? target-bytes))
       (raise-arguments-error 'decode-ksawery-command-submission
                              "copied argument record is invalid"))
     (define copied
       (submission-payload-range payload content-offset content-bytes))
     (if (eq? kind 'text)
         (make-ksawery-command-text argument (bytes->string/utf-8 copied))
         (make-ksawery-command-opaque argument copied))]
    [(selection ref revision revision-range)
     (unless (and (zero? scalar) (zero? content-offset) (zero? content-bytes)
                  (positive? target-family) (positive? target-generation)
                  (positive? target-bytes))
       (raise-arguments-error 'decode-ksawery-command-submission
                              "semantic target argument record is invalid"))
     (define family
       (code-symbol 'decode-ksawery-command-submission
                    target-family target-family-codes))
     (make-ksawery-command-target
      argument kind
      (make-ksawery-annotation-target
       family target-generation
       (submission-payload-range payload target-offset target-bytes)))]))

(define (submission-payload-range payload offset count)
  (unless (and (<= offset (bytes-length payload))
               (<= count (- (bytes-length payload) offset)))
    (raise-arguments-error 'decode-ksawery-command-submission
                           "command submission payload range is invalid"))
  (subbytes payload offset (+ offset count)))

;; ksawery-command-request-action returns one inert request tied to its exact context.
(define (ksawery-command-request-action context family action-id values #:confirmation [confirmation #f])
  (unless (= (ksawery-command-context-contributor-generation context)
             (ksawery-command-family-contributor-generation family))
    (raise-arguments-error 'ksawery-command-request-action "command family generation is stale"))
  (unless (memq (ksawery-command-context-observation context)
                (ksawery-command-family-observations family))
    (raise-arguments-error 'ksawery-command-request-action "observation is not admitted"))
  (define action
    (for/first ([entry (in-list (ksawery-command-family-actions family))]
                #:when (= (ksawery-command-action-id entry) action-id)) entry))
  (unless action (raise-arguments-error 'ksawery-command-request-action "action is not admitted"))
  (unless (eq? (ksawery-command-action-authority action) 'request-core-action)
    (raise-arguments-error 'ksawery-command-request-action
                           "action does not request a checked core action"))
  (validate-action-context 'ksawery-command-request-action action context)
  (unless (equal? (and confirmation #t) (ksawery-command-action-confirmation-required? action))
    (raise-arguments-error 'ksawery-command-request-action "confirmation does not match the action"))
  (check-unique 'ksawery-command-request-action values
                ksawery-command-value-argument ksawery-command-value-argument)
  (for ([value (in-list values)]) (validate-command-value value family context))
  (for ([argument (in-list (ksawery-command-family-arguments family))]
        #:when (ksawery-command-argument-required? argument))
    (unless (ormap (lambda (value) (= (ksawery-command-value-argument value)
                                     (ksawery-command-argument-id argument))) values)
      (raise-arguments-error 'ksawery-command-request-action "required argument is missing")))
  (ksawery-command-outcome 'action context family action-id
                           (for/list ([value (in-list values)]) value)
                           confirmation "" #f))

;; ksawery-command-request-external-operation returns one inert declared plan request.
(define (ksawery-command-request-external-operation
         context family action-id values operation confirmation)
  (unless (= (ksawery-command-context-contributor-generation context)
             (ksawery-command-family-contributor-generation family))
    (raise-arguments-error 'ksawery-command-request-external-operation
                           "command family generation is stale"))
  (define action
    (for/first ([entry (in-list (ksawery-command-family-actions family))]
                #:when (= (ksawery-command-action-id entry) action-id)) entry))
  (unless (and action
               (eq? (ksawery-command-action-authority action)
                    'submit-external-operation))
    (raise-arguments-error 'ksawery-command-request-external-operation
                           "action does not submit an external operation"))
  (validate-action-context 'ksawery-command-request-external-operation action context)
  (unless (and (ksawery-operation-plan? operation)
               (string=? (ksawery-operation-plan-contributor-identity operation)
                         (ksawery-command-family-contributor-identity family))
               (= (ksawery-operation-plan-contributor-generation operation)
                  (ksawery-command-family-contributor-generation family))
               (equal? (ksawery-command-action-mutates-repository? action)
                       (not (eq? (ksawery-operation-plan-effect operation)
                                 'read-only))))
    (raise-arguments-error 'ksawery-command-request-external-operation
                           "operation plan exceeds the admitted command action"))
  (unless (and (exact-positive-integer? confirmation)
               (ksawery-command-action-confirmation-required? action))
    (raise-arguments-error 'ksawery-command-request-external-operation
                           "confirmation does not match the action"))
  (check-unique 'ksawery-command-request-external-operation values
                ksawery-command-value-argument ksawery-command-value-argument)
  (for ([value (in-list values)]) (validate-command-value value family context))
  (for ([argument (in-list (ksawery-command-family-arguments family))]
        #:when (ksawery-command-argument-required? argument))
    (unless (ormap (lambda (value)
                     (= (ksawery-command-value-argument value)
                        (ksawery-command-argument-id argument)))
                   values)
      (raise-arguments-error 'ksawery-command-request-external-operation
                             "required argument is missing")))
  (ksawery-command-outcome
   'external-operation context family action-id
   (for/list ([value (in-list values)]) value)
   confirmation "" operation))

(define (ksawery-command-reject context diagnostic)
  (validated-text 'ksawery-command-reject diagnostic maximum-result-bytes #f)
  (ksawery-command-outcome 'rejected context #f #f '() #f
                           (string->immutable-string diagnostic) #f))
(define (ksawery-command-cancel context)
  (ksawery-command-outcome 'cancelled context #f #f '() #f "" #f))

;; encode-ksawery-command-family copies one declaration into deterministic fixed records.
(define (encode-ksawery-command-family family)
  (define arguments (ksawery-command-family-arguments family))
  (define choices (append* (map ksawery-command-argument-choices arguments)))
  (define actions (ksawery-command-family-actions family))
  (define texts
    (append (list (ksawery-command-family-contributor-identity family)
                  (ksawery-command-family-identity family)
                  (ksawery-command-family-label family))
            (append-map (lambda (argument)
                          (list (ksawery-command-argument-identity argument)
                                (ksawery-command-argument-label argument))) arguments)
            (append-map (lambda (choice) (list (ksawery-command-choice-identity choice)
                                               (ksawery-command-choice-label choice))) choices)
            (append-map (lambda (action) (list (ksawery-command-action-identity action)
                                               (ksawery-command-action-label action))) actions)))
  (define text-parts (map string->bytes/utf-8 texts))
  (define offsets
    (let loop ([parts text-parts] [offset (+ family-header-bytes
                                            (* (length arguments) argument-record-bytes)
                                            (* (length choices) choice-record-bytes)
                                            (* (length actions) action-record-bytes))]
               [result '()])
      (if (null? parts) (reverse result)
          (loop (cdr parts) (+ offset (bytes-length (car parts))) (cons offset result)))))
  (define cursor 3)
  (define choice-start 0)
  (define argument-records
    (for/list ([argument (in-list arguments)])
      (define identity-index cursor)
      (define label-index (add1 cursor))
      (set! cursor (+ cursor 2))
      (define record
        (words (ksawery-command-argument-id argument)
               (symbol-code (ksawery-command-argument-kind argument) argument-kind-codes)
               (if (ksawery-command-argument-required? argument) 1 0)
               (ksawery-command-argument-maximum-bytes argument)
               (list-ref offsets identity-index) (bytes-length (list-ref text-parts identity-index))
               (list-ref offsets label-index) (bytes-length (list-ref text-parts label-index))
               choice-start (length (ksawery-command-argument-choices argument))))
      (set! choice-start (+ choice-start (length (ksawery-command-argument-choices argument))))
      record))
  (define choice-records
    (for/list ([choice (in-list choices)])
      (define identity-index cursor)
      (define label-index (add1 cursor))
      (set! cursor (+ cursor 2))
      (words (ksawery-command-choice-id choice)
             (list-ref offsets identity-index) (bytes-length (list-ref text-parts identity-index))
             (list-ref offsets label-index) (bytes-length (list-ref text-parts label-index)))))
  (define action-records
    (for/list ([action (in-list actions)])
      (define identity-index cursor)
      (define label-index (add1 cursor))
      (set! cursor (+ cursor 2))
      (words (ksawery-command-action-id action)
             (symbol-code (ksawery-command-action-authority action) authority-codes)
             (symbol-set-code (ksawery-command-action-observations action) observations)
             (symbol-set-code (ksawery-command-action-targets action) target-families 1)
             (symbol-code (ksawery-command-action-operation action) operation-requirement-codes)
             (if (ksawery-command-action-mutates-repository? action) 1 0)
             (if (ksawery-command-action-confirmation-required? action) 1 0)
             (list-ref offsets identity-index) (bytes-length (list-ref text-parts identity-index))
             (list-ref offsets label-index) (bytes-length (list-ref text-parts label-index))
             (if (ksawery-command-action-core-operation action)
                 (add1 (index-of core-operations (ksawery-command-action-core-operation action)))
                 0))))
  (define total (+ (if (null? offsets) family-header-bytes
                       (+ (last offsets) (bytes-length (last text-parts)))) 0))
  (when (> total maximum-family-bytes)
    (raise-arguments-error 'encode-ksawery-command-family "family exceeds immutable byte limit"))
  (bytes-append
   (words schema-version total
          (ksawery-command-family-contributor-generation family)
          (ksawery-command-family-contribution family) (ksawery-command-family-id family)
          (ksawery-command-family-generation family)
          (symbol-set-code (ksawery-command-family-observations family) observations)
          (length arguments) (length actions) (length choices)
          (- total (+ family-header-bytes (* (length arguments) argument-record-bytes)
                      (* (length choices) choice-record-bytes) (* (length actions) action-record-bytes)))
          (list-ref offsets 0) (bytes-length (list-ref text-parts 0))
          (list-ref offsets 1) (bytes-length (list-ref text-parts 1))
          (list-ref offsets 2) (bytes-length (list-ref text-parts 2)) 0)
   (apply bytes-append argument-records)
   (apply bytes-append choice-records)
   (apply bytes-append action-records)
   (apply bytes-append text-parts)))

(define (validate-action-context who action context)
  (unless (and (memq (ksawery-command-context-observation context)
                     (ksawery-command-action-observations action))
               (operation-satisfied? (ksawery-command-action-operation action)
                                     (ksawery-command-context-operation-state context))
               (or (not (ksawery-command-action-mutates-repository? action))
                   (ksawery-command-context-mutation-available? context))
               (or (null? (ksawery-command-action-targets action))
                   (and (ksawery-command-context-target context)
                        (memq (ksawery-annotation-target-value-family
                               (ksawery-command-context-target context))
                              (ksawery-command-action-targets action)))))
    (raise-arguments-error who "action is unavailable in this command context")))

(define (validate-command-value value family context)
  (define definition
    (for/first ([entry (in-list (ksawery-command-family-arguments family))]
                #:when (= (ksawery-command-argument-id entry)
                          (ksawery-command-value-argument value))) entry))
  (unless (and definition (eq? (ksawery-command-argument-kind definition)
                               (ksawery-command-value-kind value)))
    (raise-arguments-error 'ksawery-command-request-action "argument kind is not admitted"))
  (define data (ksawery-command-value-value value))
  (case (ksawery-command-value-kind value)
    [(boolean)
     (unless (boolean? data)
       (raise-arguments-error 'ksawery-command-request-action "Boolean argument is malformed"))]
    [(closed-choice)
     (unless (and (exact-positive-integer? data)
                  (ormap (lambda (choice) (= (ksawery-command-choice-id choice) data))
                         (ksawery-command-argument-choices definition)))
       (raise-arguments-error 'ksawery-command-request-action "choice is not admitted"))]
    [(text)
     (unless (and (string? data)
                  (<= (bytes-length (string->bytes/utf-8 data))
                      (ksawery-command-argument-maximum-bytes definition)))
       (raise-arguments-error 'ksawery-command-request-action "text exceeds argument limit"))]
    [(opaque)
     (unless (and (bytes? data)
                  (<= (bytes-length data) (ksawery-command-argument-maximum-bytes definition)))
       (raise-arguments-error 'ksawery-command-request-action "opaque value exceeds argument limit"))]
    [(selection ref revision revision-range)
     (unless (and (ksawery-annotation-target-value? data)
                  (= (ksawery-annotation-target-value-generation data)
                     (ksawery-command-context-observation-generation context))
                  (target-supports-observation?
                   (ksawery-annotation-target-value-family data)
                   (ksawery-command-context-observation context))
                  (or (eq? (ksawery-command-value-kind value) 'selection)
                      (eq? (ksawery-command-value-kind value)
                           (ksawery-annotation-target-value-family data))))
       (raise-arguments-error 'ksawery-command-request-action "target argument is stale or incompatible"))]))

(define (operation-satisfied? requirement state)
  (case requirement
    [(any) #t] [(idle) (eq? state 'idle)]
    [(active) (memq state '(active sequence conflict))]
    [(sequence) (memq state '(sequence conflict))]
    [(conflict) (eq? state 'conflict)]))
(define (target-supports-observation? target observation)
  (case target
    [(path diff-unit) (eq? observation 'status)]
    [(revision revision-range) (eq? observation 'history)]
    [(ref remote) (eq? observation 'refs)]
    [(conflict) (memq observation '(conflict sequence))]
    [(sequence) (eq? observation 'sequence)]
    [(process) (eq? observation 'process)]))
(define (core-operation-supports-observation? operation observation)
  (cond
    [(memq operation '(stage unstage discard commit)) (eq? observation 'status)]
    [(memq operation '(amend fixup cherry-pick revert bisect bisect-good bisect-bad
                             bisect-skip bisect-reset))
     (eq? observation 'history)]
    [(memq operation '(fetch push create-branch switch-branch rename-branch delete-branch
                             create-tag delete-tag merge rebase))
     (eq? observation 'refs)]
    [(memq operation '(continue-merge abort-merge continue-rebase skip-rebase abort-rebase
                                      continue-cherry-pick skip-cherry-pick abort-cherry-pick
                                      continue-revert skip-revert abort-revert))
     (memq observation '(sequence conflict))]
    [(eq? operation 'resolve-conflict) (eq? observation 'conflict)]
    [else #f]))

(define (check-unique who entries id-accessor identity-accessor)
  (unless (and (= (length entries) (length (remove-duplicates (map id-accessor entries))))
               (= (length entries) (length (remove-duplicates (map identity-accessor entries)))))
    (raise-arguments-error who "identities must be unique")))
(define (validated-symbol-list who field entries admitted empty?)
  (unless (and (list? entries) (or empty? (pair? entries))
               (= (length entries) (length (remove-duplicates entries)))
               (andmap (lambda (entry) (memq entry admitted)) entries))
    (raise-arguments-error who "symbol list is invalid" field entries)) entries)
(define (validated-identity who value)
  (define text (if (symbol? value) (symbol->string value) value))
  (unless (and (string? text) (regexp-match? identity-pattern text)
               (<= (bytes-length (string->bytes/utf-8 text)) maximum-identity-bytes))
    (raise-arguments-error who "identity is invalid"))
  (string->immutable-string text))
(define (validated-text who value limit empty?)
  (unless (and (string? value) (or empty? (positive? (string-length value)))
               (<= (bytes-length (string->bytes/utf-8 value)) limit))
    (raise-arguments-error who "text is invalid or exceeds its byte limit"))
  (string->immutable-string value))
(define (check-member who field value admitted)
  (unless (memq value admitted) (raise-arguments-error who "value is not admitted" field value)))
(define (symbol-code value table) (cdr (assq value table)))
(define (symbol-set-code entries ordered [base 0])
  (for/fold ([mask 0]) ([entry (in-list entries)])
    (bitwise-ior mask (arithmetic-shift 1 (+ base (index-of ordered entry))))))
(define (code-symbol who code table)
  (define entry (for/first ([entry (in-list table)] #:when (= (cdr entry) code)) entry))
  (unless entry (raise-arguments-error who "numeric code is not admitted" "code" code))
  (car entry))
(define (input-word input offset)
  (integer-bytes->integer input #f #f offset (+ offset 8)))
(define (input-range input offset count minimum maximum empty?)
  (unless (and (<= minimum offset) (<= count maximum) (or empty? (positive? count))
               (<= offset (bytes-length input)) (<= count (- (bytes-length input) offset)))
    (raise-arguments-error 'decode-ksawery-command-context "copied byte range is invalid"))
  (subbytes input offset (+ offset count)))
(define (words . values)
  (apply bytes-append (map (lambda (value) (integer->integer-bytes value 8 #f #f)) values)))
