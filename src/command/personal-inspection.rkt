#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/path
         "catalog.rkt"
         "keymap-model.rkt"
         "personal.rkt"
         "../hosting/personal-command-containment.rkt")

(provide
 (struct-out personal-command-inspection)
 (struct-out personal-command-inspection-entry)
 (struct-out personal-binding-inspection-entry)
 (contract-out
  [compose-personal-command-inspection
   (-> exact-positive-integer? exact-nonnegative-integer? string?
       odra-command-catalog? odra-interaction-profile-catalog?
       (or/c #f personal-command-turn-inspection?)
       personal-command-inspection?)]))

(struct personal-command-inspection
  (active-generation rejected-generation latest-rejection commands bindings
                     last-turn factory-recovery-available?)
  #:transparent)
(struct personal-command-inspection-entry
  (name description source location requirements effects limits available?)
  #:transparent)
(struct personal-binding-inspection-entry
  (command map-name precedence sequence source effective?)
  #:transparent)

;; compose-personal-command-inspection copies one privacy-safe active snapshot.
(define (compose-personal-command-inspection
         active-generation rejected-generation latest-rejection catalog
         profile-catalog last-turn)
  (define personal-definitions
    (filter command? (odra-command-catalog-definitions catalog)))
  (define names
    (for/hash ([definition (in-list personal-definitions)])
      (values (odra-command-definition-name definition) #t)))
  (define commands
    (for/list ([definition (in-list personal-definitions)])
      (define provenance (odra-command-definition-provenance definition))
      (personal-command-inspection-entry
       (odra-command-definition-name definition)
       (odra-command-definition-description definition)
       (logical-source (odra-command-source-source provenance))
       (safe-location (odra-command-source-location provenance))
       (append (odra-command-definition-requirements definition) '())
       (append (odra-command-definition-effects definition) '())
       (command-limits definition)
       #t)))
  (define bindings
    (for*/list ([profile
                 (in-list
                  (odra-interaction-profile-catalog-profiles profile-catalog))]
                [keymap (in-list (odra-interaction-profile-maps profile))]
                [binding (in-list (odra-keymap-bindings keymap))]
                #:when (hash-ref names (odra-binding-command binding) #f))
      (personal-binding-inspection-entry
       (odra-binding-command binding)
       (odra-keymap-name keymap)
       (odra-keymap-precedence keymap)
       (odra-binding-sequence binding)
       (logical-source
        (odra-provenance-source (odra-binding-provenance binding)))
       #t)))
  (personal-command-inspection
   active-generation rejected-generation
   (safe-diagnostic-text latest-rejection)
   commands bindings last-turn #t))

(define (logical-source source)
  (define visible (visible-text source))
  (cond
    [(or (string=? visible "")
         (not (complete-path? (string->path visible))))
     visible]
    [else
     (define filename (file-name-from-path (string->path visible)))
     (if filename (path->string filename) "personal configuration")]))

(define (safe-location location)
  (if (or (string=? location "")
          (not (complete-path? (string->path location))))
      (safe-diagnostic-text location)
      ""))

(define (safe-diagnostic-text value)
  (regexp-replace*
   #px"(?:[A-Za-z]:)?/(?:[^[:space:]/]+/)+[^[:space:]]*"
   (visible-text value)
   "<path>"))

(define (visible-text value)
  (list->string
   (for/list ([character (in-string value)]
              #:when (and (char>=? character #\space)
                          (not (= (char->integer character) 127))))
     character)))

(module+ test
  (require rackunit
           "keymaps.rkt")

  (define definition
    (make-command
     'inspect-me (lambda (_context) (void))
     #:description "Inspection example."
     #:source "/home/example/.config/odra/modules/example.rkt"))
  (define catalog (compose-personal-command-catalog 7 (list definition)))
  (define provenance (odra-provenance "personal" "modules/example.rkt" ""))
  (define factory (factory-interaction-profile 7))
  (define personal-map
    (odra-keymap
     3 1 "personal" 0 0 'user-global 0 0 0 0 0 'fallthrough
     (list
      (keymap-bind
       (key-sequence (odra-key-stroke 1 (char->integer #\i) 1))
       "inspect-me" provenance))
     '() '() provenance))
  (define profile
    (compose-interaction-profile
     1 2 "personal-direct"
     (list (odra-interaction-profile-maps factory) (list personal-map))
     "insert-text"))
  (define inspection
    (compose-personal-command-inspection
     7 8 "bad\u001b[31m candidate" catalog
     (personal-interaction-profile-catalog 7 profile) #f))
  (check-equal? (personal-command-inspection-active-generation inspection) 7)
  (check-equal? (personal-command-inspection-rejected-generation inspection) 8)
  (check-equal? (length (personal-command-inspection-commands inspection)) 1)
  (check-equal?
   (personal-command-inspection-entry-source
    (car (personal-command-inspection-commands inspection)))
   "example.rkt")
  (check-equal? (length (personal-command-inspection-bindings inspection)) 1)
  (check-false
   (regexp-match? #rx"\033"
                  (personal-command-inspection-latest-rejection inspection)))
  (check-true
   (personal-command-inspection-factory-recovery-available? inspection)))
