#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         "../command/native-contracts.rkt"
         (prefix-in cap: "scoped-capability.rkt")
         (prefix-in model: "../command/terminal.rkt")
         "terminal-event-containment.rkt"
         (only-in "../command/terminal.rkt"
                  maximum-terminal-snapshot-bytes
                  exn:fail:terminal
                  odra-terminal-exit-status
                  odra-terminal-key-action
                  odra-terminal-key-identity
                  odra-terminal-key-modifiers
                  odra-terminal-key-repeat?
                  odra-terminal-key-text
                  odra-terminal-owner-provenance
                  odra-terminal-row-range
                  odra-terminal-row-range-count
                  odra-terminal-row-range-first
                  odra-terminal-session-ref
                  odra-terminal-session-ref-generation
                  odra-terminal-session-ref-id
                  odra-terminal-session-summary
                  odra-terminal-session-summary-name
                  odra-terminal-subscription-ref-generation
                  odra-terminal-subscription-ref-id
                  odra-terminal-subscription-ref
                  odra-terminal-text-snapshot
                  terminal-sessions)
         (only-in (submod "../command/terminal.rkt" bridge)
                  call-with-terminal-context))

(provide
 (contract-out
  [terminal-control? (-> any/c boolean?)]
  [call-with-terminal-control
   (-> exact-positive-integer? exact-positive-integer?
       (-> terminal-control? any/c) any/c)]
  [call-with-native-terminal-context
   (-> exact-positive-integer? exact-positive-integer? procedure? any/c)]
  [terminal-control-dispatch
   (-> terminal-control? symbol? any/c any/c)]
  [terminal-event-handler-register!
   (-> symbol? procedure? void?)]
  [terminal-event-handler-unregister!
   (-> symbol? void?)]
  [native-terminal-turn
   (-> exact-positive-integer? exact-positive-integer? list?)]
  [native-terminal-delivery-turn
   (-> exact-positive-integer? exact-positive-integer? list?)]))

