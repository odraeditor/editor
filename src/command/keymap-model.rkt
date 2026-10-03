#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         (only-in racket/list remove-duplicates))

(provide
 (struct-out odra-key-stroke)
 (struct-out odra-key-sequence)
 (struct-out odra-provenance)
 (struct-out odra-profile-state-selector)
 (struct-out odra-binding)
 (struct-out odra-remap)
 (struct-out odra-ordering)
 (struct-out odra-keymap)
 (struct-out odra-interaction-state)
 (struct-out odra-interaction-profile)
 (struct-out odra-command-entry-surface)
 (struct-out odra-interaction-profile-catalog)
 (contract-out
  [key-sequence (-> odra-key-stroke? ... odra-key-sequence?)]
  [keymap-bind (-> odra-key-sequence? string? odra-provenance? odra-binding?)]
  [keymap-replace (-> odra-key-sequence? string? odra-provenance? odra-binding?)]
  [keymap-unbind (-> odra-key-sequence? odra-provenance? odra-binding?)]
  [keymap-mask (-> odra-key-sequence? odra-provenance? odra-binding?)]
  [keymap-share
   (-> odra-binding? (listof odra-profile-state-selector?) odra-binding?)]
  [keymap-for-states
   (-> odra-binding? (listof odra-profile-state-selector?) odra-binding?)]
  [keymap-remap (-> string? string? odra-provenance? odra-remap?)]
  [keymap-before (-> exact-positive-integer? odra-ordering?)]
  [keymap-after (-> exact-positive-integer? odra-ordering?)]
  [compose-interaction-profile
   (-> exact-positive-integer? exact-positive-integer? string?
       (listof (listof odra-keymap?)) string? odra-interaction-profile?)]
  [compose-interaction-profile-catalog
   (-> exact-positive-integer? (listof odra-interaction-profile?)
       exact-positive-integer? exact-positive-integer?
       (listof odra-command-entry-surface?) odra-interaction-profile-catalog?)]))

(define precedence-classes
  '(protected-recovery transient-interaction component-tool buffer-local
    language-context project user-global profile-base factory-fallback))
