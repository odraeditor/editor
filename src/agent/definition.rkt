#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         racket/string)

(provide
 agent-substrate-api-version
 admitted-agent-interaction-kinds
 admitted-agent-effect-classes
 default-agent-resource-profile
 default-agent-capability-limits
 agent-schema?
 (struct-out odra-agent-resource-profile)
 (struct-out odra-agent-capability-limits)
 (struct-out odra-agent-definition)
 (struct-out odra-agent-capability-definition)
 (contract-out
  [make-agent-resource-profile
   (->* ()
        (#:turn-deadline-milliseconds exact-positive-integer?
         #:context-bytes exact-positive-integer?
         #:output-bytes exact-positive-integer?
         #:provider-events exact-positive-integer?)
        odra-agent-resource-profile?)]
  [make-agent-capability-limits
   (->* ()
        (#:deadline-milliseconds exact-positive-integer?
         #:input-bytes exact-positive-integer?
         #:result-bytes exact-positive-integer?
         #:target-references exact-positive-integer?)
        odra-agent-capability-limits?)]
  [make-agent
   (->* ((or/c symbol? string?))
        (#:display-name string?
         #:description string?
         #:interaction-kinds list?
         #:provider-requirements list?
         #:requested-capabilities list?
         #:resource-profile odra-agent-resource-profile?
         #:continuation-policy symbol?
         #:source string?
         #:location string?)
        odra-agent-definition?)]
  [agent? (-> any/c boolean?)]
  [make-agent-capability
   (->* ((or/c symbol? string?) (or/c symbol? string?) procedure?)
        (#:purpose string?
         #:input-schema any/c
         #:result-schema any/c
         #:target-kinds list?
         #:effects list?
         #:required-authorities list?
         #:default-limits odra-agent-capability-limits?
         #:hard-limits odra-agent-capability-limits?
         #:approval-class symbol?
         #:idempotency-class symbol?
         #:verification-class symbol?
         #:retirement-policy symbol?
         #:source string?
         #:location string?)
        odra-agent-capability-definition?)]
  [agent-capability? (-> any/c boolean?)]))

(define agent-substrate-api-version 1)

(define maximum-identity-bytes 128)
(define maximum-label-bytes 256)
(define maximum-description-bytes 4096)
(define maximum-source-bytes 512)
(define maximum-list-items 256)
(define maximum-schema-depth 8)
(define maximum-schema-fields 64)
(define maximum-schema-value-bytes (* 64 1024))

(define maximum-turn-deadline-milliseconds (* 15 60 1000))
(define maximum-context-bytes (* 1024 1024))
(define maximum-output-bytes (* 256 1024))
(define maximum-provider-events 4096)
(define maximum-capability-deadline-milliseconds (* 5 60 1000))
(define maximum-capability-value-bytes (* 64 1024))
(define maximum-target-references 32)

(define admitted-agent-interaction-kinds
  '(acknowledgement cancellation decision failure progress proposal question
                    request result))
(define admitted-agent-effect-classes
  '(credential-use external-commit filesystem-read filesystem-write
                   mutate-editor-state mutate-owned-state network-access
                   observe process-execution propose))
(define admitted-continuation-policies '(none bounded))
(define admitted-approval-classes '(always ask-once policy))
(define admitted-idempotency-classes
  '(deduplicated idempotent non-idempotent owner-defined read-only))
(define admitted-verification-classes
  '(deferred immediate not-required owner-defined))
(define admitted-retirement-policies '(cancel finish reconcile))

(define identity-pattern #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")

(define (bounded-text? value maximum #:empty? [empty? #f])
  (and (string? value)
       (or empty? (positive? (string-length value)))
       (not (string-contains? value (string #\nul)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(define (identity-text value)
  (cond
    [(symbol? value) (symbol->string value)]
    [(string? value) value]
    [else #f]))

(define (identity? value)
  (define text (identity-text value))
  (and text
       (bounded-text? text maximum-identity-bytes)
       (regexp-match? identity-pattern text)))

(define (copied-identity value who field)
  (define text (identity-text value))
  (unless (identity? value)
    (raise-arguments-error who "invalid semantic identity" field value))
  (string->immutable-string text))

(define (symbol<? left right)
  (string<? (symbol->string left) (symbol->string right)))

(define (identity<? left right)
  (string<? (identity-text left) (identity-text right)))

(define (canonical-symbol-set? values admitted maximum)
  (and (list? values)
       (<= (length values) maximum)
       (andmap symbol? values)
       (equal? values (sort (remove-duplicates values) symbol<?))
       (andmap (lambda (value) (and (memq value admitted) #t)) values)))

(define (canonical-identity-set? values maximum)
  (and (list? values)
       (<= (length values) maximum)
       (andmap identity? values)
       (equal? values (sort (remove-duplicates values equal?) identity<?))))

(define (immutable-copy value)
  (cond
    [(string? value) (string->immutable-string value)]
    [(bytes? value) (bytes->immutable-bytes value)]
    [(pair? value) (map immutable-copy value)]
    [else value]))

(define (agent-schema? value)
  (define (valid? value depth)
    (and
     (<= depth maximum-schema-depth)
     (cond
       [(eq? value 'boolean) #t]
       [(not (list? value)) #f]
       [(null? value) #f]
       [else
        (case (car value)
          [(integer)
           (and (= (length value) 3)
                (exact-integer? (cadr value))
                (exact-integer? (caddr value))
                (<= (cadr value) (caddr value)))]
          [(string bytes)
           (and (= (length value) 2)
                (exact-positive-integer? (cadr value))
                (<= (cadr value) maximum-schema-value-bytes))]
          [(enum)
           (and (<= 2 (length value) (add1 maximum-schema-fields))
                (canonical-identity-set? (cdr value) maximum-schema-fields))]
          [(optional)
           (and (= (length value) 2) (valid? (cadr value) (add1 depth)))]
          [(list)
           (and (= (length value) 3)
                (exact-positive-integer? (cadr value))
                (<= (cadr value) maximum-list-items)
                (valid? (caddr value) (add1 depth)))]
          [(map)
           (and (= (length value) 4)
                (exact-positive-integer? (cadr value))
                (<= (cadr value) maximum-list-items)
                (valid? (caddr value) (add1 depth))
                (valid? (cadddr value) (add1 depth)))]
          [(record)
           (define fields (cdr value))
           (and (<= (length fields) maximum-schema-fields)
                (for/and ([field (in-list fields)])
                  (and (list? field)
                       (= (length field) 3)
                       (identity? (car field))
                       (memq (cadr field) '(optional required))
                       (valid? (caddr field) (add1 depth))))
                (let ([names (map car fields)])
                  (equal? names
                          (sort (remove-duplicates names equal?) identity<?))))]
          [(owner-reference)
           (and (= (length value) 3)
                (identity? (cadr value))
                (exact-positive-integer? (caddr value)))]
          [else #f])])))
  (and (valid? value 0) #t))

(struct odra-agent-resource-profile
  (turn-deadline-milliseconds context-bytes output-bytes provider-events)
  #:transparent
  #:guard
  (lambda (deadline context output events _)
    (unless (and (exact-positive-integer? deadline)
                 (<= deadline maximum-turn-deadline-milliseconds)
                 (exact-positive-integer? context)
                 (<= context maximum-context-bytes)
                 (exact-positive-integer? output)
                 (<= output maximum-output-bytes)
                 (exact-positive-integer? events)
                 (<= events maximum-provider-events))
      (raise-arguments-error 'make-agent-resource-profile
                             "invalid bounded agent resource profile"))
    (values deadline context output events)))

(define (make-agent-resource-profile
         #:turn-deadline-milliseconds [deadline 60000]
         #:context-bytes [context (* 256 1024)]
         #:output-bytes [output (* 64 1024)]
         #:provider-events [events 1024])
  (odra-agent-resource-profile deadline context output events))

(define default-agent-resource-profile (make-agent-resource-profile))

(struct odra-agent-capability-limits
  (deadline-milliseconds input-bytes result-bytes target-references)
  #:transparent
  #:guard
  (lambda (deadline input result targets _)
    (unless (and (exact-positive-integer? deadline)
                 (<= deadline maximum-capability-deadline-milliseconds)
                 (exact-positive-integer? input)
                 (<= input maximum-capability-value-bytes)
                 (exact-positive-integer? result)
                 (<= result maximum-capability-value-bytes)
                 (exact-positive-integer? targets)
                 (<= targets maximum-target-references))
      (raise-arguments-error 'make-agent-capability-limits
                             "invalid bounded capability limits"))
    (values deadline input result targets)))

(define (make-agent-capability-limits
         #:deadline-milliseconds [deadline 30000]
         #:input-bytes [input (* 16 1024)]
         #:result-bytes [result (* 16 1024)]
         #:target-references [targets 8])
  (odra-agent-capability-limits deadline input result targets))

(define default-agent-capability-limits (make-agent-capability-limits))

(struct odra-agent-definition
  (identity display-name description interaction-kinds provider-requirements
            requested-capabilities resource-profile continuation-policy
            api-version source location)
  #:transparent)

(define (make-agent identity
                    #:display-name [display-name ""]
                    #:description [description ""]
                    #:interaction-kinds
                    [interaction-kinds '(progress request result)]
                    #:provider-requirements [provider-requirements '()]
                    #:requested-capabilities [requested-capabilities '()]
                    #:resource-profile
                    [resource-profile default-agent-resource-profile]
                    #:continuation-policy [continuation-policy 'none]
                    #:source [source "package contribution"]
                    #:location [location ""])
  (define normalized-identity
    (copied-identity identity 'make-agent "identity"))
  (define normalized-display
    (if (string=? display-name "") normalized-identity display-name))
  (unless (and (bounded-text? normalized-display maximum-label-bytes)
               (bounded-text? description maximum-description-bytes #:empty? #t)
               (canonical-symbol-set?
                interaction-kinds admitted-agent-interaction-kinds
                maximum-list-items)
               (canonical-identity-set? provider-requirements maximum-list-items)
               (canonical-identity-set? requested-capabilities maximum-list-items)
               (odra-agent-resource-profile? resource-profile)
               (memq continuation-policy admitted-continuation-policies)
               (bounded-text? source maximum-source-bytes)
               (bounded-text? location maximum-source-bytes #:empty? #t))
    (raise-arguments-error 'make-agent "invalid bounded agent definition"
                           "identity" identity))
  (odra-agent-definition
   normalized-identity
   (string->immutable-string normalized-display)
   (string->immutable-string description)
   interaction-kinds
   (map (lambda (value)
          (string->immutable-string (identity-text value)))
        provider-requirements)
   (map (lambda (value)
          (string->immutable-string (identity-text value)))
        requested-capabilities)
   resource-profile continuation-policy agent-substrate-api-version
   (string->immutable-string source) (string->immutable-string location)))

(define (agent? value) (odra-agent-definition? value))

(struct odra-agent-capability-definition
  (identity owner-namespace purpose input-schema result-schema target-kinds
            effects required-authorities default-limits hard-limits
            approval-class idempotency-class verification-class
            retirement-policy compatibility-version source location handler)
  #:transparent)

(define (limits-within? selected maximum)
  (and
   (<= (odra-agent-capability-limits-deadline-milliseconds selected)
       (odra-agent-capability-limits-deadline-milliseconds maximum))
   (<= (odra-agent-capability-limits-input-bytes selected)
       (odra-agent-capability-limits-input-bytes maximum))
   (<= (odra-agent-capability-limits-result-bytes selected)
       (odra-agent-capability-limits-result-bytes maximum))
   (<= (odra-agent-capability-limits-target-references selected)
       (odra-agent-capability-limits-target-references maximum))))

(define (make-agent-capability
         identity owner-namespace handler
         #:purpose [purpose ""]
         #:input-schema [input-schema '(record)]
         #:result-schema [result-schema '(record)]
         #:target-kinds [target-kinds '()]
         #:effects [effects '(observe)]
         #:required-authorities [required-authorities '()]
         #:default-limits [default-limits default-agent-capability-limits]
         #:hard-limits [hard-limits default-agent-capability-limits]
         #:approval-class [approval-class 'policy]
         #:idempotency-class [idempotency-class 'owner-defined]
         #:verification-class [verification-class 'owner-defined]
         #:retirement-policy [retirement-policy 'cancel]
         #:source [source "package contribution"]
         #:location [location ""])
  (define normalized-identity
    (copied-identity identity 'make-agent-capability "identity"))
  (define normalized-owner
    (copied-identity owner-namespace 'make-agent-capability "owner-namespace"))
  (unless (and (equal? (procedure-arity handler) 1)
               (bounded-text? purpose maximum-description-bytes #:empty? #t)
               (agent-schema? input-schema)
               (agent-schema? result-schema)
               (canonical-identity-set? target-kinds maximum-list-items)
               (canonical-symbol-set?
                effects admitted-agent-effect-classes maximum-list-items)
               (pair? effects)
               (canonical-identity-set? required-authorities maximum-list-items)
               (odra-agent-capability-limits? default-limits)
               (odra-agent-capability-limits? hard-limits)
               (limits-within? default-limits hard-limits)
               (memq approval-class admitted-approval-classes)
               (memq idempotency-class admitted-idempotency-classes)
               (memq verification-class admitted-verification-classes)
               (memq retirement-policy admitted-retirement-policies)
               (bounded-text? source maximum-source-bytes)
               (bounded-text? location maximum-source-bytes #:empty? #t))
    (raise-arguments-error
     'make-agent-capability "invalid bounded agent capability definition"
     "identity" identity))
  (odra-agent-capability-definition
   normalized-identity normalized-owner (string->immutable-string purpose)
   (immutable-copy input-schema) (immutable-copy result-schema)
   (map (lambda (value)
          (string->immutable-string (identity-text value)))
        target-kinds)
   effects
   (map (lambda (value)
          (string->immutable-string (identity-text value)))
        required-authorities)
   default-limits hard-limits approval-class idempotency-class
   verification-class retirement-policy agent-substrate-api-version
   (string->immutable-string source) (string->immutable-string location)
   handler))

(define (agent-capability? value)
  (odra-agent-capability-definition? value))
