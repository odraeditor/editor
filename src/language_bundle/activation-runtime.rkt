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
         "activation-candidate.rkt")

(provide
 (struct-out odra-bundle-replacement-relation)
 (struct-out odra-bundle-replacement-policy)
 (struct-out odra-bundle-runtime-entry)
 (struct-out odra-bundle-registry-generations)
 (struct-out odra-bundle-runtime-snapshot)
 (struct-out odra-bundle-publication-diagnostic)
 (struct-out odra-bundle-publication)
 bundle-runtime?
 (contract-out
  [make-bundle-runtime (-> bundle-runtime?)]
  [prepare-bundle-publication
   (-> bundle-runtime? odra-bundle-activation-candidate?
       odra-bundle-replacement-policy? odra-bundle-publication?)]
  [publish-bundle-publication!
   (-> bundle-runtime? odra-bundle-publication? boolean?)]
  [bundle-runtime-inspect
   (-> bundle-runtime? (or/c #f odra-bundle-runtime-snapshot?))]
  [bundle-runtime-close!
   (-> bundle-runtime? (listof string?))]))

(define admitted-kinds
  '(language syntax-provider service formatter command keymap))
(define admitted-sources '(factory package personal project))

(define (source-rank source)
  (case source
    [(factory) 1]
    [(package) 2]
    [(personal) 3]
    [(project) 4]
    [else 0]))

(struct odra-bundle-replacement-relation (kind identity replacer replaced)
  #:transparent
  #:guard
  (lambda (kind identity replacer replaced _)
    (unless (and (memq kind admitted-kinds) (symbol? identity)
                 (string? replacer) (string? replaced)
                 (not (string=? replacer replaced)))
      (raise-arguments-error
       'odra-bundle-replacement-relation "invalid replacement relation"))
    (values kind identity
            (string->immutable-string replacer)
            (string->immutable-string replaced))))

(struct odra-bundle-replacement-policy (declared approved)
  #:transparent
  #:guard
  (lambda (declared approved _)
    (unless (and (list? declared) (andmap odra-bundle-replacement-relation? declared)
                 (list? approved) (andmap odra-bundle-replacement-relation? approved))
      (raise-arguments-error
       'odra-bundle-replacement-policy "invalid replacement policy"))
    (values (remove-duplicates declared equal?)
            (remove-duplicates approved equal?))))

(struct odra-bundle-runtime-entry
  (kind identity bundle-id source contribution-generation status value)
  #:transparent)

(struct odra-bundle-registry-generations
  (language syntax service formatter command keymap artifact authority racket)
  #:transparent)

(struct odra-bundle-runtime-snapshot
  (runtime-generation lock-generation state-generation bundles registry-generations
                      effective shadowed contributions teardown-order)
  #:transparent)

(struct odra-bundle-publication-diagnostic (code kind identity participants detail)
  #:transparent)

(struct odra-bundle-publication
  (state base-runtime-generation snapshot retired-bundles failure consumed?)
  #:transparent #:mutable)

(struct bundle-runtime (snapshot generation busy? closed?)
  #:transparent #:mutable)

(define (make-bundle-runtime)
  (bundle-runtime #f 0 #f #f))

(define (semantic-key kind identity)
  (cons kind identity))

(define (status-table contribution)
  (for/hash ([status
              (in-list (odra-bundle-contribution-candidate-statuses contribution))])
    (values
     (semantic-key (odra-bundle-contribution-status-kind status)
                   (odra-bundle-contribution-status-id status))
     (odra-bundle-contribution-status-state status))))

(define (contribution-entries contribution)
  (define bundle-id
    (odra-bundle-contribution-candidate-bundle-id contribution))
  (define source (odra-bundle-contribution-candidate-source contribution))
  (define generation
    (odra-bundle-contribution-candidate-contribution-generation contribution))
  (define statuses (status-table contribution))
  (define (entries kind values identity)
    (for/list ([value (in-list values)])
      (define id (identity value))
      (odra-bundle-runtime-entry
       kind id bundle-id source generation
       (hash-ref statuses (semantic-key kind id)) value)))
  (append
   (entries 'language
            (odra-bundle-contribution-candidate-languages contribution)
            language:odra-language-id)
   (entries 'syntax-provider
            (odra-bundle-contribution-candidate-syntax-providers contribution)
            bundle:odra-tree-sitter-syntax-provider-id)
   (entries 'service
            (odra-bundle-contribution-candidate-services contribution)
            language:odra-language-service-id)
   (entries 'formatter
            (odra-bundle-contribution-candidate-formatters contribution)
            bundle:odra-language-formatter-id)
   (entries 'command
            (odra-bundle-contribution-candidate-commands contribution)
            bundle:odra-language-command-id)
   (entries 'keymap
            (odra-bundle-contribution-candidate-keymaps contribution)
            bundle:odra-language-keymap-id)))

(define (relation-present? relations kind identity replacer replaced)
  (member
   (odra-bundle-replacement-relation kind identity replacer replaced)
   relations equal?))

(define (replacement-winner entries policy)
  (define kind (odra-bundle-runtime-entry-kind (car entries)))
  (define identity (odra-bundle-runtime-entry-identity (car entries)))
  (define declared (odra-bundle-replacement-policy-declared policy))
  (define approved (odra-bundle-replacement-policy-approved policy))
  (define winners
    (for/list ([candidate (in-list entries)]
               #:when
               (for/and ([other (in-list entries)] #:unless (eq? candidate other))
                 (define replacer (odra-bundle-runtime-entry-bundle-id candidate))
                 (define replaced (odra-bundle-runtime-entry-bundle-id other))
                 (and (relation-present? declared kind identity replacer replaced)
                      (relation-present? approved kind identity replacer replaced))))
      candidate))
  (and (= (length winners) 1) (car winners)))

(define (resolve-group entries policy)
  (define highest-rank
    (apply max (map (lambda (entry)
                      (source-rank (odra-bundle-runtime-entry-source entry)))
                    entries)))
  (define leaders
    (filter (lambda (entry)
              (= (source-rank (odra-bundle-runtime-entry-source entry)) highest-rank))
            entries))
  (cond
    [(= (length leaders) 1)
     (values (car leaders) (remove (car leaders) entries eq?) #f)]
    [else
     (define winner (replacement-winner leaders policy))
     (if winner
         (values winner (remove winner entries eq?) #f)
         (values
          #f '()
          (odra-bundle-publication-diagnostic
           'symmetric-conflict
           (odra-bundle-runtime-entry-kind (car entries))
           (odra-bundle-runtime-entry-identity (car entries))
           (sort (map odra-bundle-runtime-entry-bundle-id leaders) string<?)
           "Same-precedence contributions require one declared and approved replacement")))]))

(define (resolve-entries entries policy)
  (define groups (make-hash))
  (for ([entry (in-list entries)])
    (hash-update! groups
                  (semantic-key (odra-bundle-runtime-entry-kind entry)
                                (odra-bundle-runtime-entry-identity entry))
                  (lambda (values) (cons entry values)) '()))
  (let loop ([keys (sort (hash-keys groups)
                         string<?
                         #:key (lambda (key) (format "~a/~a" (car key) (cdr key))))]
             [effective '()]
             [shadowed '()])
    (cond
      [(null? keys) (values (reverse effective) (reverse shadowed) #f)]
      [else
       (define-values (winner hidden failure)
         (resolve-group (hash-ref groups (car keys)) policy))
       (if failure
           (values '() '() failure)
           (loop (cdr keys) (cons winner effective) (append hidden shadowed)))])))

(define (bundle-dependency-map contributions)
  (for/hash ([contribution (in-list contributions)])
    (values (odra-bundle-contribution-candidate-bundle-id contribution)
            (odra-bundle-contribution-candidate-dependencies contribution))))

(define (reverse-dependency-order contributions selected)
  (define dependencies (bundle-dependency-map contributions))
  (define selected-set (for/hash ([id (in-list selected)]) (values id #t)))
  (define visited (make-hash))
  (define output '())
  (define (visit id)
    (unless (hash-ref visited id #f)
      (hash-set! visited id #t)
      (for ([dependent (in-hash-keys dependencies)]
            #:when (and (hash-ref selected-set dependent #f)
                        (member id (hash-ref dependencies dependent) string=?)))
        (visit dependent))
      (set! output (append output (list id)))))
  (for ([id (in-list (sort selected string<?))]) (visit id))
  output)

(define (registry-generations generation contributions)
  (define racket-generation
    (for/fold ([current 0]) ([contribution (in-list contributions)])
      (max current
           (odra-bundle-contribution-candidate-racket-generation contribution))))
  (odra-bundle-registry-generations
   generation generation generation generation generation generation generation generation
   racket-generation))

(define (prepare-bundle-publication runtime candidate policy)
  (cond
    [(or (bundle-runtime-closed? runtime) (bundle-runtime-busy? runtime))
     (odra-bundle-publication
      'rejected (bundle-runtime-generation runtime) #f '()
      (odra-bundle-publication-diagnostic
       'runtime-unavailable #f #f '() "Bundle runtime is closed or busy")
      #f)]
    [else
     (set-bundle-runtime-busy?! runtime #t)
     (dynamic-wind
       void
       (lambda ()
         (define contributions
           (odra-bundle-activation-candidate-contributions candidate))
         (define entries (append-map contribution-entries contributions))
         (define-values (effective shadowed failure)
           (resolve-entries entries policy))
         (cond
           [failure
            (odra-bundle-publication
             'rejected (bundle-runtime-generation runtime) #f '() failure #f)]
           [else
            (define next-generation (add1 (bundle-runtime-generation runtime)))
            (define prior
              (and (bundle-runtime-snapshot runtime)
                   (hash-keys
                    (odra-bundle-runtime-snapshot-bundles
                     (bundle-runtime-snapshot runtime)))))
            (define next
              (hash-keys (odra-bundle-activation-candidate-bundles candidate)))
            (define retired
              (filter (lambda (id) (not (member id next string=?))) (or prior '())))
            (define old-contributions
              (if (bundle-runtime-snapshot runtime)
                  (odra-bundle-runtime-snapshot-contributions
                   (bundle-runtime-snapshot runtime))
                  '()))
            (define teardown
              (reverse-dependency-order old-contributions retired))
            (odra-bundle-publication
             'prepared
             (bundle-runtime-generation runtime)
             (odra-bundle-runtime-snapshot
              next-generation
              (odra-bundle-activation-candidate-lock-generation candidate)
              (odra-bundle-activation-candidate-state-generation candidate)
              (odra-bundle-activation-candidate-bundles candidate)
              (registry-generations next-generation contributions)
              (for/hash ([entry (in-list effective)])
                (values (semantic-key (odra-bundle-runtime-entry-kind entry)
                                      (odra-bundle-runtime-entry-identity entry))
                        entry))
              (for/hash ([entry (in-list shadowed)])
                (values
                 (cons (semantic-key (odra-bundle-runtime-entry-kind entry)
                                     (odra-bundle-runtime-entry-identity entry))
                       (odra-bundle-runtime-entry-bundle-id entry))
                 entry))
              contributions teardown)
             teardown #f #f)]))
       (lambda () (set-bundle-runtime-busy?! runtime #f)))]))

(define (publish-bundle-publication! runtime publication)
  (cond
    [(or (bundle-runtime-closed? runtime) (bundle-runtime-busy? runtime)
         (odra-bundle-publication-consumed? publication)
         (not (eq? (odra-bundle-publication-state publication) 'prepared))
         (not (= (odra-bundle-publication-base-runtime-generation publication)
                 (bundle-runtime-generation runtime))))
     #f]
    [else
     (set-bundle-runtime-busy?! runtime #t)
     (set-bundle-runtime-snapshot! runtime
                                   (odra-bundle-publication-snapshot publication))
     (set-bundle-runtime-generation!
      runtime
      (odra-bundle-runtime-snapshot-runtime-generation
       (odra-bundle-publication-snapshot publication)))
     (set-odra-bundle-publication-consumed?! publication #t)
     (set-bundle-runtime-busy?! runtime #f)
     #t]))

(define (bundle-runtime-inspect runtime)
  (and (not (bundle-runtime-closed? runtime))
       (bundle-runtime-snapshot runtime)))

(define (bundle-runtime-close! runtime)
  (cond
    [(or (bundle-runtime-closed? runtime) (bundle-runtime-busy? runtime)) '()]
    [else
     (define contributions
       (if (bundle-runtime-snapshot runtime)
           (odra-bundle-runtime-snapshot-contributions
            (bundle-runtime-snapshot runtime))
           '()))
     (define order
       (reverse-dependency-order
        contributions
        (map odra-bundle-contribution-candidate-bundle-id contributions)))
     (set-bundle-runtime-snapshot! runtime #f)
     (set-bundle-runtime-closed?! runtime #t)
     order]))