(define (contract item) (native-contract-value 'terminal item))
(define sessions-header-bytes (contract 'sessions-header-bytes))
(define session-record-bytes (contract 'session-record-bytes))
(define snapshot-record-bytes (contract 'snapshot-record-bytes))
(define key-record-bytes (contract 'key-record-bytes))
(define subscription-header-bytes (contract 'subscription-header-bytes))
(define subscription-record-bytes (contract 'subscription-record-bytes))
(define event-batch-header-bytes (contract 'event-batch-header-bytes))
(define event-record-bytes (contract 'event-record-bytes))
(define event-watermark-record-bytes (contract 'event-watermark-record-bytes))
(define maximum-inspection-bytes (contract 'maximum-inspection-bytes))
(define maximum-proposal-bytes (contract 'maximum-proposal-bytes))

(define operation-sessions (contract 'operation-sessions))
(define operation-session-state (contract 'operation-session-state))
(define operation-visible-text (contract 'operation-visible-text))
(define operation-scrollback (contract 'operation-scrollback))
(define operation-send-text (contract 'operation-send-text))
(define operation-send-key (contract 'operation-send-key))
(define operation-terminate (contract 'operation-terminate))
(define operation-subscribe (contract 'operation-subscribe))
(define operation-unsubscribe (contract 'operation-unsubscribe))
(define operation-delivery-next (contract 'operation-delivery-next))
(define operation-delivery-snapshot (contract 'operation-delivery-snapshot))
(define operation-delivery-complete (contract 'operation-delivery-complete))
(define operation-delivery-reject (contract 'operation-delivery-reject))

(define lifecycle-symbols (hash 1 'running 2 'exited 3 'failed))
(define scope-symbols (hash 1 'instance 2 'workspace))
(define owner-symbols
  (hash 1 'interactive-user 2 'task 3 'language-integration 4 'agent-integration))
(define exit-symbols (hash 1 'code 2 'signal))
(define key-codes
  (hasheq 'character 1 'enter 2 'tab 3 'backspace 4 'delete 5 'escape 6
          'up 7 'down 8 'left 9 'right 10 'home 11 'end 12 'prior 13
          'next 14 'space 15))
(define action-codes (hasheq 'press 1 'repeat 2))
(define modifier-bits (hasheq 'shift 1 'control 2 'alt 4 'super 8))
(define event-kind-bits
  (hasheq 'prompt-boundary 1 'command-boundary 2 'working-context 3
          'title 4 'bell 5 'result-location 6 'process-exit 7
          'normalized-text 8 'terminal-revision 9 'raw-output 10 'overflow 11))
(define failure-symbols
  (hash (contract 'failure-invalid) 'invalid
        (contract 'failure-stale) 'stale
        (contract 'failure-unavailable) 'unavailable
        (contract 'failure-denied) 'denied
        (contract 'failure-resource-limited) 'resource-limited
        (contract 'failure-cancelled) 'unavailable))

(struct terminal-control (capability))

(define terminal-event-handlers (make-hasheq))

;; terminal-event-handler-register! admits one explicitly named delivery handler.
(define (terminal-event-handler-register! name handler)
  (hash-set! terminal-event-handlers name handler)
  (void))

;; terminal-event-handler-unregister! removes one named handler without touching sessions.
(define (terminal-event-handler-unregister! name)
  (hash-remove! terminal-event-handlers name)
  (void))

;; call-with-terminal-control confines one terminal authority to its owner thread and turn.
(define (call-with-terminal-control generation token command)
  (cap:call-with-scoped-capability
   'terminal generation token
   (lambda (capability) (command (terminal-control capability)))))

;; call-with-native-terminal-context exposes only the public copied facade within that turn.
(define (call-with-native-terminal-context generation token command)
  (call-with-terminal-control
   generation token
   (lambda (control)
     (call-with-terminal-context
      (lambda (operation payload)
        (terminal-control-dispatch control operation payload))
      command))))

;; terminal-control-dispatch translates one public facade operation into copied records.
(define (terminal-control-dispatch control operation payload)
  (case operation
    [(sessions)
     (decode-sessions
      (invoke control operation-sessions 0 0 #"" maximum-inspection-bytes))]
    [(session-state)
     (define-values (id generation) (session-identity payload))
     (decode-summary (invoke control operation-session-state id generation #""
                             maximum-inspection-bytes)
                     0)]
    [(visible-text)
     (define-values (id generation) (session-identity payload))
     (decode-snapshot
      (invoke control operation-visible-text id generation #""
              (+ snapshot-record-bytes maximum-terminal-snapshot-bytes)))]
    [(scrollback)
     (define-values (id generation) (session-identity (car payload)))
     (define range (cdr payload))
     (define request (make-bytes 16))
     (write-u64! request 0 (odra-terminal-row-range-first range))
     (write-u64! request 8 (odra-terminal-row-range-count range))
     (decode-snapshot
      (invoke control operation-scrollback id generation request
              (+ snapshot-record-bytes maximum-terminal-snapshot-bytes)))]
    [(send-text)
     (define-values (id generation) (session-identity (car payload)))
     (invoke/void control operation-send-text id generation
                  (string->bytes/utf-8 (cdr payload)))]
    [(send-key)
     (define-values (id generation) (session-identity (car payload)))
     (invoke/void control operation-send-key id generation
                  (encode-key (cdr payload)))]
    [(terminate)
     (define-values (id generation) (session-identity payload))
     (invoke/void control operation-terminate id generation #"")]
    [(subscribe)
     (define output (invoke control operation-subscribe 0 0
                            (encode-subscription payload) 16))
     (unless (= (bytes-length output) 16)
       (raise-terminal 'invalid 0 (bytes-length output)
                       "terminal-subscribe! received an invalid subscription reference"))
     (odra-terminal-subscription-ref (read-u64 output 0) (read-u64 output 8))]
    [(unsubscribe)
     (invoke/void control operation-unsubscribe
                  (odra-terminal-subscription-ref-id payload)
                  (odra-terminal-subscription-ref-generation payload) #"")]
    [else
     (raise-terminal 'invalid 0 0 "unknown terminal facade operation")]))

(define (session-identity ref)
  (values (odra-terminal-session-ref-id ref)
          (odra-terminal-session-ref-generation ref)))

(define (invoke/void control operation arg0 arg1 input)
  (define output (invoke control operation arg0 arg1 input 0))
  (unless (zero? (bytes-length output))
    (raise-terminal 'invalid 0 (bytes-length output)
                    "terminal mutation returned an unexpected payload"))
  (void))

(define (invoke control operation arg0 arg1 input output-capacity)
  (when (> (bytes-length input) maximum-proposal-bytes)
    (raise-terminal 'resource-limited maximum-proposal-bytes (bytes-length input)
                    "terminal request exceeds the copied proposal limit"))
  (when (> output-capacity maximum-inspection-bytes)
    (raise-terminal 'resource-limited maximum-inspection-bytes output-capacity
                    "terminal request exceeds the copied inspection limit"))
  (define result
    (cap:scoped-capability-invoke
     (terminal-control-capability control)
     operation arg0 arg1 input output-capacity))
  (case (cap:scoped-capability-result-status result)
    [(0) (cap:scoped-capability-result-output result)]
    [(1)
     (define native-code (cap:scoped-capability-result-failure-code result))
     (raise-terminal
      (hash-ref failure-symbols native-code 'invalid)
      (cap:scoped-capability-result-limit result)
      (cap:scoped-capability-result-actual result)
      (if (= native-code (contract 'failure-cancelled))
          "terminal request was cancelled"
          "terminal capability rejected the request"))]
    [else
     (raise-terminal 'invalid 0 0 "native terminal adapter rejected the call")]))

(define (raise-terminal code limit actual message)
  (raise
   (exn:fail:terminal message (current-continuation-marks) code limit actual)))

(define (decode-sessions bytes)
  (unless (>= (bytes-length bytes) sessions-header-bytes)
    (raise-terminal 'invalid sessions-header-bytes (bytes-length bytes)
                    "terminal session list is truncated"))
  (define count (read-u64 bytes 0))
  (unless (and (<= count 32)
               (<= (+ sessions-header-bytes (* count session-record-bytes))
                   (bytes-length bytes)))
    (raise-terminal 'invalid 32 count "terminal session list has an invalid count"))
  (for/list ([index (in-range count)])
    (decode-summary bytes (+ sessions-header-bytes (* index session-record-bytes)))))

(define (decode-summary bytes offset)
  (unless (<= (+ offset session-record-bytes) (bytes-length bytes))
    (raise-terminal 'invalid session-record-bytes (- (bytes-length bytes) offset)
                    "terminal session summary is truncated"))
  (define ref (odra-terminal-session-ref (read-u64 bytes offset)
                                         (read-u64 bytes (+ offset 8))))
  (define lifecycle (decode-symbol lifecycle-symbols (read-u64 bytes (+ offset 16))))
  (define scope (decode-symbol scope-symbols (read-u64 bytes (+ offset 24))))
  (define activity (read-u64 bytes (+ offset 32)))
  (define exit-kind-code (read-u64 bytes (+ offset 40)))
  (define exit-value (signed-i32 (read-u64 bytes (+ offset 48))))
  (define owner-kind (decode-symbol owner-symbols (read-u64 bytes (+ offset 56))))
  (define name (decode-text bytes offset 64))
  (define workspace (optional-text (decode-text bytes offset 80)))
  (define project (optional-text (decode-text bytes offset 96)))
  (define directory (decode-text bytes offset 112))
  (define title (decode-text bytes offset 128))
  (define owner-label (decode-text bytes offset 144))
  (define exit-status
    (and (eq? lifecycle 'exited)
         (odra-terminal-exit-status
          (decode-symbol exit-symbols exit-kind-code) exit-value)))
  (odra-terminal-session-summary
   ref name lifecycle scope workspace project directory title
   (odra-terminal-owner-provenance owner-kind owner-label)
   activity exit-status))

(define (decode-snapshot bytes)
  (unless (>= (bytes-length bytes) snapshot-record-bytes)
    (raise-terminal 'invalid snapshot-record-bytes (bytes-length bytes)
                    "terminal text snapshot is truncated"))
  (define text-offset (read-u64 bytes 56))
  (define text-length (read-u64 bytes 64))
  (unless (and (= text-offset snapshot-record-bytes)
               (<= (+ text-offset text-length) (bytes-length bytes)))
    (raise-terminal 'invalid (bytes-length bytes) (+ text-offset text-length)
                    "terminal text snapshot has invalid copied storage"))
  (odra-terminal-text-snapshot
   (odra-terminal-session-ref (read-u64 bytes 0) (read-u64 bytes 8))
   (read-u64 bytes 16)
   (odra-terminal-row-range (read-u64 bytes 24) (read-u64 bytes 32))
   (copied-utf8 bytes text-offset text-length)
   (decode-boolean (read-u64 bytes 40))
   (decode-boolean (read-u64 bytes 48))))

(define (encode-key key)
  (define text (or (odra-terminal-key-text key) ""))
  (define text-bytes (string->bytes/utf-8 text))
  (define result (make-bytes (+ key-record-bytes (bytes-length text-bytes))))
  (write-u64! result 0 (hash-ref key-codes (odra-terminal-key-identity key)))
  (write-u64! result 8 (hash-ref action-codes (odra-terminal-key-action key)))
  (write-u64! result 16
              (for/sum ([modifier (in-list (odra-terminal-key-modifiers key))])
                (hash-ref modifier-bits modifier)))
  (write-u64! result 24 (if (odra-terminal-key-repeat? key) 2 1))
  (write-u64! result 32 key-record-bytes)
  (write-u64! result 40 (bytes-length text-bytes))
  (bytes-copy! result key-record-bytes text-bytes)
  result)

(define (encode-subscription definition)
  (define refs
    (model:odra-terminal-subscription-definition-session-refs definition))
  (define filters
    (model:odra-terminal-subscription-definition-filters definition))
  (define handler-value (hash-ref filters 'handler 'default))
  (define handler-name
    (if (symbol? handler-value) (symbol->string handler-value) handler-value))
  (define handler-bytes (string->bytes/utf-8 handler-name))
  (unless (<= 1 (bytes-length handler-bytes) 96)
    (raise-terminal 'invalid 96 (bytes-length handler-bytes)
                    "terminal event handler identity exceeds its native bound"))
  (define refs-bytes (* 16 (length refs)))
  (define handler-offset (+ subscription-header-bytes refs-bytes))
  (define result (make-bytes (+ handler-offset (bytes-length handler-bytes))))
  (define kind-mask
    (for/fold ([mask 0])
              ([kind (in-list
                      (model:odra-terminal-subscription-definition-event-kinds
                       definition))])
      (bitwise-ior mask
                   (arithmetic-shift 1 (hash-ref event-kind-bits kind)))))
  (for ([value
         (in-list
          (list (length refs)
                kind-mask
                (if (model:odra-terminal-subscription-definition-raw-output?
                     definition)
                    1 0)
                (model:odra-terminal-subscription-definition-batch-events definition)
                (model:odra-terminal-subscription-definition-batch-bytes definition)
                (model:odra-terminal-subscription-definition-turn-milliseconds definition)
                (model:odra-terminal-subscription-definition-temporary-memory-bytes
                 definition)
                handler-offset
                (bytes-length handler-bytes)
                subscription-header-bytes))]
        [offset (in-range 0 subscription-header-bytes 8)])
    (write-u64! result offset value))
  (for ([ref (in-list refs)]
        [offset (in-range subscription-header-bytes
                          (+ subscription-header-bytes refs-bytes) 16)])
    (write-u64! result offset (model:odra-terminal-session-ref-id ref))
    (write-u64! result (+ offset 8) (model:odra-terminal-session-ref-generation ref)))
  (bytes-copy! result handler-offset handler-bytes)
  result)

(define (decode-subscription-record bytes)
  (unless (>= (bytes-length bytes) subscription-record-bytes)
    (raise-terminal 'invalid subscription-record-bytes (bytes-length bytes)
                    "terminal subscription record is truncated"))
  (define handler-offset (read-u64 bytes 24))
  (define handler-length (read-u64 bytes 32))
  (unless (and (= handler-offset subscription-record-bytes)
               (<= (+ handler-offset handler-length) (bytes-length bytes)))
    (raise-terminal 'invalid (bytes-length bytes) (+ handler-offset handler-length)
                    "terminal subscription handler points outside copied storage"))
  (values
   (model:odra-terminal-subscription-ref (read-u64 bytes 0) (read-u64 bytes 8))
   (string->symbol (copied-utf8 bytes handler-offset handler-length))
   (read-u64 bytes 40)
   (read-u64 bytes 48)
   (read-u64 bytes 56)
   (read-u64 bytes 64)))

(define (decode-event-batch bytes subscription-ref)
  (unless (>= (bytes-length bytes) event-batch-header-bytes)
    (raise-terminal 'invalid event-batch-header-bytes (bytes-length bytes)
                    "terminal event batch is truncated"))
  (unless (and (= (read-u64 bytes 0)
                  (model:odra-terminal-subscription-ref-id subscription-ref))
               (= (read-u64 bytes 8)
                  (model:odra-terminal-subscription-ref-generation subscription-ref)))
    (raise-terminal 'stale 0 0 "terminal event batch has the wrong subscription"))
  (define event-count (read-u64 bytes 16))
  (define payload-bytes (read-u64 bytes 24))
  (define session-count (read-u64 bytes 32))
  (define watermark-offset (+ event-batch-header-bytes (* event-count event-record-bytes)))
  (unless (and (<= event-count model:maximum-terminal-subscription-batch-events)
               (<= payload-bytes model:maximum-terminal-subscription-batch-bytes)
               (<= session-count model:maximum-terminal-subscription-sessions)
               (<= (+ watermark-offset (* session-count event-watermark-record-bytes))
                   (bytes-length bytes)))
    (raise-terminal 'invalid (bytes-length bytes) watermark-offset
                    "terminal event batch has invalid copied bounds"))
  (define events
    (for/list ([index (in-range event-count)])
      (decode-event bytes (+ event-batch-header-bytes (* index event-record-bytes)))))
  (define ack (make-bytes (+ 24 (* session-count event-watermark-record-bytes))))
  (write-u64! ack 0 (model:odra-terminal-subscription-ref-id subscription-ref))
  (write-u64! ack 8 (model:odra-terminal-subscription-ref-generation subscription-ref))
  (write-u64! ack 16 session-count)
  (bytes-copy! ack 24 bytes watermark-offset
               (+ watermark-offset (* session-count event-watermark-record-bytes)))
  (values events ack))

(define (decode-event bytes offset)
  (unless (<= (+ offset event-record-bytes) (bytes-length bytes))
    (raise-terminal 'invalid event-record-bytes (- (bytes-length bytes) offset)
                    "terminal event record is truncated"))
  (define session-ref
    (model:odra-terminal-session-ref (read-u64 bytes offset)
                                     (read-u64 bytes (+ offset 8))))
  (define sequence (read-u64 bytes (+ offset 16)))
  (define kind (read-u64 bytes (+ offset 24)))
  (define provider
    (string->symbol
     (copied-segment-utf8 bytes (read-u64 bytes (+ offset 32))
                          (read-u64 bytes (+ offset 40)))))
  (define value0 (read-u64 bytes (+ offset 48)))
  (define value1 (read-u64 bytes (+ offset 56)))
  (define signed-value (signed-i32 (read-u64 bytes (+ offset 80))))
  (define flags (read-u64 bytes (+ offset 88)))
  (define payload-offset (read-u64 bytes (+ offset 96)))
  (define payload-length (read-u64 bytes (+ offset 104)))
  (define payload (copied-segment-bytes bytes payload-offset payload-length))
  (define observation
    (case kind
      [(1) (model:odra-terminal-prompt-boundary provider value0 value1)]
      [(2)
       (define phase (case value0 [(1) 'started] [(2) 'finished]
                       [else (raise-terminal 'invalid 0 value0
                                             "unknown terminal command phase")]))
       (model:odra-terminal-command-boundary
        provider phase
        (and (eq? phase 'finished) (bitwise-bit-set? flags 1)
             (model:odra-terminal-exit-status 'code signed-value)))]
      [(3)
       (model:odra-terminal-working-context-change
        provider (copied-payload-utf8 payload))]
      [(4) (model:odra-terminal-title-change provider (copied-payload-utf8 payload))]
      [(5) (model:odra-terminal-bell provider (if (= value1 1) 'audible 'visual))]
      [(6)
       (define-values (path message) (decode-location-payload payload))
       (model:odra-terminal-result-location provider path value0 value1 message)]
      [(7)
       (model:odra-terminal-process-exit
        provider
        (model:odra-terminal-exit-status
         (case value0 [(1) 'code] [(2) 'signal]
           [else (raise-terminal 'invalid 0 value0 "unknown terminal exit kind")])
         signed-value))]
      [(8)
       (model:odra-terminal-normalized-text-chunk
        provider (copied-payload-utf8 payload)
        (bitwise-bit-set? flags 1) (bitwise-bit-set? flags 2))]
      [(9) (model:odra-terminal-revision provider value0)]
      [(10)
       (model:odra-terminal-raw-output-chunk
        provider (bytes->immutable-bytes payload) (bitwise-bit-set? flags 1))]
      [(11) (model:odra-terminal-overflow provider value0 value1)]
      [else (raise-terminal 'invalid 0 kind "unknown terminal event kind")]))
  (model:odra-terminal-event session-ref sequence observation
                             (bitwise-bit-set? flags 0)))

(define (copied-segment-bytes bytes start length)
  (unless (and (<= start (bytes-length bytes))
               (<= length (- (bytes-length bytes) start)))
    (raise-terminal 'invalid (bytes-length bytes) (+ start length)
                    "terminal event points outside copied storage"))
  (subbytes bytes start (+ start length)))

(define (copied-segment-utf8 bytes start length)
  (copied-payload-utf8 (copied-segment-bytes bytes start length)))

(define (copied-payload-utf8 bytes)
  (with-handlers ([exn:fail?
                   (lambda (_failure)
                     (raise-terminal 'invalid 0 (bytes-length bytes)
                                     "terminal event contains invalid UTF-8"))])
    (string->immutable-string (bytes->string/utf-8 bytes #f))))

(define (decode-location-payload payload)
  (define separator
    (for/first ([byte (in-bytes payload)] [index (in-naturals)] #:when (zero? byte))
      index))
  (unless separator
    (raise-terminal 'invalid 0 (bytes-length payload)
                    "terminal result location lacks its message separator"))
  (values (copied-payload-utf8 (subbytes payload 0 separator))
          (copied-payload-utf8 (subbytes payload (add1 separator)))))

(define (decode-text bytes record-offset pair-offset)
  (define start (read-u64 bytes (+ record-offset pair-offset)))
  (define length (read-u64 bytes (+ record-offset pair-offset 8)))
  (unless (and (>= start (+ record-offset session-record-bytes))
               (<= (+ start length) (bytes-length bytes)))
    (raise-terminal 'invalid (bytes-length bytes) (+ start length)
                    "terminal summary text points outside copied storage"))
  (copied-utf8 bytes start length))

(define (copied-utf8 bytes start length)
  (with-handlers ([exn:fail?
                   (lambda (_failure)
                     (raise-terminal 'invalid 0 length
                                     "terminal result contains invalid UTF-8"))])
    (string->immutable-string
     (bytes->string/utf-8 (subbytes bytes start (+ start length)) #f))))

(define (decode-symbol table code)
  (hash-ref table code
            (lambda ()
              (raise-terminal 'invalid 0 code "terminal result contains an unknown enum"))))

(define (decode-boolean value)
  (case value
    [(0) #f]
    [(1) #t]
    [else (raise-terminal 'invalid 1 value "terminal result contains an invalid boolean")]))

(define (optional-text text) (and (not (string=? text "")) text))

(define (signed-i32 value)
  (if (bitwise-bit-set? value 31) (- value (expt 2 32)) value))

(define (read-u64 bytes offset)
  (integer-bytes->integer bytes #f #f offset (+ offset 8)))

(define (write-u64! bytes offset value)
  (integer->integer-bytes value 8 #f #f bytes offset)
  (void))

(define (terminal-delivery-reject! control subscription-ref)
  (invoke/void control operation-delivery-reject
               (model:odra-terminal-subscription-ref-id subscription-ref)
               (model:odra-terminal-subscription-ref-generation subscription-ref)
               #""))

(define (terminal-delivery-turn control)
  (define descriptor
    (invoke control operation-delivery-next 0 0 #""
            (+ subscription-record-bytes 96)))
  (if (zero? (bytes-length descriptor))
      (values #f "")
      (let-values ([(subscription-ref handler-name _session-count _batch-events
                                      _batch-bytes deadline-milliseconds memory-bytes)
                    (decode-subscription-record descriptor)])
        (with-handlers
            ([exn?
              (lambda (_failure)
                (terminal-delivery-reject! control subscription-ref)
                (values #f "terminal event subscriber was rejected"))])
          (define copied
            (invoke control operation-delivery-snapshot
                    (model:odra-terminal-subscription-ref-id subscription-ref)
                    (model:odra-terminal-subscription-ref-generation subscription-ref)
                    #"" maximum-inspection-bytes))
          (define-values (events acknowledgment)
            (decode-event-batch copied subscription-ref))
          (define handler (hash-ref terminal-event-handlers handler-name #f))
          (unless handler
            (raise-terminal 'unavailable 0 0
                            "terminal event handler is not registered"))
          (define outcome
            (call-with-terminal-event-handler
             (symbol->string handler-name) deadline-milliseconds memory-bytes
             handler events))
          (if (terminal-event-handler-outcome-accepted? outcome)
              (begin
                (invoke/void control operation-delivery-complete 0 0 acknowledgment)
                (values #t ""))
              (begin
                (terminal-delivery-reject! control subscription-ref)
                (values #f (terminal-event-handler-outcome-diagnostic outcome))))))))

;; native-terminal-turn exercises the production copied listing path.
(define (native-terminal-turn generation token)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #f (string->bytes/utf-8 (exn-message failure))))])
    (define sessions
      (call-with-native-terminal-context generation token
        terminal-sessions))
    (list #t sessions #"")))

;; native-terminal-delivery-turn runs at most one bounded subscriber on the owner thread.
(define (native-terminal-delivery-turn generation token)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #f (string->bytes/utf-8 (exn-message failure))))])
    (define-values (delivered? diagnostic)
      (call-with-terminal-control generation token terminal-delivery-turn))
    (list (string=? diagnostic "") delivered?
          (string->bytes/utf-8 diagnostic))))

(module+ test
  (require rackunit)

  (define key-module (dynamic-require "../command/terminal.rkt" 'terminal-key))
  (define encoded (encode-key (key-module 'character #:text "λ" #:modifiers '(control))))
  (check-equal? (read-u64 encoded 0) 1)
  (check-equal? (read-u64 encoded 16) 2)
  (check-equal? (subbytes encoded key-record-bytes) (string->bytes/utf-8 "λ"))
  (define copied-record (make-bytes (+ session-record-bytes 13)))
  (for ([value (in-list '(1 2 1 1 9 0 0 1))]
        [offset (in-range 0 64 8)])
    (write-u64! copied-record offset value))
  (define text-cursor session-record-bytes)
  (for ([text (in-list '("term" "" "" "/tmp" "" "user"))]
        [pair-offset (in-list '(64 80 96 112 128 144))])
    (define text-bytes (string->bytes/utf-8 text))
    (write-u64! copied-record pair-offset text-cursor)
    (write-u64! copied-record (+ pair-offset 8) (bytes-length text-bytes))
    (bytes-copy! copied-record text-cursor text-bytes)
    (set! text-cursor (+ text-cursor (bytes-length text-bytes))))
  (define summary (decode-summary copied-record 0))
  (bytes-set! copied-record session-record-bytes (char->integer #\X))
  (check-equal? (odra-terminal-session-summary-name summary) "term")
  (check-true (immutable? (odra-terminal-session-summary-name summary)))
  (define escaped #f)
  (call-with-terminal-control 1 1 (lambda (control) (set! escaped control)))
  (check-exn exn:fail? (lambda () (terminal-control-dispatch escaped 'sessions #f)))

  (define subscription-definition
    (model:terminal-subscription-definition
     (list (model:terminal-session-ref 3 4))
     '(normalized-text)
     #:filters (hasheq 'handler 'test-handler)
     #:batch-events 4
     #:batch-bytes 64
     #:turn-milliseconds 10
     #:temporary-memory-bytes (* 4 1024 1024)))
  (define subscription-bytes (encode-subscription subscription-definition))
  (check-equal? (read-u64 subscription-bytes 0) 1)
  (check-equal? (read-u64 subscription-bytes 8) (arithmetic-shift 1 8))
  (check-equal? (subbytes subscription-bytes (read-u64 subscription-bytes 56))
                #"test-handler")

  (define event-bytes (make-bytes 188))
  (for ([value (in-list '(1 2 1 5 1))] [offset (in-range 0 40 8)])
    (write-u64! event-bytes offset value))
  (for ([value (in-list '(3 4 1 8 176 7 0 0 0 0 0 0 183 5))]
        [offset (in-range 40 152 8)])
    (write-u64! event-bytes offset value))
  (for ([value (in-list '(3 4 1))] [offset (in-range 152 176 8)])
    (write-u64! event-bytes offset value))
  (bytes-copy! event-bytes 176 #"adapterhello")
  (define-values (decoded-events acknowledgment)
    (decode-event-batch event-bytes (model:odra-terminal-subscription-ref 1 2)))
  (check-equal? (length decoded-events) 1)
  (check-equal?
   (model:odra-terminal-normalized-text-chunk-text
    (model:odra-terminal-event-observation (car decoded-events)))
   "hello")
  (check-equal? (read-u64 acknowledgment 40) 1)

  (check-false (hash-has-key? terminal-event-handlers 'registered))
  (terminal-event-handler-register! 'registered void)
  (check-true (hash-has-key? terminal-event-handlers 'registered))
  (terminal-event-handler-unregister! 'registered)
  (check-false (hash-has-key? terminal-event-handlers 'registered)))
