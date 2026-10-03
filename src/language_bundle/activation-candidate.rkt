#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         racket/match
         (prefix-in bundle: "../command/language-bundles.rkt")
         (prefix-in language: "../command/languages.rkt")
         "state-records.rkt")

(provide
 (struct-out odra-bundle-artifact-handle)
 (struct-out odra-bundle-preparation-input)
 (struct-out odra-bundle-contribution-status)
 (struct-out odra-bundle-contribution-candidate)
 (struct-out odra-bundle-activation-candidate)
 (struct-out odra-bundle-activation-failure)
 (struct-out odra-bundle-activation-preparation)
 (contract-out
  [prepare-bundle-activation
   (-> odra-activation-lock?
       (listof odra-bundle-preparation-input?)
       odra-bundle-activation-preparation?)]))

(define maximum-inputs 1024)
(define maximum-handle-bytes 4096)
(define maximum-scope-bytes 4096)
(define maximum-detail-bytes 4096)
(define admitted-sources '(factory package personal project))
(define admitted-availability '(available unavailable disabled failed unsupported))

(define (bounded-text? value maximum #:empty? [empty? #f])
  (and (string? value)
       (or empty? (positive? (string-length value)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)
       (not (for/or ([character (in-string value)]) (char=? character #\nul)))))

(define (copied-text value)
  (string->immutable-string value))

(define (identity-text value)
  (symbol->string value))

(define (sorted-symbols values)
  (sort (remove-duplicates values eq?) symbol<?))

(struct odra-bundle-artifact-handle (id digest size handle available?)
  #:transparent
  #:guard
  (lambda (id digest size handle available? _)
    (unless (and (symbol? id)
                 (regexp-match? #px"^[0-9a-f]{64}$" digest)
                 (exact-nonnegative-integer? size)
                 (bounded-text? handle maximum-handle-bytes)
                 (boolean? available?))
      (raise-arguments-error
       'odra-bundle-artifact-handle "invalid verified artifact handle"))
    (values id (copied-text digest) size (copied-text handle) available?)))

(struct odra-bundle-preparation-input
  (bundle source scope granted-authorities artifact-handles availability racket-generation)
  #:transparent
  #:guard
  (lambda (bundle source scope granted-authorities artifact-handles availability
                  racket-generation _)
    (unless (and (bundle:odra-language-support-bundle? bundle)
                 (memq source admitted-sources)
                 (bounded-text? scope maximum-scope-bytes #:empty? #t)
                 (list? granted-authorities)
                 (andmap symbol? granted-authorities)
                 (= (length granted-authorities)
                    (length (remove-duplicates granted-authorities eq?)))
                 (hash? artifact-handles)
                 (immutable? artifact-handles)
                 (for/and ([(id handle) (in-hash artifact-handles)])
                   (and (symbol? id)
                        (odra-bundle-artifact-handle? handle)
                        (eq? id (odra-bundle-artifact-handle-id handle))))
                 (hash? availability)
                 (immutable? availability)
                 (for/and ([(id state) (in-hash availability)])
                   (and (symbol? id) (memq state admitted-availability)))
                 (exact-nonnegative-integer? racket-generation))
      (raise-arguments-error
       'odra-bundle-preparation-input "invalid bundle preparation input"))
    (values bundle source (copied-text scope) (sorted-symbols granted-authorities)
            (make-immutable-hasheq (hash->list artifact-handles))
            (make-immutable-hasheq (hash->list availability))
            racket-generation)))

(struct odra-bundle-contribution-status (kind id state detail)
  #:transparent
  #:guard
  (lambda (kind id state detail _)
    (unless (and (symbol? kind) (symbol? id)
                 (memq state admitted-availability)
                 (bounded-text? detail maximum-detail-bytes #:empty? #t))
      (raise-arguments-error
       'odra-bundle-contribution-status "invalid contribution status"))
    (values kind id state (copied-text detail))))

(struct odra-bundle-contribution-candidate
  (lock-generation contribution-generation bundle-id bundle-version source scope
                   authorities artifacts languages syntax-providers services formatters
                   commands keymaps racket-generation statuses dependencies)
  #:transparent)

(struct odra-bundle-activation-candidate
  (lock-generation state-generation bundles contribution-generations contributions)
  #:transparent)

(struct odra-bundle-activation-failure (code bundle-id field detail)
  #:transparent
  #:guard
  (lambda (code bundle-id field detail _)
    (values code bundle-id field
            (copied-text
             (if (bounded-text? detail maximum-detail-bytes #:empty? #t)
                 detail
                 "activation failure detail exceeded the admitted boundary")))))

(struct odra-bundle-activation-preparation (state candidate failure)
  #:transparent)

(define (rejected code [bundle-id #f] [field #f] [detail ""])
  (odra-bundle-activation-preparation
   'rejected #f (odra-bundle-activation-failure code bundle-id field detail)))

(define (bundle-id value)
  (identity-text (bundle:odra-language-support-bundle-id value)))

(define (declared-authorities value)
  (map bundle:odra-language-bundle-authority-id
       (bundle:odra-language-support-bundle-authorities value)))

(define (authority-subset? required granted)
  (for/and ([authority (in-list required)]) (memq authority granted)))

(define (artifact-table-valid? value handles)
  (define artifacts (bundle:odra-language-support-bundle-artifacts value))
  (and (= (length artifacts) (hash-count handles))
       (for/and ([artifact (in-list artifacts)])
         (define id (bundle:odra-language-bundle-artifact-id artifact))
         (define handle (hash-ref handles id #f))
         (and handle
              (odra-bundle-artifact-handle-available? handle)
              (string=? (bundle:odra-language-bundle-artifact-sha256 artifact)
                        (odra-bundle-artifact-handle-digest handle))
              (= (bundle:odra-language-bundle-artifact-size artifact)
                 (odra-bundle-artifact-handle-size handle))))))

(define (dependency-table-valid? value lock)
  (for/and ([dependency
             (in-list (bundle:odra-language-support-bundle-dependencies value))])
    (or (hash-has-key?
         (odra-activation-lock-bundles lock)
         (identity-text (bundle:odra-language-bundle-dependency-id dependency)))
        (bundle:odra-language-bundle-dependency-optional? dependency))))

(define (contribution-statuses value availability)
  (define (records kind values identity)
    (for/list ([entry (in-list values)])
      (define id (identity entry))
      (define state (hash-ref availability id 'available))
      (odra-bundle-contribution-status
       kind id state (if (eq? state 'available) "" "Contribution is not available"))))
  (append
   (records 'language
            (bundle:odra-language-support-bundle-languages value)
            language:odra-language-id)
   (records 'syntax-provider
            (bundle:odra-language-support-bundle-syntax-providers value)
            bundle:odra-tree-sitter-syntax-provider-id)
   (records 'service
            (bundle:odra-language-support-bundle-services value)
            language:odra-language-service-id)
   (records 'formatter
            (bundle:odra-language-support-bundle-formatters value)
            bundle:odra-language-formatter-id)
   (records 'command
            (bundle:odra-language-support-bundle-commands value)
            bundle:odra-language-command-id)
   (records 'keymap
            (bundle:odra-language-support-bundle-keymaps value)
            bundle:odra-language-keymap-id)))

(define (availability-complete? value availability)
  (define valid-ids
    (map odra-bundle-contribution-status-id
         (contribution-statuses value (hasheq))))
  (for/and ([id (in-hash-keys availability)]) (memq id valid-ids)))

(define (prepare-one lock input)
  (define value (odra-bundle-preparation-input-bundle input))
  (define id (bundle-id value))
  (define version (bundle:odra-language-support-bundle-version value))
  (define locked-version
    (hash-ref (odra-activation-lock-bundles lock) id #f))
  (define generation
    (hash-ref (odra-activation-lock-contribution-generations lock) id #f))
  (define granted (odra-bundle-preparation-input-granted-authorities input))
  (cond
    [(not locked-version)
     (values #f (odra-bundle-activation-failure
                 'unknown-bundle id 'lock "Bundle is absent from the activation lock"))]
    [(not (string=? version locked-version))
     (values #f (odra-bundle-activation-failure
                 'version-mismatch id 'version "Bundle version differs from the activation lock"))]
    [(not (and generation (positive? generation)))
     (values #f (odra-bundle-activation-failure
                 'generation-mismatch id 'generation
                 "Contribution generation is absent from the activation lock"))]
    [(not (authority-subset? granted (declared-authorities value)))
     (values #f (odra-bundle-activation-failure
                 'authority-escalation id 'authorities
                 "Granted authority is absent from the bundle manifest"))]
    [(not (authority-subset? (declared-authorities value) granted))
     (values #f (odra-bundle-activation-failure
                 'authority-denied id 'authorities
                 "A declared bundle authority was not granted"))]
    [(not (artifact-table-valid?
           value (odra-bundle-preparation-input-artifact-handles input)))
     (values #f (odra-bundle-activation-failure
                 'artifact-mismatch id 'artifacts
                 "Verified artifact handles do not match the bundle manifest"))]
    [(not (dependency-table-valid? value lock))
     (values #f (odra-bundle-activation-failure
                 'dependency-mismatch id 'dependencies
                 "A required dependency is absent from the activation lock"))]
    [(and (bundle:odra-language-support-bundle-entrypoint value)
          (or (not (memq 'racket-extension granted))
              (zero? (odra-bundle-preparation-input-racket-generation input))))
     (values #f (odra-bundle-activation-failure
                 'racket-unavailable id 'entrypoint
                 "A Racket entrypoint requires authority and an exact runtime generation"))]
    [(not (availability-complete?
           value (odra-bundle-preparation-input-availability input)))
     (values #f (odra-bundle-activation-failure
                 'unknown-contribution id 'availability
                 "Availability names a contribution absent from the bundle"))]
    [else
     (values
      (odra-bundle-contribution-candidate
       (odra-activation-lock-generation lock)
       generation id (copied-text version)
       (odra-bundle-preparation-input-source input)
       (odra-bundle-preparation-input-scope input)
       granted
       (odra-bundle-preparation-input-artifact-handles input)
       (bundle:odra-language-support-bundle-languages value)
       (bundle:odra-language-support-bundle-syntax-providers value)
       (bundle:odra-language-support-bundle-services value)
       (bundle:odra-language-support-bundle-formatters value)
       (bundle:odra-language-support-bundle-commands value)
       (bundle:odra-language-support-bundle-keymaps value)
       (odra-bundle-preparation-input-racket-generation input)
       (contribution-statuses
        value (odra-bundle-preparation-input-availability input))
       (sort
        (map (lambda (dependency)
               (identity-text
                (bundle:odra-language-bundle-dependency-id dependency)))
             (bundle:odra-language-support-bundle-dependencies value))
        string<?))
      #f)]))

(define (prepare-bundle-activation lock inputs)
  (cond
    [(not (string=? (odra-activation-lock-checksum lock)
                    (activation-lock-checksum lock)))
     (rejected 'invalid-lock #f 'checksum "Activation lock checksum is invalid")]
    [(or (> (length inputs) maximum-inputs)
         (not (= (length inputs)
                 (hash-count (odra-activation-lock-bundles lock)))))
     (rejected 'input-mismatch #f 'bundles
               "Preparation inputs do not cover the exact activation lock")]
    [else
     (define seen (make-hash))
     (define prepared
       (for/fold ([result '()]) ([input (in-list inputs)] #:break (not result))
         (define id (bundle-id (odra-bundle-preparation-input-bundle input)))
         (cond
           [(hash-ref seen id #f) #f]
           [else
            (hash-set! seen id #t)
            (define-values (candidate failure) (prepare-one lock input))
            (if failure (list failure) (cons candidate result))])))
     (cond
       [(not prepared)
        (rejected 'duplicate-bundle #f 'bundles
                  "A bundle identity appears more than once")]
       [(and (= (length prepared) 1)
             (odra-bundle-activation-failure? (car prepared)))
        (odra-bundle-activation-preparation 'rejected #f (car prepared))]
       [(ormap odra-bundle-activation-failure? prepared)
        (odra-bundle-activation-preparation
         'rejected #f (findf odra-bundle-activation-failure? prepared))]
       [else
        (define contributions
          (sort prepared string<? #:key odra-bundle-contribution-candidate-bundle-id))
        (odra-bundle-activation-preparation
         'prepared
         (odra-bundle-activation-candidate
          (odra-activation-lock-generation lock)
          (odra-activation-lock-state-generation lock)
          (odra-activation-lock-bundles lock)
          (odra-activation-lock-contribution-generations lock)
          contributions)
         #f)])]))
