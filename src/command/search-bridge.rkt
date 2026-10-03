#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         "native-contracts.rkt"
         (prefix-in cap: "../hosting/scoped-capability.rkt"))

(provide
 (contract-out
  [search-control-session? (-> any/c boolean?)]
  [search-failure? (-> any/c boolean?)]
  [search-failure-code (-> search-failure? exact-nonnegative-integer?)]
  [call-with-search-control
   (-> exact-positive-integer? exact-positive-integer?
       (-> search-control-session? any/c) any/c)]
  [search-control-scope (-> search-control-session? bytes?)]
  [search-control-policy (-> search-control-session? bytes?)]
  [search-control-session-copy
   (->* (search-control-session?)
        (#:occurrences exact-positive-integer?
         #:captures exact-positive-integer?
         #:text-bytes exact-nonnegative-integer?)
        (or/c bytes? search-failure?))]
  [search-control-invoke!
   (->* (search-control-session? symbol?)
        (#:pattern bytes?
         #:replacement bytes?
         #:direction exact-nonnegative-integer?
         #:incremental-turn exact-nonnegative-integer?
         #:query-action exact-nonnegative-integer?
         #:query-id exact-nonnegative-integer?
         #:search-generation exact-nonnegative-integer?
         #:semantic-group exact-nonnegative-integer?
         #:scope (list/c exact-nonnegative-integer?
                         exact-nonnegative-integer?
                         exact-nonnegative-integer?
                         exact-nonnegative-integer?)
         #:policy (or/c #f bytes?)
         #:cancelled? boolean?)
        (or/c bytes? search-failure?))]))

(define (contract item) (native-contract-value 'search item))
(define scope-record-bytes (contract 'scope-record-bytes))
(define policy-record-bytes (contract 'policy-record-bytes))
(define session-header-bytes (contract 'session-header-bytes))
(define occurrence-record-bytes (contract 'occurrence-record-bytes))
(define capture-record-bytes (contract 'capture-record-bytes))
(define command-request-header-bytes (contract 'command-request-header-bytes))
(define command-policy-bytes (- policy-record-bytes scope-record-bytes))
(define command-result-record-bytes (contract 'command-result-record-bytes))
(define maximum-command-name-bytes (contract 'maximum-command-name-bytes))
(define maximum-pattern-bytes (contract 'maximum-pattern-bytes))
(define maximum-replacement-bytes (contract 'maximum-replacement-bytes))
(define maximum-occurrences (contract 'maximum-occurrences))
(define maximum-captures (contract 'maximum-captures))
(define maximum-session-text-bytes (contract 'maximum-session-text-bytes))
(define operation-scope (contract 'operation-scope))
(define operation-policy (contract 'operation-policy))
(define operation-session (contract 'operation-session))
(define operation-invoke (contract 'operation-invoke))

(struct search-control-session (capability))
(struct search-failure (code limit actual) #:transparent)

;; call-with-search-control confines one native capability to this dynamic extent.
(define (call-with-search-control generation token command)
  (cap:call-with-scoped-capability
   'search generation token
   (lambda (capability) (command (search-control-session capability)))))

;; search-control-scope returns one immutable pointer-free identity record.
(define (search-control-scope session)
  (native-invoke session operation-scope 0 0 #"" scope-record-bytes))

;; search-control-policy returns one immutable complete policy record.
(define (search-control-policy session)
  (native-invoke session operation-policy 0 0 #"" policy-record-bytes))

;; search-control-session-copy returns bounded copied arrays and text in one record.
(define (search-control-session-copy session
                                     #:occurrences [occurrences maximum-occurrences]
                                     #:captures [captures maximum-captures]
                                     #:text-bytes [text-bytes maximum-session-text-bytes])
  (when (> occurrences maximum-occurrences)
    (raise-arguments-error 'search-control-session-copy
                           "occurrence limit exceeds the supported maximum"
                           "limit" maximum-occurrences "actual" occurrences))
  (when (> captures maximum-captures)
    (raise-arguments-error 'search-control-session-copy
                           "capture limit exceeds the supported maximum"
                           "limit" maximum-captures "actual" captures))
  (when (> text-bytes maximum-session-text-bytes)
    (raise-arguments-error 'search-control-session-copy
                           "text limit exceeds the supported maximum"
                           "limit" maximum-session-text-bytes "actual" text-bytes))
  (define text-limit-record (make-bytes 8))
  (write-u64! text-limit-record 0 text-bytes)
  (native-invoke
   session operation-session occurrences captures text-limit-record
   (+ session-header-bytes
      (* occurrences occurrence-record-bytes)
      (* captures capture-record-bytes)
      text-bytes)))

;; search-control-invoke! sends one bounded copied semantic command request.
(define (search-control-invoke! session command
                                #:pattern [pattern #""]
                                #:replacement [replacement #""]
                                #:direction [direction 0]
                                #:incremental-turn [incremental-turn 0]
                                #:query-action [query-action 0]
                                #:query-id [query-id 0]
                                #:search-generation [search-generation 0]
                                #:semantic-group [semantic-group 0]
                                #:scope [scope '(0 0 0 0)]
                                #:policy [policy #f]
                                #:cancelled? [cancelled? #f])
  (let/ec return
    (define current-policy (and (not policy) (search-control-policy session)))
    (when (search-failure? current-policy) (return current-policy))
    (define policy-record
      (or policy (subbytes current-policy scope-record-bytes policy-record-bytes)))
    (unless (= (bytes-length policy-record) command-policy-bytes)
      (raise-argument-error 'search-control-invoke!
                            "a complete search policy record"
                            policy-record))
    (define command-name (string->bytes/utf-8 (symbol->string command)))
    (when (> (bytes-length command-name) maximum-command-name-bytes)
      (raise-arguments-error 'search-control-invoke!
                             "command name exceeds the supported maximum"
                             "limit" maximum-command-name-bytes))
    (when (> (bytes-length pattern) maximum-pattern-bytes)
      (raise-arguments-error 'search-control-invoke!
                             "pattern exceeds the supported maximum"
                             "limit" maximum-pattern-bytes))
    (when (> (bytes-length replacement) maximum-replacement-bytes)
      (raise-arguments-error 'search-control-invoke!
                             "replacement exceeds the supported maximum"
                             "limit" maximum-replacement-bytes))
    (define payload
      (make-bytes (+ command-request-header-bytes
                     (bytes-length command-name)
                     (bytes-length pattern)
                     (bytes-length replacement))))
    (for ([value (in-list
                  (list direction incremental-turn query-action query-id
                        search-generation semantic-group
                        (list-ref scope 0) (list-ref scope 1)
                        (list-ref scope 2) (list-ref scope 3)
                        (if cancelled? 1 0)
                        (bytes-length command-name)
                        (bytes-length pattern)
                        (bytes-length replacement)))]
          [offset (in-range 0 112 8)])
      (write-u64! payload offset value))
    (bytes-copy! payload 112 policy-record)
    (define command-end (+ command-request-header-bytes (bytes-length command-name)))
    (define pattern-end (+ command-end (bytes-length pattern)))
    (bytes-copy! payload command-request-header-bytes command-name)
    (bytes-copy! payload command-end pattern)
    (bytes-copy! payload pattern-end replacement)
    (native-invoke session operation-invoke 0 0 payload command-result-record-bytes)))

(define (native-invoke session operation arg0 arg1 input output-capacity)
  (define result
    (cap:scoped-capability-invoke
     (search-control-session-capability session)
     operation arg0 arg1 input output-capacity))
  (case (cap:scoped-capability-result-status result)
    [(0) (cap:scoped-capability-result-output result)]
    [(1)
     (search-failure
      (cap:scoped-capability-result-failure-code result)
      (cap:scoped-capability-result-limit result)
      (cap:scoped-capability-result-actual result))]
    [else (error 'search-control-invoke! "native search adapter rejected the call")]))

(define (write-u64! bytes offset value)
  (integer->integer-bytes value 8 #f #f bytes offset))

(module+ test
  (require rackunit)

  (define escaped #f)
  (call-with-search-control 1 1 (lambda (session) (set! escaped session)))
  (check-exn exn:fail:contract?
             (lambda () (search-control-scope escaped)))
  (check-equal? (bytes-length
                 (make-bytes (+ session-header-bytes
                                (* 2 occurrence-record-bytes)
                                (* 16 capture-record-bytes)
                                128)))
                1176))
