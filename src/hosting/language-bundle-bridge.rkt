#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         json
         (except-in openssl/sha1 sha1)
         racket/contract/base
         racket/list
         racket/path
         racket/runtime-path
         racket/sandbox
         (prefix-in bundle: "../command/language-bundles.rkt")
         (prefix-in language: "../command/languages.rkt"))

(provide
 language-bundle-bridge-schema-version
 maximum-language-bundle-bytes
 (struct-out language-bundle-load-rejection)
 (struct-out language-bundle-load-result)
 (contract-out
  [language-bundle-encode
   (-> bundle:odra-language-support-bundle? bytes?)]
  [language-bundle-digest
   (-> bundle:odra-language-support-bundle? string?)]
  [load-language-bundle-module
   (-> path-string? exact-nonnegative-integer? exact-positive-integer?
       language-bundle-load-result?)]))

(define language-bundle-bridge-schema-version 1)
(define maximum-language-bundle-bytes (* 2 1024 1024))
(define language-bundle-load-time-limit-seconds 2)
(define language-bundle-load-memory-limit-megabytes 128)
(define maximum-load-diagnostic-bytes 4096)

(struct language-bundle-load-rejection (code detail limit actual)
  #:transparent)
(struct language-bundle-load-result (state generation bundle bytes rejection)
  #:transparent)

(define-runtime-module-path bundle-api-module
  "../command/language-bundles.rkt")
(define-runtime-module-path language-api-module
  "../command/languages.rkt")

(define current-language-bundle-load (make-parameter #f))

(define (symbol-text value)
  (symbol->string value))

(define (symbol-list values)
  (map symbol-text (sort values symbol<?)))

(define (target->jsexpr target)
  (hasheq 'platform (symbol-text (car target))
          'architecture (symbol-text (cadr target))))

(define (sorted-targets values)
  (sort values string<?
        #:key (lambda (target)
                (format "~a/~a" (car target) (cadr target)))))

(define (version->jsexpr value)
  (define match
    (regexp-match
     #px"^([0-9]+)\\.([0-9]+)\\.([0-9]+)(?:-([0-9A-Za-z.-]+))?$"
     value))
  (hasheq 'major (string->number (list-ref match 1))
          'minor (string->number (list-ref match 2))
          'patch (string->number (list-ref match 3))
          'pre-release (or (list-ref match 4) 'null)))

(define (authority->jsexpr value)
  (symbol-text (bundle:odra-language-bundle-authority-id value)))

(define (dependency->jsexpr value)
  (hasheq
   'id (symbol-text (bundle:odra-language-bundle-dependency-id value))
   'minimum (version->jsexpr (bundle:odra-language-bundle-dependency-minimum value))
   'maximum (version->jsexpr (bundle:odra-language-bundle-dependency-maximum value))
   'optional (bundle:odra-language-bundle-dependency-optional? value)
   'facets (symbol-list (bundle:odra-language-bundle-dependency-facets value))
   'targets
   (map target->jsexpr
        (sorted-targets (bundle:odra-language-bundle-dependency-targets value)))))

(define (artifact->jsexpr value)
  (hasheq
   'id (symbol-text (bundle:odra-language-bundle-artifact-id value))
   'kind (symbol-text (bundle:odra-language-bundle-artifact-kind value))
   'path (bundle:odra-language-bundle-artifact-path value)
   'digest (bundle:odra-language-bundle-artifact-sha256 value)
   'size (bundle:odra-language-bundle-artifact-size value)
   'targets
   (map target->jsexpr
        (sorted-targets (bundle:odra-language-bundle-artifact-targets value)))
   'authority
   (if (bundle:odra-language-bundle-artifact-authority value)
       (symbol-text (bundle:odra-language-bundle-artifact-authority value))
       'null)))

(define (generic-contribution kind identity languages artifacts dependencies authorities)
  (hasheq 'kind (symbol-text kind)
          'id (symbol-text identity)
          'languages (symbol-list languages)
          'artifacts (symbol-list artifacts)
          'dependencies (symbol-list dependencies)
          'authorities (symbol-list authorities)))

(define (language->contribution value)
  (define identity (language:odra-language-id value))
  (generic-contribution 'language identity (list identity) '() '() '()))

(define (syntax-provider->contribution value)
  (generic-contribution
   'syntax-provider
   (bundle:odra-tree-sitter-syntax-provider-id value)
   (bundle:odra-tree-sitter-syntax-provider-languages value)
   (cons (bundle:odra-tree-sitter-syntax-provider-grammar-artifact value)
         (bundle:odra-tree-sitter-syntax-provider-query-artifacts value))
   '()
   (list (bundle:odra-tree-sitter-syntax-provider-authority value))))

(define (service->contribution value)
  (generic-contribution 'service
                        (language:odra-language-service-id value)
                        (language:odra-language-service-languages value)
                        '() '() '(external-process)))

(define (formatter->contribution value)
  (generic-contribution
   'formatter
   (bundle:odra-language-formatter-id value)
   (bundle:odra-language-formatter-languages value)
   '() '()
   (if (eq? (bundle:odra-language-formatter-kind value) 'command)
       '(external-process)
       '())))

(define (command->contribution value)
  (generic-contribution 'command
                        (bundle:odra-language-command-id value)
                        '() '() '() '()))

(define (keymap->contribution value)
  (generic-contribution 'keymap
                        (bundle:odra-language-keymap-id value)
                        (bundle:odra-language-keymap-languages value)
                        '() '() '()))

(define (contribution-key value)
  (format "~a/~a" (hash-ref value 'kind) (hash-ref value 'id)))

(define (bundle-contributions value)
  (sort
   (append
    (map language->contribution
         (bundle:odra-language-support-bundle-languages value))
    (map syntax-provider->contribution
         (bundle:odra-language-support-bundle-syntax-providers value))
    (map service->contribution
         (bundle:odra-language-support-bundle-services value))
    (map formatter->contribution
         (bundle:odra-language-support-bundle-formatters value))
    (map command->contribution
         (bundle:odra-language-support-bundle-commands value))
    (map keymap->contribution
         (bundle:odra-language-support-bundle-keymaps value)))
   string<? #:key contribution-key))

(define (bundle->jsexpr value)
  (hasheq
   'schema language-bundle-bridge-schema-version
   'format-version (bundle:odra-language-support-bundle-format-version value)
   'id (symbol-text (bundle:odra-language-support-bundle-id value))
   'display-name (bundle:odra-language-support-bundle-display-name value)
   'version (version->jsexpr (bundle:odra-language-support-bundle-version value))
   'api-range
   (hasheq 'minimum
           (version->jsexpr (bundle:odra-language-support-bundle-api-min value))
           'maximum
           (version->jsexpr (bundle:odra-language-support-bundle-api-max value)))
   'description (bundle:odra-language-support-bundle-description value)
   'publisher (symbol-text (bundle:odra-language-support-bundle-publisher value))
   'source (symbol-text (bundle:odra-language-support-bundle-source value))
   'provenance (bundle:odra-language-support-bundle-provenance value)
   'targets
   (map target->jsexpr
        (sorted-targets (bundle:odra-language-support-bundle-targets value)))
   'dependencies
   (map dependency->jsexpr
        (sort (bundle:odra-language-support-bundle-dependencies value)
              symbol<? #:key bundle:odra-language-bundle-dependency-id))
   'authorities
   (map authority->jsexpr
        (sort (bundle:odra-language-support-bundle-authorities value)
              symbol<? #:key bundle:odra-language-bundle-authority-id))
   'contributions (bundle-contributions value)
   'artifacts
   (map artifact->jsexpr
        (sort (bundle:odra-language-support-bundle-artifacts value)
              symbol<? #:key bundle:odra-language-bundle-artifact-id))
   'entrypoint (or (bundle:odra-language-support-bundle-entrypoint value) 'null)))

(define (language-bundle-encode value)
  (define encoded (jsexpr->bytes (bundle->jsexpr value)))
  (when (> (bytes-length encoded) maximum-language-bundle-bytes)
    (raise-arguments-error
     'language-bundle-encode
     "encoded language bundle exceeds the admitted byte boundary"
     "limit" maximum-language-bundle-bytes
     "actual" (bytes-length encoded)))
  (bytes->immutable-bytes encoded))

(define (language-bundle-digest value)
  (bytes->hex-string
   (sha256-bytes (open-input-bytes (language-bundle-encode value)))))

(define (bounded-diagnostic value)
  (define bytes (string->bytes/utf-8 value))
  (bytes->string/utf-8
   (subbytes bytes 0 (min (bytes-length bytes) maximum-load-diagnostic-bytes))
   #\?))

(define (rejected-load generation code detail [limit #f] [actual #f])
  (language-bundle-load-result
   'rejected generation #f #f
   (language-bundle-load-rejection code (bounded-diagnostic detail) limit actual)))

(define (bundle-module-resolver default-resolver)
  (case-lambda
    [(resolved-module-path namespace)
     (default-resolver resolved-module-path namespace)]
    [(module-path relative-to syntax load?)
     (case module-path
       [(odra/language-bundles) bundle-api-module]
       [(odra/languages) language-api-module]
       [else (default-resolver module-path relative-to syntax load?)])]))

(define (evaluate-bundle-module path)
  (define owner-namespace (current-namespace))
  (define namespace (make-base-namespace))
  (namespace-attach-module owner-namespace language-api-module namespace)
  (namespace-attach-module owner-namespace bundle-api-module namespace)
  (define default-resolver (current-module-name-resolver))
  (parameterize ([current-namespace namespace]
                 [current-load-relative-directory (path-only (path->complete-path path))]
                 [current-module-name-resolver
                  (bundle-module-resolver default-resolver)])
    (dynamic-require path 'odra-language-bundle)))

(define (load-language-bundle-module path current-generation proposed-generation)
  (cond
    [(current-language-bundle-load)
     (rejected-load current-generation 'reentrant
                    "recursive language bundle loading is unavailable")]
    [(<= proposed-generation current-generation)
     (rejected-load current-generation 'stale-generation
                    "language bundle generation did not advance"
                    (add1 current-generation) proposed-generation)]
    [else
     (with-handlers
         ([exn:fail:resource?
           (lambda (failure)
             (rejected-load current-generation 'resource-limit
                            (exn-message failure)))]
          [exn:fail:filesystem?
           (lambda (failure)
             (rejected-load current-generation 'unavailable
                            (exn-message failure)))]
          [exn:fail?
           (lambda (failure)
             (rejected-load current-generation 'exception
                            (exn-message failure)))])
       (define bundle
         (call-with-limits
          language-bundle-load-time-limit-seconds
          language-bundle-load-memory-limit-megabytes
          (lambda ()
            (parameterize ([current-language-bundle-load path])
              (evaluate-bundle-module path)))))
       (unless (bundle:language-bundle-value? bundle)
         (raise-arguments-error
          'odra-language-bundle
          "bundle module must export exactly one admitted language bundle value"))
       (define encoded (language-bundle-encode bundle))
       (language-bundle-load-result
        'prepared proposed-generation bundle encoded #f))]))

(module+ test
  (require rackunit)

  (define target '((linux x86-64)))
  (define artifact
    (bundle:language-bundle-artifact
     #:id 'grammar #:kind 'tree-sitter-grammar #:path "lib/example.so"
     #:sha256 (make-string 64 #\a) #:size 1024 #:targets target
     #:authority 'native-grammar))
  (define value
    (bundle:language-support-bundle
     #:id 'org.example.language #:display-name "Example"
     #:version "1.0.0" #:api-min "1.0.0" #:api-max "2.0.0"
     #:description "Example language bundle." #:publisher 'org.example
     #:source 'catalog.example #:targets target
     #:authorities (list (bundle:language-bundle-authority 'native-grammar))
     #:artifacts (list artifact)))
  (define encoded (language-bundle-encode value))
  (check-true (immutable? encoded))
  (check-equal? (hash-ref (bytes->jsexpr encoded) 'schema) 1)
  (check-equal? encoded (language-bundle-encode value))
  (check-equal? (language-bundle-digest value)
                (language-bundle-digest value)))
