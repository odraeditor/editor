#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         "../command/native-contracts.rkt"
         (prefix-in cap: "scoped-capability.rkt"))

(provide
 (struct-out theme-color)
 (struct-out theme-style)
 (struct-out theme-provider-handle)
 (struct-out theme-definition-handle)
 (struct-out theme-scope)
 (struct-out theme-usage)
 (struct-out theme-limits)
 (struct-out theme-provider)
 (struct-out theme-definition)
 (struct-out theme-diagnostic)
 (struct-out theme-snapshot)
 (struct-out theme-proposal)
 (struct-out theme-outcome)
 (struct-out theme-failure)
 (contract-out
  [theme-control? (-> any/c boolean?)]
  [call-with-theme-control
   (-> exact-positive-integer? exact-positive-integer?
       (-> theme-control? any/c) any/c)]
  [theme-current-scope
   (-> theme-control? (or/c theme-scope? theme-failure?))]
  [theme-inspect
   (-> theme-control? (or/c theme-snapshot? theme-failure?))]
  [theme-inspect-definition
   (-> theme-control? theme-definition-handle?
       (or/c theme-snapshot? theme-failure?))]
  [theme-propose
   (-> theme-control? theme-proposal? (or/c theme-outcome? theme-failure?))]
  [theme-confirm
   (-> theme-control? theme-definition-handle?
       (or/c theme-outcome? theme-failure?))]
  [theme-select
   (-> theme-control? theme-definition-handle?
       (or/c theme-outcome? theme-failure?))]
  [theme-replace
   (-> theme-control? theme-definition-handle? theme-proposal?
       (or/c theme-outcome? theme-failure?))]
  [theme-restore
   (-> theme-control? (or/c theme-outcome? theme-failure?))]
  [theme-select-baseline
   (-> theme-control? (or/c theme-outcome? theme-failure?))]
  [theme-teardown
   (-> theme-control? theme-provider-handle?
       (or/c theme-outcome? theme-failure?))]
  [theme-failure-diagnostic (-> theme-failure? string?)]
  [theme-control-invoke
   (-> theme-control? exact-integer? exact-nonnegative-integer?
       exact-nonnegative-integer? bytes? exact-nonnegative-integer?
       cap:scoped-capability-result?)]
  [native-theme-turn
   (-> exact-positive-integer? exact-positive-integer? list?)]))

