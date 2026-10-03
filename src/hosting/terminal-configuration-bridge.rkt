#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         (prefix-in terminal: "../command/terminal-configuration.rkt")
         (only-in "terminal-bridge.rkt"
                  terminal-event-handler-register!
                  terminal-event-handler-unregister!))

(provide
 terminal-configuration-schema-version
 terminal-configuration-header-bytes
 terminal-workspace-configuration-record-bytes
 terminal-automation-record-bytes
 (contract-out
  [load-terminal-configuration-value
   (-> any/c terminal:odra-terminal-configuration?)]
  [terminal-configuration-encode
   (-> terminal:odra-terminal-configuration? bytes?)]
  [terminal-configuration-runtime-reset! (-> void?)]
  [terminal-configuration-runtime-prepare!
   (-> exact-positive-integer? terminal:odra-terminal-configuration? void?)]
  [terminal-configuration-runtime-activate! (-> exact-positive-integer? void?)]
  [terminal-configuration-runtime-discard! (-> exact-positive-integer? void?)]
  [terminal-configuration-runtime-pending
   (-> exact-positive-integer? terminal:odra-terminal-configuration?)]))

(define terminal-configuration-schema-version 1)
(define terminal-configuration-header-bytes 96)
(define terminal-workspace-configuration-record-bytes 88)
(define terminal-automation-record-bytes 64)
(define attention-codes (hasheq 'none 1 'audible 2 'visual 3 'both 4))
(define event-codes
  (hasheq 'prompt-boundary 1 'command-boundary 2 'working-context 3
          'title 4 'bell 5 'result-location 6 'process-exit 7
          'normalized-text 8 'terminal-revision 9 'raw-output 10 'overflow 11))

