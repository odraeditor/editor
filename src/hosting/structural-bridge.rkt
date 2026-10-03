#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         "../command/native-contracts.rkt"
         (prefix-in cap: "scoped-capability.rkt"))

(provide
 (struct-out structural-host-failure)
 (contract-out
  [structural-host-control? (-> any/c boolean?)]
  [call-with-structural-host-control
   (-> exact-positive-integer? exact-positive-integer?
       (-> structural-host-control? any/c) any/c)]
  [structural-host-invoke
   (-> structural-host-control? exact-positive-integer?
       exact-nonnegative-integer? exact-nonnegative-integer? bytes?
       exact-nonnegative-integer? (or/c bytes? structural-host-failure?))]
  [structural-host-scope
   (-> structural-host-control? (or/c bytes? structural-host-failure?))]))

(define (contract item) (native-contract-value 'structural item))
(define scope-record-bytes (contract 'scope-record-bytes))
(define request-record-bytes (contract 'request-record-bytes))
(define maximum-inspection-bytes (contract 'maximum-inspection-bytes))
(define operation-scope (contract 'operation-scope))

(struct structural-host-control (capability))
(struct structural-host-failure (code limit actual) #:transparent)

;; call-with-structural-host-control confines one opaque capability to one Racket turn.
(define (call-with-structural-host-control generation token command)
  (cap:call-with-scoped-capability
   'structural generation token
   (lambda (capability) (command (structural-host-control capability)))))

;; structural-host-invoke exchanges only bounded copied records with native code.
(define (structural-host-invoke control operation arg0 arg1 input output-capacity)
  (when (> (bytes-length input) request-record-bytes)
    (raise-arguments-error
     'structural-host-invoke "input exceeds the structural request width"
     "limit" request-record-bytes "actual" (bytes-length input)))
  (when (> output-capacity maximum-inspection-bytes)
    (raise-arguments-error
     'structural-host-invoke "output exceeds the structural inspection limit"
     "limit" maximum-inspection-bytes "actual" output-capacity))
  (define result
    (cap:scoped-capability-invoke
     (structural-host-control-capability control)
     operation arg0 arg1 input output-capacity))
  (case (cap:scoped-capability-result-status result)
    [(0) (cap:scoped-capability-result-output result)]
    [(1)
     (structural-host-failure
      (cap:scoped-capability-result-failure-code result)
      (cap:scoped-capability-result-limit result)
      (cap:scoped-capability-result-actual result))]
    [else
     (error 'structural-host-invoke "native structural adapter rejected the call")]))

;; structural-host-scope copies one exact editor and analysis identity record.
(define (structural-host-scope control)
  (structural-host-invoke control operation-scope 0 0 #"" scope-record-bytes))

(module+ test
  (require rackunit)

  (define escaped #f)
  (call-with-structural-host-control
   1 1 (lambda (control) (set! escaped control)))
  (check-exn exn:fail? (lambda () (structural-host-scope escaped)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (structural-host-invoke
      escaped operation-scope 0 0 #"" (add1 maximum-inspection-bytes))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (structural-host-invoke
      escaped operation-scope 0 0 (make-bytes (add1 request-record-bytes)) 0))))
