#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         "../configuration/personal.rkt"
         (only-in "../command/status-bar.rkt"
                  factory-status-bar-configuration
                  status-bar-position-code
                  status-bar-compact-code
                  status-bar-visibility-mask)
         (only-in "status-bar-bridge.rkt"
                  load-status-bar-startup-value
                  status-bar-startup-result-status
                  status-bar-startup-result-configuration
                  status-bar-startup-result-diagnostic)
         (only-in "../command/gutter.rkt"
                  factory-gutter-configuration
                  odra-gutter-configuration-visible?
                  odra-gutter-configuration-order
                  odra-gutter-configuration-minimum-digits
                  odra-gutter-configuration-maximum-digits
                  odra-gutter-configuration-left-padding
                  odra-gutter-configuration-right-padding
                  odra-gutter-configuration-separator
                  odra-gutter-configuration-separator-fallback
                  gutter-side-code
                  gutter-mode-code
                  gutter-scope-code
                  gutter-current-line-code)
         (only-in "gutter-configuration-bridge.rkt"
                  load-gutter-startup-value
                  gutter-startup-result-status
                  gutter-startup-result-configuration
                  gutter-startup-result-diagnostic)
         (only-in "gutter-provider-bridge.rkt"
                  load-gutter-provider-startup-value
                  gutter-provider-startup-result-status
                  gutter-provider-startup-result-bytes
                  gutter-provider-startup-result-diagnostic)
         (only-in "../command/completion.rkt"
                  factory-completion-configuration
                  odra-completion-configuration-enabled?
                  odra-completion-configuration-explicit?
                  odra-completion-configuration-identifier?
                  odra-completion-configuration-trigger-character?
                  odra-completion-configuration-minimum-prefix
                  odra-completion-configuration-case-sensitive-prefix?
                  odra-completion-configuration-case-insensitive-prefix?
                  odra-completion-configuration-subsequence?
                  odra-completion-configuration-candidate-limit
                  odra-completion-configuration-additional-edit-limit
                  odra-completion-configuration-text-byte-limit
                  odra-completion-configuration-detail-byte-limit
                  odra-completion-configuration-resolve-byte-limit
                  odra-completion-configuration-implementation-limit
                  odra-completion-configuration-replacement-limit
                  odra-completion-configuration-request-replacement-limit)
         (only-in "completion-configuration-bridge.rkt"
                  load-completion-startup-value
                  completion-startup-result-status
                  completion-startup-result-configuration
                  completion-startup-result-diagnostic
                  completion-configuration-role-code)
         (only-in "terminal-configuration-bridge.rkt"
                  load-terminal-configuration-value
                  terminal-configuration-encode
                  terminal-configuration-runtime-reset!
                  terminal-configuration-runtime-prepare!
                  terminal-configuration-runtime-activate!
                  terminal-configuration-runtime-discard!
                  terminal-configuration-runtime-pending)
         (only-in "language-support-configuration-bridge.rkt"
                  load-language-support-configuration-value
                  language-support-configuration-encode)
         (only-in "../command/recovery.rkt"
                  factory-recovery-policy
                  odra-recovery-policy-enabled?
                  odra-recovery-policy-strategy
                  odra-recovery-policy-debounce-milliseconds
                  odra-recovery-policy-maximum-interval-milliseconds
                  odra-recovery-policy-retention
                  odra-recovery-policy-storage
                  odra-recovery-policy-startup
                  odra-recovery-policy-source-autosave
                  odra-recovery-retention-maximum-age-seconds
                  odra-recovery-retention-records-per-buffer
                  odra-recovery-retention-total-records
                  odra-recovery-storage-limits-record-payload-bytes
                  odra-recovery-storage-limits-buffer-storage-bytes
                  odra-recovery-storage-limits-store-storage-bytes
                  odra-recovery-storage-limits-cleanup-records)
         (only-in "personal-command-runtime.rkt"
                  personal-command-runtime-prepare!
                  personal-command-runtime-activate!
                  personal-command-runtime-catalog
                  personal-command-runtime-discard!
                  personal-command-runtime-note-rejection!
                  personal-command-runtime-reset!)
         (only-in "../command/ksawery-extension.rkt"
                  ksawery-contributor-annotation-provider
                  ksawery-contributor-annotation-execution-limits
                  ksawery-contributor-command-execution-limits
                  ksawery-contributor-conflict-assistance-provider
                  ksawery-contributor-conflict-assistance-execution-limits
                  ksawery-contributor-encode
                  ksawery-contributor-status-provider
                  ksawery-contributor-status-execution-limits
                  ksawery-contributor->datum)
         (only-in "../command/ksawery-command.rkt"
                  decode-ksawery-command-submission
                  encode-ksawery-command-family
                  ksawery-command-action-authority
                  ksawery-command-action-external-operation
                  ksawery-command-action-id
                  ksawery-command-action-identity
                  ksawery-command-family-actions
                  ksawery-command-family-definitions
                  ksawery-command-family-generation
                  ksawery-command-family-id
                  ksawery-command-family-identity
                  ksawery-command-outcome-operation
                  ksawery-command-request-external-operation
                  ksawery-command-submission-action
                  ksawery-command-submission-confirmation
                  ksawery-command-submission-context
                  ksawery-command-submission-family
                  ksawery-command-submission-family-generation
                  ksawery-command-submission-values)
         (only-in "../command/ksawery-operation.rkt"
                  encode-ksawery-operation-plan)
         (only-in "../command/ksawery-annotation.rkt"
                  compose-ksawery-annotation-proposal
                  decode-ksawery-annotation-observation
                  encode-ksawery-annotation-proposal)
         (only-in "../command/ksawery-conflict-assistance.rkt"
                  decode-ksawery-conflict-observation
                  encode-ksawery-conflict-provider
                  encode-ksawery-conflict-response
                  ksawery-conflict-response?
                  ksawery-conflict-response-provider)
         (only-in "../command/ksawery-status-section.rkt"
                  compose-ksawery-status-proposal
                  encode-ksawery-status-proposal)
         (only-in "personal-command-containment.rkt"
                  call-with-personal-command-turn)
         (only-in "../command/personal.rkt"
                  make-personal-command-limits)
         (only-in "../command/catalog.rkt"
                  odra-command-catalog-definitions
                  odra-command-definition-dispatch-class
                  odra-command-definition-name)
         (only-in "../command/package-catalogs.rkt"
                  factory-package-catalog-configuration
                  odra-package-catalog-configuration?)
         (only-in "../command/indentation.rkt"
                  factory-indentation-configuration
                  indentation-configuration-encode))

