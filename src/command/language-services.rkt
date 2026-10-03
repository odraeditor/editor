#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         "../hosting/language-service-bridge.rkt"
         "native-contracts.rkt")

(provide
 (struct-out service-provider-handle)
 (struct-out service-definition-handle)
 (struct-out service-session-handle)
 (struct-out service-scope)
 (struct-out service-limits)
 (struct-out service-policy)
 (struct-out service-option)
 (struct-out service-definition)
 (struct-out service-outcome)
 (struct-out service-failure)
 (struct-out service-diagnostic-command-outcome)
 (contract-out
  [call-with-language-services
   (-> exact-positive-integer? exact-positive-integer?
       (-> language-services? any/c) any/c)]
  [language-services-scope
   (-> language-services? (or/c service-scope? service-failure?))]
  [language-services-inspect
   (-> language-services? (or/c bytes? service-failure?))]
  [language-services-propose
   (-> language-services? service-definition?
       (or/c service-outcome? service-failure?))]
  [language-services-confirm
   (-> language-services? service-definition-handle?
       (or/c service-outcome? service-failure?))]
  [language-services-select
   (-> language-services? service-definition-handle?
       (or/c service-outcome? service-failure?))]
  [language-services-disable
   (-> language-services? service-provider-handle?
       (or/c service-outcome? service-failure?))]
  [language-services-replace
   (-> language-services? service-definition-handle? service-definition?
       (or/c service-outcome? service-failure?))]
  [language-services-restore
   (-> language-services? (or/c service-outcome? service-failure?))]
  [language-services-health
   (-> language-services? service-session-handle? (or/c bytes? service-failure?))]
  [language-services-start
   (-> language-services? service-definition-handle?
       exact-positive-integer? exact-positive-integer?
       (or/c service-outcome? service-failure?))]
  [language-services-stop
   (-> language-services? service-session-handle?
       (or/c service-outcome? service-failure?))]
  [language-services-restart
   (-> language-services? service-session-handle?
       (or/c service-outcome? service-failure?))]
  [language-services-invoke-diagnostic-command
   (-> language-services? string? exact-positive-integer? exact-positive-integer?
       (or/c service-diagnostic-command-outcome? service-failure?))]))

