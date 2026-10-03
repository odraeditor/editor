#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         "../command/native-contracts.rkt"
         (prefix-in cap: "scoped-capability.rkt"))

(provide
 (contract-out
  [buffer-session-control? (-> any/c boolean?)]
  [buffer-session-failure? (-> any/c boolean?)]
  [buffer-session-failure-code
   (-> buffer-session-failure? exact-nonnegative-integer?)]
  [buffer-session-failure-limit
   (-> buffer-session-failure? exact-nonnegative-integer?)]
  [buffer-session-failure-actual
   (-> buffer-session-failure? exact-nonnegative-integer?)]
  [call-with-buffer-session-control
   (-> exact-positive-integer? exact-positive-integer?
       (-> buffer-session-control? any/c) any/c)]
  [buffer-session-native-invoke
   (-> buffer-session-control?
       exact-positive-integer?
       exact-nonnegative-integer?
       exact-nonnegative-integer?
       bytes?
       exact-nonnegative-integer?
       (or/c bytes? buffer-session-failure?))]))

(define (contract item) (native-contract-value 'buffer-session item))
(define scope-record-bytes (contract 'scope-record-bytes))
(define descriptor-header-bytes (contract 'descriptor-header-bytes))
(define descriptor-record-bytes (contract 'descriptor-record-bytes))
(define maximum-descriptors (contract 'maximum-descriptors))
(define maximum-label-bytes (contract 'maximum-label-bytes))
(define maximum-output-bytes
  (+ descriptor-header-bytes
     (* maximum-descriptors descriptor-record-bytes)
     maximum-label-bytes))
(define maximum-request-bytes
     (+ (contract 'request-header-bytes)
         (contract 'maximum-request-text-bytes)
         (* (contract 'maximum-marks) (contract 'mark-record-bytes))
         (* (contract 'maximum-decisions) (contract 'decision-record-bytes))
     maximum-label-bytes))
(define operation-scope (contract 'operation-scope))
(define operation-descriptors (contract 'operation-descriptors))

(struct buffer-session-control (capability))
(struct buffer-session-failure (code limit actual) #:transparent)

;; call-with-buffer-session-control confines one opaque capability to one turn.
(define (call-with-buffer-session-control generation token command)
  (cap:call-with-scoped-capability
   'buffer-session generation token
   (lambda (capability) (command (buffer-session-control capability)))))

;; buffer-session-native-invoke copies one bounded request and response.
(define (buffer-session-native-invoke control operation arg0 arg1 input output-capacity)
  (when (> output-capacity maximum-output-bytes)
    (raise-arguments-error
     'buffer-session-native-invoke
     "output capacity exceeds the supported maximum"
     "limit" maximum-output-bytes
     "actual" output-capacity))
  (when (> (bytes-length input) maximum-request-bytes)
    (raise-arguments-error
     'buffer-session-native-invoke
     "input payload exceeds the supported maximum"
     "limit" maximum-request-bytes
     "actual" (bytes-length input)))
  (define result
    (cap:scoped-capability-invoke
     (buffer-session-control-capability control)
     operation arg0 arg1 input output-capacity))
  (case (cap:scoped-capability-result-status result)
    [(0)
     (cap:scoped-capability-result-output result)]
    [(1)
     (buffer-session-failure
      (cap:scoped-capability-result-failure-code result)
      (cap:scoped-capability-result-limit result)
      (cap:scoped-capability-result-actual result))]
    [else
     (error 'buffer-session-native-invoke
            "native buffer session adapter rejected the call")]))

(define (buffer-session-scope control)
  (buffer-session-native-invoke control operation-scope 0 0 #"" scope-record-bytes))

(module+ test
  (require rackunit)

  (define escaped #f)
  (call-with-buffer-session-control
   1 1 (lambda (control) (set! escaped control)))
  (check-exn exn:fail? (lambda () (buffer-session-scope escaped)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (buffer-session-native-invoke escaped operation-scope 0 0 #""
                                   (add1 maximum-output-bytes)))))
