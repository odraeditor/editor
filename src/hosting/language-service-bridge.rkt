#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         "../command/native-contracts.rkt"
         (prefix-in cap: "scoped-capability.rkt"))

(provide
 (struct-out language-service-host-failure)
 (contract-out
  [language-service-host-control? (-> any/c boolean?)]
  [call-with-language-service-host-control
   (-> exact-positive-integer? exact-positive-integer?
       (-> language-service-host-control? any/c) any/c)]
  [language-service-host-invoke
   (-> language-service-host-control? exact-positive-integer?
       exact-nonnegative-integer? exact-nonnegative-integer? bytes?
       exact-nonnegative-integer? (or/c bytes? language-service-host-failure?))]
  [language-service-host-scope
   (-> language-service-host-control? (or/c bytes? language-service-host-failure?))]
  [native-language-service-turn
   (-> exact-positive-integer? exact-positive-integer? list?)]))

(define (contract item) (native-contract-value 'language-service item))
(define scope-record-bytes (contract 'scope-record-bytes))
(define maximum-proposal-bytes (contract 'maximum-proposal-bytes))
(define maximum-inspection-bytes (contract 'maximum-inspection-bytes))
(define operation-scope (contract 'operation-scope))

(struct language-service-host-control (capability))
(struct language-service-host-failure (code limit actual) #:transparent)

;; call-with-language-service-host-control confines one opaque capability to one Racket turn.
(define (call-with-language-service-host-control generation token command)
  (cap:call-with-scoped-capability
   'language-service generation token
   (lambda (capability) (command (language-service-host-control capability)))))

;; language-service-host-invoke exchanges only bounded copied records with native code.
(define (language-service-host-invoke control operation arg0 arg1 input output-capacity)
  (when (> (bytes-length input) maximum-proposal-bytes)
    (raise-arguments-error
     'language-service-host-invoke "input exceeds the language-service proposal limit"
     "limit" maximum-proposal-bytes "actual" (bytes-length input)))
  (when (> output-capacity maximum-inspection-bytes)
    (raise-arguments-error
     'language-service-host-invoke "output exceeds the language-service inspection limit"
     "limit" maximum-inspection-bytes "actual" output-capacity))
  (define result
    (cap:scoped-capability-invoke
     (language-service-host-control-capability control)
     operation arg0 arg1 input output-capacity))
  (case (cap:scoped-capability-result-status result)
    [(0) (cap:scoped-capability-result-output result)]
    [(1)
     (language-service-host-failure
      (cap:scoped-capability-result-failure-code result)
      (cap:scoped-capability-result-limit result)
      (cap:scoped-capability-result-actual result))]
    [else
     (error 'language-service-host-invoke
            "native language-service adapter rejected the call")]))

;; language-service-host-scope copies one exact registry and Project identity record.
(define (language-service-host-scope control)
  (language-service-host-invoke control operation-scope 0 0 #"" scope-record-bytes))

;; native-language-service-turn executes one production service capability turn.
(define (native-language-service-turn generation token)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #f (string->bytes/utf-8 (exn-message failure))))])
    (define result
      (call-with-language-service-host-control
       generation token language-service-host-scope))
    (list #t result #"")))

(module+ test
  (require rackunit)

  (define escaped #f)
  (call-with-language-service-host-control
   1 1 (lambda (control) (set! escaped control)))
  (check-exn exn:fail? (lambda () (language-service-host-scope escaped)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (language-service-host-invoke
      escaped operation-scope 0 0 #"" (add1 maximum-inspection-bytes))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (language-service-host-invoke
      escaped operation-scope 0 0 (make-bytes (add1 maximum-proposal-bytes)) 0))))
