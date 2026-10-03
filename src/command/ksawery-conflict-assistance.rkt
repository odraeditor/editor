#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         "ksawery-extension.rkt"
         "ksawery-operation.rkt")

(provide
 (struct-out ksawery-conflict-provider)
 (struct-out ksawery-conflict-target)
 (struct-out ksawery-conflict-side)
 (struct-out ksawery-conflict-observation)
 (struct-out ksawery-conflict-selection-change)
 (struct-out ksawery-conflict-diagnostic)
 (struct-out ksawery-conflict-response)
 (contract-out
  [make-ksawery-conflict-provider
   (->* (ksawery-contributor? exact-positive-integer? exact-positive-integer?
                              exact-positive-integer? (or/c symbol? string?) string?
                              (listof symbol?) (listof symbol?))
        (#:lifecycle symbol?)
        ksawery-conflict-provider?)]
  [encode-ksawery-conflict-provider (-> ksawery-conflict-provider? bytes?)]
  [decode-ksawery-conflict-observation (-> bytes? ksawery-conflict-observation?)]
  [make-ksawery-conflict-selection-change
   (->* (symbol? exact-positive-integer? exact-nonnegative-integer?
                 exact-positive-integer? symbol?)
        (#:provider (or/c #f ksawery-conflict-provider?)
         #:scope-identity (or/c #f symbol? string?)
         #:repository (or/c #f string?)
         #:session exact-nonnegative-integer?)
        ksawery-conflict-selection-change?)]
  [encode-ksawery-conflict-selection-change
   (-> ksawery-conflict-selection-change? bytes?)]
  [make-ksawery-conflict-diagnostic
   (-> symbol? string? ksawery-conflict-diagnostic?)]
  [make-ksawery-conflict-decline
   (->* (exact-positive-integer? ksawery-conflict-provider?)
        (#:diagnostic (or/c #f ksawery-conflict-diagnostic?))
        ksawery-conflict-response?)]
  [make-ksawery-conflict-guidance
   (->* (exact-positive-integer? ksawery-conflict-provider? string?)
        (#:diagnostic (or/c #f ksawery-conflict-diagnostic?))
        ksawery-conflict-response?)]
  [make-ksawery-conflict-editor
   (->* (exact-positive-integer? ksawery-conflict-provider?)
        (#:diagnostic (or/c #f ksawery-conflict-diagnostic?))
        ksawery-conflict-response?)]
  [make-ksawery-conflict-tool-proposal
   (->* (exact-positive-integer? ksawery-conflict-provider? symbol?
                                 ksawery-operation-plan?)
        (#:diagnostic (or/c #f ksawery-conflict-diagnostic?))
        ksawery-conflict-response?)]
  [encode-ksawery-conflict-response (-> ksawery-conflict-response? bytes?)]))

(define schema-version 1)
(define provider-header-bytes 144)
(define observation-header-bytes 160)
(define side-record-bytes 64)
(define selection-record-bytes 160)
(define response-record-bytes 128)
(define maximum-path-bytes (* 4 1024))
(define maximum-guidance-bytes (* 32 1024))
(define maximum-content-bytes (* 4 1024 1024))
(define maximum-copy-bytes (* 8 1024 1024))
(define maximum-diagnostic-bytes (* 64 1024))
(define maximum-identity-bytes 96)
(define maximum-label-bytes 128)
(define classes
  '(text binary rename delete type-change submodule missing-stage truncated unsupported))
(define capability-vocabulary '(present-guidance open-editor submit-external-tool))
(define lifecycles
  '(declared prepared confirmed active declined failed disabled replaced retiring closed))
(define conflict-kinds
  '(both-modified added-by-both deleted-by-us deleted-by-them
                  added-by-us added-by-them both-deleted other))
(define side-kinds '(base current applied worktree))
(define material-kinds '(missing text binary submodule omitted))
(define selection-actions '(select replace disable))
(define selection-scopes '(global project repository session))
(define response-kinds '(declined guidance editor external-tool))
(define tool-accesses '(read-only worktree-only))
(define diagnostic-codes
  '(none invalid-provider invalid-contribution invalid-target unsupported-conflict
         invalid-side invalid-guidance invalid-tool-plan invalid-lifecycle
         invalid-selection invalid-response stale-contributor stale-provider
         stale-selection stale-repository stale-observation stale-target
         provider-limit guidance-limit content-limit copy-limit provider-declined
         provider-exception tool-unavailable index-mutation-prohibited
         core-action-prohibited allocation cleanup))

(struct ksawery-conflict-provider
  (contributor-identity contributor-generation contribution id generation
                        identity label supported-classes capabilities lifecycle)
  #:transparent)
(struct ksawery-conflict-target
  (repository repository-generation worktree-generation observation-generation
              sequence-generation sequence-fingerprint conflict-id kind classes path)
  #:transparent)
(struct ksawery-conflict-side (kind material mode object content truncated?) #:transparent)
(struct ksawery-conflict-observation (target sides truncated?) #:transparent)
(struct ksawery-conflict-selection-change
  (action selection previous-generation next-generation scope scope-identity
          repository session provider confirmed?)
  #:transparent)
(struct ksawery-conflict-diagnostic (code message) #:transparent)
(struct ksawery-conflict-response
  (request provider kind guidance tool-access operation diagnostic)
  #:transparent)

;; make-ksawery-conflict-provider constructs one inert replaceable-role declaration.
(define (make-ksawery-conflict-provider contributor contribution id generation
                                        identity label supported-classes capabilities
                                        #:lifecycle [lifecycle 'declared])
  (define data (ksawery-contributor->datum contributor))
  (define declaration
    (for/first ([entry (in-list (hash-ref data 'contributions))]
                #:when (= (hash-ref entry 'id) contribution)) entry))
  (define copied-classes
    (validated-symbol-list 'make-ksawery-conflict-provider 'supported-classes
                           supported-classes classes #f))
  (define copied-capabilities
    (validated-symbol-list 'make-ksawery-conflict-provider 'capabilities
                           capabilities capability-vocabulary #f))
  (check-member 'make-ksawery-conflict-provider 'lifecycle lifecycle lifecycles)
  (unless (> id 1)
    (raise-arguments-error 'make-ksawery-conflict-provider
                           "extension provider identity collides with the built-in fallback"))
  (unless (and declaration
               (eq? (hash-ref declaration 'kind) 'provider-role)
               (eq? (hash-ref declaration 'provider-role) 'conflict-assistance)
               (andmap (lambda (entry) (memq entry (hash-ref declaration 'observations)))
                       '(sequence conflict))
               (andmap (lambda (entry) (memq entry (hash-ref declaration 'authorities)))
                       '(inspect present assist-conflict))
               (or (not (memq 'submit-external-tool copied-capabilities))
                   (memq 'submit-external-operation
                         (hash-ref declaration 'authorities))))
    (raise-arguments-error 'make-ksawery-conflict-provider
                           "contribution does not admit conflict assistance"))
  (ksawery-conflict-provider
   (hash-ref data 'identity) (hash-ref data 'generation) contribution id generation
   (validated-identity 'make-ksawery-conflict-provider identity)
   (validated-text 'make-ksawery-conflict-provider 'label label maximum-label-bytes #f)
   copied-classes copied-capabilities lifecycle))

;; encode-ksawery-conflict-provider emits one fixed header and copied public text.
(define (encode-ksawery-conflict-provider provider)
  (define parts
    (map string->bytes/utf-8
         (list (ksawery-conflict-provider-contributor-identity provider)
               (ksawery-conflict-provider-identity provider)
               (ksawery-conflict-provider-label provider))))
  (define payload (apply bytes-append parts))
  (define identity-offset (bytes-length (car parts)))
  (define label-offset (+ identity-offset (bytes-length (cadr parts))))
  (bytes-append
   (words
    schema-version (+ provider-header-bytes (bytes-length payload)) 2
    (ksawery-conflict-provider-contributor-generation provider)
    (ksawery-conflict-provider-contribution provider)
    (ksawery-conflict-provider-id provider)
    (ksawery-conflict-provider-generation provider)
    (class-set-code (ksawery-conflict-provider-supported-classes provider))
    (symbol-set-code (ksawery-conflict-provider-capabilities provider)
                     capability-vocabulary)
    (add1 (index-of lifecycles (ksawery-conflict-provider-lifecycle provider)))
    0 (bytes-length (car parts))
    identity-offset (bytes-length (cadr parts))
    label-offset (bytes-length (caddr parts))
    (bytes-length payload) 0)
   payload))

;; decode-ksawery-conflict-observation copies one fixed native Conflict payload.
(define (decode-ksawery-conflict-observation input)
  (define fixed-bytes (+ observation-header-bytes (* 4 side-record-bytes)))
  (unless (and (>= (bytes-length input) fixed-bytes)
               (<= (bytes-length input) (+ fixed-bytes maximum-copy-bytes)))
    (raise-arguments-error 'decode-ksawery-conflict-observation
                           "Conflict observation header is incomplete"))
  (define header (for/list ([index (in-range 20)]) (input-word input (* 8 index))))
  (define payload (subbytes input fixed-bytes))
  (unless (and (= (list-ref header 0) schema-version)
               (= (list-ref header 1) (bytes-length input))
               (= (list-ref header 10) 4)
               (= (list-ref header 11) (bytes-length payload))
               (andmap zero? (drop header 17)))
    (raise-arguments-error 'decode-ksawery-conflict-observation
                           "Conflict observation header is invalid"))
  (define repository
    (validated-text
     'decode-ksawery-conflict-observation 'repository
     (bytes->string/utf-8
      (payload-range payload (list-ref header 12) (list-ref header 13)
                     maximum-path-bytes #f))
     maximum-path-bytes #f))
  (unless (char=? (string-ref repository 0) #\/)
    (raise-arguments-error 'decode-ksawery-conflict-observation
                           "repository path is not absolute"))
  (define path
    (validated-text
     'decode-ksawery-conflict-observation 'path
     (bytes->string/utf-8
      (payload-range payload (list-ref header 14) (list-ref header 15)
                     maximum-path-bytes #f))
     maximum-path-bytes #f))
  (define decoded-classes (decode-class-set (list-ref header 9)))
  (define target
    (ksawery-conflict-target
     (string->immutable-string repository)
     (validated-generation 'decode-ksawery-conflict-observation (list-ref header 2))
     (validated-generation 'decode-ksawery-conflict-observation (list-ref header 3))
     (validated-generation 'decode-ksawery-conflict-observation (list-ref header 4))
     (validated-generation 'decode-ksawery-conflict-observation (list-ref header 5))
     (validated-generation 'decode-ksawery-conflict-observation (list-ref header 6))
     (validated-generation 'decode-ksawery-conflict-observation (list-ref header 7))
     (code-symbol 'decode-ksawery-conflict-observation (list-ref header 8)
                  conflict-kinds 1)
     decoded-classes (string->immutable-string path)))
  (define sides
    (for/list ([index (in-range 4)])
      (define base (+ observation-header-bytes (* index side-record-bytes)))
      (define values (for/list ([field (in-range 8)])
                       (input-word input (+ base (* field 8)))))
      (define kind (code-symbol 'decode-ksawery-conflict-observation
                                (list-ref values 0) side-kinds 1))
      (unless (eq? kind (list-ref side-kinds index))
        (raise-arguments-error 'decode-ksawery-conflict-observation
                               "Conflict side order is invalid"))
      (define material (code-symbol 'decode-ksawery-conflict-observation
                                    (list-ref values 1) material-kinds 1))
      (define object
        (if (zero? (list-ref values 4)) #f
            (bytes->immutable-bytes
             (payload-range payload (list-ref values 3) (list-ref values 4) 64 #f))))
      (define content
        (payload-range payload (list-ref values 5) (list-ref values 6)
                       maximum-content-bytes #t))
      (unless (or (and (eq? material 'missing)
                       (zero? (list-ref values 2)) (not object)
                       (zero? (bytes-length content)) (zero? (list-ref values 7)))
                  (and (not (eq? material 'missing))
                       (positive? (list-ref values 2))
                       (if (eq? kind 'worktree) (not object)
                           (and object (valid-object-bytes? object)))
                       (if (eq? material 'omitted)
                           (and (zero? (bytes-length content)) (= (list-ref values 7) 1))
                           #t)
                       (<= (list-ref values 7) 1)))
        (raise-arguments-error 'decode-ksawery-conflict-observation
                               "Conflict side is inconsistent"))
      (when (and (eq? material 'text)
                 (not (valid-utf8-bytes? content)))
        (raise-arguments-error 'decode-ksawery-conflict-observation
                               "Conflict text side is not UTF-8"))
      (ksawery-conflict-side kind material (list-ref values 2) object
                             (bytes->immutable-bytes content)
                             (= (list-ref values 7) 1))))
  (unless (<= (for/sum ([side (in-list sides)])
                (bytes-length (ksawery-conflict-side-content side)))
              maximum-content-bytes)
    (raise-arguments-error 'decode-ksawery-conflict-observation
                           "copied Conflict content exceeds immutable policy"))
  (define truncated? (= (list-ref header 16) 1))
  (unless (and (<= (list-ref header 16) 1)
               (equal? truncated? (ormap ksawery-conflict-side-truncated? sides))
               (equal? truncated? (and (memq 'truncated decoded-classes) #t)))
    (raise-arguments-error 'decode-ksawery-conflict-observation
                           "Conflict truncation evidence is inconsistent"))
  (ksawery-conflict-observation target sides truncated?))

;; make-ksawery-conflict-selection-change constructs select, replace, or disable state.
(define (make-ksawery-conflict-selection-change
         action selection previous-generation next-generation scope
         #:provider [provider #f]
         #:scope-identity [scope-identity #f]
         #:repository [repository #f]
         #:session [session 0])
  (check-member 'make-ksawery-conflict-selection-change 'action action selection-actions)
  (check-member 'make-ksawery-conflict-selection-change 'scope scope selection-scopes)
  (unless (and (if (eq? action 'select) (zero? previous-generation)
                  (positive? previous-generation))
               (or (zero? previous-generation) (> next-generation previous-generation)))
    (raise-arguments-error 'make-ksawery-conflict-selection-change
                           "selection generations are inconsistent"))
  (unless (if (eq? action 'disable) (not provider) provider)
    (raise-arguments-error 'make-ksawery-conflict-selection-change
                           "provider does not match selection action"))
  (define copied-scope
    (and scope-identity
         (validated-identity 'make-ksawery-conflict-selection-change scope-identity)))
  (define copied-repository
    (and repository
         (validated-text 'make-ksawery-conflict-selection-change 'repository
                         repository maximum-path-bytes #f)))
  (when (and copied-repository
             (not (char=? (string-ref copied-repository 0) #\/)))
    (raise-arguments-error 'make-ksawery-conflict-selection-change
                           "repository scope path must be absolute"))
  (unless
      (case scope
        [(global) (and (not copied-scope) (not copied-repository) (zero? session))]
        [(project) (and copied-scope (not copied-repository) (zero? session))]
        [(repository) (and (not copied-scope) copied-repository (zero? session))]
        [(session) (and (not copied-scope) (not copied-repository) (positive? session))])
    (raise-arguments-error 'make-ksawery-conflict-selection-change
                           "selection scope fields are inconsistent"))
  (ksawery-conflict-selection-change
   action selection previous-generation next-generation scope copied-scope
   copied-repository session provider (not (eq? action 'disable))))

;; encode-ksawery-conflict-selection-change emits one fixed role transition.
(define (encode-ksawery-conflict-selection-change change)
  (define provider (ksawery-conflict-selection-change-provider change))
  (define disabled? (not provider))
  (define contributor-bytes
    (if disabled? #""
        (string->bytes/utf-8 (ksawery-conflict-provider-contributor-identity provider))))
  (define scope-bytes
    (if (ksawery-conflict-selection-change-scope-identity change)
        (string->bytes/utf-8 (ksawery-conflict-selection-change-scope-identity change)) #""))
  (define repository-bytes
    (if (ksawery-conflict-selection-change-repository change)
        (string->bytes/utf-8 (ksawery-conflict-selection-change-repository change)) #""))
  (define payload (bytes-append contributor-bytes scope-bytes repository-bytes))
  (define scope-offset (bytes-length contributor-bytes))
  (define repository-offset (+ scope-offset (bytes-length scope-bytes)))
  (bytes-append
   (words
    schema-version (+ selection-record-bytes (bytes-length payload))
    (add1 (index-of selection-actions (ksawery-conflict-selection-change-action change)))
    (ksawery-conflict-selection-change-selection change)
    (ksawery-conflict-selection-change-previous-generation change)
    (ksawery-conflict-selection-change-next-generation change)
    (+ 2 (index-of selection-scopes (ksawery-conflict-selection-change-scope change)))
    (if disabled? 1 2)
    (if disabled? 0 (ksawery-conflict-provider-contributor-generation provider))
    (if disabled? 1 (ksawery-conflict-provider-id provider))
    (if disabled? 1 (ksawery-conflict-provider-generation provider))
    (if (zero? (bytes-length scope-bytes)) 0 scope-offset) (bytes-length scope-bytes)
    (if (zero? (bytes-length repository-bytes)) 0 repository-offset)
    (bytes-length repository-bytes)
    (ksawery-conflict-selection-change-session change)
    (if (ksawery-conflict-selection-change-confirmed? change) 1 0)
    (bytes-length payload)
    (if disabled? 0 0) (bytes-length contributor-bytes))
   payload))

;; make-ksawery-conflict-diagnostic copies one attributable public failure summary.
(define (make-ksawery-conflict-diagnostic code message)
  (check-member 'make-ksawery-conflict-diagnostic 'code code (cdr diagnostic-codes))
  (ksawery-conflict-diagnostic
   code (validated-text 'make-ksawery-conflict-diagnostic 'message
                        message maximum-diagnostic-bytes #f)))

;; make-ksawery-conflict-decline returns an authority-free decline response.
(define (make-ksawery-conflict-decline request provider #:diagnostic [diagnostic #f])
  (make-response request provider 'declined #f #f #f diagnostic))

;; make-ksawery-conflict-guidance returns one bounded public guidance response.
(define (make-ksawery-conflict-guidance request provider guidance
                                        #:diagnostic [diagnostic #f])
  (unless (memq 'present-guidance (ksawery-conflict-provider-capabilities provider))
    (raise-arguments-error 'make-ksawery-conflict-guidance
                           "provider does not declare guidance"))
  (make-response
   request provider 'guidance
   (validated-text 'make-ksawery-conflict-guidance 'guidance guidance
                   maximum-guidance-bytes #f)
   #f #f diagnostic))

;; make-ksawery-conflict-editor returns one ordinary editor-workflow proposal.
(define (make-ksawery-conflict-editor request provider #:diagnostic [diagnostic #f])
  (unless (memq 'open-editor (ksawery-conflict-provider-capabilities provider))
    (raise-arguments-error 'make-ksawery-conflict-editor
                           "provider does not declare editor assistance"))
  (make-response request provider 'editor #f #f #f diagnostic))

;; make-ksawery-conflict-tool-proposal returns one inert admitted external plan.
(define (make-ksawery-conflict-tool-proposal request provider access operation
                                             #:diagnostic [diagnostic #f])
  (check-member 'make-ksawery-conflict-tool-proposal 'access access tool-accesses)
  (unless (memq 'submit-external-tool (ksawery-conflict-provider-capabilities provider))
    (raise-arguments-error 'make-ksawery-conflict-tool-proposal
                           "provider does not declare an external tool"))
  (unless (and (string=? (ksawery-operation-plan-contributor-identity operation)
                         (ksawery-conflict-provider-contributor-identity provider))
               (= (ksawery-operation-plan-contributor-generation operation)
                  (ksawery-conflict-provider-contributor-generation provider))
               (= (length (ksawery-operation-plan-refresh operation)) 4)
               (andmap (lambda (entry)
                         (memq entry (ksawery-operation-plan-refresh operation)))
                       '(status sequence conflict process))
               (case access
                 [(read-only) (eq? (ksawery-operation-plan-effect operation) 'read-only)]
                 [(worktree-only)
                  (eq? (ksawery-operation-plan-effect operation) 'repository-mutating)]))
    (raise-arguments-error 'make-ksawery-conflict-tool-proposal
                           "operation plan exceeds conflict-tool authority"))
  (make-response request provider 'external-tool #f access operation diagnostic))

;; encode-ksawery-conflict-response emits one fixed response plus copied content.
(define (encode-ksawery-conflict-response response)
  (define guidance-bytes
    (if (ksawery-conflict-response-guidance response)
        (string->bytes/utf-8 (ksawery-conflict-response-guidance response)) #""))
  (define operation-bytes
    (if (ksawery-conflict-response-operation response)
        (encode-ksawery-operation-plan (ksawery-conflict-response-operation response)) #""))
  (define diagnostic (ksawery-conflict-response-diagnostic response))
  (define diagnostic-bytes
    (if diagnostic (string->bytes/utf-8 (ksawery-conflict-diagnostic-message diagnostic)) #""))
  (define payload (bytes-append guidance-bytes operation-bytes diagnostic-bytes))
  (when (> (+ response-record-bytes (bytes-length payload)) maximum-copy-bytes)
    (raise-arguments-error 'encode-ksawery-conflict-response
                           "response exceeds immutable copy policy"))
  (define provider (ksawery-conflict-response-provider response))
  (define guidance-offset 0)
  (define operation-offset (bytes-length guidance-bytes))
  (define diagnostic-offset (+ operation-offset (bytes-length operation-bytes)))
  (bytes-append
   (words
    schema-version (+ response-record-bytes (bytes-length payload))
    (ksawery-conflict-response-request response)
    (ksawery-conflict-provider-id provider)
    (ksawery-conflict-provider-generation provider)
    (add1 (index-of response-kinds (ksawery-conflict-response-kind response)))
    (if (ksawery-conflict-response-tool-access response)
        (add1 (index-of tool-accesses (ksawery-conflict-response-tool-access response))) 0)
    (if (zero? (bytes-length guidance-bytes)) 0 guidance-offset)
    (bytes-length guidance-bytes)
    (if (zero? (bytes-length operation-bytes)) 0 operation-offset)
    (bytes-length operation-bytes)
    (if diagnostic (index-of diagnostic-codes (ksawery-conflict-diagnostic-code diagnostic)) 0)
    (if (zero? (bytes-length diagnostic-bytes)) 0 diagnostic-offset)
    (bytes-length diagnostic-bytes)
    (bytes-length payload)
    (ksawery-conflict-provider-contributor-generation provider))
   payload))

(define (make-response request provider kind guidance access operation diagnostic)
  (unless (exact-positive-integer? request)
    (raise-argument-error 'make-ksawery-conflict-response
                          "exact-positive-integer?" request))
  (when (and diagnostic (not (ksawery-conflict-diagnostic? diagnostic)))
    (raise-argument-error 'make-ksawery-conflict-response
                          "ksawery-conflict-diagnostic?" diagnostic))
  (ksawery-conflict-response request provider kind guidance access operation diagnostic))

(define (validated-generation who value)
  (unless (and (exact-positive-integer? value) (<= value #xffffffffffffffff))
    (raise-argument-error who "positive 64-bit generation" value))
  value)

(define (validated-identity who value)
  (define copied (if (symbol? value) (symbol->string value) value))
  (unless (and (string? copied)
               (regexp-match? #px"^[a-z][a-z0-9]*(?:[./-][a-z0-9]+)*$" copied)
               (<= (bytes-length (string->bytes/utf-8 copied)) maximum-identity-bytes))
    (raise-argument-error who "bounded lowercase semantic identity" value))
  (string->immutable-string copied))

(define (validated-text who field value maximum empty?)
  (unless (and (string? value) (or empty? (positive? (string-length value)))
               (<= (bytes-length (string->bytes/utf-8 value)) maximum)
               (for/and ([character (in-string value)])
                 (define code (char->integer character))
                 (not (or (< code 32) (<= 127 code 159)))))
    (raise-arguments-error who "invalid or oversized public text"
                           (symbol->string field) value))
  (string->immutable-string value))

(define (validated-symbol-list who field entries admitted empty?)
  (unless (and (list? entries) (or empty? (pair? entries))
               (= (length entries) (length (remove-duplicates entries)))
               (andmap (lambda (entry) (memq entry admitted)) entries))
    (raise-arguments-error who "invalid or duplicate closed values"
                           (symbol->string field) entries))
  (map values entries))

(define (check-member who field value admitted)
  (unless (memq value admitted)
    (raise-arguments-error who "value is outside the closed vocabulary"
                           (symbol->string field) value)))

(define (class-set-code values)
  (for/fold ([result 0]) ([value (in-list values)])
    (bitwise-ior result (arithmetic-shift 1 (add1 (index-of classes value))))))

(define (symbol-set-code values vocabulary)
  (for/fold ([result 0]) ([value (in-list values)])
    (bitwise-ior result (arithmetic-shift 1 (index-of vocabulary value)))))

(define (decode-class-set mask)
  (unless (and (positive? mask) (zero? (bitwise-and mask (bitwise-not #x3fe))))
    (raise-arguments-error 'decode-ksawery-conflict-observation
                           "Conflict class mask is invalid"))
  (for/list ([value (in-list classes)] [index (in-naturals 1)]
             #:when (bitwise-bit-set? mask index))
    value))

(define (code-symbol who code vocabulary base)
  (define index (- code base))
  (unless (and (exact-nonnegative-integer? index) (< index (length vocabulary)))
    (raise-arguments-error who "numeric code is outside the closed vocabulary"
                           "code" code))
  (list-ref vocabulary index))

(define (input-word input offset)
  (unless (<= (+ offset 8) (bytes-length input))
    (raise-arguments-error 'decode-ksawery-conflict-observation
                           "word exceeds the copied observation"))
  (integer-bytes->integer input #f #f offset (+ offset 8)))

(define (payload-range payload offset length maximum empty?)
  (cond
    [(zero? length)
     (unless (and empty? (zero? offset))
       (raise-arguments-error 'decode-ksawery-conflict-observation
                              "empty range has an invalid offset"))
     #""]
    [(or (> length maximum) (> offset (bytes-length payload))
         (> length (- (bytes-length payload) offset)))
     (raise-arguments-error 'decode-ksawery-conflict-observation
                            "range exceeds the copied observation")]
    [else (bytes->immutable-bytes (subbytes payload offset (+ offset length)))]))

(define (valid-utf8-bytes? value)
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (bytes->string/utf-8 value)
    #t))

(define (valid-object-bytes? value)
  (and (memq (bytes-length value) '(40 64))
       (for/and ([byte (in-bytes value)])
         (or (<= (char->integer #\0) byte (char->integer #\9))
             (<= (char->integer #\a) byte (char->integer #\f))))))

(define (words . values)
  (apply bytes-append
         (map (lambda (value) (integer->integer-bytes value 8 #f #f)) values)))
