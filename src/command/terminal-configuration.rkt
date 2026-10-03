#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list)

(provide
 maximum-terminal-configuration-workspaces
 maximum-terminal-automations
 factory-terminal-operating-limits
 factory-terminal-settings
 factory-terminal-configuration
 terminal-attention-channel?
 (struct-out odra-terminal-operating-limits)
 (struct-out odra-terminal-settings)
 (struct-out odra-terminal-automation)
 (struct-out odra-terminal-configuration)
 (contract-out
  [terminal-operating-limits
   (->* ()
        (#:event-entries exact-positive-integer?
         #:event-bytes exact-positive-integer?
         #:aggregate-event-entries exact-positive-integer?
         #:aggregate-event-bytes exact-positive-integer?
         #:subscribers-per-session exact-positive-integer?
         #:subscribers exact-positive-integer?)
        odra-terminal-operating-limits?)]
  [terminal-settings
   (->* ()
        (#:shell (or/c #f string?)
         #:attention terminal-attention-channel?
         #:limits odra-terminal-operating-limits?)
        odra-terminal-settings?)]
  [terminal-automation
   (->* (symbol? (listof symbol?) procedure?)
        (#:raw-output? boolean?
         #:batch-events exact-positive-integer?
         #:batch-bytes exact-positive-integer?
         #:turn-milliseconds exact-positive-integer?
         #:temporary-memory-bytes exact-positive-integer?)
        odra-terminal-automation?)]
  [terminal-configuration
   (->* ()
        (#:global odra-terminal-settings?
         #:workspaces hash?
         #:automations (listof odra-terminal-automation?))
        odra-terminal-configuration?)]))

(define maximum-terminal-configuration-workspaces 8)
(define maximum-terminal-automations 16)
(define maximum-terminal-identity-bytes 96)
(define maximum-terminal-shell-bytes 4096)
(define maximum-terminal-event-entries 4096)
(define maximum-terminal-event-bytes (* 4 1024 1024))
(define maximum-terminal-aggregate-event-entries 32768)
(define maximum-terminal-aggregate-event-bytes (* 32 1024 1024))
(define maximum-terminal-subscribers-per-session 16)
(define maximum-terminal-subscribers 64)
(define maximum-terminal-batch-events 256)
(define maximum-terminal-batch-bytes (* 1024 1024))
(define maximum-terminal-turn-milliseconds 25)
(define maximum-terminal-temporary-memory-bytes (* 8 1024 1024))
(define admitted-attention-channels '(none audible visual both))
(define admitted-event-kinds
  '(prompt-boundary command-boundary working-context title bell result-location
                    process-exit normalized-text terminal-revision raw-output overflow))

(define (terminal-attention-channel? value)
  (and (memq value admitted-attention-channels) #t))

(define (bounded-text? value maximum)
  (and (string? value)
       (positive? (string-length value))
       (not (for/or ([character (in-string value)]) (char=? character #\nul)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(define (bounded-symbol? value)
  (and (symbol? value)
       (bounded-text? (symbol->string value) maximum-terminal-identity-bytes)))

(struct odra-terminal-operating-limits
  (event-entries event-bytes aggregate-event-entries aggregate-event-bytes
                 subscribers-per-session subscribers)
  #:transparent
  #:guard
  (lambda (event-entries event-bytes aggregate-event-entries aggregate-event-bytes
                         subscribers-per-session subscribers _)
    (unless (and (<= 64 event-entries maximum-terminal-event-entries)
                 (<= (* 64 1024) event-bytes maximum-terminal-event-bytes)
                 (<= event-entries aggregate-event-entries
                     maximum-terminal-aggregate-event-entries)
                 (<= event-bytes aggregate-event-bytes
                     maximum-terminal-aggregate-event-bytes)
                 (<= 1 subscribers-per-session
                     maximum-terminal-subscribers-per-session)
                 (<= subscribers-per-session subscribers
                     maximum-terminal-subscribers))
      (raise-arguments-error 'odra-terminal-operating-limits
                             "terminal operating limits exceed immutable bounds"))
    (values event-entries event-bytes aggregate-event-entries aggregate-event-bytes
            subscribers-per-session subscribers)))

(define factory-terminal-operating-limits
  (odra-terminal-operating-limits 1024 (* 1024 1024) 8192 (* 8 1024 1024) 8 32))

(struct odra-terminal-settings (shell attention limits)
  #:transparent
  #:guard
  (lambda (shell attention limits _)
    (unless (and (or (not shell) (bounded-text? shell maximum-terminal-shell-bytes))
                 (terminal-attention-channel? attention)
                 (odra-terminal-operating-limits? limits))
      (raise-arguments-error 'odra-terminal-settings
                             "invalid terminal settings"))
    (values (and shell (string->immutable-string shell)) attention limits)))

(define factory-terminal-settings
  (odra-terminal-settings #f 'none factory-terminal-operating-limits))

(struct odra-terminal-automation
  (name event-kinds raw-output? batch-events batch-bytes turn-milliseconds
        temporary-memory-bytes handler)
  #:transparent
  #:guard
  (lambda (name event-kinds raw-output? batch-events batch-bytes turn-milliseconds
                temporary-memory-bytes handler _)
    (unless (and (bounded-symbol? name)
                 (list? event-kinds)
                 (pair? event-kinds)
                 (andmap (lambda (kind) (memq kind admitted-event-kinds)) event-kinds)
                 (= (length event-kinds) (length (remove-duplicates event-kinds)))
                 (boolean? raw-output?)
                 (eq? raw-output? (and (memq 'raw-output event-kinds) #t))
                 (<= 1 batch-events maximum-terminal-batch-events)
                 (<= 1 batch-bytes maximum-terminal-batch-bytes)
                 (<= 1 turn-milliseconds maximum-terminal-turn-milliseconds)
                 (<= 1 temporary-memory-bytes maximum-terminal-temporary-memory-bytes)
                 (procedure? handler)
                 (procedure-arity-includes? handler 1))
      (raise-arguments-error 'odra-terminal-automation
                             "invalid named terminal automation"))
    (values name (for/list ([kind (in-list event-kinds)]) kind) raw-output?
            batch-events batch-bytes turn-milliseconds temporary-memory-bytes handler)))

(struct odra-terminal-configuration (global workspaces automations)
  #:transparent
  #:guard
  (lambda (global workspaces automations _)
    (unless (and (odra-terminal-settings? global)
                 (hash? workspaces)
                 (<= (hash-count workspaces) maximum-terminal-configuration-workspaces)
                 (for/and ([(identity settings) (in-hash workspaces)])
                   (and (bounded-text? identity maximum-terminal-identity-bytes)
                        (odra-terminal-settings? settings)))
                 (list? automations)
                 (<= (length automations) maximum-terminal-automations)
                 (andmap odra-terminal-automation? automations)
                 (= (length automations)
                    (length (remove-duplicates
                             (map odra-terminal-automation-name automations)))))
      (raise-arguments-error 'odra-terminal-configuration
                             "invalid terminal configuration"))
    (values global
            (for/hash ([(identity settings) (in-hash workspaces)])
              (values (string->immutable-string identity) settings))
            (for/list ([automation (in-list automations)]) automation))))

(define factory-terminal-configuration
  (odra-terminal-configuration factory-terminal-settings (hasheq) '()))

(define (terminal-operating-limits
         #:event-entries [event-entries 1024]
         #:event-bytes [event-bytes (* 1024 1024)]
         #:aggregate-event-entries [aggregate-event-entries 8192]
         #:aggregate-event-bytes [aggregate-event-bytes (* 8 1024 1024)]
         #:subscribers-per-session [subscribers-per-session 8]
         #:subscribers [subscribers 32])
  (odra-terminal-operating-limits
   event-entries event-bytes aggregate-event-entries aggregate-event-bytes
   subscribers-per-session subscribers))

(define (terminal-settings #:shell [shell #f]
                           #:attention [attention 'none]
                           #:limits [limits factory-terminal-operating-limits])
  (odra-terminal-settings shell attention limits))

(define (terminal-automation name event-kinds handler
                             #:raw-output? [raw-output? #f]
                             #:batch-events [batch-events 64]
                             #:batch-bytes [batch-bytes (* 256 1024)]
                             #:turn-milliseconds [turn-milliseconds 10]
                             #:temporary-memory-bytes
                             [temporary-memory-bytes (* 4 1024 1024)])
  (odra-terminal-automation
   name event-kinds raw-output? batch-events batch-bytes turn-milliseconds
   temporary-memory-bytes handler))

(define (terminal-configuration #:global [global factory-terminal-settings]
                                #:workspaces [workspaces (hasheq)]
                                #:automations [automations '()])
  (odra-terminal-configuration global workspaces automations))

(module+ test
  (require rackunit)

  (define limits (terminal-operating-limits #:event-entries 64 #:event-bytes 65536))
  (define automation
    (terminal-automation 'prompt-log '(prompt-boundary) (lambda (_events) '())))
  (define configuration
    (terminal-configuration
     #:global (terminal-settings #:shell "/bin/sh" #:attention 'visual #:limits limits)
     #:workspaces (hash "work" (terminal-settings #:shell "/bin/bash"))
     #:automations (list automation)))
  (check-equal? (hash-count (odra-terminal-configuration-workspaces configuration)) 1)
  (check-true (immutable? (odra-terminal-settings-shell
                           (odra-terminal-configuration-global configuration))))
  (check-exn exn:fail?
             (lambda () (terminal-operating-limits #:event-entries 63)))
  (check-exn exn:fail?
             (lambda ()
               (terminal-automation 'raw '(normalized-text) void #:raw-output? #t))))