(define (contract item) (native-contract-value 'language-service item))
(define scope-record-bytes (contract 'scope-record-bytes))
(define definition-header-bytes (contract 'definition-header-bytes))
(define selection-record-bytes (contract 'selection-record-bytes))
(define lifecycle-record-bytes (contract 'lifecycle-record-bytes))
(define text-record-bytes (contract 'text-record-bytes))
(define option-record-bytes (contract 'option-record-bytes))
(define outcome-record-bytes (contract 'outcome-record-bytes))
(define diagnostic-command-record-bytes (contract 'diagnostic-command-record-bytes))
(define diagnostic-outcome-record-bytes (contract 'diagnostic-outcome-record-bytes))
(define maximum-options (contract 'maximum-options))
(define maximum-languages (contract 'maximum-languages))
(define maximum-proposal-bytes (contract 'maximum-proposal-bytes))
(define maximum-inspection-bytes (contract 'maximum-inspection-bytes))
(define fixed-text-records (contract 'definition-fixed-text-records))

(define operation-scope (contract 'operation-scope))
(define operation-inspect (contract 'operation-inspect))
(define operation-propose (contract 'operation-propose))
(define operation-confirm (contract 'operation-confirm))
(define operation-select (contract 'operation-select))
(define operation-disable (contract 'operation-disable))
(define operation-replace (contract 'operation-replace))
(define operation-restore (contract 'operation-restore))
(define operation-start (contract 'operation-start))
(define operation-stop (contract 'operation-stop))
(define operation-restart (contract 'operation-restart))
(define operation-invoke-diagnostic-command (contract 'operation-invoke-diagnostic-command))
(define diagnostic-command-list (contract 'diagnostic-command-list))
(define diagnostic-command-next (contract 'diagnostic-command-next))
(define diagnostic-command-previous (contract 'diagnostic-command-previous))

(struct language-services (host [cached-scope #:mutable]))
(struct service-provider-handle (id generation) #:transparent)
(struct service-definition-handle (provider id generation) #:transparent)
(struct service-session-handle (id generation) #:transparent)
(struct service-scope
  (schema-version access registry-id registry-generation selection-generation
                  active-provider active-definition active-session
                  project-id project-generation membership-id
                  membership-generation trust-generation capability-generation)
  #:transparent)
(struct service-limits
  (service-definitions providers sessions documents-per-session documents-total
   executable-bytes arguments argument-bytes environment-entries environment-bytes
   root-bytes uri-bytes options-bytes frame-header-bytes json-depth message-bytes
   buffered-stream-bytes outstanding-requests notifications queue-depth queue-bytes
   synchronization-changes synchronization-bytes diagnostics-per-document
   diagnostics-per-project diagnostic-fields diagnostic-message-bytes related-locations
   diagnostic-bytes candidates candidate-text-bytes standard-error-bytes
   work-bytes-per-turn retained-bytes temporary-bytes)
  #:transparent)
(struct service-policy
  (discovery-ns initialization-ns request-ns cancellation-ns idle-step-ns
                restart-stability-ns shutdown-ns forced-termination-ns
                automatic-restarts stability-ns)
  #:transparent)
(struct service-option (key value-json) #:transparent)
(struct service-definition
  (provider-kind name executable arguments environment root-policy root
                 languages options capabilities preferred-encoding
                 preferred-synchronization limits policy)
  #:transparent)
(struct service-outcome
  (scope operation completion changed? previous-provider previous-definition
         provider definition session health retained-bytes)
  #:transparent)
(struct service-failure (code limit actual) #:transparent)
(struct service-diagnostic-command-outcome
  (scope command diagnostic-generation source-generation accepted?) #:transparent)

;; call-with-language-services confines high-level composition to one hosted turn.
(define (call-with-language-services generation token command)
  (call-with-language-service-host-control
   generation token
   (lambda (host) (command (language-services host #f)))))

;; language-services-scope returns one exact copied native scope.
(define (language-services-scope control)
  (define result (language-service-host-scope (language-services-host control)))
  (define decoded (decode-result result decode-scope))
  (when (service-scope? decoded)
    (set-language-services-cached-scope! control decoded))
  decoded)

(define (current-scope control)
  (or (language-services-cached-scope control) (language-services-scope control)))

;; language-services-inspect returns one complete copied native inspection.
(define (language-services-inspect control)
  (invoke-with-scope control operation-inspect 0 0 maximum-inspection-bytes values))

;; language-services-propose submits one complete copied inactive definition.
(define (language-services-propose control definition)
  (invoke-definition control operation-propose #f definition))

;; language-services-confirm confirms one exact proposed definition generation.
(define (language-services-confirm control handle)
  (invoke-selection control operation-confirm handle #f))

;; language-services-select selects one exact confirmed definition generation.
(define (language-services-select control handle)
  (invoke-selection control operation-select handle #f))

;; language-services-disable disables one exact provider generation.
(define (language-services-disable control provider)
  (invoke-selection control operation-disable #f provider))

;; language-services-replace atomically proposes and selects one replacement.
(define (language-services-replace control expected definition)
  (invoke-definition control operation-replace expected definition))

;; language-services-restore restores the maintained factory definition.
(define (language-services-restore control)
  (invoke-selection control operation-restore #f #f))

;; language-services-health returns copied inspection for one exact session.
(define (language-services-health control session)
  (invoke-with-scope
   control operation-inspect
   (service-session-handle-id session)
   (service-session-handle-generation session)
   maximum-inspection-bytes values))

;; language-services-start starts one exact definition for one Project membership.
(define (language-services-start control definition project-id membership-id)
  (invoke-lifecycle
   control operation-start
   (service-session-handle 0 0)
   project-id membership-id definition))

;; language-services-stop begins shutdown for one exact session.
(define (language-services-stop control session)
  (invoke-lifecycle control operation-stop session 0 0 #f))

;; language-services-restart restarts one exact failed session.
(define (language-services-restart control session)
  (invoke-lifecycle control operation-restart session 0 0 #f))

;; language-services-invoke-diagnostic-command requests one generation-checked native command.
(define (language-services-invoke-diagnostic-command
         control command-name diagnostic-generation source-generation)
  (define command
    (cond
      [(string=? command-name "list-language-diagnostics") diagnostic-command-list]
      [(string=? command-name "next-language-diagnostic") diagnostic-command-next]
      [(string=? command-name "previous-language-diagnostic") diagnostic-command-previous]
      [else
       (raise-arguments-error 'language-services-invoke-diagnostic-command
                              "unknown diagnostic command" "command" command-name)]))
  (define scope (current-scope control))
  (if (service-failure? scope)
      scope
      (let ([request (make-bytes diagnostic-command-record-bytes)])
        (bytes-copy! request 0 (encode-scope scope))
        (write-u64! request 136 command)
        (write-u64! request 144 diagnostic-generation)
        (write-u64! request 152 source-generation)
        (decode-result
         (language-service-host-invoke
          (language-services-host control) operation-invoke-diagnostic-command 0 0
          request diagnostic-outcome-record-bytes)
         decode-diagnostic-command-outcome))))

(define (invoke-with-scope control operation arg0 arg1 output-capacity decoder)
  (define scope (current-scope control))
  (if (service-failure? scope)
      scope
      (decode-result
       (language-service-host-invoke
        (language-services-host control) operation arg0 arg1
        (encode-scope scope) output-capacity)
       decoder)))

(define (invoke-selection control operation definition provider)
  (define scope (current-scope control))
  (if (service-failure? scope)
      scope
      (let ([request (make-bytes selection-record-bytes)])
        (bytes-copy! request 0 (encode-scope scope))
        (write-u64! request 136 operation)
        (when definition
          (define owner (service-definition-handle-provider definition))
          (write-u64! request 176 (service-provider-handle-id owner))
          (write-u64! request 184 (service-provider-handle-generation owner))
          (write-u64! request 192 (service-definition-handle-id definition))
          (write-u64! request 200 (service-definition-handle-generation definition)))
        (when provider
          (write-u64! request 176 (service-provider-handle-id provider))
          (write-u64! request 184 (service-provider-handle-generation provider)))
        (decode-outcome-call control operation request))))

(define (invoke-lifecycle control operation session project-id membership-id definition)
  (define scope (current-scope control))
  (if (service-failure? scope)
      scope
      (let ([request (make-bytes lifecycle-record-bytes)])
        (bytes-copy! request 0 (encode-scope scope))
        (write-u64! request 136 operation)
        (write-u64! request 144 (service-session-handle-id session))
        (write-u64! request 152 (service-session-handle-generation session))
        (write-u64! request 160 project-id)
        (write-u64! request 168 (service-scope-project-generation scope))
        (write-u64! request 176 membership-id)
        (write-u64! request 184 (service-scope-membership-generation scope))
        (when definition
          (write-u64! request 192 (service-definition-handle-id definition))
          (write-u64! request 200 (service-definition-handle-generation definition)))
        (decode-outcome-call control operation request))))

(define (invoke-definition control operation expected definition)
  (define scope (current-scope control))
  (if (service-failure? scope)
      scope
      (decode-outcome-call control operation
                           (encode-definition scope operation expected definition))))

(define (decode-outcome-call control operation request)
  (define decoded
    (decode-result
     (language-service-host-invoke
      (language-services-host control) operation 0 0 request outcome-record-bytes)
     decode-outcome))
  (when (service-outcome? decoded)
    (set-language-services-cached-scope! control (service-outcome-scope decoded)))
  decoded)

(define (decode-result result decoder)
  (cond
    [(language-service-host-failure? result)
     (service-failure
      (language-service-host-failure-code result)
      (language-service-host-failure-limit result)
      (language-service-host-failure-actual result))]
    [else (decoder result)]))

(define (encode-definition scope operation expected definition)
  (define fixed
    (list (service-definition-name definition)
          (service-definition-executable definition)
          (service-definition-root definition)))
  (define text-values
    (append fixed
            (service-definition-arguments definition)
            (service-definition-environment definition)
            (service-definition-languages definition)))
  (define options (service-definition-options definition))
  (unless (and (<= (length options) maximum-options)
               (<= (length (service-definition-languages definition)) maximum-languages))
    (raise-arguments-error 'language-services-propose
                           "definition record count exceeds native limits"))
  (define text-payload (apply bytes-append (map string->bytes/utf-8 text-values)))
  (define option-parts
    (append-map
     (lambda (option)
       (list (string->bytes/utf-8 (service-option-key option))
             (string->bytes/utf-8 (service-option-value-json option))))
     options))
  (define option-payload (apply bytes-append option-parts))
  (define record-count (length text-values))
  (define records-end
    (+ definition-header-bytes
       (* record-count text-record-bytes)
       (* (length options) option-record-bytes)))
  (define total (+ records-end (bytes-length text-payload) (bytes-length option-payload)))
  (when (> total maximum-proposal-bytes)
    (raise-arguments-error 'language-services-propose
                           "definition exceeds native proposal bytes"
                           "limit" maximum-proposal-bytes "actual" total))
  (define output (make-bytes total))
  (bytes-copy! output 0 (encode-scope scope))
  (write-u64! output 136 operation)
  (when expected
    (define owner (service-definition-handle-provider expected))
    (write-u64! output 144 (service-provider-handle-id owner))
    (write-u64! output 152 (service-provider-handle-generation owner))
    (write-u64! output 160 (service-definition-handle-id expected))
    (write-u64! output 168 (service-definition-handle-generation expected)))
  (write-u64! output 176 (service-definition-provider-kind definition))
  (write-u64! output 184 (service-definition-root-policy definition))
  (write-u64! output 192 (service-definition-preferred-encoding definition))
  (write-u64! output 200 (service-definition-preferred-synchronization definition))
  (write-u64! output 208 (service-definition-capabilities definition))
  (write-u64! output 216 (length (service-definition-arguments definition)))
  (write-u64! output 224 (length (service-definition-environment definition)))
  (write-u64! output 232 (length options))
  (write-u64! output 240 (length (service-definition-languages definition)))
  (write-u64! output 248 (bytes-length text-payload))
  (write-u64! output 256 (bytes-length option-payload))
  (encode-u64-fields! output 264 (service-limits->list (service-definition-limits definition)))
  (encode-u64-fields! output 544 (service-policy->list (service-definition-policy definition)))
  (define text-offset records-end)
  (for ([value (in-list text-values)] [index (in-naturals)])
    (define bytes (string->bytes/utf-8 value))
    (define record-offset (+ definition-header-bytes (* index text-record-bytes)))
    (write-u64! output record-offset text-offset)
    (write-u64! output (+ record-offset 8) (bytes-length bytes))
    (bytes-copy! output text-offset bytes)
    (set! text-offset (+ text-offset (bytes-length bytes))))
  (define option-offset (+ records-end (bytes-length text-payload)))
  (for ([option (in-list options)] [index (in-naturals)])
    (define key (string->bytes/utf-8 (service-option-key option)))
    (define value (string->bytes/utf-8 (service-option-value-json option)))
    (define record-offset
      (+ definition-header-bytes (* record-count text-record-bytes)
         (* index option-record-bytes)))
    (write-u64! output record-offset option-offset)
    (write-u64! output (+ record-offset 8) (bytes-length key))
    (bytes-copy! output option-offset key)
    (set! option-offset (+ option-offset (bytes-length key)))
    (write-u64! output (+ record-offset 16) option-offset)
    (write-u64! output (+ record-offset 24) (bytes-length value))
    (bytes-copy! output option-offset value)
    (set! option-offset (+ option-offset (bytes-length value))))
  output)

(define (decode-scope bytes)
  (unless (= (bytes-length bytes) scope-record-bytes)
    (error 'language-services-scope "native scope width mismatch"))
  (service-scope
   (read-u64 bytes 0) (read-u64 bytes 8) (read-u64 bytes 16) (read-u64 bytes 24)
   (read-u64 bytes 32)
   (service-provider-handle (read-u64 bytes 40) (read-u64 bytes 48))
   (service-definition-handle
    (service-provider-handle (read-u64 bytes 40) (read-u64 bytes 48))
    (read-u64 bytes 56) (read-u64 bytes 64))
   (service-session-handle (read-u64 bytes 72) (read-u64 bytes 80))
   (read-u64 bytes 88) (read-u64 bytes 96) (read-u64 bytes 104)
   (read-u64 bytes 112) (read-u64 bytes 120) (read-u64 bytes 128)))

(define (encode-scope scope)
  (define bytes (make-bytes scope-record-bytes))
  (define provider (service-scope-active-provider scope))
  (define definition (service-scope-active-definition scope))
  (define session (service-scope-active-session scope))
  (encode-u64-fields!
   bytes 0
   (list (service-scope-schema-version scope) (service-scope-access scope)
         (service-scope-registry-id scope) (service-scope-registry-generation scope)
         (service-scope-selection-generation scope)
         (service-provider-handle-id provider) (service-provider-handle-generation provider)
         (service-definition-handle-id definition)
         (service-definition-handle-generation definition)
         (service-session-handle-id session) (service-session-handle-generation session)
         (service-scope-project-id scope) (service-scope-project-generation scope)
         (service-scope-membership-id scope) (service-scope-membership-generation scope)
         (service-scope-trust-generation scope)
         (service-scope-capability-generation scope)))
  bytes)

(define (decode-outcome bytes)
  (unless (= (bytes-length bytes) outcome-record-bytes)
    (error 'language-services-outcome "native outcome width mismatch"))
  (define scope (decode-scope (subbytes bytes 0 scope-record-bytes)))
  (define previous-provider
    (service-provider-handle (read-u64 bytes 160) (read-u64 bytes 168)))
  (define previous-definition
    (service-definition-handle previous-provider (read-u64 bytes 176) (read-u64 bytes 184)))
  (define provider (service-provider-handle (read-u64 bytes 192) (read-u64 bytes 200)))
  (service-outcome
   scope (read-u64 bytes 136) (read-u64 bytes 144) (not (zero? (read-u64 bytes 152)))
   previous-provider previous-definition provider
   (service-definition-handle provider (read-u64 bytes 208) (read-u64 bytes 216))
   (service-session-handle (read-u64 bytes 224) (read-u64 bytes 232))
   (read-u64 bytes 240) (read-u64 bytes 248)))

(define (decode-diagnostic-command-outcome bytes)
  (unless (= (bytes-length bytes) diagnostic-outcome-record-bytes)
    (error 'language-services-diagnostic-command "native outcome width mismatch"))
  (service-diagnostic-command-outcome
   (decode-scope (subbytes bytes 0 scope-record-bytes))
   (read-u64 bytes 136) (read-u64 bytes 144) (read-u64 bytes 152)
   (not (zero? (read-u64 bytes 160)))))

(define (service-limits->list value)
  (list
   (service-limits-service-definitions value) (service-limits-providers value)
   (service-limits-sessions value) (service-limits-documents-per-session value)
   (service-limits-documents-total value) (service-limits-executable-bytes value)
   (service-limits-arguments value) (service-limits-argument-bytes value)
   (service-limits-environment-entries value) (service-limits-environment-bytes value)
   (service-limits-root-bytes value) (service-limits-uri-bytes value)
   (service-limits-options-bytes value) (service-limits-frame-header-bytes value)
   (service-limits-json-depth value) (service-limits-message-bytes value)
   (service-limits-buffered-stream-bytes value) (service-limits-outstanding-requests value)
   (service-limits-notifications value) (service-limits-queue-depth value)
   (service-limits-queue-bytes value) (service-limits-synchronization-changes value)
   (service-limits-synchronization-bytes value)
   (service-limits-diagnostics-per-document value)
   (service-limits-diagnostics-per-project value) (service-limits-diagnostic-fields value)
   (service-limits-diagnostic-message-bytes value) (service-limits-related-locations value)
   (service-limits-diagnostic-bytes value) (service-limits-candidates value)
   (service-limits-candidate-text-bytes value) (service-limits-standard-error-bytes value)
   (service-limits-work-bytes-per-turn value) (service-limits-retained-bytes value)
   (service-limits-temporary-bytes value)))

(define (service-policy->list value)
  (list
   (service-policy-discovery-ns value) (service-policy-initialization-ns value)
   (service-policy-request-ns value) (service-policy-cancellation-ns value)
   (service-policy-idle-step-ns value) (service-policy-restart-stability-ns value)
   (service-policy-shutdown-ns value) (service-policy-forced-termination-ns value)
   (service-policy-automatic-restarts value) (service-policy-stability-ns value)))

(define (encode-u64-fields! bytes start values)
  (for ([value (in-list values)] [index (in-naturals)])
    (write-u64! bytes (+ start (* index 8)) value)))

(define (write-u64! bytes offset value)
  (integer->integer-bytes value 8 #f #f bytes offset)
  (void))

(define (read-u64 bytes offset)
  (integer-bytes->integer bytes #f #f offset (+ offset 8)))

(module+ test
  (require rackunit)

  (define scope
    (service-scope 1 #xffff 1 2 3
                   (service-provider-handle 4 5)
                   (service-definition-handle (service-provider-handle 4 5) 6 7)
                   (service-session-handle 8 9)
                   10 11 12 13 14 15))
  (check-equal? (decode-scope (encode-scope scope)) scope)

  (define limits (apply service-limits (build-list 35 add1)))
  (define policy (apply service-policy (build-list 10 add1)))
  (define definition
    (service-definition
     3 "fixture" "fixture-server" '("--stdio") '("LC_ALL=C") 1 "/tmp/project"
     '("fixture") (list (service-option "trace" "true")) 7 2 2 limits policy))
  (define encoded (encode-definition scope operation-propose #f definition))
  (check-true (<= (bytes-length encoded) maximum-proposal-bytes))
  (check-equal? (read-u64 encoded 216) 1)
  (check-equal? (read-u64 encoded 232) 1)
  (check-equal? (read-u64 encoded 240) 1)
  (check-equal? (read-u64 encoded 264) 1)
  (check-equal? (read-u64 encoded 544) 1))
