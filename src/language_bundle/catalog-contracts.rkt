#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/list
         racket/match
         racket/path
         racket/string
         "../package/authority-contract.rkt")

(provide
 maximum-catalog-snapshot-bytes
 maximum-catalog-entries
 maximum-catalog-artifact-descriptors
 maximum-catalog-archive-entries
 maximum-catalog-expanded-bytes
 (struct-out odra-catalog-credential-reference)
 (struct-out odra-catalog-signing-key)
 (struct-out odra-catalog-refresh-policy)
 (struct-out odra-catalog-resource-limits)
 (struct-out odra-catalog-source)
 (struct-out odra-catalog-signature)
 (struct-out odra-catalog-expiry)
 (struct-out odra-catalog-target)
 (struct-out odra-catalog-dependency-summary)
 (struct-out odra-catalog-entry)
 (struct-out odra-catalog-snapshot)
 (struct-out odra-catalog-cache-record)
 (struct-out odra-catalog-index-entry)
 (struct-out odra-catalog-search-index)
 (contract-out
  [catalog-expiry-status
   (-> odra-catalog-expiry? exact-nonnegative-integer?
       (or/c 'not-yet-valid 'fresh 'expired))]))

(define maximum-catalog-snapshot-bytes (* 64 1024 1024))
(define maximum-catalog-entries 65536)
(define maximum-catalog-artifact-descriptors 262144)
(define maximum-catalog-archive-entries 8192)
(define maximum-catalog-expanded-bytes (expt 2 30))
(define maximum-catalog-source-keys 64)
(define maximum-catalog-entry-locations 16)
(define maximum-catalog-entry-authorities 6)
(define maximum-catalog-entry-dependencies 256)
(define maximum-catalog-entry-targets 16)
(define maximum-catalog-entry-facets 6)
(define maximum-catalog-index-values 64)
(define maximum-identity-bytes 128)
(define maximum-display-name-bytes 256)
(define maximum-summary-bytes 4096)
(define maximum-location-bytes 4096)
(define maximum-diagnostic-bytes 4096)
(define maximum-refresh-seconds (* 365 24 60 60))
(define maximum-request-milliseconds (* 10 60 1000))
(define maximum-retries 8)
(define maximum-redirects 8)
(define digest-pattern #px"^[0-9a-f]{64}$")
(define signature-pattern #px"^[0-9a-f]{128}$")
(define version-pattern
  #px"^(?:0|[1-9][0-9]*)\\.(?:0|[1-9][0-9]*)\\.(?:0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?$")
(define identity-pattern #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")
(define admitted-platforms '(darwin linux windows))
(define admitted-architectures '(aarch64 x86-64))
(define admitted-facets '(command formatter keymap language service syntax-provider))
(define admitted-credential-providers '(environment keyring secret-service))
(define admitted-refresh-modes '(manual interval startup))
(define admitted-network-policies '(offline direct configured-proxy))

(define (bounded-text? value maximum #:empty? [empty? #f])
  (and (string? value)
       (or empty? (positive? (string-length value)))
       (not (string-contains? value (string #\nul)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(define (identity? value)
  (and (bounded-text? value maximum-identity-bytes)
       (regexp-match? identity-pattern value)))

(define (version? value)
  (and (bounded-text? value maximum-identity-bytes)
       (regexp-match? version-pattern value)))

(define (digest? value)
  (and (string? value) (regexp-match? digest-pattern value)))

(define (hex->bytes value)
  (apply bytes
         (for/list ([index (in-range 0 (string-length value) 2)])
           (string->number (substring value index (+ index 2)) 16))))

(define (copied value)
  (if (string? value) (string->immutable-string value) value))

(define (symbol<? left right)
  (string<? (symbol->string left) (symbol->string right)))

(define (unique-sorted? values less?)
  (and (list? values)
       (equal? values (sort (remove-duplicates values) less?))))

(define (symbol-set? values admitted maximum)
  (and (unique-sorted? values symbol<?)
       (<= (length values) maximum)
       (andmap (lambda (value) (and (memq value admitted) #t)) values)))

(define (relative-location? value)
  (and (bounded-text? value maximum-location-bytes)
       (not (regexp-match? #px"^(?:/|\\\\|[A-Za-z]:)" value))
       (for/and ([part (in-list (string-split value "/"))])
         (not (member part '("" "." ".."))))))

(define (https-location? value)
  (and (bounded-text? value maximum-location-bytes)
       (regexp-match? #px"^https://[^/@?#]+(?::[0-9]+)?/[^?#]*$" value)))

(define (absolute-local-path? value)
  (and (bounded-text? value maximum-location-bytes)
       (absolute-path? (string->path value))))

(define (entry-location? value)
  (or (relative-location? value) (https-location? value)))

(struct odra-catalog-credential-reference (provider identity)
  #:transparent
  #:guard
  (lambda (provider identity _)
    (unless (and (memq provider admitted-credential-providers)
                 (identity? identity))
      (raise-arguments-error
       'odra-catalog-credential-reference
       "credential references contain only an admitted provider and stable identity"))
    (values provider (copied identity))))

(struct odra-catalog-signing-key (id algorithm public-key)
  #:transparent
  #:guard
  (lambda (id algorithm public-key _)
    (unless (and (digest? id) (eq? algorithm 'ed25519)
                 (regexp-match? #px"^[0-9a-f]{64}$" public-key)
                 (string=? id
                           (bytes->hex-string
                            (sha256-bytes
                             (open-input-bytes (hex->bytes public-key))))))
      (raise-arguments-error 'odra-catalog-signing-key
                             "invalid Ed25519 trust-root identity"))
    (values (copied id) algorithm (copied public-key))))

(struct odra-catalog-refresh-policy (mode interval-seconds maximum-stale-seconds)
  #:transparent
  #:guard
  (lambda (mode interval-seconds maximum-stale-seconds _)
    (unless (and (memq mode admitted-refresh-modes)
                 (exact-nonnegative-integer? interval-seconds)
                 (<= interval-seconds maximum-refresh-seconds)
                 (exact-nonnegative-integer? maximum-stale-seconds)
                 (<= maximum-stale-seconds maximum-refresh-seconds)
                 (if (eq? mode 'interval)
                     (positive? interval-seconds)
                     (zero? interval-seconds)))
      (raise-arguments-error 'odra-catalog-refresh-policy
                             "invalid bounded refresh policy"))
    (values mode interval-seconds maximum-stale-seconds)))

(struct odra-catalog-resource-limits
  (snapshot-bytes entries artifact-descriptors request-milliseconds redirects retries)
  #:transparent
  #:guard
  (lambda (snapshot-bytes entries artifact-descriptors request-milliseconds
                          redirects retries _)
    (unless (and (exact-positive-integer? snapshot-bytes)
                 (<= snapshot-bytes maximum-catalog-snapshot-bytes)
                 (exact-positive-integer? entries)
                 (<= entries maximum-catalog-entries)
                 (exact-positive-integer? artifact-descriptors)
                 (<= artifact-descriptors maximum-catalog-artifact-descriptors)
                 (exact-positive-integer? request-milliseconds)
                 (<= request-milliseconds maximum-request-milliseconds)
                 (exact-nonnegative-integer? redirects)
                 (<= redirects maximum-redirects)
                 (exact-nonnegative-integer? retries)
                 (<= retries maximum-retries))
      (raise-arguments-error 'odra-catalog-resource-limits
                             "catalog resource limits exceed native maxima"))
    (values snapshot-bytes entries artifact-descriptors request-milliseconds
            redirects retries)))

(struct odra-catalog-source
  (id transport endpoint precedence refresh-policy trusted-keys
      network-policy credential-reference limits)
  #:transparent
  #:guard
  (lambda (id transport endpoint precedence refresh-policy trusted-keys
              network-policy credential-reference limits _)
    (unless (and (identity? id)
                 (memq transport '(local-file https))
                 (if (eq? transport 'local-file)
                     (absolute-local-path? endpoint)
                     (https-location? endpoint))
                 (exact-nonnegative-integer? precedence)
                 (<= precedence 65535)
                 (odra-catalog-refresh-policy? refresh-policy)
                 (list? trusted-keys)
                 (pair? trusted-keys)
                 (<= (length trusted-keys) maximum-catalog-source-keys)
                 (andmap odra-catalog-signing-key? trusted-keys)
                 (equal? (map odra-catalog-signing-key-id trusted-keys)
                         (sort (remove-duplicates
                                (map odra-catalog-signing-key-id trusted-keys)
                                string=?)
                               string<?))
                 (memq network-policy admitted-network-policies)
                 (or (not credential-reference)
                     (odra-catalog-credential-reference? credential-reference))
                 (odra-catalog-resource-limits? limits)
                 (if (eq? transport 'local-file)
                     (and (eq? network-policy 'offline)
                          (not credential-reference))
                     (not (eq? network-policy 'offline))))
      (raise-arguments-error 'odra-catalog-source
                             "invalid local-file or HTTPS catalog source"))
    (values (copied id) transport (copied endpoint) precedence refresh-policy
            trusted-keys network-policy credential-reference limits)))

(struct odra-catalog-signature (algorithm key-id domain value)
  #:transparent
  #:guard
  (lambda (algorithm key-id domain value _)
    (unless (and (eq? algorithm 'ed25519)
                 (digest? key-id)
                 (string=? domain "odra-language-catalog-v1")
                 (regexp-match? signature-pattern value))
      (raise-arguments-error 'odra-catalog-signature
                             "invalid domain-separated Ed25519 signature record"))
    (values algorithm (copied key-id) (copied domain) (copied value))))

(struct odra-catalog-expiry (generated-at expires-at confirmed-at)
  #:transparent
  #:guard
  (lambda (generated-at expires-at confirmed-at _)
    (unless (and (exact-nonnegative-integer? generated-at)
                 (exact-nonnegative-integer? expires-at)
                 (exact-nonnegative-integer? confirmed-at)
                 (<= generated-at confirmed-at expires-at))
      (raise-arguments-error 'odra-catalog-expiry
                             "expiry timestamps must be ordered"))
    (values generated-at expires-at confirmed-at)))

(define (catalog-expiry-status expiry now)
  (cond
    [(< now (odra-catalog-expiry-generated-at expiry)) 'not-yet-valid]
    [(> now (odra-catalog-expiry-expires-at expiry)) 'expired]
    [else 'fresh]))

(struct odra-catalog-target (platform architecture)
  #:transparent
  #:guard
  (lambda (platform architecture _)
    (unless (and (memq platform admitted-platforms)
                 (memq architecture admitted-architectures))
      (raise-arguments-error 'odra-catalog-target
                             "unsupported platform or architecture"))
    (values platform architecture)))

(define (target<? left right)
  (string<? (format "~a/~a" (odra-catalog-target-platform left)
                    (odra-catalog-target-architecture left))
            (format "~a/~a" (odra-catalog-target-platform right)
                    (odra-catalog-target-architecture right))))

(struct odra-catalog-dependency-summary
  (id minimum maximum optional? facets)
  #:transparent
  #:guard
  (lambda (id minimum maximum optional? facets _)
    (unless (and (identity? id) (version? minimum) (version? maximum)
                 (boolean? optional?)
                 (symbol-set? facets admitted-facets maximum-catalog-entry-facets))
      (raise-arguments-error 'odra-catalog-dependency-summary
                             "invalid catalog dependency summary"))
    (values (copied id) (copied minimum) (copied maximum) optional? facets)))

(define (dependency<? left right)
  (string<? (odra-catalog-dependency-summary-id left)
            (odra-catalog-dependency-summary-id right)))

(struct odra-catalog-entry
  (bundle-id version api-minimum api-maximum targets manifest-digest
             manifest-locations display-name summary facets authorities dependencies
             artifact-count artifact-bytes deprecated? replacement)
  #:transparent
  #:guard
  (lambda (bundle-id version api-minimum api-maximum targets manifest-digest
                     manifest-locations display-name summary facets authorities dependencies
                     artifact-count artifact-bytes deprecated? replacement _)
    (unless (and (identity? bundle-id) (version? version)
                 (version? api-minimum) (version? api-maximum)
                 (unique-sorted? targets target<?)
                 (pair? targets)
                 (<= (length targets) maximum-catalog-entry-targets)
                 (andmap odra-catalog-target? targets)
                 (digest? manifest-digest)
                 (unique-sorted? manifest-locations string<?)
                 (pair? manifest-locations)
                 (<= (length manifest-locations) maximum-catalog-entry-locations)
                 (andmap entry-location? manifest-locations)
                 (bounded-text? display-name maximum-display-name-bytes)
                 (bounded-text? summary maximum-summary-bytes #:empty? #t)
                 (symbol-set? facets admitted-facets maximum-catalog-entry-facets)
                 (package-authority-set? authorities
                                         #:maximum maximum-catalog-entry-authorities)
                 (unique-sorted? dependencies dependency<?)
                 (<= (length dependencies) maximum-catalog-entry-dependencies)
                 (andmap odra-catalog-dependency-summary? dependencies)
                 (for/and ([dependency (in-list dependencies)])
                   (not (string=? bundle-id
                                  (odra-catalog-dependency-summary-id dependency))))
                 (exact-nonnegative-integer? artifact-count)
                 (<= artifact-count maximum-catalog-artifact-descriptors)
                 (exact-nonnegative-integer? artifact-bytes)
                 (<= artifact-bytes maximum-catalog-expanded-bytes)
                 (boolean? deprecated?)
                 (or (not replacement)
                     (and (identity? replacement)
                          (not (string=? bundle-id replacement)))))
      (raise-arguments-error 'odra-catalog-entry "invalid bounded catalog entry"))
    (values (copied bundle-id) (copied version) (copied api-minimum)
            (copied api-maximum) targets (copied manifest-digest)
            (map copied manifest-locations) (copied display-name) (copied summary)
            facets authorities dependencies artifact-count artifact-bytes deprecated?
            (and replacement (copied replacement)))))

(define (entry-key entry)
  (format "~a@~a" (odra-catalog-entry-bundle-id entry)
          (odra-catalog-entry-version entry)))

(struct odra-catalog-snapshot
  (format-version source-id sequence snapshot-digest expiry entries-digest signing-key-id
                  signature entries encoded-bytes)
  #:transparent
  #:guard
  (lambda (format-version source-id sequence snapshot-digest expiry entries-digest signing-key-id
                          signature entries encoded-bytes _)
    (define entry-keys
      (and (list? entries) (map entry-key entries)))
    (unless (and (= format-version 1)
                 (identity? source-id)
                 (exact-positive-integer? sequence)
                 (digest? snapshot-digest)
                 (odra-catalog-expiry? expiry)
                 (digest? entries-digest)
                 (digest? signing-key-id)
                 (odra-catalog-signature? signature)
                 (string=? signing-key-id
                           (odra-catalog-signature-key-id signature))
                 (list? entries)
                 (<= (length entries) maximum-catalog-entries)
                 (andmap odra-catalog-entry? entries)
                 (equal? entry-keys
                         (sort (remove-duplicates entry-keys) string<?))
                 (<= (for/sum ([entry (in-list entries)])
                       (odra-catalog-entry-artifact-count entry))
                     maximum-catalog-artifact-descriptors)
                 (exact-positive-integer? encoded-bytes)
                 (<= encoded-bytes maximum-catalog-snapshot-bytes))
      (raise-arguments-error 'odra-catalog-snapshot
                             "invalid signed catalog snapshot"))
    (values format-version (copied source-id) sequence (copied snapshot-digest) expiry
            (copied entries-digest) (copied signing-key-id) signature
            entries encoded-bytes)))

(struct odra-catalog-cache-record
  (format-version source-id generation confirmed-snapshot-digest
                  previous-snapshot-digest snapshot-path index-path expiry latest-failure)
  #:transparent
  #:guard
  (lambda (format-version source-id generation confirmed-snapshot-digest
                          previous-snapshot-digest snapshot-path index-path expiry
                          latest-failure _)
    (unless (and (= format-version 1) (identity? source-id)
                 (exact-positive-integer? generation)
                 (digest? confirmed-snapshot-digest)
                 (or (not previous-snapshot-digest)
                     (and (digest? previous-snapshot-digest)
                          (not (string=? confirmed-snapshot-digest
                                         previous-snapshot-digest))))
                 (absolute-local-path? snapshot-path)
                 (absolute-local-path? index-path)
                 (odra-catalog-expiry? expiry)
                 (bounded-text? latest-failure maximum-diagnostic-bytes #:empty? #t))
      (raise-arguments-error 'odra-catalog-cache-record
                             "invalid confirmed catalog cache record"))
    (values format-version (copied source-id) generation
            (copied confirmed-snapshot-digest)
            (and previous-snapshot-digest (copied previous-snapshot-digest))
            (copied snapshot-path) (copied index-path) expiry
            (copied latest-failure))))

(struct odra-catalog-index-entry
  (bundle-id version display-name languages facets targets)
  #:transparent
  #:guard
  (lambda (bundle-id version display-name languages facets targets _)
    (unless (and (identity? bundle-id) (version? version)
                 (bounded-text? display-name maximum-display-name-bytes)
                 (unique-sorted? languages string<?)
                 (<= (length languages) maximum-catalog-index-values)
                 (andmap identity? languages)
                 (symbol-set? facets admitted-facets maximum-catalog-entry-facets)
                 (unique-sorted? targets target<?)
                 (<= (length targets) maximum-catalog-entry-targets)
                 (andmap odra-catalog-target? targets))
      (raise-arguments-error 'odra-catalog-index-entry
                             "invalid bounded catalog index entry"))
    (values (copied bundle-id) (copied version) (copied display-name)
            (map copied languages) facets targets)))

(define (index-entry-key entry)
  (format "~a@~a" (odra-catalog-index-entry-bundle-id entry)
          (odra-catalog-index-entry-version entry)))

(struct odra-catalog-search-index (snapshot-digest entries)
  #:transparent
  #:guard
  (lambda (snapshot-digest entries _)
    (define keys (and (list? entries) (map index-entry-key entries)))
    (unless (and (digest? snapshot-digest)
                 (list? entries)
                 (<= (length entries) maximum-catalog-entries)
                 (andmap odra-catalog-index-entry? entries)
                 (equal? keys (sort (remove-duplicates keys) string<?)))
      (raise-arguments-error 'odra-catalog-search-index
                             "invalid rebuildable catalog search index"))
    (values (copied snapshot-digest) entries)))