(provide
 (contract-out
  [runtime-personal-configuration-startup-batch (-> bytes? list?)]
  [runtime-personal-configuration-reload-batch
   (-> bytes? exact-positive-integer? list?)]
  [runtime-personal-generation-transition
   (-> exact-positive-integer? exact-positive-integer? list?)]
  [runtime-personal-package-catalog-configuration
   (-> odra-package-catalog-configuration?)]
  [runtime-personal-configuration-root (-> (or/c #f string?))]
  [runtime-personal-package-resources (-> list?)]
  [runtime-ksawery-annotation-projection-batch (-> bytes? list?)]
  [runtime-ksawery-conflict-assistance-batch
   (-> exact-positive-integer? bytes? list?)]
  [runtime-ksawery-command-family-batch
   (-> exact-positive-integer? exact-positive-integer? bytes? list?)]
  [runtime-ksawery-external-operation-batch
   (-> exact-positive-integer? exact-positive-integer? bytes? bytes? list?)]
  [runtime-ksawery-status-projection-batch (-> bytes? list?)]))

(define schema-version 10)
(define header-bytes 464)
(define maximum-copy-bytes (* 256 1024))

(define result-codes '((confirmed . 1) (rejected . 2)))
(define observation-codes
  '((absent . 1) (confirmed . 2) (rejected . 3) (unavailable . 4)))
(define recovery-strategy-codes
  '((transaction-debounced . 1) (interval . 2) (hybrid . 3)))
(define recovery-startup-codes
  '((ask . 1) (inspect . 2) (restore-matching . 3)))
(define recovery-autosave-codes
  '((disabled . 1) (after-checkpoint . 2)))
(define activate-transition 1)
(define discard-transition 2)
(define confirmed-state (personal-config-initialize))
(define pending-state #f)
(define pending-ksawery-extension-bytes #"")
(define pending-language-support-bytes #"")
(define configuration-root #f)

(define (runtime-personal-package-catalog-configuration)
  (define observation
    (odra-personal-config-state-observation confirmed-state))
  (if observation
      (personal-config-observation-export
       observation 'odra-package-catalogs
       factory-package-catalog-configuration)
      factory-package-catalog-configuration))

(define (runtime-personal-configuration-root)
  configuration-root)

(define (runtime-personal-package-resources)
  (define observation (odra-personal-config-state-observation confirmed-state))
  (if observation
      (personal-config-observation-export observation 'odra-package-resources '())
      '()))

;; runtime-ksawery-external-operation-batch evaluates one exact declared command action.
(define (runtime-ksawery-external-operation-batch
         generation operation name-bytes submission-bytes)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #"" (utf8 (exn-message failure))))])
    (unless (= generation
               (odra-personal-config-state-confirmed-generation confirmed-state))
      (error 'runtime-ksawery-external-operation-batch
             "Ksawery external-operation command generation is stale"))
    (define name (bytes->string/utf-8 name-bytes))
    (define catalog (personal-command-runtime-catalog generation))
    (define definitions (odra-command-catalog-definitions catalog))
    (unless (<= operation (length definitions))
      (error 'runtime-ksawery-external-operation-batch
             "Ksawery external-operation command route is unavailable"))
    (define definition (list-ref definitions (sub1 operation)))
    (unless (and (eq? (odra-command-definition-dispatch-class definition)
                      'ksawery-extension)
                 (string=? (odra-command-definition-name definition) name))
      (error 'runtime-ksawery-external-operation-batch
             "Ksawery external-operation command route is stale"))
    (define observation (odra-personal-config-state-observation confirmed-state))
    (define contributor
      (and observation
           (personal-config-observation-export
            observation 'odra-ksawery-contributor #f)))
    (define families
      (if observation
          (personal-config-observation-export
           observation 'odra-ksawery-command-families '())
          '()))
    (define provider
      (and contributor
           (hash-ref (ksawery-contributor->datum contributor) 'identity)))
    (define routed
      (and provider
           (for*/first ([family (in-list families)]
                        [action (in-list (ksawery-command-family-actions family))]
                        #:when
                        (string=?
                         name
                         (string-append provider "/"
                                        (ksawery-command-family-identity family) "/"
                                        (ksawery-command-action-identity action))))
             (cons family action))))
    (unless routed
      (error 'runtime-ksawery-external-operation-batch
             "Ksawery external-operation command family is unavailable"))
    (define family (car routed))
    (define action (cdr routed))
    (unless (and (eq? (ksawery-command-action-authority action)
                      'submit-external-operation)
                 (procedure? (ksawery-command-action-external-operation action)))
      (error 'runtime-ksawery-external-operation-batch
             "Ksawery command action does not declare an external operation"))
    (define submission
      (decode-ksawery-command-submission submission-bytes family))
    (unless (and (= (ksawery-command-submission-family submission)
                    (ksawery-command-family-id family))
                 (= (ksawery-command-submission-family-generation submission)
                    (ksawery-command-family-generation family))
                 (= (ksawery-command-submission-action submission)
                    (ksawery-command-action-id action)))
      (error 'runtime-ksawery-external-operation-batch
             "Ksawery external-operation command submission is stale"))
    (define contributor-data (ksawery-contributor->datum contributor))
    (define execution-limits
      (ksawery-contributor-command-execution-limits contributor))
    (when (> (bytes-length submission-bytes)
             (hash-ref execution-limits 'observation-bytes))
      (error 'runtime-ksawery-external-operation-batch
             "Ksawery external-operation command submission exceeds the contributor policy"))
    (define context (ksawery-command-submission-context submission))
    (define values (ksawery-command-submission-values submission))
    (define plan
      (call-with-personal-command-turn
       name
       (hash-ref contributor-data 'provenance)
       (hash-ref contributor-data 'generation)
       (make-personal-command-limits
        #:deadline-milliseconds
        (hash-ref execution-limits 'deadline-milliseconds)
        #:custodian-memory-bytes
        (hash-ref execution-limits 'custodian-memory-bytes)
        #:temporary-native-bytes
        (hash-ref execution-limits 'temporary-native-bytes)
        #:diagnostic-bytes
        (min maximum-personal-diagnostic-bytes
             (hash-ref execution-limits 'diagnostic-bytes)))
       (lambda ()
         ((ksawery-command-action-external-operation action) context values))))
    (define outcome
      (ksawery-command-request-external-operation
       context family (ksawery-command-action-id action) values plan
       (ksawery-command-submission-confirmation submission)))
    (define result
      (encode-ksawery-operation-plan
       (ksawery-command-outcome-operation outcome)))
    (when (> (bytes-length result)
             (min (hash-ref execution-limits 'result-bytes)
                  (hash-ref execution-limits 'provider-value-bytes)))
      (error 'runtime-ksawery-external-operation-batch
             "Ksawery external-operation plan exceeds the contributor policy"))
    (list #t result #"")))

;; runtime-ksawery-command-family-batch returns the exact active family and action route.
(define (runtime-ksawery-command-family-batch generation operation name-bytes)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #"" (utf8 (exn-message failure))))])
    (unless (= generation
               (odra-personal-config-state-confirmed-generation confirmed-state))
      (error 'runtime-ksawery-command-family-batch
             "Ksawery command generation is stale"))
    (define name (bytes->string/utf-8 name-bytes))
    (define catalog (personal-command-runtime-catalog generation))
    (define definitions (odra-command-catalog-definitions catalog))
    (unless (<= operation (length definitions))
      (error 'runtime-ksawery-command-family-batch
             "Ksawery command route is unavailable"))
    (define definition (list-ref definitions (sub1 operation)))
    (unless (and (eq? (odra-command-definition-dispatch-class definition)
                      'ksawery-extension)
                 (string=? (odra-command-definition-name definition) name))
      (error 'runtime-ksawery-command-family-batch
             "Ksawery command route is stale"))
    (define observation (odra-personal-config-state-observation confirmed-state))
    (define contributor
      (and observation
           (personal-config-observation-export
            observation 'odra-ksawery-contributor #f)))
    (define families
      (if observation
          (personal-config-observation-export
           observation 'odra-ksawery-command-families '())
          '()))
    (define provider
      (and contributor
           (hash-ref (ksawery-contributor->datum contributor) 'identity)))
    (define routed
      (and provider
           (for*/first ([family (in-list families)]
                        [action (in-list (ksawery-command-family-actions family))]
                        #:when
                        (string=?
                         name
                         (string-append provider "/"
                                        (ksawery-command-family-identity family) "/"
                                        (ksawery-command-action-identity action))))
             (cons family action))))
    (unless routed
      (error 'runtime-ksawery-command-family-batch
             "Ksawery command family is unavailable"))
    (define family-bytes (encode-ksawery-command-family (car routed)))
    (list #t
          (bytes-append
           (word (ksawery-command-action-id (cdr routed)))
           (word (bytes-length family-bytes))
           family-bytes)
          #"")))

;; runtime-ksawery-conflict-assistance-batch evaluates one exact selected conflict turn.
(define (runtime-ksawery-conflict-assistance-batch request observation-bytes)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #"" (utf8 (exn-message failure))))])
    (define state (or pending-state confirmed-state))
    (define observation (odra-personal-config-state-observation state))
    (define contributor
      (and observation
           (personal-config-observation-export
            observation 'odra-ksawery-contributor #f)))
    (define provider
      (and contributor
           (ksawery-contributor-conflict-assistance-provider contributor)))
    (if (not provider)
        (list #t #"" #"")
        (let* ([execution-limits
                (ksawery-contributor-conflict-assistance-execution-limits contributor)]
               [_
                (when (> (bytes-length observation-bytes)
                         (hash-ref execution-limits 'observation-bytes))
                  (error 'runtime-ksawery-conflict-assistance-batch
                         "Ksawery Conflict observation exceeds the contributor policy"))]
               [conflict-observation
                (decode-ksawery-conflict-observation observation-bytes)]
               [contributor-data (ksawery-contributor->datum contributor)]
               [response
                (call-with-personal-command-turn
                 "ksawery-conflict-assistance-provider"
                 (hash-ref contributor-data 'provenance)
                 (hash-ref contributor-data 'generation)
                 (make-personal-command-limits
                  #:deadline-milliseconds
                  (hash-ref execution-limits 'deadline-milliseconds)
                  #:custodian-memory-bytes
                  (hash-ref execution-limits 'custodian-memory-bytes)
                  #:temporary-native-bytes
                  (hash-ref execution-limits 'temporary-native-bytes)
                  #:diagnostic-bytes
                  (min maximum-personal-diagnostic-bytes
                       (hash-ref execution-limits 'diagnostic-bytes)))
                 (lambda () (provider contributor request conflict-observation)))])
          (unless (ksawery-conflict-response? response)
            (raise-argument-error
             'runtime-ksawery-conflict-assistance-batch
             "ksawery-conflict-response?" response))
          (define provider-bytes
            (encode-ksawery-conflict-provider
             (ksawery-conflict-response-provider response)))
          (define response-bytes (encode-ksawery-conflict-response response))
          (define result
            (bytes-append
             (integer->integer-bytes (bytes-length provider-bytes) 8 #f #f)
             (integer->integer-bytes (bytes-length response-bytes) 8 #f #f)
             provider-bytes response-bytes))
          (define copied-limit
            (min (hash-ref execution-limits 'result-bytes)
                 (hash-ref execution-limits 'provider-value-bytes)))
          (when (> (bytes-length result) copied-limit)
            (error 'runtime-ksawery-conflict-assistance-batch
                   "Ksawery conflict-assistance result exceeds the contributor policy"))
          (list #t result #"")))))

;; runtime-ksawery-annotation-projection-batch evaluates one bounded annotation turn.
(define (runtime-ksawery-annotation-projection-batch observation-bytes)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #"" (utf8 (exn-message failure))))])
    (define state (or pending-state confirmed-state))
    (define observation (odra-personal-config-state-observation state))
    (define contributor
      (and observation
           (personal-config-observation-export
            observation 'odra-ksawery-contributor #f)))
    (define provider
      (and contributor (ksawery-contributor-annotation-provider contributor)))
    (if (not provider)
        (list #t #"" #"")
        (let* ([execution-limits
                (ksawery-contributor-annotation-execution-limits contributor)]
               [_
                (when (> (bytes-length observation-bytes)
                         (hash-ref execution-limits 'observation-bytes))
                  (error 'runtime-ksawery-annotation-projection-batch
                         "Ksawery annotation observation exceeds the contributor policy"))]
               [annotation-observation
                (decode-ksawery-annotation-observation observation-bytes)]
               [contributor-data (ksawery-contributor->datum contributor)]
               [annotations
                (call-with-personal-command-turn
                 "ksawery-annotation-provider"
                 (hash-ref contributor-data 'provenance)
                 (hash-ref contributor-data 'generation)
                 (make-personal-command-limits
                  #:deadline-milliseconds
                  (hash-ref execution-limits 'deadline-milliseconds)
                  #:custodian-memory-bytes
                  (hash-ref execution-limits 'custodian-memory-bytes)
                  #:temporary-native-bytes
                  (hash-ref execution-limits 'temporary-native-bytes)
                  #:diagnostic-bytes
                  (min maximum-personal-diagnostic-bytes
                       (hash-ref execution-limits 'diagnostic-bytes)))
                 (lambda () (provider annotation-observation)))])
          (unless (list? annotations)
            (raise-argument-error
             'runtime-ksawery-annotation-projection-batch
             "list of Ksawery annotations" annotations))
          (if (null? annotations)
              (list #t #"" #"")
              (let* ([generation (hash-ref annotation-observation 'generation)]
                     [proposal
                      (compose-ksawery-annotation-proposal
                       contributor
                       (hash-ref annotation-observation 'repository)
                       (hash-ref annotation-observation 'family)
                       generation generation annotations)]
                     [proposal-bytes (encode-ksawery-annotation-proposal proposal)]
                     [copied-limit
                      (min (hash-ref execution-limits 'result-bytes)
                           (hash-ref execution-limits 'provider-value-bytes))])
                (when (> (bytes-length proposal-bytes) copied-limit)
                  (error 'runtime-ksawery-annotation-projection-batch
                         "Ksawery annotation proposal exceeds the contributor policy"))
                (list #t proposal-bytes #"")))))))

;; runtime-ksawery-status-projection-batch evaluates one active bounded provider turn.
(define (runtime-ksawery-status-projection-batch observation-bytes)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #"" (utf8 (exn-message failure))))])
    (define state (or pending-state confirmed-state))
    (define observation (odra-personal-config-state-observation state))
    (define contributor
      (and observation
           (personal-config-observation-export
            observation 'odra-ksawery-contributor #f)))
    (define provider
      (and contributor (ksawery-contributor-status-provider contributor)))
    (if (not provider)
        (list #t #"" #"")
        (let* ([execution-limits
                (ksawery-contributor-status-execution-limits contributor)]
               [_
                (when (> (bytes-length observation-bytes)
                         (hash-ref execution-limits 'observation-bytes))
                  (error 'runtime-ksawery-status-projection-batch
                         "Ksawery Status observation exceeds the contributor policy"))]
               [status-observation (decode-ksawery-status-observation observation-bytes)]
               [contributor-data (ksawery-contributor->datum contributor)]
               [sections
                (call-with-personal-command-turn
                 "ksawery-status-provider"
                 (hash-ref contributor-data 'provenance)
                 (hash-ref contributor-data 'generation)
                 (make-personal-command-limits
                  #:deadline-milliseconds
                  (hash-ref execution-limits 'deadline-milliseconds)
                  #:custodian-memory-bytes
                  (hash-ref execution-limits 'custodian-memory-bytes)
                  #:temporary-native-bytes
                  (hash-ref execution-limits 'temporary-native-bytes)
                  #:diagnostic-bytes
                  (min maximum-personal-diagnostic-bytes
                       (hash-ref execution-limits 'diagnostic-bytes)))
                 (lambda () (provider status-observation)))])
          (unless (list? sections)
            (raise-argument-error
             'runtime-ksawery-status-projection-batch
             "list of Ksawery Status sections" sections))
          (define generation (hash-ref status-observation 'generation))
          (define proposal
            (compose-ksawery-status-proposal
             contributor
             (hash-ref status-observation 'repository)
             generation
             generation
             sections))
          (define proposal-bytes (encode-ksawery-status-proposal proposal))
          (define copied-limit
            (min (hash-ref execution-limits 'result-bytes)
                 (hash-ref execution-limits 'provider-value-bytes)))
          (when (> (bytes-length proposal-bytes) copied-limit)
            (error 'runtime-ksawery-status-projection-batch
                   "Ksawery Status proposal exceeds the contributor policy"))
          (list #t proposal-bytes #"")))))

(define (decode-ksawery-status-observation input)
  (define (read-word offset)
    (unless (<= (+ offset 8) (bytes-length input))
      (error 'decode-ksawery-status-observation "truncated observation record"))
    (integer-bytes->integer input #f #f offset (+ offset 8)))
  (define schema (read-word 0))
  (define total (read-word 8))
  (define path-count (read-word 16))
  (define generation (read-word 24))
  (unless (and (= schema 1) (= total (bytes-length input))
               (positive? generation) (<= path-count 4096)
               (<= (+ 64 (* path-count 32)) total))
    (error 'decode-ksawery-status-observation "invalid observation header"))
  (define (read-text offset length)
    (unless (and (positive? length) (<= offset total) (<= length (- total offset)))
      (error 'decode-ksawery-status-observation "invalid observation text range"))
    (bytes->string/utf-8 (subbytes input offset (+ offset length))))
  (define group-names '#(invalid unmerged untracked unstaged staged))
  (define changes
    (for/list ([index (in-range path-count)])
      (define base (+ 64 (* index 32)))
      (define group (read-word (+ base 8)))
      (unless (< 0 group (vector-length group-names))
        (error 'decode-ksawery-status-observation "invalid Status group"))
      (hash 'id (read-word base)
            'group (vector-ref group-names group)
            'path (read-text (read-word (+ base 16))
                             (read-word (+ base 24))))))
  (hash 'repository (read-text (read-word 32) (read-word 40))
        'generation generation
        'branch (read-text (read-word 48) (read-word 56))
        'changes changes))

(define (word value)
  (integer->integer-bytes value 8 #f #f))

(define (words . values)
  (apply bytes-append (map word values)))

(define (utf8 value)
  (string->bytes/utf-8 value))

(define (code table key who)
  (define found (assq key table))
  (unless found (error who "unsupported value: ~a" key))
  (cdr found))

;; runtime-personal-configuration-startup-batch loads one startup init.rkt generation.
(define (runtime-personal-configuration-startup-batch configuration-root-bytes)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #"" (utf8 (exn-message failure))))])
    (personal-command-runtime-reset!)
    (terminal-configuration-runtime-reset!)
    (set! confirmed-state (personal-config-initialize))
    (set! pending-state #f)
    (set! pending-ksawery-extension-bytes #"")
    (set! pending-language-support-bytes #"")
    (define root (bytes->path configuration-root-bytes))
    (set! configuration-root
          (path->string (simplify-path (path->complete-path root))))
    (define source (personal-config-source root))
    (define result
      (personal-config-reload confirmed-state 1 source))
    (prepare-result! result #t)
    (list #t (startup-result-encode result) #"")))

(define (runtime-personal-configuration-reload-batch
         configuration-root-bytes expected-generation)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #"" (utf8 (exn-message failure))))])
    (when pending-state
      (error 'runtime-personal-configuration-reload-batch
             "a personal configuration candidate is already prepared"))
    (define source
      (personal-config-source (bytes->path configuration-root-bytes)))
    (define result
      (personal-config-reload confirmed-state expected-generation source))
    (if (eq? (odra-personal-config-result-status result) 'confirmed)
        (prepare-result! result #f)
        (let* ([rejected-state (odra-personal-config-result-state result)]
               [diagnostics
                (odra-personal-config-state-diagnostics rejected-state)])
          (set! confirmed-state rejected-state)
          (personal-command-runtime-note-rejection!
           (odra-personal-config-state-rejected-generation rejected-state)
           (if (pair? diagnostics)
               (odra-personal-config-diagnostic-message (car diagnostics))
               "Personal configuration candidate rejected"))))
    (list #t (startup-result-encode result) #"")))

(define (runtime-personal-generation-transition transition generation)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #f (utf8 (exn-message failure))))])
    (unless (and pending-state
                 (= generation
                    (odra-personal-config-state-confirmed-generation pending-state)))
      (error 'runtime-personal-generation-transition
             "personal configuration generation is not prepared"))
    (case transition
      [(1)
       (terminal-configuration-runtime-activate! generation)
       (personal-command-runtime-activate! generation)
       (set! confirmed-state pending-state)]
      [(2)
       (terminal-configuration-runtime-discard! generation)
       (personal-command-runtime-discard! generation)]
      [else
       (raise-argument-error
        'runtime-personal-generation-transition
        "a supported personal generation transition" transition)])
    (set! pending-state #f)
    (set! pending-ksawery-extension-bytes #"")
    (set! pending-language-support-bytes #"")
    (list #t #t #"")))

(define (prepare-result! result startup-fallback?)
  (define state (odra-personal-config-result-state result))
  (define observation (odra-personal-config-state-observation state))
  (define admitted?
    (and (eq? (odra-personal-config-result-status result) 'confirmed)
         observation
         (memq (odra-personal-config-observation-state observation)
               '(absent confirmed))))
  (define configured?
    (and admitted?
         (eq? (odra-personal-config-observation-state observation) 'confirmed)))
  (unless (or admitted? startup-fallback?)
    (error 'prepare-result! "rejected reload cannot prepare a runtime generation"))
  (define generation
    (odra-personal-config-state-confirmed-generation state))
  (define contributor
    (and configured?
         (personal-config-observation-export
          observation 'odra-ksawery-contributor #f)))
  (set! pending-ksawery-extension-bytes
        (if configured?
            (if contributor
                (ksawery-contributor-encode contributor generation)
                #"")
            #""))
  (set! pending-language-support-bytes
        (language-support-configuration-encode
         (load-language-support-configuration-value
          (and configured?
               (personal-config-observation-export
                observation 'odra-language-support #f)))))
  (personal-command-runtime-prepare!
   generation
   (if configured?
       (personal-config-observation-export
        observation 'odra-personal-commands '())
       '())
   (and configured?
        (personal-config-observation-export
         observation 'odra-interaction-profile #f))
   (if contributor
       (ksawery-command-family-definitions
        contributor
        (personal-config-observation-export
         observation 'odra-ksawery-command-families '()))
       '()))
  (terminal-configuration-runtime-prepare!
   generation
   (load-terminal-configuration-value
    (and configured?
         (personal-config-observation-export
          observation 'odra-terminal-configuration #f))))
  (set! pending-state state))

(define (startup-result-encode result)
  (define state (odra-personal-config-result-state result))
  (define observation (odra-personal-config-state-observation state))
  (define observation-state
    (if observation
        (odra-personal-config-observation-state observation)
        'rejected))
  (define diagnostic
    (and (pair? (odra-personal-config-state-diagnostics state))
         (car (odra-personal-config-state-diagnostics state))))
  (define configuration factory-status-bar-configuration)
  (define gutter-configuration factory-gutter-configuration)
  (define gutter-provider-bytes #"")
  (define completion-configuration factory-completion-configuration)
  (define effective-result-status (odra-personal-config-result-status result))
  (define effective-observation-state observation-state)
  (define effective-rejected-generation
    (odra-personal-config-state-rejected-generation state))
  (define effective-diagnostic diagnostic)
  (when (and (eq? effective-result-status 'confirmed)
             (eq? observation-state 'confirmed)
             observation)
    (define status-result
      (load-status-bar-startup-value
       (personal-config-observation-export
        observation 'odra-status-bar-configuration #f)))
    (set! configuration (status-bar-startup-result-configuration status-result))
    (when (eq? (status-bar-startup-result-status status-result) 'rejected)
      (set! effective-result-status 'rejected)
      (set! effective-observation-state 'rejected)
      (set! effective-rejected-generation (add1 effective-rejected-generation))
      (set! effective-diagnostic (status-bar-startup-result-diagnostic status-result))))
  (when (and (eq? effective-result-status 'confirmed)
             (eq? observation-state 'confirmed)
             observation)
    (define gutter-result
      (load-gutter-startup-value
       (personal-config-observation-export
        observation 'odra-gutter-configuration #f)))
    (set! gutter-configuration
          (gutter-startup-result-configuration gutter-result))
    (when (eq? (gutter-startup-result-status gutter-result) 'rejected)
      (set! effective-result-status 'rejected)
      (set! effective-observation-state 'rejected)
      (set! effective-rejected-generation (add1 effective-rejected-generation))
      (set! effective-diagnostic (gutter-startup-result-diagnostic gutter-result))))
  (when (and (eq? effective-result-status 'confirmed)
             (eq? observation-state 'confirmed)
             observation)
    (define provider-result
      (load-gutter-provider-startup-value
       (personal-config-observation-export observation 'odra-gutter-provider #f)))
    (set! gutter-provider-bytes
          (gutter-provider-startup-result-bytes provider-result))
    (when (eq? (gutter-provider-startup-result-status provider-result) 'rejected)
      (set! effective-result-status 'rejected)
      (set! effective-observation-state 'rejected)
      (set! effective-rejected-generation (add1 effective-rejected-generation))
      (set! effective-diagnostic
            (gutter-provider-startup-result-diagnostic provider-result))))
  (when (and (eq? effective-result-status 'confirmed)
             (eq? observation-state 'confirmed)
             observation)
    (define completion-result
      (load-completion-startup-value
       (personal-config-observation-export
        observation 'odra-completion-configuration #f)))
    (set! completion-configuration
          (completion-startup-result-configuration completion-result))
    (when (eq? (completion-startup-result-status completion-result) 'rejected)
      (set! effective-result-status 'rejected)
      (set! effective-observation-state 'rejected)
      (set! effective-rejected-generation (add1 effective-rejected-generation))
      (set! effective-diagnostic
            (completion-startup-result-diagnostic completion-result))))
  (define diagnostic-bytes
    (if effective-diagnostic
        (utf8 (if (string? effective-diagnostic)
                  effective-diagnostic
                  (odra-personal-config-diagnostic-message effective-diagnostic)))
        #""))
  (define terminal-configuration-bytes
    (if (eq? effective-result-status 'confirmed)
        (terminal-configuration-encode
         (terminal-configuration-runtime-pending
          (odra-personal-config-state-confirmed-generation state)))
        (terminal-configuration-encode
         (load-terminal-configuration-value #f))))
  (define ksawery-extension-bytes
    (if (eq? effective-result-status 'confirmed)
        pending-ksawery-extension-bytes
        #""))
  (define language-support-bytes
    (if (eq? effective-result-status 'confirmed)
        pending-language-support-bytes
        (language-support-configuration-encode
         (load-language-support-configuration-value #f))))
  (define recovery-configuration
    (if (and (eq? effective-result-status 'confirmed)
             (eq? observation-state 'confirmed)
             observation)
        (personal-config-observation-export
         observation 'odra-recovery-policy factory-recovery-policy)
        factory-recovery-policy))
  (define recovery-retention
    (odra-recovery-policy-retention recovery-configuration))
  (define recovery-storage
    (odra-recovery-policy-storage recovery-configuration))
  (define indentation-configuration-bytes
    (indentation-configuration-encode
     (if (and (eq? effective-result-status 'confirmed)
              (eq? observation-state 'confirmed)
              observation)
         (personal-config-observation-export
          observation
          'odra-indentation-configuration
          factory-indentation-configuration)
         factory-indentation-configuration)))
  (define total (+ header-bytes (bytes-length diagnostic-bytes)))
  (define separator-bytes
    (string->bytes/utf-8
     (odra-gutter-configuration-separator gutter-configuration)))
  (define separator-fallback-bytes
    (string->bytes/utf-8
     (odra-gutter-configuration-separator-fallback gutter-configuration)))
  (set! total (+ total (bytes-length separator-bytes)
                 (bytes-length separator-fallback-bytes)
                 (bytes-length gutter-provider-bytes)
                 (bytes-length terminal-configuration-bytes)
                 (bytes-length ksawery-extension-bytes)
                 (bytes-length language-support-bytes)
                 (bytes-length indentation-configuration-bytes)))
  (when (> total maximum-copy-bytes)
    (error 'startup-result-encode "personal configuration startup result exceeds copied storage"))
  (bytes-append
   (words schema-version
          (code result-codes effective-result-status
                'startup-result-encode)
          (code observation-codes effective-observation-state 'startup-result-encode)
          (odra-personal-config-state-confirmed-generation state)
          effective-rejected-generation
          (bytes-length diagnostic-bytes)
          (status-bar-position-code configuration)
          (status-bar-compact-code configuration)
          (status-bar-visibility-mask configuration)
          (if (odra-gutter-configuration-visible? gutter-configuration) 1 0)
          (gutter-side-code gutter-configuration)
          (+ 32768 (odra-gutter-configuration-order gutter-configuration))
          (gutter-mode-code gutter-configuration)
          (gutter-scope-code gutter-configuration)
          (gutter-current-line-code gutter-configuration)
          (odra-gutter-configuration-minimum-digits gutter-configuration)
          (odra-gutter-configuration-maximum-digits gutter-configuration)
          (odra-gutter-configuration-left-padding gutter-configuration)
          (odra-gutter-configuration-right-padding gutter-configuration)
          (bytes-length separator-bytes)
          (bytes-length separator-fallback-bytes)
          (bytes-length gutter-provider-bytes)
          (if (odra-completion-configuration-enabled? completion-configuration) 1 0)
          (completion-configuration-role-code completion-configuration 'provider)
          (completion-configuration-role-code completion-configuration 'policy)
          (completion-configuration-role-code completion-configuration 'presentation)
          (if (odra-completion-configuration-explicit? completion-configuration) 1 0)
          (if (odra-completion-configuration-identifier? completion-configuration) 1 0)
          (if (odra-completion-configuration-trigger-character? completion-configuration) 1 0)
          (odra-completion-configuration-minimum-prefix completion-configuration)
          (if (odra-completion-configuration-case-sensitive-prefix? completion-configuration) 1 0)
          (if (odra-completion-configuration-case-insensitive-prefix? completion-configuration) 1 0)
          (if (odra-completion-configuration-subsequence? completion-configuration) 1 0)
          (odra-completion-configuration-candidate-limit completion-configuration)
          (odra-completion-configuration-additional-edit-limit completion-configuration)
          (odra-completion-configuration-text-byte-limit completion-configuration)
          (odra-completion-configuration-detail-byte-limit completion-configuration)
          (odra-completion-configuration-resolve-byte-limit completion-configuration)
          (odra-completion-configuration-implementation-limit completion-configuration)
          (odra-completion-configuration-replacement-limit completion-configuration)
          (odra-completion-configuration-request-replacement-limit
           completion-configuration)
          (bytes-length terminal-configuration-bytes)
          (bytes-length ksawery-extension-bytes)
          (bytes-length language-support-bytes)
          (if (odra-recovery-policy-enabled? recovery-configuration) 1 0)
          (code recovery-strategy-codes
                (odra-recovery-policy-strategy recovery-configuration)
                'startup-result-encode)
          (odra-recovery-policy-debounce-milliseconds recovery-configuration)
          (odra-recovery-policy-maximum-interval-milliseconds recovery-configuration)
          (odra-recovery-retention-maximum-age-seconds recovery-retention)
          (odra-recovery-retention-records-per-buffer recovery-retention)
          (odra-recovery-retention-total-records recovery-retention)
          (odra-recovery-storage-limits-record-payload-bytes recovery-storage)
          (odra-recovery-storage-limits-buffer-storage-bytes recovery-storage)
          (odra-recovery-storage-limits-store-storage-bytes recovery-storage)
          (odra-recovery-storage-limits-cleanup-records recovery-storage)
          (code recovery-startup-codes
                (odra-recovery-policy-startup recovery-configuration)
                'startup-result-encode)
          (code recovery-autosave-codes
                (odra-recovery-policy-source-autosave recovery-configuration)
                'startup-result-encode)
          (bytes-length indentation-configuration-bytes))
   diagnostic-bytes
   separator-bytes
   separator-fallback-bytes
   gutter-provider-bytes
   terminal-configuration-bytes
   ksawery-extension-bytes
   language-support-bytes
   indentation-configuration-bytes))

(module+ test
  (require racket/file
           racket/list
           rackunit
           (only-in "../command/catalog.rkt"
                    odra-command-catalog-definitions
                    odra-command-definition-name)
           (only-in "personal-command-runtime.rkt"
                    personal-command-runtime-call
                    personal-command-runtime-catalog))

  (define (read-word value offset)
    (integer-bytes->integer value #f #f offset (+ offset 8)))

  (define root (make-temporary-file "odra-personal-startup-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define configuration-root (build-path root "config" "odra"))
     (define absent
       (runtime-personal-configuration-startup-batch
        (path->bytes configuration-root)))
     (check-true (car absent))
     (define absent-batch (cadr absent))
     (check-equal? (read-word absent-batch 0) schema-version)
     (check-equal? (read-word absent-batch 8) 1)
     (check-equal? (read-word absent-batch 16) 1)
     (check-equal? (read-word absent-batch 24) 2)
     (check-equal? (read-word absent-batch 40) 0)
     (check-equal? (read-word absent-batch 48) 1)
     (check-equal? (read-word absent-batch 56) 1)
     (check-equal? (read-word absent-batch 64) #x1f)
     (check-equal? (runtime-personal-configuration-root)
                   (path->string
                    (simplify-path (path->complete-path configuration-root))))

     (make-directory* configuration-root)
     (call-with-output-file (build-path configuration-root "init.rkt")
       (lambda (output)
         (display "#lang racket/base\n(define selected-theme 'night)\n" output))
       #:exists 'truncate/replace)
     (define loaded
       (runtime-personal-configuration-startup-batch
        (path->bytes configuration-root)))
     (check-true (car loaded))
     (define loaded-batch (cadr loaded))
     (define loaded-diagnostic
       (bytes->string/utf-8
        (subbytes loaded-batch header-bytes
                  (+ header-bytes (read-word loaded-batch 40)))))
     (check-equal? (read-word loaded-batch 8) 1 loaded-diagnostic)
     (check-equal? (read-word loaded-batch 16) 2 loaded-diagnostic)
     (check-equal? (read-word loaded-batch 24) 2)

     (call-with-output-file (build-path configuration-root "init.rkt")
       (lambda (output)
         (display
          (string-append
           "#lang racket/base\n"
           "(provide odra-gutter-configuration)\n"
           "(define odra-gutter-configuration\n"
           "  '#hash((visible? . #f) (side . right) (order . -2)\n"
           "         (mode . relative) (current-line . zero)\n"
           "         (minimum-digits . 3) (maximum-digits . 12)\n"
           "         (left-padding . 1) (right-padding . 2)\n"
           "         (separator . \"|\") (separator-fallback . \"!\")))\n")
          output))
       #:exists 'truncate/replace)
     (define gutter-loaded
       (runtime-personal-configuration-startup-batch
        (path->bytes configuration-root)))
     (define gutter-batch (cadr gutter-loaded))
     (check-equal? (read-word gutter-batch 72) 0)
     (check-equal? (read-word gutter-batch 80) 2)
     (check-equal? (read-word gutter-batch 88) 32766)
     (check-equal? (read-word gutter-batch 96) 3)
     (check-equal? (read-word gutter-batch 104) 1)
     (check-equal? (read-word gutter-batch 112) 2)
     (check-equal? (read-word gutter-batch 120) 3)
     (check-equal? (read-word gutter-batch 128) 12)
     (check-equal? (read-word gutter-batch 136) 1)
     (check-equal? (read-word gutter-batch 144) 2)
     (check-equal? (subbytes gutter-batch header-bytes (+ header-bytes 2)) #"|!")

     (call-with-output-file (build-path configuration-root "init.rkt")
       (lambda (output)
         (display
          (string-append
           "#lang racket/base\n"
           "(require odra/completion)\n"
           "(provide odra-completion-configuration)\n"
           "(define odra-completion-configuration\n"
           "  (completion-configuration #:identifier? #f #:minimum-prefix 3\n"
           "                            #:subsequence? #f #:candidate-limit 64))\n")
          output))
       #:exists 'truncate/replace)
     (define completion-loaded
       (runtime-personal-configuration-startup-batch
        (path->bytes configuration-root)))
     (define completion-batch (cadr completion-loaded))
     (check-equal? (read-word completion-batch 176) 1)
     (check-equal? (read-word completion-batch 184) 1)
     (check-equal? (read-word completion-batch 192) 1)
     (check-equal? (read-word completion-batch 200) 1)
     (check-equal? (read-word completion-batch 216) 0)
     (check-equal? (read-word completion-batch 232) 3)
     (check-equal? (read-word completion-batch 256) 0)
     (check-equal? (read-word completion-batch 264) 64)

     (call-with-output-file (build-path configuration-root "init.rkt")
       (lambda (output)
         (display
          (string-append
           "#lang racket/base\n"
           "(require odra/indentation)\n"
           "(provide odra-indentation-configuration)\n"
           "(define odra-indentation-configuration\n"
           "  (indentation-configuration\n"
           "   #:factory (indentation-policy #:indent-width 2 #:display-tab-width 8)\n"
           "   #:rules (list\n"
           "            (indentation-rule\n"
           "             #:scope 'language #:matcher-kind 'language #:matcher \"odin\"\n"
           "             #:policy (indentation-policy #:representation 'tabs\n"
           "                                         #:indent-width 4\n"
           "                                         #:display-tab-width 8)\n"
           "             #:source-generation 7))))\n")
          output))
       #:exists 'truncate/replace)
     (define indentation-loaded
       (runtime-personal-configuration-startup-batch
        (path->bytes configuration-root)))
     (check-true (car indentation-loaded)
                 (bytes->string/utf-8 (caddr indentation-loaded)))
     (define indentation-batch (cadr indentation-loaded))
     (define indentation-diagnostic
       (bytes->string/utf-8
        (subbytes indentation-batch header-bytes
                  (+ header-bytes (read-word indentation-batch 40)))))
     (check-equal? (read-word indentation-batch 8) 1 indentation-diagnostic)
     (check-equal? (read-word indentation-batch 16) 2 indentation-diagnostic)
     (define indentation-length (read-word indentation-batch 456))
     (define indentation-offset (- (bytes-length indentation-batch)
                                   indentation-length))
     (check-equal? indentation-length 116)
     (check-equal? (read-word indentation-batch indentation-offset) 1)
     (check-equal? (read-word indentation-batch (+ indentation-offset 8)) 2)
     (check-equal? (read-word indentation-batch (+ indentation-offset 16)) 2)
     (check-equal? (read-word indentation-batch (+ indentation-offset 24)) 8)
     (check-equal? (read-word indentation-batch (+ indentation-offset 32)) 1)
     (check-equal? (subbytes indentation-batch
                             (- (bytes-length indentation-batch) 4))
                   #"odin")

     (call-with-output-file (build-path configuration-root "init.rkt")
       (lambda (output)
         (display
          (string-append
           "#lang racket/base\n"
           "(require odra/terminal)\n"
           "(provide odra-terminal-configuration)\n"
           "(define odra-terminal-configuration\n"
           "  (terminal-configuration\n"
           "   #:global (terminal-settings #:shell \"/bin/sh\" #:attention 'visual)\n"
           "   #:workspaces (hash \"work\" (terminal-settings #:shell \"/bin/bash\"))))\n")
          output))
       #:exists 'truncate/replace)
     (define terminal-loaded
       (runtime-personal-configuration-startup-batch
        (path->bytes configuration-root)))
     (define terminal-batch (cadr terminal-loaded))
     (define terminal-offset
       (+ header-bytes
          (read-word terminal-batch 40)
          (read-word terminal-batch 152)
          (read-word terminal-batch 160)
          (read-word terminal-batch 168)))
     (check-true (> (read-word terminal-batch 328) 96))
     (check-equal? (read-word terminal-batch terminal-offset) 1)
     (check-equal? (read-word terminal-batch (+ terminal-offset 8)) 3)
     (check-equal? (read-word terminal-batch (+ terminal-offset 72))
                   (bytes-length #"/bin/sh"))
     (check-equal? (read-word terminal-batch (+ terminal-offset 80)) 1)
     (define terminal-shell-offset
       (read-word terminal-batch (+ terminal-offset 64)))
     (check-equal?
      (subbytes terminal-batch
                (+ terminal-offset terminal-shell-offset)
                (+ terminal-offset terminal-shell-offset (bytes-length #"/bin/sh")))
      #"/bin/sh")

     (call-with-output-file (build-path configuration-root "init.rkt")
       (lambda (output)
         (display "#lang racket/base\n(define broken\n" output))
       #:exists 'truncate/replace)
     (define rejected
       (runtime-personal-configuration-startup-batch
        (path->bytes configuration-root)))
     (check-true (car rejected))
     (define rejected-batch (cadr rejected))
     (check-equal? (read-word rejected-batch 8) 2)
     (check-equal? (read-word rejected-batch 16) 3)
     (check-equal? (read-word rejected-batch 24) 1)
     (check-equal? (read-word rejected-batch 32) 1)
     (check-true (> (read-word rejected-batch 40) 0)))
   (lambda () (delete-directory/files root)))

  (define (write-personal-commands configuration-root definitions)
    (make-directory* configuration-root)
    (call-with-output-file (build-path configuration-root "init.rkt")
      (lambda (output)
        (display
         (string-append
          "#lang racket/base\n"
          "(require odra/commands)\n"
          "(provide odra-personal-commands)\n"
          "(define odra-personal-commands (list " definitions "))\n")
         output))
      #:exists 'truncate/replace))

  (test-case "reload preserves active behavior on rejection"
    (define reload-root
      (make-temporary-file "odra-personal-reload-~a" 'directory))
    (dynamic-wind
     void
     (lambda ()
       (define configuration-root (build-path reload-root "config" "odra"))
       (write-personal-commands
        configuration-root
        "(make-command 'first-command (lambda (_context) 'first))")
       (define startup
         (runtime-personal-configuration-startup-batch
          (path->bytes configuration-root)))
       (define first-generation (read-word (cadr startup) 24))
       (check-equal?
        (runtime-personal-generation-transition activate-transition first-generation)
        '(#t #t #""))
       (check-eq?
        (personal-command-runtime-call
         first-generation 1 "first-command"
         (lambda (implementation) (implementation #f)))
        'first)

       (write-personal-commands
        configuration-root
        "(make-command 'second-command (lambda (_context) 'second))")
       (define reload
         (runtime-personal-configuration-reload-batch
          (path->bytes configuration-root) first-generation))
       (define second-generation (read-word (cadr reload) 24))
       (check-equal? second-generation (add1 first-generation))
       (define second-definitions
         (odra-command-catalog-definitions
          (personal-command-runtime-catalog second-generation)))
       (check-equal? (length second-definitions) 8)
       (check-equal?
        (odra-command-definition-name (last second-definitions))
        "second-command")
       (check-equal?
        (runtime-personal-generation-transition activate-transition second-generation)
        '(#t #t #""))
       (check-exn
        #rx"unavailable"
        (lambda ()
          (personal-command-runtime-call
           first-generation 1 "first-command"
           (lambda (_implementation) (void)))))
       (check-eq?
        (personal-command-runtime-call
         second-generation 1 "second-command"
         (lambda (implementation) (implementation #f)))
        'second)

       (call-with-output-file (build-path configuration-root "init.rkt")
         (lambda (output) (display "#lang racket/base\n(define broken\n" output))
         #:exists 'truncate/replace)
       (define rejected
         (runtime-personal-configuration-reload-batch
          (path->bytes configuration-root) second-generation))
       (check-equal? (read-word (cadr rejected) 8) 2)
       (check-eq?
        (personal-command-runtime-call
         second-generation 1 "second-command"
         (lambda (implementation) (implementation #f)))
        'second)

       (write-personal-commands configuration-root "")
       (define empty
         (runtime-personal-configuration-reload-batch
          (path->bytes configuration-root) second-generation))
       (define empty-generation (read-word (cadr empty) 24))
       (check-equal?
        (runtime-personal-generation-transition activate-transition empty-generation)
        '(#t #t #""))
       (check-equal?
        (length
         (odra-command-catalog-definitions
          (personal-command-runtime-catalog empty-generation)))
        7)
       (check-exn
        #rx"unavailable"
        (lambda ()
          (personal-command-runtime-call
           second-generation 1 "second-command"
           (lambda (_implementation) (void)))))

       (delete-file (build-path configuration-root "init.rkt"))
       (define absent
         (runtime-personal-configuration-reload-batch
          (path->bytes configuration-root) empty-generation))
       (check-true (car absent))
       (define absent-generation (read-word (cadr absent) 24))
       (check-equal? absent-generation (add1 empty-generation))
       (check-equal?
        (runtime-personal-generation-transition
         activate-transition absent-generation)
        '(#t #t #""))
       (check-equal?
        (length
         (odra-command-catalog-definitions
          (personal-command-runtime-catalog absent-generation)))
        7))
     (lambda ()
       (personal-command-runtime-reset!)
       (delete-directory/files reload-root)))))
