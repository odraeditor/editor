#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         "../command/native-contracts.rkt"
         (prefix-in cap: "scoped-capability.rkt")
         (only-in "../command/status-bar.rkt"
                  factory-status-bar-configuration
                  normalize-status-bar-configuration
                  odra-status-bar-configuration?
                  odra-status-bar-provider?
                  odra-status-bar-provider-name
                  odra-status-bar-provider-package
                  odra-status-bar-provider-segments
                  odra-status-bar-segment-identity
                  odra-status-bar-segment-kind
                  odra-status-bar-segment-group
                  odra-status-bar-segment-order
                  odra-status-bar-segment-priority
                  odra-status-bar-segment-full-text
                  odra-status-bar-segment-compact-text
                  odra-status-bar-segment-omittable?
                  odra-status-bar-segment-truncatable?
                  odra-status-bar-segment-style
                  odra-status-bar-segment-inspection-text
                  odra-status-bar-segment-primary-command
                  odra-status-bar-segment-secondary-command
                  status-bar-segment
                  status-bar-provider
                  status-bar-position-code
                  status-bar-compact-code
                  status-bar-visibility-mask))

(provide
 (struct-out status-bar-startup-result)
 (struct-out status-bar-provider-handle)
 (struct-out status-bar-segment-handle)
 (struct-out status-bar-scope)
 (struct-out status-bar-usage)
 (struct-out status-bar-limits)
 (struct-out status-bar-native-provider)
 (struct-out status-bar-native-segment)
 (struct-out status-bar-diagnostic)
 (struct-out status-bar-snapshot)
 (struct-out status-bar-outcome)
 (struct-out status-bar-failure)
 (contract-out
  [load-status-bar-startup-value
   (-> any/c status-bar-startup-result?)]
  [status-bar-control? (-> any/c boolean?)]
  [call-with-status-bar-control
   (-> exact-positive-integer? exact-positive-integer?
       (-> status-bar-control? any/c) any/c)]
  [status-bar-current-scope
   (-> status-bar-control? symbol? (or/c status-bar-scope? status-bar-failure?))]
  [status-bar-inspect
   (-> status-bar-control? (or/c status-bar-snapshot? status-bar-failure?))]
  [status-bar-register
   (-> status-bar-control? odra-status-bar-provider?
       (or/c status-bar-outcome? status-bar-failure?))]
  [status-bar-replace
   (-> status-bar-control? status-bar-provider-handle? odra-status-bar-provider?
       (or/c status-bar-outcome? status-bar-failure?))]
  [status-bar-remove
   (-> status-bar-control? status-bar-provider-handle?
       (or/c status-bar-outcome? status-bar-failure?))]
  [status-bar-teardown
   (-> status-bar-control? status-bar-provider-handle?
       (or/c status-bar-outcome? status-bar-failure?))]
  [status-bar-failure-diagnostic (-> status-bar-failure? string?)]
  [status-bar-control-invoke
   (-> status-bar-control? exact-integer? exact-nonnegative-integer?
       exact-nonnegative-integer? bytes? exact-nonnegative-integer?
       cap:scoped-capability-result?)]
  [native-status-bar-turn
   (-> exact-positive-integer? exact-positive-integer? list?)]))

(define maximum-diagnostic-bytes 4096)

