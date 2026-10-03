#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         (only-in racket/list make-list remove-duplicates)
         (only-in "keymaps.rkt"
                  odra-key-sequence?
                  odra-profile-state-selector
                  odra-profile-state-selector?
                  odra-profile-state-selector-profile-id
                  odra-profile-state-selector-state-id))

(provide
 (struct-out odra-keymap-inspection-request)
 (struct-out odra-keymap-inspection-record)
 (struct-out odra-keymap-inspection)
 (contract-out
  [describe-key (-> odra-key-sequence? odra-keymap-inspection-request?)]
  [where-is (->* (string?) (#:include-inactive? boolean?) odra-keymap-inspection-request?)]
  [describe-bindings (->* () (#:include-inactive? boolean?) odra-keymap-inspection-request?)]
  [describe-keymap
   (->* (exact-positive-integer?) (#:include-inactive? boolean?)
        odra-keymap-inspection-request?)]
  [describe-keymap-conflicts (-> odra-keymap-inspection-request?)]
  [describe-keymap-state (-> odra-keymap-inspection-request?)]
  [compose-keymap-inspection
   (-> odra-keymap-inspection-request?
       exact-positive-integer? exact-positive-integer? exact-positive-integer?
       exact-positive-integer? exact-positive-integer?
       exact-positive-integer? exact-positive-integer?
       exact-positive-integer? exact-positive-integer?
       string? symbol? (listof odra-keymap-inspection-record?)
       odra-keymap-inspection?)]))

(define maximum-command-name-bytes 96)
(define maximum-identity-bytes 96)
(define maximum-source-bytes 256)
(define maximum-location-bytes 512)
(define maximum-protection-reason-bytes 256)
(define maximum-sequence-notation-bytes (* 16 32))
(define maximum-inspection-records 128)

(define request-kinds
  '(sequence command map active-maps bindings snapshot compatibility latest-rejection))
(define record-kinds '(binding remap map snapshot catalog profile state surface rejection))
(define dispositions '(effective shadowed masked inactive rejected))
(define precedences
  '(none protected-recovery transient-interaction component-tool buffer-local
         language-context project user-global profile-base factory-fallback))
(define operations '(none bind replace unbind mask))
(define binding-scopes '(none protected-recovery shared-continuity profile-specific))
(define command-effects '(buffer view lifecycle text-mutation))

(define (bounded-string? value maximum [empty-allowed? #f])
  (and (string? value)
       (or empty-allowed? (positive? (string-length value)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(struct odra-keymap-inspection-request
  (kind sequence command-name map-id include-inactive?)
  #:transparent
  #:guard
  (lambda (kind sequence command-name map-id include-inactive? _)
    (unless (and (memq kind request-kinds)
                 (or (and (eq? kind 'sequence) (odra-key-sequence? sequence))
                     (and (not (eq? kind 'sequence)) (not sequence)))
                 (bounded-string? command-name maximum-command-name-bytes #t)
                 (if (eq? kind 'command) (positive? (string-length command-name))
                     (string=? command-name ""))
                 (exact-nonnegative-integer? map-id)
                 (if (eq? kind 'map) (positive? map-id) (zero? map-id))
                 (boolean? include-inactive?))
      (raise-arguments-error 'odra-keymap-inspection-request
                             "invalid bounded inspection request"
                             "kind" kind "command-name" command-name "map-id" map-id))
    (values kind sequence (string-copy command-name) map-id include-inactive?)))

(struct odra-keymap-inspection-record
  (kind disposition sequence-notation command-name original-command-name
        remap-target-name map-id map-revision map-name precedence priority active?
        operation provider source location protected? protection-reason failure-code
        catalog-generation profile-id profile-revision profile-name
        state-id state-revision state-name state-admits-text-input? state-admitted-effects
        binding-scope selectors surface-id surface-revision surface-name effects-admitted?)
  #:transparent
  #:guard
  (lambda (kind disposition sequence-notation command-name original-command-name
                remap-target-name map-id map-revision map-name precedence priority active?
                operation provider source location protected? protection-reason failure-code
                catalog-generation profile-id profile-revision profile-name
                state-id state-revision state-name state-admits-text-input? state-admitted-effects
                binding-scope selectors surface-id surface-revision surface-name effects-admitted? _)
    (unless (and (memq kind record-kinds)
                 (memq disposition dispositions)
                 (bounded-string? sequence-notation maximum-sequence-notation-bytes #t)
                 (bounded-string? command-name maximum-command-name-bytes #t)
                 (bounded-string? original-command-name maximum-command-name-bytes #t)
                 (bounded-string? remap-target-name maximum-command-name-bytes #t)
                 (exact-nonnegative-integer? map-id)
                 (exact-nonnegative-integer? map-revision)
                 (bounded-string? map-name maximum-identity-bytes #t)
                 (memq precedence precedences)
                 (exact-integer? priority)
                 (boolean? active?)
                 (memq operation operations)
                 (bounded-string? provider maximum-source-bytes #t)
                 (bounded-string? source maximum-source-bytes #t)
                 (bounded-string? location maximum-location-bytes #t)
                 (boolean? protected?)
                 (bounded-string? protection-reason maximum-protection-reason-bytes #t)
                 (symbol? failure-code)
                 (exact-nonnegative-integer? catalog-generation)
                 (exact-nonnegative-integer? profile-id)
                 (exact-nonnegative-integer? profile-revision)
                 (bounded-string? profile-name maximum-identity-bytes #t)
                 (exact-nonnegative-integer? state-id)
                 (exact-nonnegative-integer? state-revision)
                 (bounded-string? state-name maximum-identity-bytes #t)
                 (boolean? state-admits-text-input?)
                 (list? state-admitted-effects)
                 (= (length state-admitted-effects)
                    (length (remove-duplicates state-admitted-effects)))
                 (andmap (lambda (effect) (memq effect command-effects)) state-admitted-effects)
                 (memq binding-scope binding-scopes)
                 (list? selectors) (<= (length selectors) 64)
                 (andmap odra-profile-state-selector? selectors)
                 (if (eq? binding-scope 'shared-continuity) (pair? selectors) (null? selectors))
                 (exact-nonnegative-integer? surface-id)
                 (exact-nonnegative-integer? surface-revision)
                 (bounded-string? surface-name maximum-identity-bytes #t)
                 (boolean? effects-admitted?))
      (raise-arguments-error 'odra-keymap-inspection-record
                             "invalid copied inspection record"
                             "kind" kind "disposition" disposition "map-id" map-id))
    (values kind disposition
            (string-copy sequence-notation)
            (string-copy command-name)
            (string-copy original-command-name)
            (string-copy remap-target-name)
            map-id map-revision (string-copy map-name) precedence priority active?
            operation (string-copy provider) (string-copy source) (string-copy location)
            protected? (string-copy protection-reason) failure-code
            catalog-generation profile-id profile-revision (string-copy profile-name)
            state-id state-revision (string-copy state-name) state-admits-text-input?
            (for/list ([effect (in-list state-admitted-effects)]) effect)
            binding-scope
            (for/list ([selector (in-list selectors)])
              (odra-profile-state-selector
               (odra-profile-state-selector-profile-id selector)
               (odra-profile-state-selector-state-id selector)))
            surface-id surface-revision (string-copy surface-name) effects-admitted?)))

(struct odra-keymap-inspection
  (query registry-generation snapshot-generation profile-id profile-revision
           catalog-generation state-id state-revision context-id context-generation
           pending-sequence latest-rejection records)
  #:transparent)

(define (describe-key sequence)
  (odra-keymap-inspection-request 'sequence sequence "" 0 #f))

(define (where-is command-name #:include-inactive? [include-inactive? #f])
  (odra-keymap-inspection-request 'command #f command-name 0 include-inactive?))

(define (describe-bindings #:include-inactive? [include-inactive? #f])
  (odra-keymap-inspection-request 'bindings #f "" 0 include-inactive?))

(define (describe-keymap map-id #:include-inactive? [include-inactive? #f])
  (odra-keymap-inspection-request 'map #f "" map-id include-inactive?))

(define (describe-keymap-conflicts)
  (odra-keymap-inspection-request 'latest-rejection #f "" 0 #f))

(define (describe-keymap-state)
  (odra-keymap-inspection-request 'compatibility #f "" 0 #t))

;; compose-keymap-inspection owns only copied values and never calls into the resolver.
(define (compose-keymap-inspection
         request registry-generation snapshot-generation profile-id profile-revision
         catalog-generation state-id state-revision context-id context-generation
         pending-sequence latest-rejection records)
  (unless (and (odra-keymap-inspection-request? request)
               (exact-positive-integer? registry-generation)
               (exact-positive-integer? snapshot-generation)
               (exact-positive-integer? profile-id)
               (exact-positive-integer? profile-revision)
               (exact-positive-integer? catalog-generation)
               (exact-positive-integer? state-id)
               (exact-positive-integer? state-revision)
               (exact-positive-integer? context-id)
               (exact-positive-integer? context-generation)
               (bounded-string? pending-sequence maximum-sequence-notation-bytes #t)
               (symbol? latest-rejection)
               (list? records)
               (<= (length records) maximum-inspection-records)
               (andmap odra-keymap-inspection-record? records))
    (raise-arguments-error 'compose-keymap-inspection
                           "invalid copied inspection result"
                           "record-count" (if (list? records) (length records) records)))
  (odra-keymap-inspection
   request registry-generation snapshot-generation profile-id profile-revision
   catalog-generation state-id state-revision context-id context-generation
   (string-copy pending-sequence) latest-rejection
   (for/list ([record (in-list records)]) record)))

(module+ test
  (require rackunit
           (only-in "keymaps.rkt" odra-key-sequence odra-key-stroke))

  (define sequence (odra-key-sequence (list (odra-key-stroke 1 (char->integer #\x) 2))))
  (check-equal? (odra-keymap-inspection-request-kind (describe-key sequence)) 'sequence)
  (check-equal? (odra-keymap-inspection-request-command-name (where-is "save")) "save")
  (check-true (odra-keymap-inspection-request-include-inactive?
               (where-is "save" #:include-inactive? #t)))
  (check-equal? (odra-keymap-inspection-request-kind (describe-bindings)) 'bindings)
  (check-equal? (odra-keymap-inspection-request-map-id (describe-keymap 7)) 7)
  (check-equal? (odra-keymap-inspection-request-kind (describe-keymap-conflicts))
                'latest-rejection)
  (check-equal? (odra-keymap-inspection-request-kind (describe-keymap-state)) 'compatibility)

  (define record
    (odra-keymap-inspection-record
     'binding 'effective "M-x" "execute-extended-command" "execute-extended-command"
     "" 1 1 "protected-recovery" 'protected-recovery 0 #t 'bind
     "native" "factory recovery policy" "" #t "Preserve command access." 'none
     5 1 1 "direct" 1 1 "direct-editing" #t
     '(buffer view lifecycle text-mutation) 'protected-recovery '() 0 0 "" #t))
  (define result
    (compose-keymap-inspection
     (describe-key sequence) 17 23 1 2 5 1 1 3 4 "C-x" 'none (list record)))
  (check-equal? (odra-keymap-inspection-registry-generation result) 17)
  (check-equal? (odra-keymap-inspection-pending-sequence result) "C-x")
  (check-equal? (length (odra-keymap-inspection-records result)) 1)
  (check-exn exn:fail:contract?
             (lambda () (where-is "")))
  (check-exn exn:fail:contract?
             (lambda ()
               (compose-keymap-inspection
                (describe-key sequence) 17 23 1 2 5 1 1 3 4 "" 'none
                (make-list 129 record)))))