(define (contract item) (native-contract-value 'theme item))
(define scope-record-bytes (contract 'scope-record-bytes))
(define usage-record-bytes (contract 'usage-record-bytes))
(define limits-record-bytes (contract 'limits-record-bytes))
(define snapshot-header-bytes (contract 'snapshot-header-bytes))
(define provider-record-bytes (contract 'provider-record-bytes))
(define definition-record-bytes (contract 'definition-record-bytes))
(define style-record-bytes (contract 'style-record-bytes))
(define proposal-header-bytes (contract 'proposal-header-bytes))
(define outcome-record-bytes (contract 'outcome-record-bytes))
(define diagnostic-record-bytes (contract 'diagnostic-record-bytes))
(define maximum-styles (contract 'maximum-styles))
(define maximum-proposal-bytes (contract 'maximum-proposal-bytes))
(define maximum-proposal-text-bytes (contract 'maximum-proposal-text-bytes))
(define maximum-inspection-bytes (contract 'maximum-inspection-bytes))
(define maximum-diagnostic-bytes (contract 'maximum-diagnostic-bytes))
(define maximum-inspection-diagnostics (contract 'maximum-inspection-diagnostics))
(define current-style-role-count (contract 'current-style-role-count))

(define operation-scope (contract 'operation-scope))
(define operation-inspect (contract 'operation-inspect))
(define operation-inspect-definition (contract 'operation-inspect-definition))
(define operation-propose (contract 'operation-propose))
(define operation-confirm (contract 'operation-confirm))
(define operation-select (contract 'operation-select))
(define operation-replace (contract 'operation-replace))
(define operation-restore (contract 'operation-restore))
(define operation-select-baseline (contract 'operation-select-baseline))
(define operation-teardown (contract 'operation-teardown))

(define role-codes
  (hasheq
   'text-normal (contract 'role-text-normal)
   'text-region (contract 'role-text-region)
   'text-search-current (contract 'role-text-search-current)
   'list-normal (contract 'role-list-normal)
   'list-current (contract 'role-list-current)
   'list-mark-save (contract 'role-list-mark-save)
   'list-mark-kill (contract 'role-list-mark-kill)
   'status-normal (contract 'role-status-normal)
   'status-active (contract 'role-status-active)
   'diagnostic-normal (contract 'role-diagnostic-normal)
   'diagnostic-rejected (contract 'role-diagnostic-rejected)
   'syntax-attribute (contract 'role-syntax-attribute)
   'syntax-boolean (contract 'role-syntax-boolean)
   'syntax-comment (contract 'role-syntax-comment)
   'syntax-constant (contract 'role-syntax-constant)
   'syntax-constructor (contract 'role-syntax-constructor)
   'syntax-function (contract 'role-syntax-function)
   'syntax-function-builtin (contract 'role-syntax-function-builtin)
   'syntax-keyword (contract 'role-syntax-keyword)
   'syntax-label (contract 'role-syntax-label)
   'syntax-number (contract 'role-syntax-number)
   'syntax-operator (contract 'role-syntax-operator)
   'syntax-punctuation (contract 'role-syntax-punctuation)
   'syntax-string (contract 'role-syntax-string)
   'syntax-type (contract 'role-syntax-type)
   'syntax-variable (contract 'role-syntax-variable)
   'syntax-variable-parameter (contract 'role-syntax-variable-parameter)
   'diagnostic-error (contract 'role-diagnostic-error)
   'diagnostic-warning (contract 'role-diagnostic-warning)
   'diagnostic-information (contract 'role-diagnostic-information)
   'diagnostic-hint (contract 'role-diagnostic-hint)
   'list-emphasis (contract 'role-list-emphasis)
   'filesystem-directory (contract 'role-filesystem-directory)
   'filesystem-permission-read (contract 'role-filesystem-permission-read)
   'filesystem-permission-write (contract 'role-filesystem-permission-write)
   'filesystem-permission-execute (contract 'role-filesystem-permission-execute)
   'filesystem-metadata (contract 'role-filesystem-metadata)
   'status-safety (contract 'role-status-safety)
   'status-identity (contract 'role-status-identity)
   'status-position (contract 'role-status-position)
   'status-alert (contract 'role-status-alert)
   'status-workspace (contract 'role-status-workspace)
   'status-project (contract 'role-status-project)
   'status-editing-context (contract 'role-status-editing-context)
   'tree-project (contract 'role-tree-project)
   'tree-directory (contract 'role-tree-directory)
   'tree-directory-special (contract 'role-tree-directory-special)
   'tree-file (contract 'role-tree-file)
   'tree-file-source (contract 'role-tree-file-source)
   'tree-file-documentation (contract 'role-tree-file-documentation)
   'tree-file-configuration (contract 'role-tree-file-configuration)
   'tree-file-version-control (contract 'role-tree-file-version-control)
   'tree-hierarchy (contract 'role-tree-hierarchy)
   'tree-inactive (contract 'role-tree-inactive)
   'tree-loading (contract 'role-tree-loading)
   'tree-failure (contract 'role-tree-failure)
   'tree-destructive (contract 'role-tree-destructive)
   'gutter-background (contract 'role-gutter-background)
   'gutter-line-number (contract 'role-gutter-line-number)
   'gutter-line-number-current (contract 'role-gutter-line-number-current)
   'gutter-separator (contract 'role-gutter-separator)
   'popup-background (contract 'role-popup-background)
   'popup-content (contract 'role-popup-content)
   'popup-border (contract 'role-popup-border)
   'popup-diagnostic (contract 'role-popup-diagnostic)
   'popup-unavailable (contract 'role-popup-unavailable)))
(define role-symbols
  (for/hasheq ([(name code) (in-hash role-codes)]) (values code name)))
(define attribute-bits
  (hasheq 'bold (contract 'attribute-bold)
          'dim (contract 'attribute-dim)
          'underline (contract 'attribute-underline)
          'reverse (contract 'attribute-reverse)))
(define known-attribute-mask
  (for/fold ([mask 0]) ([bit (in-hash-values attribute-bits)])
    (bitwise-ior mask bit)))