(define (contract item) (native-contract-value 'status-bar item))
(define scope-record-bytes (contract 'scope-record-bytes))
(define usage-record-bytes (contract 'usage-record-bytes))
(define limits-record-bytes (contract 'limits-record-bytes))
(define snapshot-header-bytes (contract 'snapshot-header-bytes))
(define provider-record-bytes (contract 'provider-record-bytes))
(define segment-record-bytes (contract 'segment-record-bytes))
(define proposal-header-bytes (contract 'proposal-header-bytes))
(define outcome-record-bytes (contract 'outcome-record-bytes))
(define diagnostic-record-bytes (contract 'diagnostic-record-bytes))
(define maximum-proposal-bytes (contract 'maximum-proposal-bytes))
(define maximum-proposal-text-bytes (contract 'maximum-proposal-text-bytes))
(define maximum-inspection-bytes (contract 'maximum-inspection-bytes))
(define operation-scope (contract 'operation-scope))
(define operation-inspect (contract 'operation-inspect))
(define operation-register (contract 'operation-register))
(define operation-replace (contract 'operation-replace))
(define operation-remove (contract 'operation-remove))
(define operation-teardown (contract 'operation-teardown))
(define access-codes
  (hasheq 'inspect (contract 'access-inspect)
          'register (contract 'access-register)
          'replace (contract 'access-replace)
          'remove (contract 'access-remove)
          'teardown (contract 'access-teardown)))
(define provider-state-symbols
  (hash (contract 'provider-state-registered) 'registered
        (contract 'provider-state-confirmed) 'confirmed
        (contract 'provider-state-rejected) 'rejected
        (contract 'provider-state-closed) 'closed))
(define completion-symbols
  (hash (contract 'completion-confirmed) 'confirmed
        (contract 'completion-rejected) 'rejected))
(define group-codes
  (hasheq 'left (contract 'group-left)
          'right (contract 'group-right)))
(define group-symbols
  (for/hash ([(name code) (in-hash group-codes)]) (values code name)))
(define kind-codes (hasheq 'miscellaneous (contract 'kind-miscellaneous)))
(define kind-symbols
  (for/hash ([(name code) (in-hash kind-codes)]) (values code name)))
(define role-codes
  (hasheq 'ordinary (contract 'role-ordinary)
          'context (contract 'role-context)
          'editing-context (contract 'role-editing-context)
          'disabled (contract 'role-disabled)))
(define role-symbols
  (for/hash ([(name code) (in-hash role-codes)]) (values code name)))
(define failure-diagnostics
  (hash
   (contract 'failure-none) ""
   (contract 'failure-invalid-schema) "Status Bar capability schema is invalid"
   (contract 'failure-access-denied) "Status Bar capability access was denied"
   (contract 'failure-invalid-scope) "Status Bar capability scope is invalid"
   (contract 'failure-stale-scope) "Status Bar capability scope is stale"
   (contract 'failure-invalid-provider) "Status Bar provider is invalid"
   (contract 'failure-stale-provider) "Status Bar provider generation is stale"
   (contract 'failure-provider-limit) "Status Bar provider limit exceeded"
   (contract 'failure-duplicate-provider) "Status Bar provider already exists"
   (contract 'failure-invalid-segment) "Status Bar segment is invalid"
   (contract 'failure-segment-limit) "Status Bar segment limit exceeded"
   (contract 'failure-duplicate-segment) "Status Bar segment identity is duplicated"
   (contract 'failure-factory-identity-conflict) "Status Bar segment conflicts with a factory identity"
   (contract 'failure-text-limit) "Status Bar segment text limit exceeded"
   (contract 'failure-invalid-style) "Status Bar segment style is not admitted"
   (contract 'failure-command-not-admitted) "Status Bar segment command is not admitted"
   (contract 'failure-proposal-limit) "Status Bar proposal limit exceeded"
   (contract 'failure-generation-limit) "Status Bar generation is exhausted"
   (contract 'failure-allocation) "Status Bar provider allocation failed"))

(struct status-bar-startup-result (status configuration diagnostic)
  #:transparent
  #:guard
  (lambda (status configuration diagnostic _)
    (unless (and (memq status '(confirmed rejected))
                 (odra-status-bar-configuration? configuration)
                 (string? diagnostic)
                 (<= (bytes-length (string->bytes/utf-8 diagnostic))
                     maximum-diagnostic-bytes))
      (raise-arguments-error 'status-bar-startup-result
                             "invalid bounded Status Bar startup result"))
    (values status configuration diagnostic)))

(struct status-bar-control (capability [scopes #:mutable]))
(struct status-bar-provider-handle (provider-id provider-generation) #:transparent)
(struct status-bar-segment-handle
  (provider-id provider-generation segment-id segment-generation)
  #:transparent)
(struct status-bar-scope
  (schema-version access session-id session-generation registry-id
                  registry-generation definition-generation provider
                  command-registry-generation presentation-generation
                  capability-generation)
  #:transparent)
(struct status-bar-usage
  (providers segments retained-bytes inspection-bytes preparation-peak-bytes
             operations-in-turn hosted-turns)
  #:transparent)
(struct status-bar-limits
  (providers segments-per-provider total-segments identity-bytes
             provider-name-bytes package-name-bytes segment-text-bytes
             command-name-bytes retained-bytes proposal-bytes
             operations-per-turn inspection-bytes preparation-bytes
             diagnostic-bytes concurrent-hosted-turns)
  #:transparent)
(struct status-bar-native-provider
  (handle state name package first-segment segment-count retained-bytes)
  #:transparent)
(struct status-bar-native-segment
  (handle state kind group order priority omittable? truncatable? style
          identity full-text compact-text inspection-text
          primary-command secondary-command)
  #:transparent)
(struct status-bar-diagnostic
  (operation code provider segment expected-generation actual-generation
             limit actual message)
  #:transparent)
(struct status-bar-snapshot
  (scope usage limits providers segments diagnostic)
  #:transparent)
(struct status-bar-outcome
  (scope operation completion changed? provider definition-generation
         segment-count retained-bytes operation-count diagnostic)
  #:transparent)
(struct status-bar-failure (code limit actual) #:transparent)

;; load-status-bar-startup-value normalizes one already evaluated export.
(define (load-status-bar-startup-value candidate)
  (with-handlers
      ([exn:fail?
        (lambda (failure)
          (status-bar-startup-result
           'rejected
           factory-status-bar-configuration
           (bounded-diagnostic (exn-message failure))))])
    (status-bar-startup-result
     'confirmed
     (normalize-status-bar-configuration candidate)
     "")))

(define (bounded-diagnostic message)
  (if (> (bytes-length (string->bytes/utf-8 message)) maximum-diagnostic-bytes)
      "Status Bar configuration failed with an oversized diagnostic"
      message))

;; call-with-status-bar-control confines one capability to its owner thread and turn.
(define (call-with-status-bar-control generation token command)
  (cap:call-with-scoped-capability
   'status-bar generation token
   (lambda (capability) (command (status-bar-control capability (make-hasheq))))))

;; status-bar-control-invoke enforces copied input and output bounds before native entry.
(define (status-bar-control-invoke control operation arg0 arg1 input output-capacity)
  (when (> (bytes-length input) maximum-proposal-bytes)
    (raise-arguments-error
     'status-bar-control-invoke "Status Bar input exceeds the copied proposal limit"
     "limit" maximum-proposal-bytes "actual" (bytes-length input)))
  (when (> output-capacity maximum-inspection-bytes)
    (raise-arguments-error
     'status-bar-control-invoke "Status Bar output exceeds the copied inspection limit"
     "limit" maximum-inspection-bytes "actual" output-capacity))
  (cap:scoped-capability-invoke
   (status-bar-control-capability control)
   operation arg0 arg1 input output-capacity))

;; status-bar-current-scope obtains exact authority for one lifecycle operation.
(define (status-bar-current-scope control access)
  (define access-code
    (hash-ref access-codes access
              (lambda ()
                (raise-argument-error 'status-bar-current-scope
                                      "an admitted Status Bar access symbol" access))))
  (define result
    (status-bar-native-invoke
     control operation-scope access-code 0 #"" scope-record-bytes))
  (if (status-bar-failure? result)
      result
      (let ([scope (decode-scope result 0)])
        (hash-set! (status-bar-control-scopes control) access scope)
        scope)))

(define (current-or-fetch-scope control access)
  (hash-ref (status-bar-control-scopes control) access
            (lambda () (status-bar-current-scope control access))))

;; status-bar-inspect returns one complete copied package registry snapshot.
(define (status-bar-inspect control)
  (define scope (current-or-fetch-scope control 'inspect))
  (if (status-bar-failure? scope)
      scope
      (let ([result
             (status-bar-native-invoke
              control operation-inspect 0 0
              (encode-scope scope) maximum-inspection-bytes)])
        (if (status-bar-failure? result) result (decode-snapshot result)))))

;; status-bar-register publishes one complete copied package generation.
(define (status-bar-register control provider)
  (invoke-provider-mutation control 'register operation-register #f provider))

;; status-bar-replace atomically replaces one exact package provider generation.
(define (status-bar-replace control expected provider)
  (invoke-provider-mutation control 'replace operation-replace expected provider))

;; status-bar-remove removes one exact provider and every owned segment.
(define (status-bar-remove control provider)
  (invoke-provider-mutation control 'remove operation-remove provider #f))

;; status-bar-teardown removes state owned by one closing package provider.
(define (status-bar-teardown control provider)
  (invoke-provider-mutation control 'teardown operation-teardown provider #f))

;; status-bar-failure-diagnostic returns the schema-checked native rejection meaning.
(define (status-bar-failure-diagnostic failure)
  (hash-ref failure-diagnostics (status-bar-failure-code failure)
            (lambda ()
              (format "unknown Status Bar failure ~a" (status-bar-failure-code failure)))))

(define (invoke-provider-mutation control access operation expected provider)
  (define scope (current-or-fetch-scope control access))
  (if (status-bar-failure? scope)
      scope
      (let* ([request (encode-provider-request scope operation expected provider)]
             [result
              (status-bar-native-invoke
               control operation 0 0 request outcome-record-bytes)])
        (if (status-bar-failure? result)
            result
            (let ([outcome (decode-outcome result)])
              (hash-clear! (status-bar-control-scopes control))
              outcome)))))

(define (status-bar-native-invoke control operation arg0 arg1 input output-capacity)
  (define result
    (status-bar-control-invoke control operation arg0 arg1 input output-capacity))
  (case (cap:scoped-capability-result-status result)
    [(0) (cap:scoped-capability-result-output result)]
    [(1)
     (status-bar-failure
      (cap:scoped-capability-result-failure-code result)
      (cap:scoped-capability-result-limit result)
      (cap:scoped-capability-result-actual result))]
    [else
     (error 'status-bar-native-invoke
            "native Status Bar adapter rejected the call")]))

(define (encode-provider-request scope operation expected provider)
  (define handle (or expected (status-bar-provider-handle 0 0)))
  (define segments (if provider (odra-status-bar-provider-segments provider) '()))
  (define provider-parts
    (if provider
        (list (string->bytes/utf-8 (odra-status-bar-provider-name provider))
              (string->bytes/utf-8
               (symbol->string (odra-status-bar-provider-package provider))))
        (list #"" #"")))
  (define segment-parts
    (for/list ([segment (in-list segments)])
      (map string->bytes/utf-8
           (list (symbol->string (odra-status-bar-segment-identity segment))
                 (odra-status-bar-segment-full-text segment)
                 (odra-status-bar-segment-compact-text segment)
                 (odra-status-bar-segment-inspection-text segment)
                 (or (odra-status-bar-segment-primary-command segment) "")
                 (or (odra-status-bar-segment-secondary-command segment) "")))))
  (define all-parts (append provider-parts (append* segment-parts)))
  (define text-bytes (for/sum ([part (in-list all-parts)]) (bytes-length part)))
  (when (> text-bytes maximum-proposal-text-bytes)
    (raise-arguments-error
     'status-bar-provider "provider text exceeds the copied proposal limit"
     "limit" maximum-proposal-text-bytes "actual" text-bytes))
  (define text-start (+ proposal-header-bytes (* (length segments) segment-record-bytes)))
  (define total (+ text-start text-bytes))
  (when (> total maximum-proposal-bytes)
    (raise-arguments-error
     'status-bar-provider "provider proposal exceeds the copied limit"
     "limit" maximum-proposal-bytes "actual" total))
  (define output (make-bytes total))
  (bytes-copy! output 0 (encode-scope scope))
  (define cursor text-start)
  (define ranges
    (for/list ([part (in-list all-parts)])
      (define range (list cursor (bytes-length part)))
      (set! cursor (+ cursor (bytes-length part)))
      range))
  (define provider-name-range (list-ref ranges 0))
  (define package-name-range (list-ref ranges 1))
  (define header-values
    (list operation
          (status-bar-provider-handle-provider-id handle)
          (status-bar-provider-handle-provider-generation handle)
          (status-bar-scope-definition-generation scope)
          (status-bar-provider-handle-provider-id handle)
          (status-bar-provider-handle-provider-generation handle)
          (contract 'provider-kind-package)
          (length segments)
          (car provider-name-range) (cadr provider-name-range)
          (car package-name-range) (cadr package-name-range)
          text-bytes
          1))
  (for ([value (in-list header-values)]
        [offset (in-range scope-record-bytes proposal-header-bytes 8)])
    (write-u64! output offset value))
  (for ([segment (in-list segments)] [index (in-naturals)])
    (define part-ranges (take (drop ranges (+ 2 (* index 6))) 6))
    (encode-segment-proposal!
     output (+ proposal-header-bytes (* index segment-record-bytes))
     handle segment part-ranges))
  (set! cursor text-start)
  (for ([part (in-list all-parts)])
    (bytes-copy! output cursor part)
    (set! cursor (+ cursor (bytes-length part))))
  output)

(define (encode-segment-proposal! output offset provider segment ranges)
  (define range-values (append* ranges))
  (define values
    (append
     (list (status-bar-provider-handle-provider-id provider)
           (status-bar-provider-handle-provider-generation provider)
           0 0
           (contract 'provider-state-registered)
           (hash-ref kind-codes (odra-status-bar-segment-kind segment))
           (hash-ref group-codes (odra-status-bar-segment-group segment))
           (odra-status-bar-segment-order segment)
           (odra-status-bar-segment-priority segment)
           (boolean->code (odra-status-bar-segment-omittable? segment))
           (boolean->code (odra-status-bar-segment-truncatable? segment))
           (hash-ref role-codes (odra-status-bar-segment-style segment)))
     range-values))
  (unless (= (length values) 24)
    (error 'status-bar-provider "internal segment record width mismatch"))
  (for ([value (in-list values)] [field (in-naturals)])
    (write-u64! output (+ offset (* field 8)) value)))

(define (encode-scope scope)
  (define provider (or (status-bar-scope-provider scope)
                       (status-bar-provider-handle 0 0)))
  (define output (make-bytes scope-record-bytes))
  (define values
    (list (status-bar-scope-schema-version scope)
          (status-bar-scope-access scope)
          (status-bar-scope-session-id scope)
          (status-bar-scope-session-generation scope)
          (status-bar-scope-registry-id scope)
          (status-bar-scope-registry-generation scope)
          (status-bar-scope-definition-generation scope)
          (status-bar-provider-handle-provider-id provider)
          (status-bar-provider-handle-provider-generation provider)
          (status-bar-scope-command-registry-generation scope)
          (status-bar-scope-presentation-generation scope)
          (status-bar-scope-capability-generation scope)))
  (for ([value (in-list values)] [offset (in-range 0 scope-record-bytes 8)])
    (write-u64! output offset value))
  output)

(define (decode-scope input [offset 0])
  (require-record-bytes 'status-bar-scope input offset scope-record-bytes)
  (define values (read-record-values input offset scope-record-bytes))
  (define provider-id (list-ref values 7))
  (define provider-generation (list-ref values 8))
  (unless (eq? (zero? provider-id) (zero? provider-generation))
    (error 'status-bar-scope "native provider scope is incomplete"))
  (status-bar-scope
   (list-ref values 0) (list-ref values 1) (list-ref values 2)
   (list-ref values 3) (list-ref values 4) (list-ref values 5)
   (list-ref values 6)
   (and (positive? provider-id)
        (status-bar-provider-handle provider-id provider-generation))
   (list-ref values 9) (list-ref values 10) (list-ref values 11)))

(define (decode-outcome input)
  (unless (= (bytes-length input) outcome-record-bytes)
    (error 'status-bar-outcome "native Status Bar outcome has an invalid width"))
  (define scope (decode-scope input 0))
  (define values
    (read-record-values input scope-record-bytes
                        (- outcome-record-bytes scope-record-bytes)))
  (define provider-id (list-ref values 3))
  (define provider-generation (list-ref values 4))
  (status-bar-outcome
   scope
   (list-ref values 0)
   (code->symbol 'status-bar-outcome completion-symbols (list-ref values 1))
   (code->boolean 'status-bar-outcome (list-ref values 2))
   (and (positive? provider-id)
        (status-bar-provider-handle provider-id provider-generation))
   (list-ref values 5)
   (list-ref values 6)
   (list-ref values 7)
   (list-ref values 8)
   (and (positive? (list-ref values 9))
        (list (list-ref values 9) (list-ref values 10)))))

(define (decode-snapshot input)
  (when (< (bytes-length input) snapshot-header-bytes)
    (error 'status-bar-snapshot "native Status Bar snapshot is truncated"))
  (define scope (decode-scope input 0))
  (define usage-offset scope-record-bytes)
  (define limits-offset (+ usage-offset usage-record-bytes))
  (define counts-offset (+ limits-offset limits-record-bytes))
  (define usage-values (read-record-values input usage-offset usage-record-bytes))
  (define limit-values (read-record-values input limits-offset limits-record-bytes))
  (define counts (read-record-values input counts-offset 40))
  (define provider-count (list-ref counts 0))
  (define segment-count (list-ref counts 1))
  (define diagnostic-count (list-ref counts 2))
  (define text-bytes (list-ref counts 3))
  (define diagnostic-bytes (list-ref counts 4))
  (unless (and (<= provider-count (contract 'maximum-providers))
               (<= segment-count (contract 'maximum-segments))
               (<= diagnostic-count 1)
               (<= diagnostic-bytes maximum-diagnostic-bytes))
    (error 'status-bar-snapshot "native Status Bar snapshot exceeds declared bounds"))
  (define providers-offset snapshot-header-bytes)
  (define segments-offset (+ providers-offset (* provider-count provider-record-bytes)))
  (define text-start (+ segments-offset (* segment-count segment-record-bytes)))
  (define text-end (+ text-start text-bytes))
  (define diagnostic-offset text-end)
  (define expected
    (+ text-end
       (if (zero? diagnostic-count) 0 (+ diagnostic-record-bytes diagnostic-bytes))))
  (unless (= expected (bytes-length input))
    (error 'status-bar-snapshot "native Status Bar snapshot has an invalid width"))
  (define providers
    (for/list ([index (in-range provider-count)])
      (decode-provider input (+ providers-offset (* index provider-record-bytes))
                       text-start text-end)))
  (define segments
    (for/list ([index (in-range segment-count)])
      (decode-segment input (+ segments-offset (* index segment-record-bytes))
                      text-start text-end)))
  (for ([provider (in-list providers)])
    (unless (<= (+ (status-bar-native-provider-first-segment provider)
                   (status-bar-native-provider-segment-count provider))
                segment-count)
      (error 'status-bar-snapshot "native provider segment range is invalid")))
  (status-bar-snapshot
   scope
   (apply status-bar-usage usage-values)
   (apply status-bar-limits limit-values)
   providers
   segments
   (and (= diagnostic-count 1)
        (decode-diagnostic input diagnostic-offset text-start expected))))

(define (decode-provider input offset text-start text-end)
  (define values (read-record-values input offset provider-record-bytes))
  (status-bar-native-provider
   (status-bar-provider-handle (list-ref values 0) (list-ref values 1))
   (code->symbol 'status-bar-provider provider-state-symbols (list-ref values 2))
   (decode-text input (list-ref values 3) (list-ref values 4) text-start text-end)
   (decode-text input (list-ref values 5) (list-ref values 6) text-start text-end)
   (list-ref values 7) (list-ref values 8) (list-ref values 9)))

(define (decode-segment input offset text-start text-end)
  (define values (read-record-values input offset segment-record-bytes))
  (status-bar-native-segment
   (status-bar-segment-handle
    (list-ref values 0) (list-ref values 1)
    (list-ref values 2) (list-ref values 3))
   (code->symbol 'status-bar-segment provider-state-symbols (list-ref values 4))
   (code->symbol 'status-bar-segment kind-symbols (list-ref values 5))
   (code->symbol 'status-bar-segment group-symbols (list-ref values 6))
   (list-ref values 7) (list-ref values 8)
   (code->boolean 'status-bar-segment (list-ref values 9))
   (code->boolean 'status-bar-segment (list-ref values 10))
   (code->symbol 'status-bar-segment role-symbols (list-ref values 11))
   (decode-text input (list-ref values 12) (list-ref values 13) text-start text-end)
   (decode-text input (list-ref values 14) (list-ref values 15) text-start text-end)
   (decode-text input (list-ref values 16) (list-ref values 17) text-start text-end)
   (decode-text input (list-ref values 18) (list-ref values 19) text-start text-end)
   (decode-text input (list-ref values 20) (list-ref values 21) text-start text-end)
   (decode-text input (list-ref values 22) (list-ref values 23) text-start text-end)))

(define (decode-diagnostic input offset text-start text-end)
  (define values (read-record-values input offset diagnostic-record-bytes))
  (status-bar-diagnostic
   (list-ref values 0) (list-ref values 1)
   (status-bar-provider-handle (list-ref values 2) (list-ref values 3))
   (status-bar-segment-handle
    (list-ref values 2) (list-ref values 3)
    (list-ref values 4) (list-ref values 5))
   (list-ref values 6) (list-ref values 7) (list-ref values 8) (list-ref values 9)
   (decode-text input (list-ref values 10) (list-ref values 11)
                (+ offset diagnostic-record-bytes) text-end)))

(define (read-record-values input offset width)
  (require-record-bytes 'status-bar-record input offset width)
  (for/list ([field-offset (in-range offset (+ offset width) 8)])
    (read-u64 input field-offset)))

(define (decode-text input offset length minimum maximum)
  (unless (record-range-valid? offset length maximum minimum)
    (error 'status-bar-record "native Status Bar text range is invalid"))
  (bytes->string/utf-8 (subbytes input offset (+ offset length))))

(define (record-range-valid? offset count total [minimum 0])
  (and (exact-nonnegative-integer? offset)
       (exact-nonnegative-integer? count)
       (<= minimum offset total)
       (<= count (- total offset))))

(define (require-record-bytes who input offset width)
  (unless (record-range-valid? offset width (bytes-length input))
    (error who "native Status Bar record is truncated")))

(define (code->symbol who table code)
  (hash-ref table code
            (lambda () (error who "native Status Bar enum code is invalid"))))

(define (code->boolean who code)
  (case code [(0) #f] [(1) #t]
    [else (error who "native Status Bar boolean is invalid")]))

(define (boolean->code value) (if value 1 0))

(define (read-u64 input offset)
  (integer-bytes->integer input #f #f offset (+ offset 8)))

(define (write-u64! output offset value)
  (integer->integer-bytes value 8 #f #f output offset)
  (void))

;; native-status-bar-turn publishes one bounded fixture through the public facade.
(define (native-status-bar-turn generation token)
  (with-handlers ([exn? (lambda (failure)
                          (list #f #f (string->bytes/utf-8 (exn-message failure))))])
    (define result
      (call-with-status-bar-control
       generation token
       (lambda (control)
         (define registered
           (status-bar-register
            control
            (status-bar-provider
             "Racket fixture"
             'racket-fixture
             (list
              (status-bar-segment
               'racket-state "Racket" #:compact "Rkt" #:group 'right
               #:order 100 #:priority 10 #:style 'context)))))
         (if (status-bar-failure? registered)
             registered
             (status-bar-inspect control)))))
    (if (status-bar-failure? result)
        (list #f result #"native Status Bar provider rejected the fixture")
        (list #t result #""))))

(module+ test
  (require rackunit)

  (define loaded
    (load-status-bar-startup-value
     (hash 'position 'line-column
           'visible '(project editing-context)
           'compact 'prefer-compact)))
  (check-eq? (status-bar-startup-result-status loaded) 'confirmed
             (status-bar-startup-result-diagnostic loaded))
  (check-equal? (status-bar-position-code
                 (status-bar-startup-result-configuration loaded))
                2)
  (check-equal? (status-bar-visibility-mask
                 (status-bar-startup-result-configuration loaded))
                #x18)
  (define rejected
    (load-status-bar-startup-value '#hash((visible . (unknown)))))
  (check-eq? (status-bar-startup-result-status rejected) 'rejected)
  (check-eq? (status-bar-startup-result-configuration rejected)
             factory-status-bar-configuration)
  (check-true (positive? (string-length
                          (status-bar-startup-result-diagnostic rejected))))

  (define scope
    (status-bar-scope
     1 (contract 'access-register) 11 13 17 19 23 #f 29 31 37))
  (check-equal? (decode-scope (encode-scope scope)) scope)
  (define segment
    (status-bar-segment
     'task-count "3 tasks" #:compact "3" #:group 'right #:order 20
     #:priority 30 #:style 'context #:inspection "Three active tasks"
     #:primary-command 'tasks-open))
  (define provider (status-bar-provider "Tasks" 'tasks-package (list segment)))
  (define encoded
    (encode-provider-request scope operation-register #f provider))
  (check-true (<= (bytes-length encoded) maximum-proposal-bytes))
  (check-equal? (read-u64 encoded scope-record-bytes) operation-register)
  (check-equal? (read-u64 encoded (+ scope-record-bytes 56)) 1)
  (check-equal? (read-u64 encoded (+ proposal-header-bytes 40))
                (contract 'kind-miscellaneous))
  (check-equal? (read-u64 encoded (+ proposal-header-bytes 48))
                (contract 'group-right))
  (check-equal? (read-u64 encoded (+ proposal-header-bytes 88))
                (contract 'role-context))
  (define escaped #f)
  (check-true
   (void?
    (call-with-status-bar-control
     1 1 (lambda (control) (set! escaped control)))))
  (check-exn #rx"escaped its dynamic extent"
             (lambda ()
               (status-bar-control-invoke
                escaped operation-scope (contract 'access-inspect) 0 #"" 0)))
  (check-equal?
   (status-bar-failure-diagnostic
    (status-bar-failure (contract 'failure-command-not-admitted) 0 0))
   "Status Bar segment command is not admitted"))
