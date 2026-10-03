#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         "terminal-configuration.rkt")

(provide
 maximum-terminal-sessions
 maximum-terminal-input-text-bytes
 maximum-terminal-snapshot-bytes
 maximum-terminal-metadata-bytes
 maximum-terminal-subscription-sessions
 maximum-terminal-subscription-batch-events
 maximum-terminal-subscription-batch-bytes
 maximum-terminal-subscription-turn-milliseconds
 maximum-terminal-subscription-memory-bytes
 terminal-lifecycle?
 terminal-key-identity?
 terminal-key-action?
 terminal-modifier?
 terminal-event-kind?
 terminal-failure-code?
 terminal-event-observation?
 (all-from-out "terminal-configuration.rkt")
 (struct-out odra-terminal-session-ref)
 (struct-out odra-terminal-owner-provenance)
 (struct-out odra-terminal-exit-status)
 (struct-out odra-terminal-session-summary)
 (struct-out odra-terminal-row-range)
 (struct-out odra-terminal-text-snapshot)
 (struct-out odra-terminal-key)
 (struct-out odra-terminal-subscription-definition)
 (struct-out odra-terminal-subscription-ref)
 (struct-out odra-terminal-event)
 (struct-out odra-terminal-prompt-boundary)
 (struct-out odra-terminal-command-boundary)
 (struct-out odra-terminal-working-context-change)
 (struct-out odra-terminal-title-change)
 (struct-out odra-terminal-bell)
 (struct-out odra-terminal-result-location)
 (struct-out odra-terminal-process-exit)
 (struct-out odra-terminal-normalized-text-chunk)
 (struct-out odra-terminal-revision)
 (struct-out odra-terminal-raw-output-chunk)
 (struct-out odra-terminal-overflow)
 (struct-out exn:fail:terminal)
 (contract-out
  [terminal-context? (-> any/c boolean?)]
  [terminal-session-ref
   (-> positive-u64? positive-u64?
       odra-terminal-session-ref?)]
  [terminal-row-range
   (-> u64? positive-u64?
       odra-terminal-row-range?)]
  [terminal-key
   (->* (terminal-key-identity?)
        (#:action terminal-key-action?
         #:modifiers (listof terminal-modifier?)
         #:text (or/c #f string?)
         #:repeat? boolean?)
        odra-terminal-key?)]
  [terminal-subscription-definition
   (->* ((listof odra-terminal-session-ref?)
         (listof terminal-event-kind?))
        (#:raw-output? boolean?
         #:filters hash?
         #:batch-events exact-positive-integer?
         #:batch-bytes exact-positive-integer?
         #:turn-milliseconds exact-positive-integer?
         #:temporary-memory-bytes exact-positive-integer?)
        odra-terminal-subscription-definition?)]
  [terminal-sessions
   (-> terminal-context? (listof odra-terminal-session-summary?))]
  [terminal-session-state
   (-> terminal-context? odra-terminal-session-ref?
       odra-terminal-session-summary?)]
  [terminal-visible-text
   (-> terminal-context? odra-terminal-session-ref?
       odra-terminal-text-snapshot?)]
  [terminal-scrollback
   (-> terminal-context? odra-terminal-session-ref? odra-terminal-row-range?
       odra-terminal-text-snapshot?)]
  [terminal-send-text!
   (-> terminal-context? odra-terminal-session-ref? string? void?)]
  [terminal-send-key!
   (-> terminal-context? odra-terminal-session-ref? odra-terminal-key? void?)]
  [terminal-terminate!
   (-> terminal-context? odra-terminal-session-ref? void?)]
  [terminal-subscribe!
   (-> terminal-context? odra-terminal-subscription-definition?
       odra-terminal-subscription-ref?)]
  [terminal-unsubscribe!
   (-> terminal-context? odra-terminal-subscription-ref? void?)]
  [terminal-send-return!
   (-> terminal-context? odra-terminal-session-ref? void?)]
  [terminal-send-tab!
   (-> terminal-context? odra-terminal-session-ref? void?)]
  [terminal-send-escape!
   (-> terminal-context? odra-terminal-session-ref? void?)]
  [terminal-events-of-kind
   (-> terminal-event-kind? (listof odra-terminal-event?)
       (listof odra-terminal-event?))]))

(define maximum-terminal-sessions 32)
(define maximum-terminal-input-text-bytes (* 4 1024))
(define maximum-terminal-snapshot-bytes (* 4 1024 1024))
(define maximum-terminal-metadata-bytes (* 16 1024))
(define maximum-terminal-name-bytes 96)
(define maximum-terminal-owner-label-bytes 96)
(define maximum-terminal-directory-bytes (* 4 1024))
(define maximum-terminal-subscription-sessions 32)
(define maximum-terminal-subscription-batch-events 256)
(define maximum-terminal-subscription-batch-bytes (* 1024 1024))
(define maximum-terminal-subscription-turn-milliseconds 25)
(define maximum-terminal-subscription-memory-bytes (* 8 1024 1024))
(define maximum-terminal-filter-fields 32)
(define maximum-terminal-modifiers 4)
(define maximum-u64 (sub1 (expt 2 64)))

(define (u64? value)
  (and (exact-nonnegative-integer? value) (<= value maximum-u64)))

(define (positive-u64? value)
  (and (exact-positive-integer? value) (<= value maximum-u64)))

(define terminal-lifecycles
  '(prepared starting running exited closing closed failed))
(define terminal-key-identities
  '(character enter tab backspace delete escape up down left right
              home end prior next space))
(define terminal-key-actions '(press repeat))
(define terminal-modifiers '(shift control alt super))
(define terminal-event-kinds
  '(prompt-boundary command-boundary working-context title bell result-location
                    process-exit normalized-text terminal-revision raw-output overflow))
(define terminal-failure-codes
  '(invalid stale unavailable denied resource-limited))
(define terminal-owner-kinds
  '(interactive-user task language-integration agent-integration))
(define terminal-scopes '(instance workspace))
(define terminal-exit-kinds '(code signal))
(define terminal-command-phases '(started finished))
(define terminal-bell-kinds '(audible visual))

(define (terminal-lifecycle? value) (and (memq value terminal-lifecycles) #t))
(define (terminal-key-identity? value) (and (memq value terminal-key-identities) #t))
(define (terminal-key-action? value) (and (memq value terminal-key-actions) #t))
(define (terminal-modifier? value) (and (memq value terminal-modifiers) #t))
(define (terminal-event-kind? value) (and (memq value terminal-event-kinds) #t))
(define (terminal-failure-code? value) (and (memq value terminal-failure-codes) #t))

(define (bounded-string? value maximum #:empty? [empty? #t])
  (and (string? value)
       (or empty? (positive? (string-length value)))
       (not (for/or ([character (in-string value)]) (char=? character #\nul)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(define (bounded-symbol? value maximum)
  (and (symbol? value)
       (bounded-string? (symbol->string value) maximum #:empty? #f)))

(define (copied-string who value maximum #:empty? [empty? #t])
  (unless (bounded-string? value maximum #:empty? empty?)
    (raise-arguments-error who "text is not valid within the admitted UTF-8 bound"))
  (string->immutable-string value))

(define (copied-symbol-list who values predicate maximum)
  (unless (and (list? values)
               (<= (length values) maximum)
               (andmap predicate values)
               (= (length values) (length (remove-duplicates values))))
    (raise-arguments-error who "value must be a bounded list of distinct admitted symbols"))
  (for/list ([value (in-list values)]) value))

(define (optional-identity? value)
  (or (not value)
      (bounded-string? value maximum-terminal-metadata-bytes #:empty? #f)))

(define (copied-optional-identity who value)
  (and value
       (copied-string who value maximum-terminal-metadata-bytes #:empty? #f)))

(struct terminal-context (owner-thread [state #:mutable] dispatcher))

(struct odra-terminal-session-ref (id generation)
  #:transparent
  #:guard
  (lambda (id generation _)
    (unless (and (positive-u64? id)
                 (positive-u64? generation))
      (raise-arguments-error 'odra-terminal-session-ref
                             "session identity and generation must be positive"))
    (values id generation)))

(struct odra-terminal-owner-provenance (kind label)
  #:transparent
  #:guard
  (lambda (kind label _)
    (unless (memq kind terminal-owner-kinds)
      (raise-arguments-error 'odra-terminal-owner-provenance
                             "unknown terminal owner kind"))
    (values kind
            (copied-string 'odra-terminal-owner-provenance label
                           maximum-terminal-owner-label-bytes #:empty? #f))))

(struct odra-terminal-exit-status (kind value)
  #:transparent
  #:guard
  (lambda (kind value _)
    (unless (and (memq kind terminal-exit-kinds)
                 (exact-integer? value)
                 (<= (- (expt 2 31)) value (sub1 (expt 2 31))))
      (raise-arguments-error 'odra-terminal-exit-status
                             "invalid terminal process exit status"))
    (values kind value)))

(struct odra-terminal-session-summary
  (ref name lifecycle scope workspace-id project-id working-dir title
       owner-provenance activity-sequence exit-status)
  #:transparent
  #:guard
  (lambda (ref name lifecycle scope workspace-id project-id working-dir title
               owner-provenance activity-sequence exit-status _)
    (unless (and (odra-terminal-session-ref? ref)
                 (terminal-lifecycle? lifecycle)
                 (memq scope terminal-scopes)
                 (optional-identity? workspace-id)
                 (optional-identity? project-id)
                 (if (eq? scope 'workspace) workspace-id (not workspace-id))
                 (odra-terminal-owner-provenance? owner-provenance)
                 (u64? activity-sequence)
                 (or (not exit-status) (odra-terminal-exit-status? exit-status))
                 (if (eq? lifecycle 'exited) exit-status (not exit-status)))
      (raise-arguments-error 'odra-terminal-session-summary
                             "invalid terminal session summary"))
    (values ref
            (copied-string 'odra-terminal-session-summary name
                           maximum-terminal-name-bytes #:empty? #f)
            lifecycle scope
            (copied-optional-identity 'odra-terminal-session-summary workspace-id)
            (copied-optional-identity 'odra-terminal-session-summary project-id)
            (copied-string 'odra-terminal-session-summary working-dir
                           maximum-terminal-directory-bytes #:empty? #f)
            (copied-string 'odra-terminal-session-summary title
                           maximum-terminal-metadata-bytes)
            owner-provenance activity-sequence exit-status)))

(struct odra-terminal-row-range (first count)
  #:transparent
  #:guard
  (lambda (first count _)
    (unless (and (u64? first)
                 (positive-u64? count))
      (raise-arguments-error 'odra-terminal-row-range
                             "retained row range must have a nonnegative start and positive count"))
    (values first count)))

(struct odra-terminal-text-snapshot
  (session-ref revision retained-range text leading-truncated? trailing-truncated?)
  #:transparent
  #:guard
  (lambda (session-ref revision retained-range text leading-truncated?
                       trailing-truncated? _)
    (unless (and (odra-terminal-session-ref? session-ref)
                 (u64? revision)
                 (odra-terminal-row-range? retained-range)
                 (boolean? leading-truncated?)
                 (boolean? trailing-truncated?))
      (raise-arguments-error 'odra-terminal-text-snapshot
                             "invalid terminal text snapshot"))
    (values session-ref revision retained-range
            (copied-string 'odra-terminal-text-snapshot text
                           maximum-terminal-snapshot-bytes)
            leading-truncated? trailing-truncated?)))

(struct odra-terminal-key (identity action modifiers text repeat?)
  #:transparent
  #:guard
  (lambda (identity action modifiers text repeat? _)
    (define copied-modifiers
      (copied-symbol-list 'odra-terminal-key modifiers terminal-modifier?
                          maximum-terminal-modifiers))
    (unless (and (terminal-key-identity? identity)
                 (terminal-key-action? action)
                 (or (not text)
                     (bounded-string? text maximum-terminal-input-text-bytes #:empty? #f))
                 (boolean? repeat?)
                 (eq? repeat? (eq? action 'repeat))
                 (if (eq? identity 'character) text (not text)))
      (raise-arguments-error 'odra-terminal-key "invalid normalized terminal key"))
    (values identity action copied-modifiers
            (and text (string->immutable-string text)) repeat?)))

(define (terminal-filter-value? value)
  (or (boolean? value)
      (bounded-symbol? value maximum-terminal-name-bytes)
      (u64? value)
      (and (string? value)
           (bounded-string? value maximum-terminal-metadata-bytes))))

(define (copied-filters value)
  (unless (and (hash? value)
               (<= (hash-count value) maximum-terminal-filter-fields)
               (for/and ([(key item) (in-hash value)])
                 (and (bounded-symbol? key maximum-terminal-name-bytes)
                      (terminal-filter-value? item))))
    (raise-arguments-error 'odra-terminal-subscription-definition
                           "filters must be a bounded symbol-keyed scalar hash"))
  (for/hasheq ([(key item) (in-hash value)])
    (values key (if (string? item) (string->immutable-string item) item))))

(struct odra-terminal-subscription-definition
  (session-refs event-kinds raw-output? filters batch-events batch-bytes
                turn-milliseconds temporary-memory-bytes)
  #:transparent
  #:guard
  (lambda (session-refs event-kinds raw-output? filters batch-events batch-bytes
                        turn-milliseconds temporary-memory-bytes _)
    (unless (and (list? session-refs)
                 (<= 1 (length session-refs) maximum-terminal-subscription-sessions)
                 (andmap odra-terminal-session-ref? session-refs)
                 (= (length session-refs) (length (remove-duplicates session-refs)))
                 (pair? event-kinds)
                 (boolean? raw-output?)
                 (<= 1 batch-events maximum-terminal-subscription-batch-events)
                 (<= 1 batch-bytes maximum-terminal-subscription-batch-bytes)
                 (<= 1 turn-milliseconds
                     maximum-terminal-subscription-turn-milliseconds)
                 (<= 1 temporary-memory-bytes
                     maximum-terminal-subscription-memory-bytes))
      (raise-arguments-error 'odra-terminal-subscription-definition
                             "invalid terminal subscription bounds"))
    (define copied-kinds
      (copied-symbol-list 'odra-terminal-subscription-definition event-kinds
                          terminal-event-kind? (length terminal-event-kinds)))
    (unless (eq? raw-output? (and (memq 'raw-output copied-kinds) #t))
      (raise-arguments-error 'odra-terminal-subscription-definition
                             "raw-output capability and event class must agree"))
    (values (for/list ([ref (in-list session-refs)]) ref)
            copied-kinds raw-output? (copied-filters filters)
            batch-events batch-bytes turn-milliseconds temporary-memory-bytes)))

(struct odra-terminal-subscription-ref (id generation)
  #:transparent
  #:guard
  (lambda (id generation _)
    (unless (and (positive-u64? id)
                 (positive-u64? generation))
      (raise-arguments-error 'odra-terminal-subscription-ref
                             "subscription identity and generation must be positive"))
    (values id generation)))

(define (provider? value)
  (bounded-symbol? value maximum-terminal-name-bytes))

(define (guard-provider who provider)
  (unless (provider? provider)
    (raise-arguments-error who "provider must be a bounded non-empty symbol"))
  provider)

(struct odra-terminal-prompt-boundary (provider row column)
  #:transparent
  #:guard
  (lambda (provider row column _)
    (unless (and (u64? row)
                 (u64? column))
      (raise-arguments-error 'odra-terminal-prompt-boundary
                             "invalid prompt coordinates"))
    (values (guard-provider 'odra-terminal-prompt-boundary provider) row column)))

(struct odra-terminal-command-boundary (provider phase exit-status)
  #:transparent
  #:guard
  (lambda (provider phase exit-status _)
    (unless (and (memq phase terminal-command-phases)
                 (if (eq? phase 'finished)
                     (or (not exit-status) (odra-terminal-exit-status? exit-status))
                     (not exit-status)))
      (raise-arguments-error 'odra-terminal-command-boundary
                             "invalid command boundary"))
    (values (guard-provider 'odra-terminal-command-boundary provider)
            phase exit-status)))

(struct odra-terminal-working-context-change (provider working-dir)
  #:transparent
  #:guard
  (lambda (provider working-dir _)
    (values (guard-provider 'odra-terminal-working-context-change provider)
            (copied-string 'odra-terminal-working-context-change working-dir
                           maximum-terminal-directory-bytes #:empty? #f))))

(struct odra-terminal-title-change (provider title)
  #:transparent
  #:guard
  (lambda (provider title _)
    (values (guard-provider 'odra-terminal-title-change provider)
            (copied-string 'odra-terminal-title-change title
                           maximum-terminal-metadata-bytes))))

(struct odra-terminal-bell (provider kind)
  #:transparent
  #:guard
  (lambda (provider kind _)
    (unless (memq kind terminal-bell-kinds)
      (raise-arguments-error 'odra-terminal-bell "unknown bell kind"))
    (values (guard-provider 'odra-terminal-bell provider) kind)))

(struct odra-terminal-result-location (provider path line column message)
  #:transparent
  #:guard
  (lambda (provider path line column message _)
    (unless (and (positive-u64? line)
                 (positive-u64? column))
      (raise-arguments-error 'odra-terminal-result-location
                             "result location coordinates must be positive"))
    (values (guard-provider 'odra-terminal-result-location provider)
            (copied-string 'odra-terminal-result-location path
                           maximum-terminal-directory-bytes #:empty? #f)
            line column
            (copied-string 'odra-terminal-result-location message
                           maximum-terminal-metadata-bytes))))

(struct odra-terminal-process-exit (provider status)
  #:transparent
  #:guard
  (lambda (provider status _)
    (unless (odra-terminal-exit-status? status)
      (raise-arguments-error 'odra-terminal-process-exit "invalid exit status"))
    (values (guard-provider 'odra-terminal-process-exit provider) status)))

(struct odra-terminal-normalized-text-chunk
  (provider text leading-truncated? trailing-truncated?)
  #:transparent
  #:guard
  (lambda (provider text leading-truncated? trailing-truncated? _)
    (unless (and (boolean? leading-truncated?) (boolean? trailing-truncated?))
      (raise-arguments-error 'odra-terminal-normalized-text-chunk
                             "invalid truncation flags"))
    (values (guard-provider 'odra-terminal-normalized-text-chunk provider)
            (copied-string 'odra-terminal-normalized-text-chunk text
                           maximum-terminal-subscription-batch-bytes)
            leading-truncated? trailing-truncated?)))

(struct odra-terminal-revision (provider revision)
  #:transparent
  #:guard
  (lambda (provider revision _)
    (unless (u64? revision)
      (raise-arguments-error 'odra-terminal-revision "invalid terminal revision"))
    (values (guard-provider 'odra-terminal-revision provider) revision)))

(struct odra-terminal-raw-output-chunk (provider bytes truncated?)
  #:transparent
  #:guard
  (lambda (provider bytes truncated? _)
    (unless (and (bytes? bytes)
                 (immutable? bytes)
                 (<= (bytes-length bytes) maximum-terminal-subscription-batch-bytes)
                 (boolean? truncated?))
      (raise-arguments-error 'odra-terminal-raw-output-chunk
                             "raw output must be bounded immutable bytes"))
    (values (guard-provider 'odra-terminal-raw-output-chunk provider)
            bytes truncated?)))

(struct odra-terminal-overflow (provider dropped-events dropped-bytes)
  #:transparent
  #:guard
  (lambda (provider dropped-events dropped-bytes _)
    (unless (and (positive-u64? dropped-events)
                 (u64? dropped-bytes))
      (raise-arguments-error 'odra-terminal-overflow "invalid overflow accounting"))
    (values (guard-provider 'odra-terminal-overflow provider)
            dropped-events dropped-bytes)))

(define (terminal-event-observation? value)
  (or (odra-terminal-prompt-boundary? value)
      (odra-terminal-command-boundary? value)
      (odra-terminal-working-context-change? value)
      (odra-terminal-title-change? value)
      (odra-terminal-bell? value)
      (odra-terminal-result-location? value)
      (odra-terminal-process-exit? value)
      (odra-terminal-normalized-text-chunk? value)
      (odra-terminal-revision? value)
      (odra-terminal-raw-output-chunk? value)
      (odra-terminal-overflow? value)))

(struct odra-terminal-event (session-ref sequence observation sequence-gap?)
  #:transparent
  #:guard
  (lambda (session-ref sequence observation sequence-gap? _)
    (unless (and (odra-terminal-session-ref? session-ref)
                 (positive-u64? sequence)
                 (terminal-event-observation? observation)
                 (boolean? sequence-gap?))
      (raise-arguments-error 'odra-terminal-event "invalid terminal event"))
    (values session-ref sequence observation sequence-gap?)))

(struct exn:fail:terminal exn:fail (code limit actual)
  #:transparent
  #:guard
  (lambda (message continuation-marks code limit actual _)
    (unless (and (bounded-string? message maximum-terminal-metadata-bytes #:empty? #f)
                 (continuation-mark-set? continuation-marks)
                 (terminal-failure-code? code)
                 (u64? limit)
                 (u64? actual))
      (raise-arguments-error 'exn:fail:terminal "invalid bounded terminal failure"))
    (values (string->immutable-string message) continuation-marks code limit actual)))

;; terminal-session-ref constructs one explicit generation-checked target.
(define (terminal-session-ref id generation)
  (odra-terminal-session-ref id generation))

;; terminal-row-range selects a positive bounded span of retained rows.
(define (terminal-row-range first count)
  (odra-terminal-row-range first count))

;; terminal-key constructs one normalized semantic input independent of VT bytes.
(define (terminal-key identity
                      #:action [action 'press]
                      #:modifiers [modifiers '()]
                      #:text [text #f]
                      #:repeat? [repeat? #f])
  (odra-terminal-key identity action modifiers text repeat?))

;; terminal-subscription-definition copies one explicit bounded observation policy.
(define (terminal-subscription-definition
         session-refs event-kinds
         #:raw-output? [raw-output? #f]
         #:filters [filters #hasheq()]
         #:batch-events [batch-events 64]
         #:batch-bytes [batch-bytes (* 256 1024)]
         #:turn-milliseconds [turn-milliseconds 10]
         #:temporary-memory-bytes [temporary-memory-bytes (* 4 1024 1024)])
  (odra-terminal-subscription-definition
   session-refs event-kinds raw-output? filters batch-events batch-bytes
   turn-milliseconds temporary-memory-bytes))

;; call-with-terminal-context confines bridge authority to one owner-thread turn.
(define (call-with-terminal-context dispatcher command)
  (unless (and (procedure? dispatcher)
               (procedure-arity-includes? dispatcher 2)
               (procedure? command)
               (procedure-arity-includes? command 1))
    (raise-arguments-error 'call-with-terminal-context
                           "dispatcher and command must accept two and one arguments"))
  (define context (terminal-context (current-thread) 'prepared dispatcher))
  (dynamic-wind
   (lambda ()
     (unless (eq? (terminal-context-state context) 'prepared)
       (raise-arguments-error 'call-with-terminal-context
                              "terminal context cannot be resumed"))
     (set-terminal-context-state! context 'active))
   (lambda () (command context))
   (lambda () (set-terminal-context-state! context 'closed))))

(define (ensure-context who context)
  (unless (eq? (terminal-context-owner-thread context) (current-thread))
    (raise-arguments-error who "terminal context belongs to another thread"))
  (unless (eq? (terminal-context-state context) 'active)
    (raise-arguments-error who "terminal context escaped its dynamic extent")))

(define (raise-invalid-result who result)
  (raise
   (exn:fail:terminal
    (format "~a received an invalid bounded terminal result" who)
    (current-continuation-marks) 'invalid 0 0)))

(define (terminal-dispatch context who operation payload predicate)
  (ensure-context who context)
  (define result ((terminal-context-dispatcher context) operation payload))
  (unless (predicate result) (raise-invalid-result who result))
  result)

(define (matching-summary? summary ref)
  (and (odra-terminal-session-summary? summary)
       (equal? (odra-terminal-session-summary-ref summary) ref)))

(define (matching-snapshot? snapshot ref)
  (and (odra-terminal-text-snapshot? snapshot)
       (equal? (odra-terminal-text-snapshot-session-ref snapshot) ref)))

;; terminal-sessions returns all copied session summaries visible to this context.
(define (terminal-sessions context)
  (terminal-dispatch
   context 'terminal-sessions 'sessions #f
   (lambda (result)
     (and (list? result)
          (<= (length result) maximum-terminal-sessions)
          (andmap odra-terminal-session-summary? result)
          (= (length (map odra-terminal-session-summary-ref result))
             (length (remove-duplicates
                      (map odra-terminal-session-summary-ref result))))))))

;; terminal-session-state returns one exact generation-matched copied summary.
(define (terminal-session-state context session-ref)
  (terminal-dispatch
   context 'terminal-session-state 'session-state session-ref
   (lambda (result) (matching-summary? result session-ref))))

;; terminal-visible-text returns one bounded copied snapshot of the visible grid.
(define (terminal-visible-text context session-ref)
  (terminal-dispatch
   context 'terminal-visible-text 'visible-text session-ref
   (lambda (result) (matching-snapshot? result session-ref))))

;; terminal-scrollback returns one bounded copied retained-row snapshot.
(define (terminal-scrollback context session-ref range)
  (terminal-dispatch
   context 'terminal-scrollback 'scrollback (cons session-ref range)
   (lambda (result) (matching-snapshot? result session-ref))))

;; terminal-send-text! requests literal text input without shell evaluation.
(define (terminal-send-text! context session-ref text)
  (unless (bounded-string? text maximum-terminal-input-text-bytes)
    (raise
     (exn:fail:terminal
      "terminal-send-text! rejected invalid or oversized UTF-8 text"
      (current-continuation-marks) 'invalid
      maximum-terminal-input-text-bytes
      (if (string? text) (bytes-length (string->bytes/utf-8 text)) 0))))
  (define copied
    (copied-string 'terminal-send-text! text maximum-terminal-input-text-bytes))
  (terminal-dispatch context 'terminal-send-text! 'send-text
                     (cons session-ref copied) void?)
  (void))

;; terminal-send-key! requests one normalized semantic key encoding.
(define (terminal-send-key! context session-ref key)
  (terminal-dispatch context 'terminal-send-key! 'send-key
                     (cons session-ref key) void?)
  (void))

;; terminal-terminate! requests coordinated termination of one exact session.
(define (terminal-terminate! context session-ref)
  (terminal-dispatch context 'terminal-terminate! 'terminate session-ref void?)
  (void))

;; terminal-subscribe! requests one generation-scoped bounded subscription.
(define (terminal-subscribe! context definition)
  (terminal-dispatch context 'terminal-subscribe! 'subscribe definition
                     odra-terminal-subscription-ref?))

;; terminal-unsubscribe! closes one exact subscription generation.
(define (terminal-unsubscribe! context subscription-ref)
  (terminal-dispatch context 'terminal-unsubscribe! 'unsubscribe
                     subscription-ref void?)
  (void))

;; Special-key conveniences reuse terminal-send-key! and native mode encoding.
(define (terminal-send-return! context session-ref)
  (terminal-send-key! context session-ref (terminal-key 'enter)))

(define (terminal-send-tab! context session-ref)
  (terminal-send-key! context session-ref (terminal-key 'tab)))

(define (terminal-send-escape! context session-ref)
  (terminal-send-key! context session-ref (terminal-key 'escape)))

(define (terminal-observation-kind observation)
  (cond
    [(odra-terminal-prompt-boundary? observation) 'prompt-boundary]
    [(odra-terminal-command-boundary? observation) 'command-boundary]
    [(odra-terminal-working-context-change? observation) 'working-context]
    [(odra-terminal-title-change? observation) 'title]
    [(odra-terminal-bell? observation) 'bell]
    [(odra-terminal-result-location? observation) 'result-location]
    [(odra-terminal-process-exit? observation) 'process-exit]
    [(odra-terminal-normalized-text-chunk? observation) 'normalized-text]
    [(odra-terminal-revision? observation) 'terminal-revision]
    [(odra-terminal-raw-output-chunk? observation) 'raw-output]
    [(odra-terminal-overflow? observation) 'overflow]))

;; terminal-events-of-kind returns an immutable list with one admitted event class.
(define (terminal-events-of-kind kind events)
  (for/list ([event (in-list events)]
             #:when (eq? kind
                         (terminal-observation-kind
                          (odra-terminal-event-observation event))))
    event))

(module+ bridge
  (provide call-with-terminal-context))

(module+ test
  (require rackunit)

  (define ref (terminal-session-ref 1 2))
  (define owner (odra-terminal-owner-provenance 'interactive-user "interactive user"))
  (define running
    (odra-terminal-session-summary
     ref "terminal-1" 'running 'instance #f #f "/tmp" "shell"
     owner 7 #f))
  (define snapshot
    (odra-terminal-text-snapshot
     ref 9 (terminal-row-range 0 2) "one\ntwo" #f #f))

  (test-case "public terminal values own immutable copied text"
    (define mutable-title (string-copy "shell"))
    (define summary
      (odra-terminal-session-summary
       ref "terminal-1" 'running 'instance #f #f "/tmp" mutable-title
       owner 7 #f))
    (string-set! mutable-title 0 #\X)
    (check-equal? (odra-terminal-session-summary-title summary) "shell")
    (check-true (immutable? (odra-terminal-session-summary-title summary)))
    (check-true (immutable? (odra-terminal-text-snapshot-text snapshot))))

  (test-case "guards reject stale identities and unknown enums"
    (check-exn exn:fail:contract? (lambda () (terminal-session-ref 0 1)))
    (check-exn exn:fail:contract?
               (lambda () (terminal-key 'unknown)))
    (check-exn exn:fail:contract?
               (lambda ()
                 (odra-terminal-session-summary
                  ref "terminal-1" 'unknown 'instance #f #f "/tmp" ""
                  owner 0 #f))))

  (test-case "normalized keys reject ambiguous text and repeat state"
    (check-equal? (odra-terminal-key-text (terminal-key 'character #:text "λ")) "λ")
    (check-exn exn:fail:contract?
               (lambda () (terminal-key 'character)))
    (check-exn exn:fail:contract?
               (lambda () (terminal-key 'enter #:text "\r")))
    (check-exn exn:fail:contract?
               (lambda () (terminal-key 'enter #:repeat? #t))))

  (test-case "raw output requires explicit capability and immutable bytes"
    (check-exn exn:fail:contract?
               (lambda ()
                 (terminal-subscription-definition (list ref) '(raw-output))))
    (define definition
      (terminal-subscription-definition
       (list ref) '(terminal-revision raw-output) #:raw-output? #t))
    (check-equal?
     (odra-terminal-subscription-definition-event-kinds definition)
     '(terminal-revision raw-output))
    (check-exn exn:fail:contract?
               (lambda ()
                 (odra-terminal-raw-output-chunk 'terminal (bytes 1 2 3) #f))))

  (test-case "public byte and execution limits reject oversized requests"
    (check-exn
     exn:fail:contract?
     (lambda ()
       (odra-terminal-text-snapshot
        ref 1 (terminal-row-range 0 1)
        (make-string (add1 maximum-terminal-snapshot-bytes) #\x) #f #f)))
    (check-exn
     exn:fail:contract?
     (lambda ()
       (terminal-subscription-definition
        (list ref) '(terminal-revision)
        #:batch-events (add1 maximum-terminal-subscription-batch-events))))
    (check-exn
     exn:fail:terminal?
     (lambda ()
       (call-with-terminal-context
        (lambda (_operation _payload) (void))
        (lambda (context)
          (terminal-send-text!
           context ref
           (make-string (add1 maximum-terminal-input-text-bytes) #\x)))))))

  (test-case "typed facade checks targets and copied results"
    (define calls '())
    (call-with-terminal-context
     (lambda (operation payload)
       (set! calls (cons operation calls))
       (case operation
         [(sessions) (list running)]
         [(session-state) running]
         [(visible-text scrollback) snapshot]
         [(send-text send-key terminate unsubscribe) (void)]
         [(subscribe) (odra-terminal-subscription-ref 4 5)]))
     (lambda (context)
       (check-equal? (terminal-sessions context) (list running))
       (check-equal? (terminal-session-state context ref) running)
       (check-equal? (terminal-visible-text context ref) snapshot)
       (check-equal? (terminal-scrollback context ref (terminal-row-range 0 2)) snapshot)
       (terminal-send-text! context ref "echo ok")
       (terminal-send-return! context ref)
       (terminal-terminate! context ref)
       (define subscription
         (terminal-subscribe!
          context
          (terminal-subscription-definition (list ref) '(process-exit))))
       (terminal-unsubscribe! context subscription)))
    (check-equal?
     (reverse calls)
     '(sessions session-state visible-text scrollback send-text send-key
                terminate subscribe unsubscribe)))

  (test-case "facade rejects malformed native results atomically"
    (check-exn
     exn:fail:terminal?
     (lambda ()
       (call-with-terminal-context
        (lambda (_operation _payload) (list "not a summary"))
        terminal-sessions))))

  (test-case "terminal context cannot escape its owner turn"
    (define escaped #f)
    (call-with-terminal-context
     (lambda (_operation _payload) '())
     (lambda (context) (set! escaped context)))
    (check-exn #rx"escaped its dynamic extent"
               (lambda () (terminal-sessions escaped))))

  (test-case "event variants remain closed and filterable"
    (define prompt
      (odra-terminal-event
       ref 1 (odra-terminal-prompt-boundary 'shell 4 2) #f))
    (define revision
      (odra-terminal-event
       ref 2 (odra-terminal-revision 'terminal 9) #f))
    (check-equal? (terminal-events-of-kind 'prompt-boundary
                                           (list prompt revision))
                  (list prompt))
    (check-exn exn:fail:contract?
               (lambda () (odra-terminal-event ref 0 'unknown #f))))

  (test-case "terminal failures are bounded typed exceptions"
    (define failure
      (exn:fail:terminal "stale terminal session"
                         (current-continuation-marks)
                         'stale 0 0))
    (check-true (exn:fail:terminal? failure))
    (check-equal? (exn:fail:terminal-code failure) 'stale)))
