#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         "keymap-inspection.rkt"
         "native-contracts.rkt"
         "transaction.rkt")

(provide
 maximum-personal-commands
 (struct-out odra-command-source)
 (struct-out odra-command-definition)
 (struct-out odra-command-catalog)
 (contract-out
  [make-command-definition
   (->* (string? symbol? symbol? symbol? list? string? procedure?)
        (#:interactive? boolean?
         #:requirements list?
         #:provider string?
         #:source string?
         #:location string?)
        odra-command-definition?)]
  [compose-command-catalog
   (-> exact-positive-integer? list? odra-command-catalog?)]
  [compose-personal-command-catalog
   (->* (exact-positive-integer? any/c) (list?) odra-command-catalog?)]
  [factory-command-catalog (-> odra-command-catalog?)]
  [runtime-command-dispatch
   (-> bytes? exact-positive-integer? exact-positive-integer?
       exact-nonnegative-integer? exact-nonnegative-integer? list?)]))

(define (contract item) (native-contract-value 'command-catalog item))
(define maximum-commands (contract 'maximum-commands))
(define maximum-personal-commands 512)

(define dispatch-classes '(keymap-inspection transaction personal ksawery-extension))
(define invocation-classes '(ordinary text-input cancellation))
(define text-requirements '(optional required prohibited))
(define command-effects '(buffer view lifecycle text-mutation))
(define command-requirements '(active-buffer active-document active-region))

(define (bounded-string? value maximum [empty-allowed? #f])
  (and (string? value)
       (or empty-allowed? (positive? (string-length value)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(define (symbol-set? values admitted)
  (and (list? values)
       (= (length values) (length (remove-duplicates values)))
       (andmap (lambda (value) (memq value admitted)) values)))

(struct odra-command-source (provider source location)
  #:transparent
  #:guard
  (lambda (provider source location _)
    (unless (and (bounded-string? provider 256)
                 (bounded-string? source 256)
                 (bounded-string? location 512 #t))
      (raise-arguments-error 'odra-command-source
                             "invalid bounded command provenance"
                             "provider" provider
                             "source" source
                             "location" location))
    (values (string-copy provider) (string-copy source) (string-copy location))))

(struct odra-command-definition
  (name dispatch-class invocation text-requirement effects description
        interactive? requirements provenance implementation)
  #:transparent
  #:guard
  (lambda (name dispatch-class invocation text-requirement effects description
                interactive? requirements provenance implementation _)
    (unless (and (bounded-string? name 96)
                 (memq dispatch-class dispatch-classes)
                 (memq invocation invocation-classes)
                 (memq text-requirement text-requirements)
                 (symbol-set? effects command-effects)
                 (pair? effects)
                 (bounded-string? description 256 #t)
                 (boolean? interactive?)
                 (symbol-set? requirements command-requirements)
                 (odra-command-source? provenance)
                 (procedure? implementation)
                 (or (not (eq? invocation 'text-input))
                     (eq? text-requirement 'required))
                 (or (not (eq? invocation 'cancellation))
                     (eq? text-requirement 'prohibited)))
      (raise-arguments-error 'odra-command-definition
                             "invalid bounded command definition"
                             "name" name
                             "dispatch-class" dispatch-class
                             "invocation" invocation
                             "text-requirement" text-requirement
                             "effects" effects))
    (values (string-copy name) dispatch-class invocation text-requirement
            (append effects '()) (string-copy description) interactive?
            (append requirements '()) provenance implementation)))

(struct odra-command-catalog (generation definitions)
  #:transparent
  #:guard
  (lambda (generation definitions _)
    (unless (and (exact-positive-integer? generation)
                 (list? definitions)
                 (pair? definitions)
                 (<= (length definitions) maximum-commands)
                 (andmap odra-command-definition? definitions))
      (raise-arguments-error 'odra-command-catalog
                             "invalid bounded command catalog"
                             "generation" generation
                             "definitions" definitions))
    (define names (map odra-command-definition-name definitions))
    (unless (= (length names) (length (remove-duplicates names)))
      (raise-arguments-error 'odra-command-catalog
                             "command names must be unique"
                             "names" names))
    (values generation (append definitions '()))))

(define (make-command-definition
         name dispatch-class invocation text-requirement effects description implementation
         #:interactive? [interactive? #t]
         #:requirements [requirements '()]
         #:provider [provider "odra-racket"]
         #:source [source "src/command/catalog.rkt"]
         #:location [location ""])
  (odra-command-definition
   name dispatch-class invocation text-requirement effects description
   interactive? requirements (odra-command-source provider source location)
   implementation))

(define (compose-command-catalog generation definitions)
  (odra-command-catalog generation definitions))

;; compose-personal-command-catalog validates one bounded personal contribution
;; before combining it with the immutable factory definitions.
(define (compose-personal-command-catalog generation definitions
                                          [ksawery-definitions '()])
  (unless (and (list? definitions)
               (<= (length definitions) maximum-personal-commands))
    (raise-arguments-error
     'compose-personal-command-catalog
     "personal command list exceeds the admitted bound"
     "limit" maximum-personal-commands))
  (for ([definition (in-list definitions)])
    (unless (and (odra-command-definition? definition)
                 (string=?
                  (odra-command-source-provider
                   (odra-command-definition-provenance definition))
                  "personal"))
      (raise-arguments-error
       'compose-personal-command-catalog
       "expected personal command definitions"
       "definition" definition)))
  (for ([definition (in-list ksawery-definitions)])
    (unless (and (odra-command-definition? definition)
                 (eq? (odra-command-definition-dispatch-class definition)
                      'ksawery-extension))
      (raise-arguments-error
       'compose-personal-command-catalog
       "expected Ksawery extension command definitions"
       "definition" definition)))
  (compose-command-catalog
   generation
   (append factory-definitions definitions ksawery-definitions)))

(define (inspection-definition name description implementation)
  (make-command-definition
   name 'keymap-inspection 'ordinary 'prohibited '(view) description implementation
   #:source "src/command/keymap-inspection.rkt"))

(define (transaction-uppercase-current-line transaction start end)
  (define source (transaction-inspect transaction start end))
  (if (transaction-failure? source)
      source
      (let ([replacement
             (string->bytes/utf-8
              (string-upcase (bytes->string/utf-8 source)))])
        (if (bytes=? source replacement)
            (void)
            (transaction-splice! transaction start end replacement)))))

(define factory-definitions
  (list
   (inspection-definition
    "describe-key"
    "Describe the active command and alternatives for a key sequence."
    describe-key)
   (inspection-definition
    "where-is"
    "List active key sequences associated with a command."
    where-is)
   (inspection-definition
    "describe-bindings"
    "List active keymaps in resolution order."
    describe-bindings)
   (inspection-definition
    "describe-keymap"
    "Describe one keymap and its bindings and remaps."
    describe-keymap)
   (inspection-definition
    "describe-keymap-conflicts"
    "Describe the most recent rejected keymap candidate."
    describe-keymap-conflicts)
   (inspection-definition
    "describe-keymap-state"
    "Describe the catalog, profiles, states, surfaces, pending input, and generations."
    describe-keymap-state)
   (make-command-definition
    "uppercase-current-line"
    'transaction
    'ordinary
    'prohibited
    '(buffer view text-mutation)
    "Uppercase the current logical line."
    transaction-uppercase-current-line
    #:requirements '(active-buffer))))

(define factory-catalog (compose-command-catalog 1 factory-definitions))

(define (factory-command-catalog)
  factory-catalog)

(define factory-command-by-name
  (for/hash ([definition (in-list factory-definitions)])
    (values (odra-command-definition-name definition) definition)))

;; runtime-command-dispatch resolves one admitted semantic name through one Racket root.
(define (runtime-command-dispatch command-name generation token start end)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #f (string->bytes/utf-8 (exn-message failure))))])
    (define name (bytes->string/utf-8 command-name))
    (define definition
      (hash-ref factory-command-by-name name
                (lambda ()
                  (error 'runtime-command-dispatch "unknown Racket command: ~a" name))))
    (unless (eq? (odra-command-definition-dispatch-class definition) 'transaction)
      (error 'runtime-command-dispatch "command is not transaction-dispatched: ~a" name))
    (define result
      (call-with-native-transaction
       generation token
       (lambda (transaction)
         ((odra-command-definition-implementation definition) transaction start end))))
    (void result)
    (list #t #t #"")))

(module+ test
  (require rackunit)

  (define catalog (factory-command-catalog))
  (check-equal? (odra-command-catalog-generation catalog) 1)
  (check-equal? (length (odra-command-catalog-definitions catalog)) 7)
  (check-equal?
   (map odra-command-definition-name (odra-command-catalog-definitions catalog))
   '("describe-key" "where-is" "describe-bindings" "describe-keymap"
     "describe-keymap-conflicts" "describe-keymap-state"
     "uppercase-current-line"))
  (check-equal?
   (map odra-command-definition-dispatch-class
        (odra-command-catalog-definitions catalog))
   '(keymap-inspection keymap-inspection keymap-inspection keymap-inspection
     keymap-inspection keymap-inspection transaction))

  (define extra
    (make-command-definition
     "test-lowercase-line" 'transaction 'ordinary 'prohibited
     '(buffer view text-mutation) "Lowercase one test line."
     (lambda (_transaction _start _end) (void))
     #:requirements '(active-buffer)
     #:provider "test"
     #:source "catalog-test"))
  (define extended
    (compose-command-catalog
     2 (append (odra-command-catalog-definitions catalog) (list extra))))
  (check-equal? (length (odra-command-catalog-definitions extended)) 8)
  (check-exn #rx"unique"
             (lambda ()
               (compose-command-catalog
                2 (list extra extra)))))