(define unmatched-input-policies '(fallthrough text-input reject))
(define binding-operations '(bind replace unbind mask))
(define ordering-relations '(before after))
(define binding-scopes
  '(protected-recovery shared-continuity profile-specific state-specific))
(define command-effects '(buffer view lifecycle text-mutation))

(define (bounded-string? value maximum [empty-allowed? #f])
  (and (string? value)
       (or empty-allowed? (positive? (string-length value)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(struct odra-key-stroke (kind scalar modifiers)
  #:transparent
  #:guard
  (lambda (kind scalar modifiers _)
    (unless (and (exact-positive-integer? kind) (<= kind 16)
                 (exact-integer? scalar)
                 (exact-nonnegative-integer? modifiers) (<= modifiers #x1f)
                 (if (= kind 1)
                     (and (<= 0 scalar #x10ffff)
                          (not (<= #xd800 scalar #xdfff)))
                     (= scalar 0)))
      (raise-arguments-error 'odra-key-stroke "invalid normalized key stroke"
                             "kind" kind "scalar" scalar "modifiers" modifiers))
    (values kind scalar modifiers)))

(struct odra-key-sequence (strokes)
  #:transparent
  #:guard
  (lambda (strokes _)
    (unless (and (list? strokes) (<= 1 (length strokes) 16)
                 (andmap odra-key-stroke? strokes))
      (raise-argument-error 'odra-key-sequence
                            "a list of one through sixteen key strokes" strokes))
    (for/list ([stroke (in-list strokes)]) stroke)))

(struct odra-provenance (provider source location)
  #:transparent
  #:guard
  (lambda (provider source location _)
    (unless (and (bounded-string? provider 256)
                 (bounded-string? source 256)
                 (bounded-string? location 512 #t))
      (raise-arguments-error 'odra-provenance "invalid bounded provenance"
                             "provider" provider "source" source "location" location))
    (values provider source location)))

(struct odra-profile-state-selector (profile-id state-id)
  #:transparent
  #:guard
  (lambda (profile-id state-id _)
    (unless (and (exact-positive-integer? profile-id) (exact-positive-integer? state-id))
      (raise-arguments-error 'odra-profile-state-selector "invalid profile/state selector"
                             "profile-id" profile-id "state-id" state-id))
    (values profile-id state-id)))

(struct odra-binding (operation sequence command scope selectors provenance protection-reason)
  #:transparent
  #:guard
  (lambda (operation sequence command scope selectors provenance protection-reason _)
    (unless (and (memq operation binding-operations)
                 (odra-key-sequence? sequence)
                 (bounded-string? command 96 (memq operation '(unbind mask)))
                 (if (memq operation '(unbind mask)) (string=? command "") #t)
                 (memq scope binding-scopes)
                 (list? selectors) (<= (length selectors) 64)
                 (andmap odra-profile-state-selector? selectors)
                 (if (memq scope '(shared-continuity state-specific))
                     (pair? selectors)
                     (null? selectors))
                 (odra-provenance? provenance)
                 (bounded-string? protection-reason 256 #t)
                 (if (eq? scope 'protected-recovery)
                     (positive? (string-length protection-reason))
                     (string=? protection-reason "")))
      (raise-arguments-error 'odra-binding "invalid binding operation"
                             "operation" operation "command" command "scope" scope))
    (values operation sequence command scope
            (for/list ([selector (in-list selectors)]) selector)
            provenance protection-reason)))

(struct odra-remap (from-command to-command provenance)
  #:transparent
  #:guard
  (lambda (from-command to-command provenance _)
    (unless (and (bounded-string? from-command 96)
                 (bounded-string? to-command 96)
                 (not (string=? from-command to-command))
                 (odra-provenance? provenance))
      (raise-arguments-error 'odra-remap "invalid semantic remap"
                             "from-command" from-command "to-command" to-command))
    (values from-command to-command provenance)))

(struct odra-ordering (relation other-map-id)
  #:transparent
  #:guard
  (lambda (relation other-map-id _)
    (unless (and (memq relation ordering-relations) (exact-positive-integer? other-map-id))
      (raise-arguments-error 'odra-ordering "invalid map ordering"
                             "relation" relation "other-map-id" other-map-id))
    (values relation other-map-id)))

(struct odra-keymap
  (id revision name owner-id owner-generation precedence priority
      context-id context-generation context-owner-id context-owner-generation
      unmatched-input-policy bindings remaps ordering provenance)
  #:transparent
  #:guard
  (lambda (id revision name owner-id owner-generation precedence priority
              context-id context-generation context-owner-id context-owner-generation
              unmatched-input-policy bindings remaps ordering provenance _)
    (define context-empty?
      (and (zero? context-id) (zero? context-generation)
           (zero? context-owner-id) (zero? context-owner-generation)))
    (define context-complete?
      (and (positive? context-id) (positive? context-generation)
           (positive? context-owner-id) (positive? context-owner-generation)
           (= owner-id context-owner-id) (= owner-generation context-owner-generation)))
    (unless (and (exact-positive-integer? id) (exact-positive-integer? revision)
                 (bounded-string? name 96)
                 (exact-nonnegative-integer? owner-id)
                 (exact-nonnegative-integer? owner-generation)
                 (memq precedence precedence-classes)
                 (exact-integer? priority) (<= (- (expt 2 31)) priority (sub1 (expt 2 31)))
                 (or context-empty? context-complete?)
                 (memq unmatched-input-policy unmatched-input-policies)
                 (list? bindings) (<= (length bindings) 4096)
                 (andmap odra-binding? bindings)
                 (list? remaps) (andmap odra-remap? remaps)
                 (list? ordering) (<= (length ordering) 64)
                 (andmap odra-ordering? ordering)
                 (odra-provenance? provenance))
      (raise-arguments-error 'odra-keymap "invalid complete keymap definition"
                             "id" id "name" name "precedence" precedence))
    (values id revision name owner-id owner-generation precedence priority
            context-id context-generation context-owner-id context-owner-generation
            unmatched-input-policy
            (for/list ([binding (in-list bindings)]) binding)
            (for/list ([remap (in-list remaps)]) remap)
            (for/list ([constraint (in-list ordering)]) constraint)
            provenance)))

(struct odra-interaction-state
  (id revision name admits-text-input admitted-effects provenance)
  #:transparent
  #:guard
  (lambda (id revision name admits-text-input admitted-effects provenance _)
    (unless (and (exact-positive-integer? id) (exact-positive-integer? revision)
                 (bounded-string? name 96) (boolean? admits-text-input)
                 (list? admitted-effects)
                 (= (length admitted-effects) (length (remove-duplicates admitted-effects)))
                 (andmap (lambda (effect) (memq effect command-effects)) admitted-effects)
                 (odra-provenance? provenance))
      (raise-arguments-error 'odra-interaction-state "invalid interaction state"
                             "id" id "name" name))
    (values id revision name admits-text-input
            (for/list ([effect (in-list admitted-effects)]) effect) provenance)))

(struct odra-interaction-profile (id revision name states initial-state-id maps text-fallback-name)
  #:transparent
  #:guard
  (lambda (id revision name states initial-state-id maps text-fallback-name _)
    (unless (and (exact-positive-integer? id) (exact-positive-integer? revision)
                 (bounded-string? name 96)
                 (list? states) (<= 1 (length states) 16)
                 (andmap odra-interaction-state? states)
                 (= (length states) (length (remove-duplicates (map odra-interaction-state-id states))))
                 (member initial-state-id (map odra-interaction-state-id states))
                 (list? maps) (<= 1 (length maps) 128) (andmap odra-keymap? maps)
                 (= (length maps) (length (remove-duplicates (map odra-keymap-id maps))))
                 (bounded-string? text-fallback-name 96))
      (raise-arguments-error 'odra-interaction-profile "invalid complete interaction profile"
                             "id" id "name" name))
    (values id revision name (for/list ([state (in-list states)]) state) initial-state-id
            (for/list ([keymap (in-list maps)]) keymap) text-fallback-name)))

(struct odra-command-entry-surface (id revision name provenance)
  #:transparent
  #:guard
  (lambda (id revision name provenance _)
    (unless (and (exact-positive-integer? id) (<= id #xffff)
                 (exact-positive-integer? revision) (bounded-string? name 96)
                 (odra-provenance? provenance))
      (raise-arguments-error 'odra-command-entry-surface "invalid command-entry surface"
                             "id" id "name" name))
    (values id revision name provenance)))

(struct odra-interaction-profile-catalog
  (generation profiles active-profile-id active-state-id surfaces)
  #:transparent
  #:guard
  (lambda (generation profiles active-profile-id active-state-id surfaces _)
    (unless (and (exact-positive-integer? generation)
                 (list? profiles) (<= 1 (length profiles) 32)
                 (andmap odra-interaction-profile? profiles)
                 (= (length profiles) (length (remove-duplicates (map odra-interaction-profile-id profiles))))
                 (member active-profile-id (map odra-interaction-profile-id profiles))
                 (let ([active (for/first ([profile (in-list profiles)]
                                           #:when (= active-profile-id (odra-interaction-profile-id profile)))
                                 profile)])
                   (member active-state-id (map odra-interaction-state-id
                                                (odra-interaction-profile-states active))))
                 (list? surfaces) (<= 1 (length surfaces) 8)
                 (andmap odra-command-entry-surface? surfaces)
                 (= (length surfaces)
                    (length (remove-duplicates (map odra-command-entry-surface-id surfaces)))))
      (raise-arguments-error 'odra-interaction-profile-catalog "invalid profile catalog"
                             "generation" generation "active-profile-id" active-profile-id))
    (values generation (for/list ([profile (in-list profiles)]) profile)
            active-profile-id active-state-id
            (for/list ([surface (in-list surfaces)]) surface))))

(define (key-sequence . strokes)
  (odra-key-sequence strokes))

(define (keymap-bind sequence command provenance)
  (odra-binding 'bind sequence command 'profile-specific '() provenance ""))

(define (keymap-replace sequence command provenance)
  (odra-binding 'replace sequence command 'profile-specific '() provenance ""))

(define (keymap-unbind sequence provenance)
  (odra-binding 'unbind sequence "" 'profile-specific '() provenance ""))

(define (keymap-mask sequence provenance)
  (odra-binding 'mask sequence "" 'profile-specific '() provenance ""))

(define (keymap-share binding selectors)
  (struct-copy odra-binding binding
               [scope 'shared-continuity]
               [selectors (for/list ([selector (in-list selectors)]) selector)]))

(define (keymap-for-states binding selectors)
  (struct-copy odra-binding binding
               [scope 'state-specific]
               [selectors (for/list ([selector (in-list selectors)]) selector)]))

(define (keymap-remap from-command to-command provenance)
  (odra-remap from-command to-command provenance))

(define (keymap-before other-map-id)
  (odra-ordering 'before other-map-id))

(define (keymap-after other-map-id)
  (odra-ordering 'after other-map-id))

;; compose-interaction-profile flattens contributions in declared stable order.
(define (compose-interaction-profile id revision name contributions text-fallback-name)
  (define provenance (odra-provenance "odra" "composition" ""))
  (odra-interaction-profile
   id revision name
   (list (odra-interaction-state
          1 1 "direct-editing" #t command-effects provenance))
   1
   (for*/list ([contribution (in-list contributions)]
               [keymap (in-list contribution)])
     keymap)
   text-fallback-name))

(define (compose-interaction-profile-catalog
         generation profiles active-profile-id active-state-id surfaces)
  (odra-interaction-profile-catalog
   generation profiles active-profile-id active-state-id surfaces))