(define pending-generation #f)
(define pending-configuration #f)
(define active-handler-names '())

(define (load-terminal-configuration-value value)
  (cond
    [(not value) terminal:factory-terminal-configuration]
    [(terminal:odra-terminal-configuration? value) value]
    [else
     (raise-argument-error
      'odra-terminal-configuration "odra-terminal-configuration?" value)]))

(define (terminal-configuration-runtime-reset!)
  (for ([name (in-list active-handler-names)])
    (terminal-event-handler-unregister! name))
  (set! active-handler-names '())
  (set! pending-generation #f)
  (set! pending-configuration #f)
  (void))

(define (terminal-configuration-runtime-prepare! generation configuration)
  (when pending-generation
    (error 'terminal-configuration-runtime-prepare!
           "a terminal configuration generation is already prepared"))
  (set! pending-generation generation)
  (set! pending-configuration configuration)
  (void))

(define (terminal-configuration-runtime-activate! generation)
  (unless (and (equal? generation pending-generation) pending-configuration)
    (raise-arguments-error 'terminal-configuration-runtime-activate!
                           "terminal configuration generation is not prepared"))
  (for ([name (in-list active-handler-names)])
    (terminal-event-handler-unregister! name))
  (define automations
    (terminal:odra-terminal-configuration-automations pending-configuration))
  (for ([automation (in-list automations)])
    (terminal-event-handler-register!
     (terminal:odra-terminal-automation-name automation)
     (terminal:odra-terminal-automation-handler automation)))
  (set! active-handler-names
        (map terminal:odra-terminal-automation-name automations))
  (set! pending-generation #f)
  (set! pending-configuration #f)
  (void))

(define (terminal-configuration-runtime-discard! generation)
  (unless (equal? generation pending-generation)
    (raise-arguments-error 'terminal-configuration-runtime-discard!
                           "terminal configuration generation is not prepared"))
  (set! pending-generation #f)
  (set! pending-configuration #f)
  (void))

(define (terminal-configuration-runtime-pending generation)
  (unless (and (equal? generation pending-generation) pending-configuration)
    (raise-arguments-error 'terminal-configuration-runtime-pending
                           "terminal configuration generation is not prepared"))
  pending-configuration)

(define (terminal-configuration-encode configuration)
  (define global (terminal:odra-terminal-configuration-global configuration))
  (define workspace-identities
    (sort (hash-keys (terminal:odra-terminal-configuration-workspaces configuration))
          string<?))
  (define automations (terminal:odra-terminal-configuration-automations configuration))
  (define fixed-bytes
    (+ terminal-configuration-header-bytes
       (* (length workspace-identities) terminal-workspace-configuration-record-bytes)
       (* (length automations) terminal-automation-record-bytes)))
  (define payloads
    (append
     (list (settings-shell-bytes global))
     (append-map
      (lambda (identity)
        (list (string->bytes/utf-8 identity)
              (settings-shell-bytes
               (hash-ref (terminal:odra-terminal-configuration-workspaces configuration)
                         identity))))
      workspace-identities)
     (for/list ([automation (in-list automations)])
       (string->bytes/utf-8
        (symbol->string (terminal:odra-terminal-automation-name automation))))))
  (define total (+ fixed-bytes (for/sum ([payload (in-list payloads)])
                                 (bytes-length payload))))
  (define output (make-bytes total))
  (define cursor fixed-bytes)
  (define global-shell (car payloads))
  (write-settings! output 8 global cursor (bytes-length global-shell))
  (write-u64! output 0 terminal-configuration-schema-version)
  (write-u64! output 80 (length workspace-identities))
  (write-u64! output 88 (length automations))
  (bytes-copy! output cursor global-shell)
  (set! cursor (+ cursor (bytes-length global-shell)))
  (for ([identity (in-list workspace-identities)] [index (in-naturals)])
    (define settings
      (hash-ref (terminal:odra-terminal-configuration-workspaces configuration) identity))
    (define identity-bytes (string->bytes/utf-8 identity))
    (define shell-bytes (settings-shell-bytes settings))
    (define record-offset
      (+ terminal-configuration-header-bytes
         (* index terminal-workspace-configuration-record-bytes)))
    (write-u64! output record-offset cursor)
    (write-u64! output (+ record-offset 8) (bytes-length identity-bytes))
    (bytes-copy! output cursor identity-bytes)
    (set! cursor (+ cursor (bytes-length identity-bytes)))
    (write-settings! output (+ record-offset 16) settings cursor (bytes-length shell-bytes))
    (bytes-copy! output cursor shell-bytes)
    (set! cursor (+ cursor (bytes-length shell-bytes))))
  (define automation-base
    (+ terminal-configuration-header-bytes
       (* (length workspace-identities) terminal-workspace-configuration-record-bytes)))
  (for ([automation (in-list automations)] [index (in-naturals)])
    (define name-bytes
      (string->bytes/utf-8
       (symbol->string (terminal:odra-terminal-automation-name automation))))
    (define offset (+ automation-base (* index terminal-automation-record-bytes)))
    (write-u64! output offset cursor)
    (write-u64! output (+ offset 8) (bytes-length name-bytes))
    (write-u64! output (+ offset 16) (automation-event-mask automation))
    (write-u64! output (+ offset 24)
                (if (terminal:odra-terminal-automation-raw-output? automation) 1 0))
    (write-u64! output (+ offset 32)
                (terminal:odra-terminal-automation-batch-events automation))
    (write-u64! output (+ offset 40)
                (terminal:odra-terminal-automation-batch-bytes automation))
    (write-u64! output (+ offset 48)
                (terminal:odra-terminal-automation-turn-milliseconds automation))
    (write-u64! output (+ offset 56)
                (terminal:odra-terminal-automation-temporary-memory-bytes automation))
    (bytes-copy! output cursor name-bytes)
    (set! cursor (+ cursor (bytes-length name-bytes))))
  output)

(define (write-settings! output offset settings shell-offset shell-length)
  (define limits (terminal:odra-terminal-settings-limits settings))
  (for ([value
         (in-list
          (list (hash-ref attention-codes
                          (terminal:odra-terminal-settings-attention settings))
                (terminal:odra-terminal-operating-limits-event-entries limits)
                (terminal:odra-terminal-operating-limits-event-bytes limits)
                (terminal:odra-terminal-operating-limits-aggregate-event-entries limits)
                (terminal:odra-terminal-operating-limits-aggregate-event-bytes limits)
                (terminal:odra-terminal-operating-limits-subscribers-per-session limits)
                (terminal:odra-terminal-operating-limits-subscribers limits)
                shell-offset shell-length))]
        [word-offset (in-range offset (+ offset 72) 8)])
    (write-u64! output word-offset value)))

(define (settings-shell-bytes settings)
  (string->bytes/utf-8 (or (terminal:odra-terminal-settings-shell settings) "")))

(define (automation-event-mask automation)
  (for/fold ([mask 0])
            ([kind (in-list (terminal:odra-terminal-automation-event-kinds automation))])
    (bitwise-ior mask (arithmetic-shift 1 (hash-ref event-codes kind)))))

(define (write-u64! bytes offset value)
  (integer->integer-bytes value 8 #f #f bytes offset)
  (void))

(module+ test
  (require rackunit)

  (define configuration
    (terminal:terminal-configuration
     #:global (terminal:terminal-settings #:shell "/bin/sh" #:attention 'audible)
     #:workspaces (hash "work" (terminal:terminal-settings #:shell "/bin/bash"))
     #:automations
     (list (terminal:terminal-automation
            'prompt-log '(prompt-boundary) (lambda (_events) '())))))
  (define encoded (terminal-configuration-encode configuration))
  (check-equal? (integer-bytes->integer encoded #f #f 0 8) 1)
  (check-equal? (integer-bytes->integer encoded #f #f 80 88) 1)
  (check-equal? (integer-bytes->integer encoded #f #f 88 96) 1)
  (terminal-configuration-runtime-reset!)
  (terminal-configuration-runtime-prepare! 2 configuration)
  (check-eq? (terminal-configuration-runtime-pending 2) configuration)
  (terminal-configuration-runtime-activate! 2)
  (terminal-configuration-runtime-prepare! 3 terminal:factory-terminal-configuration)
  (terminal-configuration-runtime-discard! 3)
  (terminal-configuration-runtime-reset!))
