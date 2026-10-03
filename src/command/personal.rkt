#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         "catalog.rkt"
         "personal-limits.rkt")

(provide
 maximum-personal-diagnostic-bytes
 default-personal-command-limits
 make-personal-command-limits
 personal-command-limits?
 personal-command-limits-deadline-milliseconds
 personal-command-limits-custodian-memory-bytes
 personal-command-limits-inspection-bytes
 personal-command-limits-replacement-bytes
 personal-command-limits-splices
 personal-command-limits-temporary-native-bytes
 personal-command-limits-nested-operations
 personal-command-limits-diagnostic-bytes
 (contract-out
  [make-command
   (->* ((or/c symbol? string?) procedure?)
        (#:description string?
         #:interactive? boolean?
         #:requirements list?
         #:effects list?
         #:source string?
         #:location string?
         #:limits personal-command-limits?)
        command?)]
  [command? (-> any/c boolean?)]
  [command-limits (-> command? personal-command-limits?)]
  [personal-command-implementation-limits
   (-> procedure? personal-command-limits?)]
  [register-personal-command-implementation-limits!
   (-> procedure? personal-command-limits? void?)]
  [command-reject (-> symbol? string? command-rejection?)]
  [command-rejection? (-> any/c boolean?)]
  [command-rejection-code (-> command-rejection? symbol?)]
  [command-rejection-message (-> command-rejection? string?)]
  [make-command-candidate
   (->* (string? string? (listof string?) path-string?
         exact-nonnegative-integer? exact-nonnegative-integer?
         exact-nonnegative-integer?)
        (#:action (or/c 'navigate 'resume 'resume-value 'resume-query))
        command-candidate?)]
  [command-candidate? (-> any/c boolean?)]
  [command-candidate-identity (-> command-candidate? string?)]
  [command-candidate-label (-> command-candidate? string?)]
  [command-candidate-searchable-fields
   (-> command-candidate? (listof string?))]
  [command-candidate-document-path (-> command-candidate? path-string?)]
  [command-candidate-start (-> command-candidate? exact-nonnegative-integer?)]
  [command-candidate-end (-> command-candidate? exact-nonnegative-integer?)]
  [command-candidate-source-revision
   (-> command-candidate? exact-nonnegative-integer?)]
  [command-candidate-action
   (-> command-candidate?
       (or/c 'navigate 'resume 'resume-value 'resume-query))]
  [make-command-candidate-result
   (->* (exact-positive-integer? string? (listof command-candidate?))
        (#:title string?)
        command-candidate-result?)]
  [command-candidate-result? (-> any/c boolean?)]
  [command-candidate-result-generation
   (-> command-candidate-result? exact-positive-integer?)]
  [command-candidate-result-title (-> command-candidate-result? string?)]
  [command-candidate-result-initial-query (-> command-candidate-result? string?)]
  [command-candidate-result-candidates
   (-> command-candidate-result? (listof command-candidate?))]
  [make-command-navigation-result
   (-> string? path-string? exact-nonnegative-integer?
       exact-nonnegative-integer? exact-nonnegative-integer?
       command-navigation-result?)]
  [command-navigation-result? (-> any/c boolean?)]
  [command-navigation-result-label
   (-> command-navigation-result? string?)]
  [command-navigation-result-document-path
   (-> command-navigation-result? string?)]
  [command-navigation-result-start
   (-> command-navigation-result? exact-nonnegative-integer?)]
  [command-navigation-result-end
   (-> command-navigation-result? exact-nonnegative-integer?)]
  [command-navigation-result-source-revision
   (-> command-navigation-result? exact-nonnegative-integer?)]))

(define personal-requirements '(active-buffer active-document active-region))
(define personal-effects '(buffer view text-mutation))
(define personal-rejection-codes
  '(cancelled invalid-state invalid-text unavailable user))
(define command-limit-table (make-weak-hasheq))
(define implementation-limit-table (make-weak-hasheq))

(define maximum-command-candidates 256)
(define maximum-command-candidate-text-bytes (* 4 1024))

(define (candidate-text? value maximum)
  (bounded-string? value maximum #f))

(define (candidate-path-text value)
  (if (path? value) (path->string value) value))

(struct command-candidate
  (identity label searchable-fields document-path start end source-revision action)
  #:transparent
  #:constructor-name make-command-candidate-value
  #:guard
  (lambda (identity label searchable-fields document-path start end
                    source-revision action _)
    (unless (and (candidate-text? identity 1024)
                 (candidate-text? label maximum-command-candidate-text-bytes)
                 (list? searchable-fields)
                 (<= (length searchable-fields) 4)
                 (andmap (lambda (value)
                           (candidate-text? value maximum-command-candidate-text-bytes))
                         searchable-fields)
                 (path-string? document-path)
                 (candidate-text? (candidate-path-text document-path)
                                  maximum-command-candidate-text-bytes)
                 (exact-nonnegative-integer? start)
                 (exact-nonnegative-integer? end)
                 (<= start end)
                 (exact-nonnegative-integer? source-revision)
                 (memq action '(navigate resume resume-value resume-query)))
      (raise-arguments-error 'make-command-candidate
                             "invalid bounded command candidate"))
    (values (string->immutable-string identity)
            (string->immutable-string label)
            (map string->immutable-string searchable-fields)
            (string->immutable-string (candidate-path-text document-path))
            start end source-revision action)))

(define (make-command-candidate identity label searchable-fields document-path
                                start end source-revision
                                #:action [action 'navigate])
  (make-command-candidate-value
   identity label searchable-fields document-path start end source-revision
   action))

(struct command-candidate-result (generation title initial-query candidates)
  #:transparent
  #:constructor-name make-command-candidate-result-value
  #:guard
  (lambda (generation title initial-query candidates _)
    (unless (and (exact-positive-integer? generation)
                 (bounded-string? title 96 #t)
                 (bounded-string? initial-query 4096 #t)
                 (list? candidates)
                 (pair? candidates)
                 (<= (length candidates) maximum-command-candidates)
                 (andmap command-candidate? candidates)
                 (= (length candidates)
                    (length
                     (remove-duplicates
                      (map command-candidate-identity candidates) string=?))))
      (raise-arguments-error 'make-command-candidate-result
                             "invalid bounded command candidate result"))
    (values generation (string->immutable-string title)
            (string->immutable-string initial-query)
            (append candidates '()))))

(define (make-command-candidate-result generation initial-query candidates
                                       #:title [title ""])
  (make-command-candidate-result-value
   generation title initial-query candidates))

(struct command-navigation-result
  (label document-path start end source-revision)
  #:transparent
  #:constructor-name make-command-navigation-result-value
  #:guard
  (lambda (label document-path start end source-revision _)
    (unless (and (candidate-text? label maximum-command-candidate-text-bytes)
                 (path-string? document-path)
                 (candidate-text? (candidate-path-text document-path)
                                  maximum-command-candidate-text-bytes)
                 (exact-nonnegative-integer? start)
                 (exact-nonnegative-integer? end)
                 (<= start end)
                 (exact-nonnegative-integer? source-revision))
      (raise-arguments-error 'make-command-navigation-result
                             "invalid bounded command navigation result"))
    (values (string->immutable-string label)
            (string->immutable-string (candidate-path-text document-path))
            start end source-revision)))

(define (make-command-navigation-result label document-path start end
                                        source-revision)
  (make-command-navigation-result-value
   label document-path start end source-revision))

(struct command-rejection (code message)
  #:guard
  (lambda (code message _)
    (unless (memq code personal-rejection-codes)
      (raise-argument-error 'command-reject
                            "an admitted personal command rejection code"
                            code))
    (unless (bounded-string? message maximum-personal-diagnostic-bytes #t)
      (raise-arguments-error
       'command-reject
       "rejection message exceeds the admitted bound"
       "limit" maximum-personal-diagnostic-bytes))
    (values code (string->immutable-string message))))

;; make-command constructs one ordinary personal command definition without
;; registering or activating it.
(define (make-command name implementation
                      #:description [description ""]
                      #:interactive? [interactive? #t]
                      #:requirements [requirements '(active-buffer)]
                      #:effects [effects '(buffer view text-mutation)]
                      #:source [source "personal configuration"]
                      #:location [location ""]
                      #:limits [limits default-personal-command-limits])
  (define normalized-name (normalize-command-name name))
  (unless (equal? (procedure-arity implementation) 1)
    (raise-arguments-error
     'make-command
     "personal command procedure must accept exactly one argument"
     "name" normalized-name
     "arity" (procedure-arity implementation)))
  (unless (and (symbol-list? requirements personal-requirements)
               (memq 'active-buffer requirements))
    (raise-arguments-error
     'make-command
     "personal command requirements must include active-buffer"
     "name" normalized-name
     "requirements" requirements))
  (unless (and (pair? effects) (symbol-list? effects personal-effects))
    (raise-arguments-error
     'make-command
     "personal command effects are not admitted"
     "name" normalized-name
     "effects" effects))
  (define definition
    (make-command-definition
     normalized-name
     'personal
     'ordinary
     'prohibited
     effects
     description
     implementation
     #:interactive? interactive?
     #:requirements requirements
     #:provider "personal"
     #:source source
     #:location location))
  (hash-set! command-limit-table definition limits)
  (hash-set! implementation-limit-table implementation limits)
  definition)

(define (command? value)
  (and (odra-command-definition? value)
       (string=?
        (odra-command-source-provider
         (odra-command-definition-provenance value))
        "personal")))

(define (command-limits command)
  (hash-ref command-limit-table command default-personal-command-limits))

(define (personal-command-implementation-limits implementation)
  (hash-ref implementation-limit-table implementation
            default-personal-command-limits))

(define (register-personal-command-implementation-limits! implementation limits)
  (hash-set! implementation-limit-table implementation limits)
  (void))

(define (command-reject code message)
  (command-rejection code message))

(define (normalize-command-name value)
  (define name
    (cond
      [(symbol? value) (symbol->string value)]
      [(string? value) value]
      [else (raise-argument-error 'make-command "symbol? or string?" value)]))
  (unless (regexp-match? #px"^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$" name)
    (raise-arguments-error
     'make-command
     "command name must use lowercase hyphenated words"
     "name" name))
  name)

(define (symbol-list? values admitted)
  (and (list? values)
       (= (length values) (length (remove-duplicates values)))
       (andmap (lambda (value) (memq value admitted)) values)))

(define (bounded-string? value maximum empty-allowed?)
  (and (string? value)
       (or empty-allowed? (positive? (string-length value)))
       (not (for/or ([character (in-string value)])
              (char=? character #\nul)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(module+ test
  (require rackunit)

  (define entered? #f)
  (define command
    (make-command
     'uppercase-selection
     (lambda (_context)
       (set! entered? #t)
       (void))
     #:description "Uppercase the active selection."
     #:requirements '(active-buffer active-region)
     #:source "modules/text-commands.rkt"))

  (check-true (command? command))
  (check-false entered?)
  (check-equal? (odra-command-definition-name command) "uppercase-selection")
  (check-equal? (odra-command-definition-invocation command) 'ordinary)
  (check-equal? (odra-command-definition-text-requirement command) 'prohibited)
  (check-equal? (odra-command-definition-requirements command)
                '(active-buffer active-region))
  (check-equal?
   (odra-command-source-source (odra-command-definition-provenance command))
   "modules/text-commands.rkt")

  (check-exn #rx"exactly one argument"
             (lambda () (make-command 'zero-arity (lambda () (void)))))
  (check-exn #rx"exactly one argument"
             (lambda () (make-command 'rest-arity (lambda values values))))
  (check-exn #rx"lowercase hyphenated"
             (lambda () (make-command 'UppercaseSelection void)))
  (check-exn #rx"must include active-buffer"
             (lambda ()
               (make-command 'document-only (lambda (_context) (void))
                             #:requirements '(active-document))))
  (check-exn #rx"effects are not admitted"
             (lambda ()
               (make-command 'lifecycle-command (lambda (_context) (void))
                             #:effects '(lifecycle))))

  (define rejection (command-reject 'user "Selection is empty"))
  (check-true (command-rejection? rejection))
  (check-exn #rx"admitted personal command rejection code"
             (lambda () (command-reject 'unknown "No")))
  (check-exn #rx"exceeds the admitted bound"
             (lambda ()
               (command-reject
                'user
                (make-string (add1 maximum-personal-diagnostic-bytes) #\x))))

  (define candidate
    (make-command-candidate
     "ada" "Ada Lovelace" '("mathematician" "computing")
     "/brain/ada.org" 12 24 3))
  (check-true (command-candidate? candidate))
  (check-equal? (command-candidate-document-path candidate) "/brain/ada.org")
  (check-true
   (command-candidate?
    (make-command-candidate
     "fresh" "Fresh document" '() "/brain/fresh.org" 0 0 0)))
  (define candidates
    (make-command-candidate-result
     7 "Ada" (list candidate) #:title "Roman relations: Ada Lovelace"))
  (check-true (command-candidate-result? candidates))
  (check-equal? (command-candidate-result-title candidates)
                "Roman relations: Ada Lovelace")
  (check-equal? (command-candidate-result-initial-query candidates) "Ada")
  (check-exn
   #rx"invalid bounded command candidate result"
   (lambda () (make-command-candidate-result 7 "" '())))
  (check-exn
   #rx"invalid bounded command candidate result"
   (lambda () (make-command-candidate-result 7 "" (list candidate candidate))))

  (define navigation
    (make-command-navigation-result
     "Daily 2026-09-23 — daily/2026-09-23.org"
     "/brain/daily/2026-09-23.org" 0 0 4))
  (check-true (command-navigation-result? navigation))
  (check-equal? (command-navigation-result-document-path navigation)
                "/brain/daily/2026-09-23.org")
  (check-true
   (command-navigation-result?
    (make-command-navigation-result
     "Fresh document" "/brain/fresh.org" 0 0 0)))
  (check-exn
   #rx"invalid bounded command navigation result"
   (lambda ()
     (make-command-navigation-result "Daily" "/brain/daily.org" 2 1 4))))