(define provider-kind-symbols
  (hash (contract 'provider-kind-invalid) 'invalid
        (contract 'provider-kind-factory) 'factory
        (contract 'provider-kind-racket) 'racket))
(define provider-state-symbols
  (hash (contract 'provider-state-invalid) 'invalid
        (contract 'provider-state-confirmed) 'confirmed
        (contract 'provider-state-failed) 'failed
        (contract 'provider-state-closed) 'closed))
(define definition-state-symbols
  (hash (contract 'definition-state-invalid) 'invalid
        (contract 'definition-state-proposed) 'proposed
        (contract 'definition-state-confirmed) 'confirmed
        (contract 'definition-state-failed) 'failed
        (contract 'definition-state-closed) 'closed))

(define failure-diagnostics
  (hash
   (contract 'failure-none) ""
   (contract 'failure-invalid-registry) "theme registry is invalid"
   (contract 'failure-closed-registry) "theme registry is closed"
   (contract 'failure-wrong-registry) "theme handle belongs to another registry"
   (contract 'failure-invalid-provider) "theme provider is invalid"
   (contract 'failure-stale-provider) "theme provider generation is stale"
   (contract 'failure-duplicate-provider) "theme provider already exists"
   (contract 'failure-provider-limit) "theme provider limit exceeded"
   (contract 'failure-provider-name-limit) "theme provider name is invalid or too large"
   (contract 'failure-provider-not-confirmed) "theme provider is not confirmed"
   (contract 'failure-factory-provider-required) "maintained factory provider is required"
   (contract 'failure-invalid-definition) "theme definition is invalid"
   (contract 'failure-stale-definition) "theme definition generation is stale"
   (contract 'failure-duplicate-definition) "theme identity already exists"
   (contract 'failure-definition-limit) "theme definition limit exceeded"
   (contract 'failure-definition-not-proposed) "theme definition is not proposed"
   (contract 'failure-definition-not-confirmed) "theme definition is not confirmed"
   (contract 'failure-factory-definition-immutable) "factory theme definition is immutable"
   (contract 'failure-invalid-identity) "theme identity is invalid"
   (contract 'failure-identity-limit) "theme identity is too large"
   (contract 'failure-display-name-limit) "theme display name is invalid or too large"
   (contract 'failure-provenance-limit) "theme provenance is invalid or too large"
   (contract 'failure-invalid-style) "theme style is invalid"
   (contract 'failure-unknown-style-role) "theme style role is unknown"
   (contract 'failure-duplicate-style-role) "theme style role is duplicated"
   (contract 'failure-incomplete-style-roles) "theme style mapping is incomplete"
   (contract 'failure-monochrome-indistinguishable) "theme loses required monochrome distinctions"
   (contract 'failure-stale-registry) "theme registry generation is stale"
   (contract 'failure-stale-selection) "theme selection generation is stale"
   (contract 'failure-retained-definition-limit) "retained theme definition limit exceeded"
   (contract 'failure-proposal-limit) "theme proposal limit exceeded"
   (contract 'failure-operation-limit) "theme operation limit exceeded"
   (contract 'failure-inspection-limit) "theme inspection limit exceeded"
   (contract 'failure-preparation-limit) "theme preparation limit exceeded"
   (contract 'failure-diagnostic-limit) "theme diagnostic limit exceeded"
   (contract 'failure-generation-limit) "theme generation is exhausted"
   (contract 'failure-allocation) "theme allocation failed"
   (contract 'failure-busy) "theme registry is busy"))

(struct theme-control (capability [scope #:mutable]))
(struct theme-color (red green blue) #:transparent)
(struct theme-style (role foreground background attributes) #:transparent)
(struct theme-provider-handle (provider-id provider-generation) #:transparent)
(struct theme-definition-handle
  (provider-id provider-generation definition-id definition-generation)
  #:transparent)
(struct theme-scope
  (schema-version access registry-id registry-generation selection-generation
                  active fallback baseline capability-generation)
  #:transparent)
(struct theme-usage
  (providers definitions retained-definition-bytes inspection-bytes
             preparation-peak-bytes operations-in-turn hosted-turns)
  #:transparent)
(struct theme-limits
  (providers definitions theme-identity-bytes display-name-bytes
             provider-name-bytes provenance-bytes styles
             retained-definition-bytes proposal-bytes operations-per-turn
             inspection-bytes preparation-bytes diagnostic-bytes
             concurrent-hosted-turns)
  #:transparent)
(struct theme-provider
  (descriptor kind state name first-definition definition-count)
  #:transparent)
(struct theme-definition
  (descriptor state identity display-name provenance first-style style-count retained-bytes)
  #:transparent)
(struct theme-diagnostic
  (operation code provider definition expected-generation actual-generation
             limit actual message)
  #:transparent)
(struct theme-snapshot
  (scope usage limits providers definitions styles diagnostic)
  #:transparent)
(struct theme-proposal
  (identity display-name provider-name provenance styles)
  #:transparent)
(struct theme-outcome
  (scope operation completion changed? previous definition fallback-selected?
         baseline-selected? retained-bytes operation-count)
  #:transparent)
(struct theme-failure (code limit actual) #:transparent)

;; call-with-theme-control confines one opaque theme capability to one Racket turn.
(define (call-with-theme-control generation token command)
  (cap:call-with-scoped-capability
   'theme generation token
   (lambda (capability) (command (theme-control capability #f)))))

;; theme-control-invoke applies copied byte bounds before entering native code.
(define (theme-control-invoke control operation arg0 arg1 input output-capacity)
  (when (> (bytes-length input) maximum-proposal-bytes)
    (raise-arguments-error
     'theme-control-invoke "theme input exceeds the copied proposal limit"
     "limit" maximum-proposal-bytes "actual" (bytes-length input)))
  (when (> output-capacity maximum-inspection-bytes)
    (raise-arguments-error
     'theme-control-invoke "theme output exceeds the copied inspection limit"
     "limit" maximum-inspection-bytes "actual" output-capacity))
  (cap:scoped-capability-invoke
   (theme-control-capability control)
   operation arg0 arg1 input output-capacity))

;; theme-current-scope obtains one exact registry and selection snapshot.
(define (theme-current-scope control)
  (define result
    (theme-native-invoke control operation-scope 0 0 #"" scope-record-bytes))
  (if (theme-failure? result)
      result
      (let ([scope (decode-scope result 0)])
        (set-theme-control-scope! control scope)
        scope)))

(define (current-or-fetch-scope control)
  (or (theme-control-scope control) (theme-current-scope control)))

;; theme-inspect returns one immutable complete copied registry snapshot.
(define (theme-inspect control)
  (define scope (current-or-fetch-scope control))
  (if (theme-failure? scope)
      scope
      (let ([result
             (theme-native-invoke
              control operation-inspect 0 0
              (encode-scope scope) maximum-inspection-bytes)])
        (if (theme-failure? result) result (decode-snapshot result)))))

;; theme-inspect-definition returns one copied definition and its complete styles.
(define (theme-inspect-definition control handle)
  (define result
    (invoke-with-request
     control operation-inspect-definition handle #f maximum-inspection-bytes))
  (if (theme-failure? result) result (decode-snapshot result)))

;; theme-propose copies one complete inactive Racket definition.
(define (theme-propose control proposal)
  (decode-outcome-result
   control (invoke-with-request control operation-propose #f proposal outcome-record-bytes)))

;; theme-confirm confirms one exact proposed definition generation.
(define (theme-confirm control handle)
  (decode-outcome-result
   control (invoke-with-request control operation-confirm handle #f outcome-record-bytes)))

;; theme-select selects one exact confirmed definition generation.
(define (theme-select control handle)
  (decode-outcome-result
   control (invoke-with-request control operation-select handle #f outcome-record-bytes)))

;; theme-replace publishes and selects one new immutable definition generation.
(define (theme-replace control expected proposal)
  (decode-outcome-result
   control
   (invoke-with-request control operation-replace expected proposal outcome-record-bytes)))

;; theme-restore selects the maintained factory fallback.
(define (theme-restore control)
  (decode-outcome-result
   control (invoke-with-request control operation-restore #f #f outcome-record-bytes)))

;; theme-select-baseline selects the color-minimal safe definition.
(define (theme-select-baseline control)
  (decode-outcome-result
   control
   (invoke-with-request control operation-select-baseline #f #f outcome-record-bytes)))

;; theme-teardown closes one exact Racket provider generation.
(define (theme-teardown control provider)
  (decode-outcome-result
   control (invoke-with-request control operation-teardown provider #f outcome-record-bytes)))

;; theme-failure-diagnostic returns the schema-checked native failure meaning.
(define (theme-failure-diagnostic failure)
  (hash-ref failure-diagnostics (theme-failure-code failure)
            (lambda ()
              (format "unknown theme failure ~a" (theme-failure-code failure)))))

(define (invoke-with-request control operation expected proposal output-capacity)
  (define scope (current-or-fetch-scope control))
  (if (theme-failure? scope)
      scope
      (let ([request (encode-request scope operation expected proposal)])
        (theme-native-invoke control operation 0 0 request output-capacity))))

(define (decode-outcome-result control result)
  (if (theme-failure? result)
      result
      (let ([outcome (decode-outcome result)])
        (set-theme-control-scope! control (theme-outcome-scope outcome))
        outcome)))

(define (theme-native-invoke control operation arg0 arg1 input output-capacity)
  (define result
    (theme-control-invoke control operation arg0 arg1 input output-capacity))
  (case (cap:scoped-capability-result-status result)
    [(0) (cap:scoped-capability-result-output result)]
    [(1)
     (theme-failure
      (cap:scoped-capability-result-failure-code result)
      (cap:scoped-capability-result-limit result)
      (cap:scoped-capability-result-actual result))]
    [else (error 'theme-native-invoke "native theme adapter rejected the call")]))

(define (encode-request scope operation expected proposal)
  (define expected-provider
    (cond
      [(theme-definition-handle? expected)
       (theme-provider-handle
        (theme-definition-handle-provider-id expected)
        (theme-definition-handle-provider-generation expected))]
      [(theme-provider-handle? expected) expected]
      [else (theme-provider-handle 0 0)]))
  (define expected-definition-id
    (if (theme-definition-handle? expected)
        (theme-definition-handle-definition-id expected) 0))
  (define expected-definition-generation
    (if (theme-definition-handle? expected)
        (theme-definition-handle-definition-generation expected) 0))
  (define styles (if proposal (theme-proposal-styles proposal) '()))
  (unless (and (list? styles) (<= (length styles) maximum-styles))
    (raise-argument-error 'theme-proposal "a bounded list of theme styles" styles))
  (define text-parts
    (if proposal
        (map string->bytes/utf-8
             (list (theme-proposal-identity proposal)
                   (theme-proposal-display-name proposal)
                   (theme-proposal-provider-name proposal)
                   (theme-proposal-provenance proposal)))
        (list #"" #"" #"" #"")))
  (define text-bytes (for/sum ([part (in-list text-parts)]) (bytes-length part)))
  (when (> text-bytes maximum-proposal-text-bytes)
    (raise-arguments-error
     'theme-proposal "theme proposal text exceeds the copied limit"
     "limit" maximum-proposal-text-bytes "actual" text-bytes))
  (define total
    (+ proposal-header-bytes (* (length styles) style-record-bytes) text-bytes))
  (when (> total maximum-proposal-bytes)
    (raise-arguments-error
     'theme-proposal "theme proposal exceeds the copied limit"
     "limit" maximum-proposal-bytes "actual" total))
  (define output (make-bytes total))
  (bytes-copy! output 0 (encode-scope scope))
  (define text-cursor (+ proposal-header-bytes (* (length styles) style-record-bytes)))
  (define ranges
    (for/list ([part (in-list text-parts)])
      (define result (list text-cursor (bytes-length part)))
      (set! text-cursor (+ text-cursor (bytes-length part)))
      result))
  (define header-values
    (append
     (list operation
           (theme-provider-handle-provider-id expected-provider)
           (theme-provider-handle-provider-generation expected-provider)
           expected-definition-id expected-definition-generation)
     (append* ranges)
     (list (length styles) text-bytes)))
  (for ([value (in-list header-values)]
        [offset (in-range scope-record-bytes proposal-header-bytes 8)])
    (write-u64! output offset value))
  (for ([style (in-list styles)] [index (in-naturals)])
    (encode-style! output (+ proposal-header-bytes (* index style-record-bytes)) style))
  (define cursor (+ proposal-header-bytes (* (length styles) style-record-bytes)))
  (for ([part (in-list text-parts)])
    (bytes-copy! output cursor part)
    (set! cursor (+ cursor (bytes-length part))))
  output)

(define (encode-style! output offset style)
  (unless (theme-style? style)
    (raise-argument-error 'theme-proposal "a theme-style value" style))
  (define foreground (theme-style-foreground style))
  (define background (theme-style-background style))
  (define values
    (list (role->code (theme-style-role style))
          (if foreground 1 0)
          (if foreground (theme-color-red foreground) 0)
          (if foreground (theme-color-green foreground) 0)
          (if foreground (theme-color-blue foreground) 0)
          (if background 1 0)
          (if background (theme-color-red background) 0)
          (if background (theme-color-green background) 0)
          (if background (theme-color-blue background) 0)
          (attributes->mask (theme-style-attributes style))))
  (for ([value (in-list values)] [field (in-naturals)])
    (unless (exact-u8? value)
      (raise-argument-error 'theme-style "an eight-bit color channel" value))
    (write-u64! output (+ offset (* field 8)) value)))

(define (encode-scope scope)
  (define output (make-bytes scope-record-bytes))
  (define values
    (append
     (list (theme-scope-schema-version scope)
           (theme-scope-access scope)
           (theme-scope-registry-id scope)
           (theme-scope-registry-generation scope)
           (theme-scope-selection-generation scope))
     (definition-handle-values (theme-scope-active scope))
     (definition-handle-values (theme-scope-fallback scope))
     (definition-handle-values (theme-scope-baseline scope))
     (list (theme-scope-capability-generation scope))))
  (for ([value (in-list values)] [offset (in-range 0 scope-record-bytes 8)])
    (write-u64! output offset value))
  output)

(define (decode-scope input [offset 0])
  (require-record-bytes 'theme-scope input offset scope-record-bytes)
  (theme-scope
   (read-u64 input offset)
   (read-u64 input (+ offset 8))
   (read-u64 input (+ offset 16))
   (read-u64 input (+ offset 24))
   (read-u64 input (+ offset 32))
   (decode-definition-handle input (+ offset 40))
   (decode-definition-handle input (+ offset 72))
   (decode-definition-handle input (+ offset 104))
   (read-u64 input (+ offset 136))))

(define (decode-outcome input)
  (unless (= (bytes-length input) outcome-record-bytes)
    (error 'theme-outcome "native theme outcome has an invalid width"))
  (define scope (decode-scope input 0))
  (define values
    (for/list ([offset (in-range scope-record-bytes outcome-record-bytes 8)])
      (read-u64 input offset)))
  (theme-outcome
   scope
   (list-ref values 0)
   (list-ref values 1)
   (code->boolean 'theme-outcome (list-ref values 2))
   (definition-handle-or-false values 3)
   (definition-handle-or-false values 7)
   (code->boolean 'theme-outcome (list-ref values 11))
   (code->boolean 'theme-outcome (list-ref values 12))
   (list-ref values 13)
   (list-ref values 14)))

(define (decode-snapshot input)
  (when (< (bytes-length input) snapshot-header-bytes)
    (error 'theme-snapshot "native theme snapshot is truncated"))
  (define scope (decode-scope input 0))
  (define usage-offset scope-record-bytes)
  (define usage-values
    (for/list ([offset (in-range usage-offset
                                 (+ usage-offset usage-record-bytes) 8)])
      (read-u64 input offset)))
  (define limits-offset (+ usage-offset usage-record-bytes))
  (define limit-values
    (for/list ([offset (in-range limits-offset
                                 (+ limits-offset limits-record-bytes) 8)])
      (read-u64 input offset)))
  (define counts-offset (+ limits-offset limits-record-bytes))
  (define counts
    (for/list ([offset (in-range counts-offset snapshot-header-bytes 8)])
      (read-u64 input offset)))
  (define provider-count (list-ref counts 0))
  (define definition-count (list-ref counts 1))
  (define style-count (list-ref counts 2))
  (define diagnostic-count (list-ref counts 3))
  (define text-bytes (list-ref counts 4))
  (define diagnostic-bytes (list-ref counts 5))
  (unless (and (<= diagnostic-count maximum-inspection-diagnostics)
               (<= diagnostic-bytes maximum-diagnostic-bytes))
    (error 'theme-snapshot "native theme snapshot exceeds copied quotas"))
  (define provider-offset snapshot-header-bytes)
  (define definition-offset
    (+ provider-offset (* provider-count provider-record-bytes)))
  (define style-offset
    (+ definition-offset (* definition-count definition-record-bytes)))
  (define diagnostic-offset
    (+ style-offset (* style-count style-record-bytes)))
  (define text-offset
    (+ diagnostic-offset (* diagnostic-count diagnostic-record-bytes)))
  (define diagnostic-text-offset (+ text-offset text-bytes))
  (define expected (+ diagnostic-text-offset diagnostic-bytes))
  (unless (and (= expected (bytes-length input))
               (<= expected maximum-inspection-bytes))
    (error 'theme-snapshot "native theme snapshot has an invalid width"))
  (define providers
    (for/list ([index (in-range provider-count)])
      (decode-provider
       input (+ provider-offset (* index provider-record-bytes))
       text-offset diagnostic-text-offset)))
  (define definitions
    (for/list ([index (in-range definition-count)])
      (decode-definition
       input (+ definition-offset (* index definition-record-bytes))
       text-offset diagnostic-text-offset)))
  (define styles
    (for/list ([index (in-range style-count)])
      (decode-style input (+ style-offset (* index style-record-bytes)))))
  (for ([definition (in-list definitions)])
    (unless (record-range-valid?
             (theme-definition-first-style definition)
             (theme-definition-style-count definition)
             style-count)
      (error 'theme-snapshot "definition style range is invalid")))
  (theme-snapshot
   scope
   (apply theme-usage usage-values)
   (apply theme-limits limit-values)
   providers definitions styles
   (and (= diagnostic-count 1)
        (decode-diagnostic
         input diagnostic-offset diagnostic-text-offset expected))))

(define (decode-provider input offset text-start text-end)
  (define values (read-record-values input offset provider-record-bytes))
  (theme-provider
   (theme-provider-handle (list-ref values 0) (list-ref values 1))
   (code->symbol 'theme-provider provider-kind-symbols (list-ref values 2))
   (code->symbol 'theme-provider provider-state-symbols (list-ref values 3))
   (decode-text input (list-ref values 4) (list-ref values 5) text-start text-end)
   (list-ref values 6)
   (list-ref values 7)))

(define (decode-definition input offset text-start text-end)
  (define values (read-record-values input offset definition-record-bytes))
  (theme-definition
   (theme-definition-handle
    (list-ref values 0) (list-ref values 1)
    (list-ref values 2) (list-ref values 3))
   (code->symbol 'theme-definition definition-state-symbols (list-ref values 4))
   (decode-text input (list-ref values 5) (list-ref values 6) text-start text-end)
   (decode-text input (list-ref values 7) (list-ref values 8) text-start text-end)
   (decode-text input (list-ref values 9) (list-ref values 10) text-start text-end)
   (list-ref values 11)
   (list-ref values 12)
   (list-ref values 13)))

(define (decode-style input offset)
  (define values (read-record-values input offset style-record-bytes))
  (theme-style
   (code->symbol 'theme-style role-symbols (list-ref values 0))
   (decode-color 'theme-style (drop values 1))
   (decode-color 'theme-style (drop values 5))
   (mask->attributes (list-ref values 9))))

(define (decode-diagnostic input offset text-start text-end)
  (define values (read-record-values input offset diagnostic-record-bytes))
  (theme-diagnostic
   (list-ref values 0)
   (list-ref values 1)
   (theme-provider-handle (list-ref values 2) (list-ref values 3))
   (theme-definition-handle
    (list-ref values 2) (list-ref values 3)
    (list-ref values 4) (list-ref values 5))
   (list-ref values 6)
   (list-ref values 7)
   (list-ref values 8)
   (list-ref values 9)
   (decode-text input (list-ref values 10) (list-ref values 11) text-start text-end)))

(define (decode-color who values)
  (case (car values)
    [(0) #f]
    [(1)
     (for ([channel (in-list (take (cdr values) 3))])
       (unless (exact-u8? channel)
         (error who "native theme color channel is invalid")))
     (apply theme-color (take (cdr values) 3))]
    [else (error who "native optional-color presence is invalid")]))

(define (role->code role)
  (hash-ref role-codes role
            (lambda ()
              (raise-argument-error 'theme-style "a current theme role symbol" role))))

(define (attributes->mask attributes)
  (unless (and (list? attributes)
               (= (length attributes) (length (remove-duplicates attributes)))
               (andmap (lambda (attribute) (hash-has-key? attribute-bits attribute))
                       attributes))
    (raise-argument-error 'theme-style "a unique list of theme attributes" attributes))
  (for/fold ([mask 0]) ([attribute (in-list attributes)])
    (bitwise-ior mask (hash-ref attribute-bits attribute))))

(define (mask->attributes mask)
  (unless (zero? (bitwise-and mask (bitwise-not known-attribute-mask)))
    (error 'theme-style "native theme attribute mask is invalid"))
  (for/list ([(attribute bit) (in-hash attribute-bits)]
             #:when (not (zero? (bitwise-and mask bit))))
    attribute))

(define (definition-handle-values handle)
  (list (theme-definition-handle-provider-id handle)
        (theme-definition-handle-provider-generation handle)
        (theme-definition-handle-definition-id handle)
        (theme-definition-handle-definition-generation handle)))

(define (decode-definition-handle input offset)
  (theme-definition-handle
   (read-u64 input offset)
   (read-u64 input (+ offset 8))
   (read-u64 input (+ offset 16))
   (read-u64 input (+ offset 24))))

(define (definition-handle-or-false values offset)
  (define fields (take (drop values offset) 4))
  (and (ormap positive? fields) (apply theme-definition-handle fields)))

(define (read-record-values input offset width)
  (require-record-bytes 'theme-record input offset width)
  (for/list ([field-offset (in-range offset (+ offset width) 8)])
    (read-u64 input field-offset)))

(define (decode-text input offset length minimum maximum)
  (unless (record-range-valid? offset length maximum minimum)
    (error 'theme-record "native theme text range is invalid"))
  (bytes->string/utf-8 (subbytes input offset (+ offset length))))

(define (record-range-valid? offset count total [minimum 0])
  (and (exact-nonnegative-integer? offset)
       (exact-nonnegative-integer? count)
       (<= minimum offset total)
       (<= count (- total offset))))

(define (require-record-bytes who input offset width)
  (unless (record-range-valid? offset width (bytes-length input))
    (error who "native theme record is truncated")))

(define (code->symbol who table code)
  (hash-ref table code (lambda () (error who "native theme enum code is invalid"))))

(define (code->boolean who code)
  (case code [(0) #f] [(1) #t] [else (error who "native theme boolean is invalid")]))

(define (exact-u8? value)
  (and (exact-integer? value) (<= 0 value 255)))

(define (read-u64 input offset)
  (integer-bytes->integer input #f #f offset (+ offset 8)))

(define (write-u64! output offset value)
  (integer->integer-bytes value 8 #f #f output offset)
  (void))

;; native-theme-turn executes one production theme capability turn.
(define (native-theme-turn generation token)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f 0 (string->bytes/utf-8 (exn-message failure))))])
    (define result
      (call-with-theme-control
       generation token
       (lambda (control)
         (theme-scope-registry-generation (theme-current-scope control)))))
    (list #t result #"")))

(module+ test-support
  (provide theme-control-scope set-theme-control-scope!))

(module+ test
  (require rackunit)

  (define active (theme-definition-handle 1 1 4 1))
  (define fallback active)
  (define baseline (theme-definition-handle 1 1 5 1))
  (define scope (theme-scope 1 #xff 91 7 3 active fallback baseline 12))
  (check-equal? (decode-scope (encode-scope scope)) scope)
  (check-equal? (hash-count role-codes) current-style-role-count)

  (define styles
    (for/list ([role (in-hash-keys role-codes)])
      (theme-style
       role #f #f
       (cond [(eq? role 'text-region) '(reverse)]
             [(eq? role 'diagnostic-rejected) '(bold underline)]
             [(eq? role 'diagnostic-error) '(bold underline)]
             [(eq? role 'diagnostic-warning) '(underline)]
             [(eq? role 'diagnostic-information) '(reverse)]
             [(eq? role 'diagnostic-hint) '(dim)]
             [(eq? role 'list-emphasis) '(bold)]
             [else '()]))))
  (define proposal
    (theme-proposal
     "racket-fixture" "Racket Fixture" "racket-fixture-provider"
     "module+ test" styles))
  (define encoded (encode-request scope operation-propose #f proposal))
  (check-true (<= (bytes-length encoded) maximum-proposal-bytes))
  (check-equal? (read-u64 encoded (- proposal-header-bytes 16))
                current-style-role-count)

  (define escaped #f)
  (check-true
   (void?
    (call-with-theme-control
     1 1 (lambda (control) (set! escaped control)))))
  (check-exn #rx"escaped its dynamic extent"
             (lambda () (theme-current-scope escaped)))
  (check-exn
   #rx"input exceeds"
   (lambda ()
     (call-with-theme-control
      1 1
      (lambda (control)
        (theme-control-invoke
         control operation-scope 0 0
         (make-bytes (add1 maximum-proposal-bytes)) 0)))))
  (check-equal?
   (theme-failure-diagnostic
    (theme-failure (contract 'failure-stale-selection) 0 0))
   "theme selection generation is stale")
  (check-equal? (hash-count failure-diagnostics) 38)
  (for ([code (in-range 38)])
    (check-true (string? (theme-failure-diagnostic (theme-failure code 0 0))))))
