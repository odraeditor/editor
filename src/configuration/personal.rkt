#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/port
         racket/runtime-path
         racket/sandbox
         "../command/package-resources.rkt"
         (only-in "../command/api.rkt"
                  command?
                  ksawery-command-family?
                  ksawery-contributor?)
         (only-in "../command/ksawery-extension.rkt"
                  ksawery-contributor-encode)
         (only-in "../command/catalog.rkt"
                  compose-personal-command-catalog)
         (only-in "../command/keymap-model.rkt"
                  odra-interaction-profile?)
         (only-in "../command/keymap-api.rkt"
                  [factory-interaction-profile
                   personal-factory-interaction-profile])
         (only-in "../command/gutter-provider.rkt"
                  odra-gutter-provider?)
         (only-in "../command/completion.rkt"
                  odra-completion-configuration?)
         (only-in "../command/jan.rkt"
                  odra-jan-editing-configuration?)
         (only-in "../command/languages.rkt"
                  odra-language-support-set?)
         (only-in "../command/package-catalogs.rkt"
                  odra-package-catalog-configuration?)
         (only-in "../command/indentation.rkt"
                  odra-indentation-configuration?)
         (only-in "../hosting/language-support-configuration-bridge.rkt"
                  language-support-configuration-encode)
         ;; Instantiate the facade before attaching it to an isolated
         ;; configuration namespace.
         (only-in "../command/terminal.rkt"
                  terminal-context?
                  odra-terminal-configuration?)
         (only-in "../command/recovery.rkt"
                  odra-recovery-policy?)
         "root.rkt")

(provide
 maximum-personal-configuration-bytes
 maximum-personal-diagnostic-bytes
 maximum-personal-generation
 (struct-out odra-personal-config-source)
 (struct-out odra-personal-config-observation)
 (struct-out odra-personal-config-proposal)
 (struct-out odra-personal-config-diagnostic)
 (struct-out odra-personal-config-state)
 (struct-out odra-personal-config-result)
 (contract-out
  [personal-config-source (-> path-string? odra-personal-config-source?)]
  [personal-config-initialize (-> odra-personal-config-state?)]
  [personal-config-load
   (-> odra-personal-config-source? odra-personal-config-observation?)]
  [personal-config-observation-export
   (->* (odra-personal-config-observation? symbol?) (any/c) any/c)]
  [personal-config-proposal-export
   (->* (odra-personal-config-proposal? symbol?) (any/c) any/c)]
  [personal-config-reload
   (-> odra-personal-config-state? exact-positive-integer?
       odra-personal-config-source? odra-personal-config-result?)]))

