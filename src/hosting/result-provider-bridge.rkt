#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         "../command/native-contracts.rkt"
         (prefix-in cap: "scoped-capability.rkt"))

(provide
 (struct-out result-host-failure)
 (contract-out
  [result-host-control? (-> any/c boolean?)]
  [call-with-result-host-control
   (-> exact-positive-integer? exact-positive-integer?
       (-> result-host-control? any/c) any/c)]
  [result-host-invoke
   (-> result-host-control? exact-positive-integer?
       exact-nonnegative-integer? exact-nonnegative-integer? bytes?
       exact-nonnegative-integer? (or/c bytes? result-host-failure?))]
  [result-host-scope
   (-> result-host-control? (or/c bytes? result-host-failure?))]))

(define (contract item) (native-contract-value 'result item))
(define scope-record-bytes (contract 'scope-record-bytes))
(define maximum-proposal-bytes (contract 'maximum-proposal-bytes))
(define maximum-inspection-bytes (contract 'maximum-inspection-bytes))
(define operation-scope (contract 'operation-scope))

(struct result-host-control (capability))
(struct result-host-failure (code limit actual) #:transparent)

;; call-with-result-host-control confines one opaque provider capability to one turn.
(define (call-with-result-host-control generation token command)
  (cap:call-with-scoped-capability
   'result generation token
   (lambda (capability) (command (result-host-control capability)))))

;; result-host-invoke exchanges bounded copied records only.
(define (result-host-invoke control operation arg0 arg1 input output-capacity)
  (when (> (bytes-length input) maximum-proposal-bytes)
    (raise-arguments-error
     'result-host-invoke "input exceeds the result proposal limit"
     "limit" maximum-proposal-bytes "actual" (bytes-length input)))
  (when (> output-capacity maximum-inspection-bytes)
    (raise-arguments-error
     'result-host-invoke "output exceeds the result inspection limit"
     "limit" maximum-inspection-bytes "actual" output-capacity))
  (define result
    (cap:scoped-capability-invoke
     (result-host-control-capability control)
     operation arg0 arg1 input output-capacity))
  (case (cap:scoped-capability-result-status result)
    [(0) (cap:scoped-capability-result-output result)]
    [(1)
     (result-host-failure
      (cap:scoped-capability-result-failure-code result)
      (cap:scoped-capability-result-limit result)
      (cap:scoped-capability-result-actual result))]
    [else (error 'result-host-invoke "native result adapter rejected the call")]))

;; result-host-scope copies one exact registry and set-generation identity.
(define (result-host-scope control)
  (result-host-invoke control operation-scope 0 0 #"" scope-record-bytes))

(module+ test
  (require rackunit)

  (define escaped #f)
  (call-with-result-host-control
   1 1 (lambda (control) (set! escaped control)))
  (check-exn exn:fail? (lambda () (result-host-scope escaped)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (result-host-invoke escaped operation-scope 0 0 #""
                         (add1 maximum-inspection-bytes))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (result-host-invoke escaped operation-scope 0 0
                         (make-bytes (add1 maximum-proposal-bytes)) 0))))
