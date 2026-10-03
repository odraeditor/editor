#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         "native-contracts.rkt"
         (prefix-in cap: "../hosting/scoped-capability.rkt"))

(provide
 (contract-out
  [selection-snapshot? (-> any/c boolean?)]
  [selection-snapshot-point (-> selection-snapshot? exact-nonnegative-integer?)]
  [selection-snapshot-mark (-> selection-snapshot? (or/c #f exact-nonnegative-integer?))]
  [selection-snapshot-active? (-> selection-snapshot? boolean?)]
  [selection-snapshot-start (-> selection-snapshot? (or/c #f exact-nonnegative-integer?))]
  [selection-snapshot-end (-> selection-snapshot? (or/c #f exact-nonnegative-integer?))]
  [ring-entry? (-> any/c boolean?)]
  [ring-entry-id (-> ring-entry? exact-positive-integer?)]
  [ring-entry-byte-count (-> ring-entry? exact-nonnegative-integer?)]
  [ring-snapshot? (-> any/c boolean?)]
  [ring-snapshot-entries (-> ring-snapshot? list?)]
  [transfer-failure? (-> any/c boolean?)]
  [transfer-failure-code (-> transfer-failure? exact-nonnegative-integer?)]
  [call-with-text-transfer
   (-> exact-positive-integer? exact-positive-integer?
       (-> transfer-session? any/c) any/c)]
  [text-transfer-region
   (-> transfer-session? (or/c selection-snapshot? transfer-failure?))]
  [text-transfer-ring
   (->* (transfer-session?)
        (#:entries exact-nonnegative-integer?)
        (or/c ring-snapshot? transfer-failure?))]
  [text-transfer-entry-text
   (->* (transfer-session? exact-positive-integer?)
        (#:bytes exact-nonnegative-integer?)
        (or/c bytes? transfer-failure?))]
  [text-transfer-command!
   (-> transfer-session? symbol? (or/c exact-nonnegative-integer? transfer-failure?))]
  [native-transfer-turn
   (-> exact-positive-integer? exact-positive-integer? list?)]))

(define (contract item) (native-contract-value 'transfer item))
(define scope-record-bytes (contract 'scope-record-bytes))
(define region-record-bytes (contract 'region-record-bytes))
(define ring-header-bytes (contract 'ring-header-bytes))
(define ring-entry-bytes (contract 'ring-entry-bytes))
(define maximum-ring-entries (contract 'maximum-ring-entries))
(define maximum-entry-bytes (contract 'maximum-entry-bytes))
(define operation-scope (contract 'operation-scope))
(define operation-region (contract 'operation-region))
(define operation-ring (contract 'operation-ring))
(define operation-entry-text (contract 'operation-entry-text))
(define operation-invoke (contract 'operation-invoke))
(define region-mark-present 1)
(define region-active 2)
(define region-present 4)

(struct transfer-session (capability))
(struct selection-snapshot
  (scope point mark active? start end)
  #:transparent)
(struct ring-entry
  (id byte-count admission-kind coalesced-operations generation)
  #:transparent)
(struct ring-snapshot (scope entries) #:transparent)
(struct transfer-failure (code limit actual) #:transparent)

;; call-with-text-transfer bounds one opaque native capability to this dynamic extent.
(define (call-with-text-transfer generation token command)
  (cap:call-with-scoped-capability
   'transfer generation token
   (lambda (capability) (command (transfer-session capability)))))

;; text-transfer-region returns one immutable copied point, mark, and ordered range.
(define (text-transfer-region session)
  (define result
    (native-invoke session operation-region 0 0 #"" region-record-bytes))
  (if (transfer-failure? result)
      result
      (let* ([scope (decode-scope result 0)]
             [point (read-u64 result scope-record-bytes)]
             [mark-offset (read-u64 result (+ scope-record-bytes 8))]
             [start (read-u64 result (+ scope-record-bytes 16))]
             [end (read-u64 result (+ scope-record-bytes 24))]
             [flags (read-u64 result (+ scope-record-bytes 32))]
             [mark? (flag-set? flags region-mark-present)]
             [region? (flag-set? flags region-present)])
        (selection-snapshot
         scope point (and mark? mark-offset)
         (flag-set? flags region-active)
         (and region? start) (and region? end)))))

;; text-transfer-ring returns newest-to-oldest immutable entry metadata.
(define (text-transfer-ring session #:entries [entry-limit maximum-ring-entries])
  (when (> entry-limit maximum-ring-entries)
    (raise-arguments-error 'text-transfer-ring
                           "entry limit exceeds the supported maximum"
                           "limit" maximum-ring-entries
                           "actual" entry-limit))
  (define result
    (native-invoke session operation-ring entry-limit 0 #""
                   (+ ring-header-bytes (* entry-limit ring-entry-bytes))))
  (if (transfer-failure? result)
      result
      (let* ([scope (decode-scope result 0)]
             [count (read-u64 result scope-record-bytes)])
        (unless (and (<= count entry-limit)
                     (= (bytes-length result)
                        (+ ring-header-bytes (* count ring-entry-bytes))))
          (raise-result-error 'text-transfer-ring "a complete bounded ring record" result))
        (ring-snapshot
         scope
         (for/list ([index (in-range count)])
           (define base (+ ring-header-bytes (* index ring-entry-bytes)))
           (ring-entry
            (read-u64 result base)
            (read-u64 result (+ base 8))
            (read-u64 result (+ base 16))
            (read-u64 result (+ base 24))
            (read-u64 result (+ base 32))))))))

;; text-transfer-entry-text returns an authorized immutable UTF-8 byte copy.
(define (text-transfer-entry-text session entry-id #:bytes [byte-limit maximum-entry-bytes])
  (when (> byte-limit maximum-entry-bytes)
    (raise-arguments-error 'text-transfer-entry-text
                           "byte limit exceeds the supported maximum"
                           "limit" maximum-entry-bytes
                           "actual" byte-limit))
  (define result
    (native-invoke session operation-entry-text entry-id byte-limit #"" byte-limit))
  (if (transfer-failure? result) result (bytes->immutable-bytes result)))

;; text-transfer-command! invokes one admitted stable semantic command name.
(define (text-transfer-command! session command)
  (define encoded (string->bytes/utf-8 (symbol->string command)))
  (define result
    (native-invoke session operation-invoke 0 0 encoded scope-record-bytes #t))
  (if (transfer-failure? result)
      result
      (cdr result)))

;; native-transfer-turn executes one production transfer capability turn.
(define (native-transfer-turn generation token)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #f (string->bytes/utf-8 (exn-message failure))))])
    (define result (call-with-text-transfer generation token transfer-scope))
    (list #t result #"")))

(module+ test-support
  (provide transfer-session-capability
           transfer-scope
           native-invoke
           operation-scope
           scope-record-bytes))

(define (transfer-scope session)
  (native-invoke session operation-scope 0 0 #"" scope-record-bytes))

(define (native-invoke session operation arg0 arg1 input output-capacity [with-value? #f])
  (define result
    (cap:scoped-capability-invoke
     (transfer-session-capability session)
     operation arg0 arg1 input output-capacity))
  (case (cap:scoped-capability-result-status result)
    [(0)
     (define copied (cap:scoped-capability-result-output result))
     (if with-value?
         (cons copied (cap:scoped-capability-result-value result))
         copied)]
    [(1)
     (transfer-failure
      (cap:scoped-capability-result-failure-code result)
      (cap:scoped-capability-result-limit result)
      (cap:scoped-capability-result-actual result))]
    [else (error 'text-transfer-command! "native transfer adapter rejected the call")]))

(define (decode-scope bytes base)
  (unless (>= (bytes-length bytes) (+ base scope-record-bytes))
    (raise-result-error 'text-transfer "a complete scope record" bytes))
  (for/list ([offset (in-range base (+ base scope-record-bytes) 8)])
    (read-u64 bytes offset)))

(define (read-u64 bytes offset)
  (integer-bytes->integer bytes #f #f offset (+ offset 8)))

(define (flag-set? flags bit)
  (not (zero? (bitwise-and flags bit))))

(module+ test
  (require rackunit)

  (define session #f)
  (call-with-text-transfer 1 1 (lambda (current) (set! session current)))
  (check-exn exn:fail? (lambda () (transfer-scope session)))
  (check-exn exn:fail:contract?
             (lambda () (text-transfer-ring session #:entries 257)))
  (check-exn exn:fail:contract?
             (lambda () (text-transfer-entry-text session 1 #:bytes (add1 maximum-entry-bytes))))
  (check-equal? (read-u64 (integer->integer-bytes 42 8 #f #f) 0) 42)
  (check-true (flag-set? 5 region-mark-present))
  (check-false (flag-set? 5 region-active)))