(define maximum-personal-configuration-bytes (* 8 1024 1024))
(define maximum-personal-diagnostic-bytes 4096)
(define maximum-personal-path-bytes 4096)
(define maximum-personal-generation (sub1 (expt 2 64)))
(define configuration-time-limit-seconds 2)
(define configuration-memory-limit-megabytes 128)
(define module-header #"#lang racket/base\n")
(define module-header-crlf #"#lang racket/base\r\n")
(define admitted-export-names
  '(odra-status-bar-configuration
    odra-gutter-configuration
    odra-gutter-provider
    odra-completion-configuration
    odra-jan-editing-configuration
    odra-language-support
    odra-package-catalogs
    odra-package-resources
    odra-indentation-configuration
    odra-terminal-configuration
    odra-recovery-policy
    odra-personal-commands
    odra-interaction-profile
    odra-ksawery-contributor
    odra-ksawery-command-families))
(define absent-export (gensym 'absent-personal-export))
(define-runtime-module-path personal-command-api-module
  "../command/api.rkt")
(define-runtime-module-path personal-keymap-api-module
  "../command/keymap-api.rkt")
(define-runtime-module-path personal-gutter-api-module
  "../command/gutter-provider.rkt")
(define-runtime-module-path personal-completion-api-module
  "../command/completion.rkt")
(define-runtime-module-path personal-jan-api-module
  "../command/jan.rkt")
(define-runtime-module-path personal-language-api-module
  "../command/languages.rkt")
(define-runtime-module-path personal-package-catalog-api-module
  "../command/package-catalogs.rkt")
(define-runtime-module-path personal-indentation-api-module
  "../command/indentation.rkt")
(define-runtime-module-path personal-terminal-api-module
  "../command/terminal.rkt")
(define-runtime-module-path personal-recovery-api-module
  "../command/recovery.rkt")

(define (personal-exports? value)
  (and (hash? value)
       (immutable? value)
       (for/and ([name (in-hash-keys value)])
         (memq name admitted-export-names))))

(define (immutable-exports value)
  (make-immutable-hasheq (hash->list value)))

(define allowed-observation-states '(absent confirmed rejected unavailable))
(define allowed-result-status '(confirmed rejected))
(define allowed-diagnostic-codes
  '(io size invalid-language invalid-syntax evaluation-limit exception
       stale-generation generation-limit))

(define (bounded-string? value maximum #:empty? [empty? #f])
  (and (string? value)
       (or empty? (positive? (string-length value)))
       (not (string-contains-nul? value))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(define (string-contains-nul? value)
  (for/or ([character (in-string value)]) (char=? character #\nul)))

(define (immutable-text value)
  (string->immutable-string value))

(define (source-text value)
  (immutable-text (path->string value)))

(struct odra-personal-config-source (root path)
  #:transparent
  #:guard
  (lambda (root path _)
    (unless (and (path-string? root)
                 (path-string? path)
                 (bounded-string? (path->string root) maximum-personal-path-bytes)
                 (bounded-string? (path->string path) maximum-personal-path-bytes))
      (raise-arguments-error 'odra-personal-config-source
                             "invalid bounded personal configuration source"))
    (values (source-text root) (source-text path))))

(struct odra-personal-config-observation
  (state source diagnostic module-bytes exports)
  #:transparent
  #:guard
  (lambda (state source diagnostic module-bytes exports _)
    (unless (and (memq state allowed-observation-states)
                 (odra-personal-config-source? source)
                 (or (not diagnostic) (odra-personal-config-diagnostic? diagnostic))
                 (bytes? module-bytes)
                 (<= (bytes-length module-bytes)
                     maximum-personal-configuration-bytes)
                 (personal-exports? exports))
      (raise-arguments-error 'odra-personal-config-observation
                             "invalid personal configuration observation"))
    (values state source diagnostic (bytes->immutable-bytes module-bytes)
            (immutable-exports exports))))

(struct odra-personal-config-proposal (source module-bytes exports)
  #:transparent
  #:guard
  (lambda (source module-bytes exports _)
    (unless (and (or (not source) (odra-personal-config-source? source))
                 (bytes? module-bytes)
                 (<= (bytes-length module-bytes)
                     maximum-personal-configuration-bytes)
                 (personal-exports? exports))
      (raise-arguments-error 'odra-personal-config-proposal
                             "invalid personal configuration proposal"))
    (values source (bytes->immutable-bytes module-bytes)
            (immutable-exports exports))))

(struct odra-personal-config-provenance (source line column position span)
  #:transparent
  #:guard
  (lambda (source line column position span _)
    (unless (and (string? source)
                 (exact-nonnegative-integer? line)
                 (exact-nonnegative-integer? column)
                 (exact-nonnegative-integer? position)
                 (exact-nonnegative-integer? span))
      (raise-arguments-error 'odra-personal-config-provenance
                             "invalid copied source provenance"))
    (values (immutable-text source) line column position span)))

(struct odra-personal-config-diagnostic (code message source provenance limit actual)
  #:transparent
  #:guard
  (lambda (code message source provenance limit actual _)
    (unless (and (memq code allowed-diagnostic-codes)
                 (bounded-string? message maximum-personal-diagnostic-bytes
                                  #:empty? #t)
                 (odra-personal-config-source? source)
                 (odra-personal-config-provenance? provenance)
                 (exact-nonnegative-integer? limit)
                 (exact-nonnegative-integer? actual))
      (raise-arguments-error 'odra-personal-config-diagnostic
                             "invalid bounded personal configuration diagnostic"))
    (values code (immutable-text message) source provenance limit actual)))

(struct odra-personal-config-state
  (confirmed-generation proposal observation rejected-generation diagnostics)
  #:transparent
  #:guard
  (lambda (confirmed-generation proposal observation rejected-generation diagnostics _)
    (unless (and (exact-positive-integer? confirmed-generation)
                 (<= confirmed-generation maximum-personal-generation)
                 (odra-personal-config-proposal? proposal)
                 (or (not observation) (odra-personal-config-observation? observation))
                 (exact-nonnegative-integer? rejected-generation)
                 (<= rejected-generation maximum-personal-generation)
                 (list? diagnostics)
                 (andmap odra-personal-config-diagnostic? diagnostics))
      (raise-arguments-error 'odra-personal-config-state
                             "invalid immutable personal configuration state"))
    (values confirmed-generation proposal observation rejected-generation diagnostics)))

(struct odra-personal-config-result (status state)
  #:transparent
  #:guard
  (lambda (status state _)
    (unless (and (memq status allowed-result-status)
                 (odra-personal-config-state? state))
      (raise-arguments-error 'odra-personal-config-result
                             "invalid personal configuration result"))
    (values status state)))

(define (personal-config-source root)
  (odra-personal-config-source
   root
   (configuration-init-path root)))

;; personal-config-initialize creates the initial empty confirmed generation.
(define (personal-config-initialize)
  (odra-personal-config-state
   1
   (odra-personal-config-proposal #f #"" (hasheq))
   #f
   0
   '()))

;; personal-config-load validates and evaluates one copied init.rkt generation.
(define (personal-config-load source)
  (define path (odra-personal-config-source-path source))
  (cond
    [(not (file-exists? path))
     (odra-personal-config-observation 'absent source #f #"" (hasheq))]
    [else
     (with-handlers
         ([exn:fail:resource?
           (lambda (failure)
             (rejected-observation source 'evaluation-limit (exn-message failure)))]
          [exn:fail:filesystem?
           (lambda (failure)
             (unavailable-observation source (exn-message failure)))]
          [exn:fail?
           (lambda (failure)
             (rejected-observation source 'exception (exn-message failure)))])
       (call-with-limits
        configuration-time-limit-seconds
        configuration-memory-limit-megabytes
        (lambda () (load-existing-source source))))]))

;; personal-config-reload publishes one generation or preserves the last confirmed one.
(define (personal-config-reload current expected-generation source)
  (cond
    [(not (= expected-generation
             (odra-personal-config-state-confirmed-generation current)))
     (rejected-result
      current
      #f
      (config-diagnostic
       source
       'stale-generation
       "Personal configuration generation changed before reload"))]
    [(= expected-generation maximum-personal-generation)
     (rejected-result
      current
      #f
      (config-diagnostic
       source
       'generation-limit
       "Personal configuration generation cannot advance"
       maximum-personal-generation
       expected-generation))]
    [else
     (define observation (personal-config-load source))
     (case (odra-personal-config-observation-state observation)
       [(absent confirmed)
        (odra-personal-config-result
         'confirmed
         (odra-personal-config-state
          (add1 expected-generation)
          (observation->proposal observation)
          observation
          0
          '()))]
       [else
        (rejected-result
         current
         observation
         (odra-personal-config-observation-diagnostic observation))])]))

(define current-personal-configuration-file-size
  (make-parameter file-size))

(define current-personal-configuration-read-file
  (make-parameter
   (lambda (path)
     (call-with-input-file path
       (lambda (input)
         (define copied
           (read-bytes (add1 maximum-personal-configuration-bytes) input))
         (if (eof-object? copied) #"" copied))
       #:mode 'binary))))

(define (load-existing-source source)
  (define path (odra-personal-config-source-path source))
  (define observed-size ((current-personal-configuration-file-size) path))
  (cond
    [(> observed-size maximum-personal-configuration-bytes)
     (rejected-observation
      source
      'size
      "Personal init.rkt exceeds the byte limit"
      maximum-personal-configuration-bytes
      observed-size)]
    [else
     (define module-bytes ((current-personal-configuration-read-file) path))
     (cond
       [(> (bytes-length module-bytes) maximum-personal-configuration-bytes)
        (rejected-observation
         source
         'size
         "Personal init.rkt exceeds the byte limit"
         maximum-personal-configuration-bytes
         (bytes-length module-bytes))]
       [(not (personal-module-language? module-bytes))
        (rejected-observation
         source
         'invalid-language
         "Personal init.rkt must use #lang racket/base")]
       [else
        (define syntax-diagnostic (validate-personal-module source module-bytes))
        (if syntax-diagnostic
            (odra-personal-config-observation
             'rejected source syntax-diagnostic #"" (hasheq))
            (odra-personal-config-observation
             'confirmed source #f module-bytes
             (evaluate-personal-module source module-bytes)))])]))

(define (personal-module-language? module-bytes)
  (or (bytes-prefix? module-bytes module-header)
      (bytes-prefix? module-bytes module-header-crlf)))

(define (validate-personal-module source module-bytes)
  (with-handlers
      ([exn:fail:read?
        (lambda (failure)
          (config-diagnostic source 'invalid-syntax (exn-message failure)))]
       [exn:fail?
        (lambda (failure)
          (config-diagnostic source 'invalid-syntax (exn-message failure)))])
    (define input (open-input-bytes module-bytes))
    (port-count-lines! input)
    (read-line input 'any)
    (parameterize ([read-accept-reader #f]
                   [read-accept-lang #f])
      (let loop ()
        (unless (eof-object? (read-syntax (odra-personal-config-source-path source) input))
          (loop))))
    #f))

;; evaluate-personal-module instantiates one candidate exactly once and copies
;; its admitted exported values into one immutable generation observation.
(define (evaluate-personal-module source module-bytes)
  (define input (open-input-bytes module-bytes))
  (port-count-lines! input)
  (read-line input 'any)
  (define forms
    (parameterize ([read-accept-reader #f]
                   [read-accept-lang #f])
      (let loop ([forms '()])
        (define form (read-syntax (odra-personal-config-source-path source) input))
        (if (eof-object? form)
            (reverse forms)
            (loop (cons form forms))))))
  (define module-name (gensym 'odra-personal-init))
  (define module-form
    (datum->syntax
     #f
     `(module ,module-name racket/base ,@(map syntax->datum forms))
     (and (pair? forms) (car forms))))
  (define owner-namespace (current-namespace))
  (define namespace (make-base-namespace))
  (namespace-attach-module owner-namespace personal-command-api-module namespace)
  (namespace-attach-module owner-namespace personal-keymap-api-module namespace)
  (namespace-attach-module owner-namespace personal-gutter-api-module namespace)
  (namespace-attach-module owner-namespace personal-completion-api-module namespace)
  (namespace-attach-module owner-namespace personal-jan-api-module namespace)
  (namespace-attach-module owner-namespace personal-language-api-module namespace)
  (namespace-attach-module owner-namespace personal-package-catalog-api-module
                           namespace)
  (namespace-attach-module owner-namespace personal-indentation-api-module namespace)
  (namespace-attach-module owner-namespace personal-terminal-api-module namespace)
  (namespace-attach-module owner-namespace personal-recovery-api-module namespace)
  (define default-resolver (current-module-name-resolver))
  (parameterize ([current-namespace namespace]
                 [current-load-relative-directory
                  (odra-personal-config-source-root source)]
                 [current-module-name-resolver
                  (personal-module-name-resolver default-resolver)])
    (eval module-form)
    (define exports
      (for/fold ([exports (hasheq)])
                ([name (in-list admitted-export-names)])
        (define value
          (dynamic-require `(quote ,module-name) name (lambda () absent-export)))
        (if (eq? value absent-export)
            exports
            (hash-set exports name value))))
    (validate-personal-command-export exports)
    (validate-personal-interaction-profile-export exports)
    (validate-personal-gutter-provider-export exports)
    (validate-personal-completion-configuration-export exports)
    (validate-personal-jan-editing-configuration-export exports)
    (validate-personal-language-support-export exports)
    (validate-personal-package-catalog-export exports)
    (unless (package-resources? (hash-ref exports 'odra-package-resources '()))
      (raise-arguments-error 'odra-package-resources
                             "expected at most 32 unique named package resources"))
    (validate-personal-indentation-configuration-export exports)
    (validate-personal-terminal-configuration-export exports)
    (validate-personal-recovery-policy-export exports)
    (validate-personal-ksawery-contributor-export exports)
    (validate-personal-ksawery-command-families-export exports)
    exports))

(define (personal-module-name-resolver default-resolver)
  (case-lambda
    [(resolved-module-path namespace)
     (default-resolver resolved-module-path namespace)]
    [(module-path relative-to syntax load?)
     (case module-path
       [(odra/commands) personal-command-api-module]
       [(odra/keymaps) personal-keymap-api-module]
       [(odra/gutters) personal-gutter-api-module]
       [(odra/completion) personal-completion-api-module]
       [(odra/jan) personal-jan-api-module]
       [(odra/languages) personal-language-api-module]
       [(odra/package-catalogs) personal-package-catalog-api-module]
       [(odra/indentation) personal-indentation-api-module]
       [(odra/terminal) personal-terminal-api-module]
       [(odra/recovery) personal-recovery-api-module]
       [else (default-resolver module-path relative-to syntax load?)])]))

(define (validate-personal-command-export exports)
  (define definitions
    (hash-ref exports 'odra-personal-commands (lambda () '())))
  (unless (immutable-proper-list? definitions)
    (raise-arguments-error
     'odra-personal-commands
     "personal command export must be a proper immutable list"
     "value" definitions))
  (unless (andmap command? definitions)
    (raise-arguments-error
     'odra-personal-commands
     "personal command export contains a non-command value"
     "value" definitions))
  (compose-personal-command-catalog 1 definitions)
  (void))

(define (validate-personal-ksawery-command-families-export exports)
  (define families
    (hash-ref exports 'odra-ksawery-command-families (lambda () '())))
  (unless (and (immutable-proper-list? families)
               (andmap ksawery-command-family? families))
    (raise-arguments-error
     'odra-ksawery-command-families
     "Ksawery command-family export must be an immutable list of admitted families"
     "value" families))
  (when (and (pair? families)
             (not (hash-ref exports 'odra-ksawery-contributor #f)))
    (raise-arguments-error
     'odra-ksawery-command-families
     "Ksawery command families require one exported contributor"))
  (void))

(define (validate-personal-interaction-profile-export exports)
  (define profile
    (hash-ref exports 'odra-interaction-profile (lambda () #f)))
  (unless (or (not profile) (odra-interaction-profile? profile))
    (raise-arguments-error
     'odra-interaction-profile
     "personal interaction profile export must be an interaction profile"
     "value" profile))
  (void))

(define (validate-personal-gutter-provider-export exports)
  (define provider
    (hash-ref exports 'odra-gutter-provider (lambda () #f)))
  (unless (or (not provider) (odra-gutter-provider? provider))
    (raise-arguments-error
     'odra-gutter-provider
     "personal Gutter provider export must be one admitted provider"
     "value" provider))
  (void))

(define (validate-personal-completion-configuration-export exports)
  (define configuration
    (hash-ref exports 'odra-completion-configuration (lambda () #f)))
  (unless (or (not configuration)
              (odra-completion-configuration? configuration))
    (raise-arguments-error
     'odra-completion-configuration
     "personal completion configuration export must be one admitted configuration"
     "value" configuration))
  (void))

(define (validate-personal-jan-editing-configuration-export exports)
  (define configuration
    (hash-ref exports 'odra-jan-editing-configuration (lambda () #f)))
  (unless (or (not configuration)
              (odra-jan-editing-configuration? configuration))
    (raise-arguments-error
     'odra-jan-editing-configuration
     "personal Jan editing configuration export must be one admitted configuration"
     "value" configuration))
  (void))

(define (validate-personal-language-support-export exports)
  (define support
    (hash-ref exports 'odra-language-support (lambda () #f)))
  (unless (or (not support) (odra-language-support-set? support))
    (raise-arguments-error
     'odra-language-support
     "personal language support export must be one admitted language-support set"))
  (when support
    (language-support-configuration-encode support))
  (void))

(define (validate-personal-package-catalog-export exports)
  (define configuration
    (hash-ref exports 'odra-package-catalogs (lambda () #f)))
  (unless (or (not configuration)
              (odra-package-catalog-configuration? configuration))
    (raise-arguments-error
     'odra-package-catalogs
     "personal package catalog export must be one admitted configuration"
     "value" configuration))
  (void))

(define (validate-personal-indentation-configuration-export exports)
  (define configuration
    (hash-ref exports 'odra-indentation-configuration (lambda () #f)))
  (unless (or (not configuration)
              (odra-indentation-configuration? configuration))
    (raise-arguments-error
     'odra-indentation-configuration
     "personal indentation export must be one admitted configuration"
     "value" configuration))
  (void))

(define (validate-personal-terminal-configuration-export exports)
  (define configuration
    (hash-ref exports 'odra-terminal-configuration (lambda () #f)))
  (unless (or (not configuration)
              (odra-terminal-configuration? configuration))
    (raise-arguments-error
     'odra-terminal-configuration
     "personal terminal configuration export must be one admitted configuration"
     "value" configuration))
  (void))

(define (validate-personal-recovery-policy-export exports)
  (define policy
    (hash-ref exports 'odra-recovery-policy (lambda () #f)))
  (unless (or (not policy) (odra-recovery-policy? policy))
    (raise-arguments-error
     'odra-recovery-policy
     "personal recovery policy export must be one admitted policy"
     "value" policy))
  (void))

(define (validate-personal-ksawery-contributor-export exports)
  (define contributor
    (hash-ref exports 'odra-ksawery-contributor (lambda () #f)))
  (unless (or (not contributor) (ksawery-contributor? contributor))
    (raise-arguments-error
     'odra-ksawery-contributor
     "personal Ksawery contributor export must be one admitted contributor"
     "value" contributor))
  (when contributor
    (ksawery-contributor-encode contributor 1))
  (void))

(define (immutable-proper-list? value)
  (list? value))

(define (personal-config-observation-export observation name [default #f])
  (personal-export-ref
   'personal-config-observation-export
   (odra-personal-config-observation-exports observation)
   name
   default))

(define (personal-config-proposal-export proposal name [default #f])
  (personal-export-ref
   'personal-config-proposal-export
   (odra-personal-config-proposal-exports proposal)
   name
   default))

(define (personal-export-ref who exports name default)
  (unless (memq name admitted-export-names)
    (raise-argument-error who "an admitted personal configuration export name" name))
  (hash-ref exports name (lambda () default)))

(define (observation->proposal observation)
  (if (eq? (odra-personal-config-observation-state observation) 'confirmed)
      (odra-personal-config-proposal
       (odra-personal-config-observation-source observation)
       (odra-personal-config-observation-module-bytes observation)
       (odra-personal-config-observation-exports observation))
      (odra-personal-config-proposal #f #"" (hasheq))))

(define (rejected-result current observation diagnostic)
  (odra-personal-config-result
   'rejected
   (odra-personal-config-state
    (odra-personal-config-state-confirmed-generation current)
    (odra-personal-config-state-proposal current)
    observation
    (add1 (odra-personal-config-state-rejected-generation current))
    (list diagnostic))))

(define (unavailable-observation source message)
  (odra-personal-config-observation
   'unavailable source (config-diagnostic source 'io message) #"" (hasheq)))

(define (rejected-observation source code message [limit 0] [actual 0])
  (odra-personal-config-observation
   'rejected source (config-diagnostic source code message limit actual)
   #"" (hasheq)))

(define (config-diagnostic source code message [limit 0] [actual 0])
  (odra-personal-config-diagnostic
   code
   (bounded-diagnostic-message message)
   source
   (base-provenance source)
   limit
   actual))

(define (base-provenance source)
  (odra-personal-config-provenance
   (odra-personal-config-source-path source) 0 0 0 0))

(define (bounded-diagnostic-message message)
  (if (> (bytes-length (string->bytes/utf-8 message))
         maximum-personal-diagnostic-bytes)
      "Personal configuration failure exceeds the diagnostic byte limit"
      message))

(define (bytes-prefix? value prefix)
  (and (>= (bytes-length value) (bytes-length prefix))
       (bytes=? (subbytes value 0 (bytes-length prefix)) prefix)))

(module+ test-support
  (provide current-personal-configuration-file-size
           current-personal-configuration-read-file))
