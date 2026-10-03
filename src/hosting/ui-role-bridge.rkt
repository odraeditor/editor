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
 (struct-out ui-role-provider-handle)
 (struct-out ui-role-scope)
 (struct-out ui-role-provider)
 (struct-out ui-role-snapshot)
 (struct-out ui-role-proposal)
 (struct-out ui-role-outcome)
 (struct-out ui-role-failure)
 (contract-out
  [ui-role-control? (-> any/c boolean?)]
  [call-with-ui-role-control
   (-> exact-positive-integer? exact-positive-integer?
       (-> ui-role-control? any/c) any/c)]
  [ui-role-current-scope
   (-> ui-role-control? symbol? (or/c ui-role-scope? ui-role-failure?))]
  [ui-role-inspect
   (-> ui-role-control? symbol? (or/c ui-role-snapshot? ui-role-failure?))]
  [ui-role-inspect-provider
   (-> ui-role-control? ui-role-provider-handle?
       (or/c ui-role-provider? ui-role-failure?))]
  [ui-role-propose
   (-> ui-role-control? ui-role-proposal? (or/c ui-role-outcome? ui-role-failure?))]
  [ui-role-activate
   (-> ui-role-control? ui-role-provider-handle?
       (or/c ui-role-outcome? ui-role-failure?))]
  [ui-role-replace
   (-> ui-role-control? ui-role-provider-handle? ui-role-proposal?
       (or/c ui-role-outcome? ui-role-failure?))]
  [ui-role-rollback
   (-> ui-role-control? symbol? (or/c ui-role-outcome? ui-role-failure?))]
  [ui-role-teardown
   (-> ui-role-control? ui-role-provider-handle?
       (or/c ui-role-outcome? ui-role-failure?))]
  [ui-role-invoke-command
   (-> ui-role-control? ui-role-provider-handle? bytes?
       (or/c ui-role-outcome? ui-role-failure?))]
  [ui-role-failure-diagnostic (-> ui-role-failure? string?)]
  [native-ui-role-turn
   (-> exact-positive-integer? exact-positive-integer? list?)]))

