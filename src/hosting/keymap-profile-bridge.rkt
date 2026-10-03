#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         "../command/native-contracts.rkt"
         "../command/keymaps.rkt"
         (only-in "personal-command-runtime.rkt"
                  personal-command-runtime-profile-catalog))

(provide
 (contract-out
  [runtime-keymap-profile-batch
   (-> exact-positive-integer? list?)]))

(define (contract item) (native-contract-value 'keymap-profile item))
(define schema-version (contract 'schema-version))
(define header-bytes (contract 'profile-header-bytes))
(define profile-record-bytes (contract 'profile-record-bytes))
(define state-record-bytes (contract 'state-record-bytes))
(define map-record-bytes (contract 'map-record-bytes))
(define binding-record-bytes (contract 'binding-record-bytes))
(define selector-record-bytes (contract 'selector-record-bytes))
(define surface-record-bytes (contract 'surface-record-bytes))
(define remap-record-bytes (contract 'remap-record-bytes))
(define ordering-record-bytes (contract 'ordering-record-bytes))
(define stroke-record-bytes (contract 'stroke-record-bytes))
(define maximum-copy-bytes (contract 'maximum-copy-bytes))

(define (unsigned-word value)
  (integer->integer-bytes value 8 #f #f))

(define (signed-word value)
  (integer->integer-bytes value 8 #t #f))

(define (words . values)
  (apply bytes-append (map unsigned-word values)))

(define (precedence-value value)
  (case value
    [(protected-recovery) 1]
    [(transient-interaction) 2]
    [(component-tool) 3]
    [(buffer-local) 4]
    [(language-context) 5]
    [(project) 6]
    [(user-global) 7]
    [(profile-base) 8]
    [(factory-fallback) 9]))

(define (unmatched-value value)
  (case value
    [(fallthrough) 1]
    [(text-input) 2]
    [(reject) 3]))

(define (operation-value value)
  (case value
    [(bind) 1]
    [(replace) 2]
    [(unbind) 3]
    [(mask) 4]))

(define (scope-value value)
  (case value
    [(protected-recovery) 1]
    [(shared-continuity) 2]
    [(profile-specific) 3]
    [(state-specific) 4]))

(define (ordering-value value)
  (case value
    [(before) 1]
    [(after) 2]))

(define (effect-mask effects)
  (for/fold ([result 0]) ([effect (in-list effects)])
    (bitwise-ior
     result
     (case effect
       [(buffer) #x01]
       [(view) #x02]
       [(lifecycle) #x04]
       [(text-mutation) #x08]))))

(define (profile-catalog-batch registry-generation [version schema-version]
                               [catalog (personal-command-runtime-profile-catalog
                                         registry-generation)])
  (define text-output (open-output-bytes))
  (define (add-text value)
    (define encoded (string->bytes/utf-8 value))
    (define offset (file-position text-output))
    (write-bytes encoded text-output)
    (values offset (bytes-length encoded)))
  (define (add-provenance provenance)
    (define-values (provider-offset provider-bytes)
      (add-text (odra-provenance-provider provenance)))
    (define-values (source-offset source-bytes)
      (add-text (odra-provenance-source provenance)))
    (define-values (location-offset location-bytes)
      (add-text (odra-provenance-location provenance)))
    (list provider-offset provider-bytes source-offset source-bytes
          location-offset location-bytes))

  (define state-index 0)
  (define map-index 0)
  (define binding-index 0)
  (define selector-index 0)
  (define remap-index 0)
  (define ordering-index 0)
  (define stroke-index 0)
  (define state-records '())
  (define map-records '())
  (define binding-records '())
  (define selector-records '())
  (define remap-records '())
  (define ordering-records '())
  (define stroke-records '())

  (define profile-records
    (for/list ([profile (in-list (odra-interaction-profile-catalog-profiles catalog))])
      (define first-state state-index)
      (define local-state-records
        (for/list ([state (in-list (odra-interaction-profile-states profile))])
          (define-values (name-offset name-bytes)
            (add-text (odra-interaction-state-name state)))
          (apply words
                 (append
                  (list (odra-interaction-state-id state)
                        (odra-interaction-state-revision state)
                        (if (odra-interaction-state-admits-text-input state) 1 0)
                        (effect-mask (odra-interaction-state-admitted-effects state))
                        name-offset name-bytes)
                  (add-provenance (odra-interaction-state-provenance state))))))
      (set! state-records (append state-records local-state-records))
      (set! state-index (+ state-index (length local-state-records)))

      (define first-map map-index)
      (define local-map-records
        (for/list ([keymap (in-list (odra-interaction-profile-maps profile))])
          (define first-binding binding-index)
          (define local-bindings
            (for/list ([binding (in-list (odra-keymap-bindings keymap))])
              (define sequence-strokes
                (odra-key-sequence-strokes (odra-binding-sequence binding)))
              (define first-stroke stroke-index)
              (set! stroke-index (+ stroke-index (length sequence-strokes)))
              (set! stroke-records
                    (append
                     stroke-records
                     (for/list ([stroke (in-list sequence-strokes)])
                       (bytes-append
                        (unsigned-word (odra-key-stroke-kind stroke))
                        (unsigned-word (odra-key-stroke-modifiers stroke))
                        (signed-word (odra-key-stroke-scalar stroke))))))
              (define first-selector selector-index)
              (define local-selectors
                (for/list ([selector (in-list (odra-binding-selectors binding))])
                  (words (odra-profile-state-selector-profile-id selector)
                         (odra-profile-state-selector-state-id selector))))
              (set! selector-records (append selector-records local-selectors))
              (set! selector-index (+ selector-index (length local-selectors)))
              (define-values (command-offset command-bytes)
                (add-text (odra-binding-command binding)))
              (define-values (reason-offset reason-bytes)
                (add-text (odra-binding-protection-reason binding)))
              (apply words
                     (append
                      (list (operation-value (odra-binding-operation binding))
                            first-stroke (length sequence-strokes)
                            (scope-value (odra-binding-scope binding))
                            first-selector (length local-selectors)
                            command-offset command-bytes reason-offset reason-bytes)
                      (add-provenance (odra-binding-provenance binding))))))
          (set! binding-records (append binding-records local-bindings))
          (set! binding-index (+ binding-index (length local-bindings)))

          (define first-remap remap-index)
          (define local-remaps
            (for/list ([remap (in-list (odra-keymap-remaps keymap))])
              (define-values (from-offset from-bytes)
                (add-text (odra-remap-from-command remap)))
              (define-values (to-offset to-bytes)
                (add-text (odra-remap-to-command remap)))
              (apply words
                     (append (list from-offset from-bytes to-offset to-bytes)
                             (add-provenance (odra-remap-provenance remap))))))
          (set! remap-records (append remap-records local-remaps))
          (set! remap-index (+ remap-index (length local-remaps)))

          (define first-ordering ordering-index)
          (define local-ordering
            (for/list ([constraint (in-list (odra-keymap-ordering keymap))])
              (words (ordering-value (odra-ordering-relation constraint))
                     (odra-ordering-other-map-id constraint))))
          (set! ordering-records (append ordering-records local-ordering))
          (set! ordering-index (+ ordering-index (length local-ordering)))

          (define-values (name-offset name-bytes) (add-text (odra-keymap-name keymap)))
          (define provenance-fields (add-provenance (odra-keymap-provenance keymap)))
          (bytes-append
           (words (odra-keymap-id keymap)
                  (odra-keymap-revision keymap)
                  (odra-keymap-owner-id keymap)
                  (odra-keymap-owner-generation keymap)
                  (precedence-value (odra-keymap-precedence keymap)))
           (signed-word (odra-keymap-priority keymap))
           (apply words
                  (append
                   (list (odra-keymap-context-id keymap)
                         (odra-keymap-context-generation keymap)
                         (odra-keymap-context-owner-id keymap)
                         (odra-keymap-context-owner-generation keymap)
                         (unmatched-value (odra-keymap-unmatched-input-policy keymap))
                         first-binding (length local-bindings)
                         first-remap (length local-remaps)
                         first-ordering (length local-ordering)
                         name-offset name-bytes)
                   provenance-fields)))))
      (set! map-records (append map-records local-map-records))
      (set! map-index (+ map-index (length local-map-records)))

      (define-values (profile-name-offset profile-name-bytes)
        (add-text (odra-interaction-profile-name profile)))
      (define-values (fallback-offset fallback-bytes)
        (add-text (odra-interaction-profile-text-fallback-name profile)))
      (words (odra-interaction-profile-id profile)
             (odra-interaction-profile-revision profile)
             first-state (length local-state-records)
             (odra-interaction-profile-initial-state-id profile)
             first-map (length local-map-records)
             profile-name-offset profile-name-bytes fallback-offset fallback-bytes)))

  (define surface-records
    (for/list ([surface (in-list (odra-interaction-profile-catalog-surfaces catalog))])
      (define-values (name-offset name-bytes)
        (add-text (odra-command-entry-surface-name surface)))
      (apply words
             (append
              (list (odra-command-entry-surface-id surface)
                    (odra-command-entry-surface-revision surface)
                    name-offset name-bytes)
              (add-provenance (odra-command-entry-surface-provenance surface))))))

  (define text (get-output-bytes text-output))
  (define total-bytes
    (+ header-bytes
       (* profile-record-bytes (length profile-records))
       (* state-record-bytes (length state-records))
       (* map-record-bytes (length map-records))
       (* binding-record-bytes (length binding-records))
       (* selector-record-bytes (length selector-records))
       (* surface-record-bytes (length surface-records))
       (* remap-record-bytes (length remap-records))
       (* ordering-record-bytes (length ordering-records))
       (* stroke-record-bytes (length stroke-records))
       (bytes-length text)))
  (when (> total-bytes maximum-copy-bytes)
    (error 'runtime-keymap-profile-batch "profile catalog exceeds copied storage"))
  (define header
    (words version total-bytes registry-generation
           (odra-interaction-profile-catalog-generation catalog)
           (odra-interaction-profile-catalog-active-profile-id catalog)
           (odra-interaction-profile-catalog-active-state-id catalog)
           (length profile-records) (length state-records) (length map-records)
           (length binding-records) (length selector-records) (length surface-records)
           (length remap-records) (length ordering-records) (length stroke-records)
           (bytes-length text) 0 0))
  (apply bytes-append
         header
         (append profile-records state-records map-records binding-records
                 selector-records surface-records remap-records ordering-records
                 stroke-records (list text))))

(define (batch-with-u64 batch offset value)
  (define result (bytes-copy batch))
  (bytes-copy! result offset (unsigned-word value))
  result)

(define (synthetic-profile-catalog registry-generation)
  (define provenance (odra-provenance "test" "synthetic" ""))
  (define direct (factory-interaction-profile registry-generation))
  (define first-map (car (odra-interaction-profile-maps direct)))
  (define first-binding (car (odra-keymap-bindings first-map)))
  (define shared
    (keymap-share first-binding
                  (list (odra-profile-state-selector 1 1)
                        (odra-profile-state-selector 2 2))))
  (define shared-map
    (struct-copy odra-keymap first-map
                 [bindings (cons shared (cdr (odra-keymap-bindings first-map)))]))
  (define direct-with-shared
    (struct-copy odra-interaction-profile direct
                 [maps (cons shared-map (cdr (odra-interaction-profile-maps direct)))]))
  (define synthetic-state
    (odra-interaction-state 2 1 "synthetic-state" #f '(view) provenance))
  (define synthetic-map
    (struct-copy odra-keymap first-map
                 [name "synthetic-map"] [bindings '()]))
  (define synthetic-profile
    (odra-interaction-profile
     2 1 "synthetic" (list synthetic-state) 2 (list synthetic-map) "insert-text"))
  (compose-interaction-profile-catalog
   registry-generation (list direct-with-shared synthetic-profile) 1 1
   (list (odra-command-entry-surface 1 1 "extended-command" provenance))))

;; runtime-keymap-profile-batch returns one production profile catalog copy.
(define (runtime-keymap-profile-batch registry-generation)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f 0 #"" (string->bytes/utf-8 (exn-message failure))))])
    (list #t registry-generation
          (profile-catalog-batch registry-generation)
          #"")))

(module+ test-support
  (provide profile-catalog-batch
           maximum-copy-bytes
           schema-version
           synthetic-profile-catalog
           batch-with-u64))

(module+ test
  (require rackunit)

  (define result (runtime-keymap-profile-batch 17))
  (define batch (caddr result))
  (check-true (car result))
  (check-equal? (cadr result) 17)
  (check-equal? (bytes-length batch)
                (integer-bytes->integer batch #f #f 8 16))
  (check-equal? (integer-bytes->integer batch #f #f 16 24) 17)
  (check-equal? (integer-bytes->integer batch #f #f 24 32) 17)
  (check-equal? (integer-bytes->integer batch #f #f 48 56) 2)
  (check-equal? (integer-bytes->integer batch #f #f 56 64) 7)
  (check-equal? (integer-bytes->integer batch #f #f 64 72) 8)
  (check-equal? (integer-bytes->integer batch #f #f 88 96) 1))
