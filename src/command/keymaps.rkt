#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         "keymap-model.rkt"
         (only-in "builtins.rkt"
                  factory-interaction-profile-definition
                  factory-modal-interaction-profile-definition))

(provide
 (all-from-out "keymap-model.rkt")
 (contract-out
  [stage-interaction-profile! (-> odra-interaction-profile? void?)]
  [stage-interaction-profile-catalog! (-> odra-interaction-profile-catalog? void?)]
  [clear-staged-interaction-profile! (-> void?)]
  [interaction-profile-candidate
   (-> exact-positive-integer? odra-interaction-profile?)]
  [interaction-profile-catalog-candidate
   (-> exact-positive-integer? odra-interaction-profile-catalog?)]
  [personal-interaction-profile-catalog
   (-> exact-positive-integer? (or/c #f odra-interaction-profile?)
       odra-interaction-profile-catalog?)]
  [factory-interaction-profile
   (-> exact-positive-integer? odra-interaction-profile?)]
  [factory-modal-interaction-profile
   (-> exact-positive-integer? odra-interaction-profile?)]
  [factory-interaction-profile-catalog
   (-> exact-positive-integer? odra-interaction-profile-catalog?)]))

(define staged-interaction-profile-catalog #f)

;; stage-interaction-profile! replaces only Racket-owned candidate configuration.
(define (stage-interaction-profile! profile)
  (set! staged-interaction-profile-catalog
        (selected-interaction-profile-catalog 1 profile "staged")))

(define (stage-interaction-profile-catalog! catalog)
  (set! staged-interaction-profile-catalog catalog))

;; clear-staged-interaction-profile! restores lazy construction of the factory candidate.
(define (clear-staged-interaction-profile!)
  (set! staged-interaction-profile-catalog #f))

;; interaction-profile-candidate returns one immutable staged or factory definition.
(define (interaction-profile-candidate registry-generation)
  (define catalog (interaction-profile-catalog-candidate registry-generation))
  (for/first ([profile (in-list (odra-interaction-profile-catalog-profiles catalog))]
              #:when (= (odra-interaction-profile-id profile)
                        (odra-interaction-profile-catalog-active-profile-id catalog)))
    profile))

(define (interaction-profile-catalog-candidate registry-generation)
  (or staged-interaction-profile-catalog
      (factory-interaction-profile-catalog registry-generation)))

(define (personal-interaction-profile-catalog registry-generation profile)
  (if profile
      (selected-interaction-profile-catalog
       registry-generation profile "init.rkt" "personal")
      (factory-interaction-profile-catalog registry-generation)))

;; factory-interaction-profile returns the canonical typed factory definition.
(define (factory-interaction-profile registry-generation)
  (void registry-generation)
  (factory-interaction-profile-definition))

(define (factory-modal-interaction-profile registry-generation)
  (void registry-generation)
  (factory-modal-interaction-profile-definition))

(define (factory-interaction-profiles registry-generation)
  (list (factory-interaction-profile registry-generation)
        (factory-modal-interaction-profile registry-generation)))

(define (selected-interaction-profile-catalog registry-generation profile
                                              source [provider "odra"])
  (define replaced? #f)
  (define profiles
    (for/list ([factory (in-list (factory-interaction-profiles registry-generation))])
      (if (= (odra-interaction-profile-id factory)
             (odra-interaction-profile-id profile))
          (begin (set! replaced? #t) profile)
          factory)))
  (define selected-profiles
    (if replaced? profiles (append profiles (list profile))))
  (define provenance (odra-provenance provider source ""))
  (odra-interaction-profile-catalog
   registry-generation
   selected-profiles
   (odra-interaction-profile-id profile)
   (odra-interaction-profile-initial-state-id profile)
   (list (odra-command-entry-surface 1 1 "extended-command" provenance))))

(define (factory-interaction-profile-catalog registry-generation)
  (define provenance (odra-provenance "odra" "factory" ""))
  (odra-interaction-profile-catalog
   registry-generation
   (factory-interaction-profiles registry-generation)
   1 1
   (list (odra-command-entry-surface 1 1 "extended-command" provenance))))

(module+ test
  (require rackunit)

  (define provenance (odra-provenance "user" "test" "keymaps.rkt:1"))
  (define sequence (key-sequence (odra-key-stroke 1 (char->integer #\x) 1)))
  (check-equal? (odra-binding-operation (keymap-bind sequence "save" provenance)) 'bind)
  (check-equal? (odra-binding-operation (keymap-replace sequence "save" provenance)) 'replace)
  (check-equal? (odra-binding-operation (keymap-unbind sequence provenance)) 'unbind)
  (check-equal? (odra-binding-operation (keymap-mask sequence provenance)) 'mask)
  (define shared
    (keymap-share (keymap-bind sequence "save" provenance)
                  (list (odra-profile-state-selector 1 1))))
  (check-equal? (odra-binding-scope shared) 'shared-continuity)
  (check-equal? (length (odra-binding-selectors shared)) 1)
  (check-equal? (odra-remap-to-command (keymap-remap "save" "write" provenance)) "write")
  (check-equal? (odra-ordering-relation (keymap-before 2)) 'before)
  (check-equal? (odra-ordering-relation (keymap-after 2)) 'after)
  (define factory (factory-interaction-profile 17))
  (check-equal? (odra-interaction-profile-name factory) "direct")
  (check-equal? (odra-interaction-state-name
                 (car (odra-interaction-profile-states factory)))
                "direct-editing")
	(check-equal? (length (odra-interaction-profile-maps factory)) 3)
	(check-equal? (length (odra-keymap-bindings (car (odra-interaction-profile-maps factory)))) 144)
  (check-equal? (length (odra-keymap-bindings (cadr (odra-interaction-profile-maps factory)))) 19)
  (check-equal? (odra-keymap-precedence (cadr (odra-interaction-profile-maps factory))) 'project)
  (check-equal? (odra-keymap-precedence (caddr (odra-interaction-profile-maps factory)))
                'language-context)
  (define second-map
    (struct-copy odra-keymap (car (odra-interaction-profile-maps factory))
				 [id 4] [name "user"] [bindings '()]))
  (define composed
    (compose-interaction-profile 2 1 "composed"
                                 (list (odra-interaction-profile-maps factory)
                                       (list second-map))
                                 "insert-text"))
	(check-equal? (map odra-keymap-id (odra-interaction-profile-maps composed)) '(1 2 3 4))
  (stage-interaction-profile! composed)
  (check-eq? (interaction-profile-candidate 17) composed)
  (clear-staged-interaction-profile!)
  (check-equal? (odra-interaction-profile-name (interaction-profile-candidate 17)) "direct")
  (define catalog (interaction-profile-catalog-candidate 17))
  (check-equal? (odra-interaction-profile-catalog-generation catalog) 17)
  (check-equal? (map odra-interaction-profile-name
                     (odra-interaction-profile-catalog-profiles catalog))
                '("direct" "modal"))
  (define modal (factory-modal-interaction-profile 17))
  (check-equal? (map odra-interaction-state-name
                     (odra-interaction-profile-states modal))
                '("Normal" "Insert" "Visual Character" "Visual Line" "Replace" "Visual Block"))
  (check-equal? (map (lambda (keymap) (length (odra-keymap-bindings keymap)))
                     (odra-interaction-profile-maps modal))
                '(111 144 19 17 12))
  (check-equal? (for/sum ([keymap (in-list (odra-interaction-profile-maps modal))])
                  (length (odra-keymap-bindings keymap)))
                303)
  (check-equal? (odra-command-entry-surface-name
                 (car (odra-interaction-profile-catalog-surfaces catalog)))
                "extended-command")
  (define selected-modal
    (personal-interaction-profile-catalog
     18 (factory-modal-interaction-profile 18)))
  (check-equal? (odra-interaction-profile-catalog-active-profile-id selected-modal) 2)
  (check-equal? (odra-interaction-profile-catalog-active-state-id selected-modal) 1)
  (check-equal? (length (odra-interaction-profile-catalog-profiles selected-modal)) 2)
  (check-exn exn:fail? (lambda () (keymap-remap "save" "save" provenance))))