(define (contract item) (native-contract-value 'ui-role item))
(define scope-record-bytes (contract 'scope-record-bytes))
(define snapshot-header-bytes (contract 'snapshot-header-bytes))
(define provider-record-bytes (contract 'provider-record-bytes))
(define capability-requirement-record-bytes
  (contract 'capability-requirement-record-bytes))
(define request-header-bytes (contract 'request-header-bytes))
(define outcome-record-bytes (contract 'outcome-record-bytes))
(define maximum-proposal-bytes (contract 'maximum-proposal-bytes))
(define maximum-provider-text-bytes (contract 'maximum-provider-text-bytes))
(define maximum-capability-requirements
  (contract 'maximum-capability-requirements))
(define operation-scope (contract 'operation-scope))
(define operation-snapshot (contract 'operation-snapshot))
(define operation-inspect-provider (contract 'operation-inspect-provider))
(define operation-propose (contract 'operation-propose))
(define operation-activate (contract 'operation-activate))
(define operation-replace (contract 'operation-replace))
(define operation-rollback (contract 'operation-rollback))
(define operation-teardown (contract 'operation-teardown))
(define operation-invoke-command (contract 'operation-invoke-command))

(define role-codes
  (hasheq 'startup (contract 'role-startup)
          'buffer-menu (contract 'role-buffer-menu)
          'candidate-navigation (contract 'role-candidate-navigation)
          'project-inventory (contract 'role-project-inventory)
          'keymap-inspection (contract 'role-keymap-inspection)
          'transient-input (contract 'role-transient-input)
          'status (contract 'role-status)))
(define role-symbols
  (for/hasheq ([(name code) (in-hash role-codes)]) (values code name)))
(define renderer-capability-codes
  (hasheq 'cell-geometry (contract 'renderer-cell-geometry)
          'clipping (contract 'renderer-clipping)
          'unicode-profile (contract 'renderer-unicode-profile)
          'text-cursor (contract 'renderer-text-cursor)
          'input-cursor (contract 'renderer-input-cursor)
          'semantic-attributes (contract 'renderer-semantic-attributes)
          'atomic-generation (contract 'renderer-atomic-generation)
          'full-redraw (contract 'renderer-full-redraw)))
(define failure-diagnostics
  (hash
   (contract 'failure-none) ""
   (contract 'failure-invalid-registry) "invalid UI role registry"
   (contract 'failure-closed-registry) "closed UI role registry"
   (contract 'failure-invalid-session) "invalid UI role session"
   (contract 'failure-invalid-role) "invalid UI role"
   (contract 'failure-invalid-provider) "invalid UI role provider"
   (contract 'failure-stale-provider) "stale UI role provider generation"
   (contract 'failure-provider-limit) "UI role provider limit exceeded"
   (contract 'failure-provider-name-limit) "provider name limit exceeded"
   (contract 'failure-package-name-limit) "package name limit exceeded"
   (contract 'failure-duplicate-provider) "duplicate UI role provider"
   (contract 'failure-stale-scope) "stale UI role scope"
   (contract 'failure-provider-not-package) "provider is not package-owned"
   (contract 'failure-provider-not-registered) "package provider is not registered"
   (contract 'failure-provider-not-confirmed) "package provider is not confirmed"
   (contract 'failure-provider-not-active) "package provider is not active"
   (contract 'failure-renderer-incompatible) "provider renderer requirements are incompatible"
   (contract 'failure-stale-root) "provider root generation is stale"
   (contract 'failure-proposal-limit) "provider proposal byte limit exceeded"
   (contract 'failure-callback-budget) "provider callback budget exhausted"
   (contract 'failure-focus-effect) "provider proposal cannot change focus"
   (contract 'failure-layout-effect) "provider proposal cannot change layout"
   (contract 'failure-command-name-limit) "provider command name limit exceeded"
   (contract 'failure-command-not-admitted) "provider command is not admitted"
   (contract 'failure-generation-limit) "provider generation limit exhausted"
   (contract 'failure-allocation) "UI role provider allocation failed"))

(struct ui-role-control (capability scopes))
(struct ui-role-provider-handle
  (role provider-id provider-generation)
  #:transparent)
(struct ui-role-scope
  (schema-version access session-id session-generation ui-registry-id
                  root-generation registry-generation role active-provider
                  renderer-profile-id capability-generation)
  #:transparent)
(struct ui-role-provider
  (provider-handle kind state name package-name requirements confirmed-root-generation)
  #:transparent)
(struct ui-role-snapshot (scope payload) #:transparent)
(struct ui-role-proposal
  (role name package-name requirements content command callback-budget)
  #:transparent)
(struct ui-role-outcome
  (scope previous-provider provider confirmed-root-generation changed?
         fallback-selected? diagnostic-code diagnostic-bytes retained-bytes
         callback-count)
  #:transparent)
(struct ui-role-failure (code limit actual) #:transparent)

;; ui-role-failure-diagnostic returns the schema-checked native failure meaning.
(define (ui-role-failure-diagnostic failure)
  (hash-ref failure-diagnostics (ui-role-failure-code failure)
            (lambda () (format "unknown UI role failure ~a" (ui-role-failure-code failure)))))


(define (fixture-proposal role [callback-budget 32]
                          [content #"compact package presentation"])
  (ui-role-proposal
   role "compact provider" "example/ui"
   '(cell-geometry clipping unicode-profile atomic-generation)
   content #"open" callback-budget))

(define maximum-fixture-content-bytes
  (- maximum-proposal-bytes
     request-header-bytes
     (* 4 capability-requirement-record-bytes)
     (bytes-length #"compact provider")
     (bytes-length #"example/ui")
     (bytes-length #"open")))

(define (run-fixture control content-bytes)
  (define proposed
    (ui-role-propose
     control
     (fixture-proposal 'startup 32 (make-bytes content-bytes 120))))
  (define provider (ui-role-outcome-provider proposed))
  (define activated (ui-role-activate control provider))
  (define inspected (ui-role-inspect-provider control provider))
  (define invoked (ui-role-invoke-command control provider #"open"))
  (define rolled-back (ui-role-rollback control 'startup))
  (define torn-down (ui-role-teardown control provider))
  (list proposed activated inspected invoked rolled-back torn-down))

;; call-with-ui-role-control confines one opaque role capability to one Racket turn.
(define (call-with-ui-role-control generation token command)
  (cap:call-with-scoped-capability
   'ui-role generation token
   (lambda (capability) (command (ui-role-control capability (make-hasheq))))))

(define (role->code role)
  (hash-ref role-codes role
            (lambda ()
              (raise-argument-error 'ui-role "an accepted UI role symbol" role))))

(define (code->role code)
  (hash-ref role-symbols code
            (lambda ()
              (raise-argument-error 'ui-role "an accepted UI role code" code))))

(define (ui-role-native-invoke control operation arg0 arg1 input output-capacity)
  (when (> output-capacity maximum-proposal-bytes)
    (raise-arguments-error
     'ui-role-native-invoke
     "output capacity exceeds the supported maximum"
     "limit" maximum-proposal-bytes
     "actual" output-capacity))
  (when (> (bytes-length input) maximum-proposal-bytes)
    (raise-arguments-error
     'ui-role-native-invoke
     "input payload exceeds the supported maximum"
     "limit" maximum-proposal-bytes
     "actual" (bytes-length input)))
  (define result
    (cap:scoped-capability-invoke
     (ui-role-control-capability control)
     operation arg0 arg1 input output-capacity))
  (case (cap:scoped-capability-result-status result)
    [(0) (cap:scoped-capability-result-output result)]
    [(1)
     (ui-role-failure
      (cap:scoped-capability-result-failure-code result)
      (cap:scoped-capability-result-limit result)
      (cap:scoped-capability-result-actual result))]
    [else
     (error 'ui-role-native-invoke "native UI role adapter rejected the call")]))

;; ui-role-current-scope returns one exact session, root, role, and provider generation.
(define (ui-role-current-scope control role)
  (define result
    (ui-role-native-invoke
     control operation-scope (role->code role) 0 #"" scope-record-bytes))
  (if (ui-role-failure? result)
      result
      (let ([scope (decode-scope result 0)])
        (hash-set! (ui-role-control-scopes control) role scope)
        scope)))

(define (current-or-fetch-scope control role)
  (hash-ref (ui-role-control-scopes control) role
            (lambda () (ui-role-current-scope control role))))

;; ui-role-inspect returns one immutable copied snapshot payload.
(define (ui-role-inspect control role)
  (define scope (current-or-fetch-scope control role))
  (if (ui-role-failure? scope)
      scope
      (let ([result
             (ui-role-native-invoke
              control operation-snapshot (role->code role) 0
              (encode-scope scope) maximum-proposal-bytes)])
        (if (ui-role-failure? result)
            result
            (begin
              (unless (>= (bytes-length result) snapshot-header-bytes)
                (error 'ui-role-inspect "native UI role snapshot is truncated"))
              (ui-role-snapshot
               (decode-scope result 0)
               (bytes->immutable-bytes result)))))))

;; ui-role-inspect-provider returns copied provider identity, text, and requirements.
(define (ui-role-inspect-provider control handle)
  (define role (ui-role-provider-handle-role handle))
  (define scope (current-or-fetch-scope control role))
  (if (ui-role-failure? scope)
      scope
      (let ([result
             (ui-role-native-invoke
              control operation-inspect-provider (role->code role)
              (ui-role-provider-handle-provider-id handle)
              (encode-scope scope) maximum-proposal-bytes)])
        (if (ui-role-failure? result) result (decode-provider result)))))

;; ui-role-propose registers one copied package provider without activating it.
(define (ui-role-propose control proposal)
  (invoke-proposal control operation-propose #f proposal))

;; ui-role-activate activates one already confirmed provider generation.
(define (ui-role-activate control provider)
  (invoke-provider control operation-activate provider #""))

;; ui-role-replace atomically proposes and activates one copied provider generation.
(define (ui-role-replace control expected proposal)
  (invoke-proposal control operation-replace expected proposal))

;; ui-role-rollback restores the confirmed built-in provider for one role.
(define (ui-role-rollback control role)
  (invoke-role control operation-rollback role))

;; ui-role-teardown closes one package provider and restores fallback when active.
(define (ui-role-teardown control provider)
  (invoke-provider control operation-teardown provider #""))

;; ui-role-invoke-command dispatches one copied admitted command name.
(define (ui-role-invoke-command control provider command)
  (when (> (bytes-length command) maximum-provider-text-bytes)
    (raise-arguments-error
     'ui-role-invoke-command
     "command exceeds the supported maximum"
     "limit" maximum-provider-text-bytes
     "actual" (bytes-length command)))
  (invoke-provider control operation-invoke-command provider command))

(define (invoke-role control operation role)
  (define scope (current-or-fetch-scope control role))
  (if (ui-role-failure? scope)
      scope
      (decode-outcome-result
       control role
       (ui-role-native-invoke
        control operation (role->code role) 0 (encode-scope scope)
        outcome-record-bytes))))

(define (invoke-provider control operation provider command)
  (define role (ui-role-provider-handle-role provider))
  (define scope (current-or-fetch-scope control role))
  (if (ui-role-failure? scope)
      scope
      (let ([request
             (encode-request
              scope operation provider provider #f #"" #"" '() #"" command 0)])
        (decode-outcome-result
         control role
         (ui-role-native-invoke
          control operation (role->code role)
          (ui-role-provider-handle-provider-id provider)
          request outcome-record-bytes)))))

(define (invoke-proposal control operation expected proposal)
  (define role (ui-role-proposal-role proposal))
  (define scope (current-or-fetch-scope control role))
  (if (ui-role-failure? scope)
      scope
      (let* ([provider
              (or expected (ui-role-provider-handle role 0 0))]
             [request
              (encode-request
               scope operation provider provider #t
               (string->bytes/utf-8 (ui-role-proposal-name proposal))
               (string->bytes/utf-8 (ui-role-proposal-package-name proposal))
               (ui-role-proposal-requirements proposal)
               (ui-role-proposal-content proposal)
               (ui-role-proposal-command proposal)
               (ui-role-proposal-callback-budget proposal))])
        (decode-outcome-result
         control role
         (ui-role-native-invoke
          control operation (role->code role) 0 request outcome-record-bytes)))))

(define (decode-outcome-result control role result)
  (if (ui-role-failure? result)
      result
      (let ([outcome (decode-outcome result)])
        (hash-set! (ui-role-control-scopes control) role (ui-role-outcome-scope outcome))
        outcome)))

(define (encode-request scope operation expected provider package-provider?
                        name package-name requirements content command callback-budget)
  (unless (and (list? requirements)
               (<= (length requirements) maximum-capability-requirements)
               (andmap (lambda (requirement)
                         (hash-has-key? renderer-capability-codes requirement))
                       requirements))
    (raise-argument-error
     'ui-role-proposal "a bounded list of renderer capability symbols" requirements))
  (when (> (+ (bytes-length name) (bytes-length package-name))
           maximum-provider-text-bytes)
    (raise-arguments-error
     'ui-role-proposal
     "provider identity exceeds the supported maximum"
     "limit" maximum-provider-text-bytes
     "actual" (+ (bytes-length name) (bytes-length package-name))))
  (define requirement-bytes
    (* (length requirements) capability-requirement-record-bytes))
  (define total
    (+ request-header-bytes requirement-bytes (bytes-length name)
       (bytes-length package-name) (bytes-length content) (bytes-length command)))
  (when (> total maximum-proposal-bytes)
    (raise-arguments-error
     'ui-role-proposal "proposal exceeds the supported maximum"
     "limit" maximum-proposal-bytes "actual" total))
  (define output (make-bytes total))
  (bytes-copy! output 0 (encode-scope scope))
  (define expected-id
    (if expected (ui-role-provider-handle-provider-id expected) 0))
  (define expected-generation
    (if expected (ui-role-provider-handle-provider-generation expected) 0))
  (define provider-id (ui-role-provider-handle-provider-id provider))
  (define provider-generation (ui-role-provider-handle-provider-generation provider))
  (define header-values
    (list operation
          (role->code (ui-role-scope-role scope))
          expected-id expected-generation provider-id provider-generation
          (if package-provider? 2 0)
          (ui-role-scope-root-generation scope)
          0 0 0 0 0 0 0 0 0
          (length requirements)
          (bytes-length name)
          (bytes-length package-name)
          (bytes-length content)
          (bytes-length command)
          callback-budget))
  (for ([value (in-list header-values)]
        [offset (in-range scope-record-bytes request-header-bytes 8)])
    (write-u64! output offset value))
  (define cursor request-header-bytes)
  (for ([requirement (in-list requirements)])
    (write-u64! output cursor (hash-ref renderer-capability-codes requirement))
    (write-u64! output (+ cursor 8) 1)
    (set! cursor (+ cursor capability-requirement-record-bytes)))
  (for ([part (in-list (list name package-name content command))])
    (bytes-copy! output cursor part)
    (set! cursor (+ cursor (bytes-length part))))
  output)

(define (encode-scope scope)
  (define output (make-bytes scope-record-bytes))
  (define provider (ui-role-scope-active-provider scope))
  (for ([value
         (in-list
          (list (ui-role-scope-schema-version scope)
                (ui-role-scope-access scope)
                (ui-role-scope-session-id scope)
                (ui-role-scope-session-generation scope)
                (ui-role-scope-ui-registry-id scope)
                (ui-role-scope-root-generation scope)
                (ui-role-scope-registry-generation scope)
                (role->code (ui-role-scope-role scope))
                (ui-role-provider-handle-provider-id provider)
                (ui-role-provider-handle-provider-generation provider)
                (ui-role-scope-renderer-profile-id scope)
                (ui-role-scope-capability-generation scope)))]
        [offset (in-range 0 scope-record-bytes 8)])
    (write-u64! output offset value))
  output)

(define (decode-scope input offset)
  (unless (>= (bytes-length input) (+ offset scope-record-bytes))
    (error 'decode-ui-role-scope "truncated scope record"))
  (define role (code->role (read-u64 input (+ offset 56))))
  (define provider
    (ui-role-provider-handle
     role (read-u64 input (+ offset 64)) (read-u64 input (+ offset 72))))
  (ui-role-scope
   (read-u64 input offset)
   (read-u64 input (+ offset 8))
   (read-u64 input (+ offset 16))
   (read-u64 input (+ offset 24))
   (read-u64 input (+ offset 32))
   (read-u64 input (+ offset 40))
   (read-u64 input (+ offset 48))
   role provider
   (read-u64 input (+ offset 80))
   (read-u64 input (+ offset 88))))

(define (decode-provider input)
  (unless (>= (bytes-length input) provider-record-bytes)
    (error 'decode-ui-role-provider "truncated provider record"))
  (define role (code->role (read-u64 input 0)))
  (define handle
    (ui-role-provider-handle role (read-u64 input 8) (read-u64 input 16)))
  (define requirement-offset (read-u64 input 40))
  (define requirement-count (read-u64 input 48))
  (define name-offset (read-u64 input 56))
  (define name-bytes (read-u64 input 64))
  (define package-offset (read-u64 input 72))
  (define package-bytes (read-u64 input 80))
  (define (checked-subbytes offset count)
    (unless (<= provider-record-bytes offset (+ offset count) (bytes-length input))
      (error 'decode-ui-role-provider "provider range is outside the copied record"))
    (subbytes input offset (+ offset count)))
  (define requirements
    (for/list ([index (in-range requirement-count)])
      (define base (+ requirement-offset (* index capability-requirement-record-bytes)))
      (define code (read-u64 input base))
      (for/first ([(name value) (in-hash renderer-capability-codes)] #:when (= code value))
        name)))
  (ui-role-provider
   handle (read-u64 input 24) (read-u64 input 32)
   (bytes->string/utf-8 (checked-subbytes name-offset name-bytes))
   (bytes->string/utf-8 (checked-subbytes package-offset package-bytes))
   requirements (read-u64 input 88)))

(define (decode-outcome input)
  (unless (= (bytes-length input) outcome-record-bytes)
    (error 'decode-ui-role-outcome "invalid outcome width"))
  (define scope (decode-scope input 0))
  (define role (ui-role-scope-role scope))
  (ui-role-outcome
   scope
   (ui-role-provider-handle role (read-u64 input 96) (read-u64 input 104))
   (ui-role-provider-handle role (read-u64 input 112) (read-u64 input 120))
   (read-u64 input 128)
   (not (zero? (read-u64 input 136)))
   (not (zero? (read-u64 input 144)))
   (read-u64 input 152)
   (read-u64 input 160)
   (read-u64 input 168)
   (read-u64 input 176)))

(define (read-u64 input offset)
  (unless (<= 0 offset (+ offset 8) (bytes-length input))
    (error 'ui-role-record "truncated unsigned integer"))
  (integer-bytes->integer input #f #f offset (+ offset 8)))

(define (write-u64! output offset value)
  (integer->integer-bytes value 8 #f #f output offset)
  (void))

;; native-ui-role-turn executes one production UI-role capability turn.
(define (native-ui-role-turn generation token)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #f (string->bytes/utf-8 (exn-message failure))))])
    (define result
      (call-with-ui-role-control
       generation token (lambda (control) (ui-role-current-scope control 'startup))))
    (list #t result #"")))

(module+ test-support
  (provide role-codes
           run-fixture
           fixture-proposal
           maximum-fixture-content-bytes
           ui-role-control-scopes))

(module+ test
  (require rackunit)

  (check-equal? (role->code 'startup) 1)
  (check-equal? (code->role 7) 'status)
  (check-exn exn:fail:contract? (lambda () (role->code 'notification)))
  (define scope
    (ui-role-scope 1 127 1 1 2 3 4 'startup
                   (ui-role-provider-handle 'startup 5 6) 7 8))
  (check-equal? (decode-scope (encode-scope scope) 0) scope)
  (define request
    (encode-request
     scope operation-propose #f (ui-role-provider-handle 'startup 0 0) #t
     #"compact" #"example/ui" '(cell-geometry clipping) #"payload" #"open" 32))
  (check-true (<= (bytes-length request) maximum-proposal-bytes))
  (check-equal? (read-u64 request 96) operation-propose)
  (check-equal? (read-u64 request 232) 2)
  (check-equal?
   (ui-role-failure-diagnostic
    (ui-role-failure (contract 'failure-stale-scope) 0 0))
   "stale UI role scope"))
