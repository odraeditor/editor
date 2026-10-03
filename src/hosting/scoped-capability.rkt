#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (prefix-in ffi: ffi/unsafe)
         racket/promise)

(provide
 scoped-capability?
 scoped-capability-kind
 scoped-capability-generation
 scoped-capability-token
 scoped-capability-result?
 scoped-capability-result-status
 scoped-capability-result-output
 scoped-capability-result-value
 scoped-capability-result-failure-code
 scoped-capability-result-limit
 scoped-capability-result-actual
 call-with-scoped-capability
 scoped-capability-invoke
 scoped-capability-invoke/identity)

(define capability-kinds
  (hasheq 'transaction 1
          'transfer 2
          'search 3
          'buffer-session 4
          'project 5
          'layout 6
          'ui-role 7
          'theme 8
          'structural 9
          'language-service 10
          'result 11
          'status-bar 12
          'terminal 13))

(struct scoped-capability
  (kind generation token owner-thread [active? #:mutable]))
(struct scoped-capability-result
  (status output value failure-code limit actual)
  #:transparent)

(define native-call
  (delay
    (ffi:get-ffi-obj
     "odra_racket_scoped_capability_call"
     (ffi:ffi-lib #f)
     (ffi:_fun ffi:_int32 ffi:_uint64 ffi:_uint64 ffi:_int32
               ffi:_uint64 ffi:_uint64 ffi:_bytes ffi:_uint64
               ffi:_bytes ffi:_uint64 ffi:_pointer ffi:_pointer
               ffi:_pointer ffi:_pointer ffi:_pointer
               ffi:-> ffi:_int32))))

;; call-with-scoped-capability confines one native capability to its owner thread and turn.
(define (call-with-scoped-capability kind generation token command)
  (unless (hash-has-key? capability-kinds kind)
    (raise-argument-error 'call-with-scoped-capability
                          "a registered capability kind"
                          kind))
  (unless (exact-positive-integer? generation)
    (raise-argument-error 'call-with-scoped-capability
                          "an exact positive generation"
                          generation))
  (unless (exact-positive-integer? token)
    (raise-argument-error 'call-with-scoped-capability
                          "an exact positive token"
                          token))
  (define capability
    (scoped-capability kind generation token (current-thread) #t))
  (dynamic-wind
   void
   (lambda () (command capability))
   (lambda () (set-scoped-capability-active?! capability #f))))

;; scoped-capability-invoke exchanges one fixed result envelope and bounded byte payload.
(define (scoped-capability-invoke capability operation arg0 arg1 input output-capacity)
  (scoped-capability-invoke/identity
   capability
   (scoped-capability-kind capability)
   (scoped-capability-generation capability)
   (scoped-capability-token capability)
   operation arg0 arg1 input output-capacity))

;; scoped-capability-invoke/identity keeps adversarial identity checks on the same transport.
(define (scoped-capability-invoke/identity
         capability kind generation token operation arg0 arg1 input output-capacity)
  (unless (scoped-capability-active? capability)
    (raise-arguments-error
     'scoped-capability-invoke
     "native capability escaped its dynamic extent"))
  (unless (eq? (current-thread) (scoped-capability-owner-thread capability))
    (raise-arguments-error
     'scoped-capability-invoke
     "native capability crossed its owning Racket thread"))
  (define output (make-bytes output-capacity))
  (define output-length (ffi:malloc ffi:_uint64 'atomic))
  (define value (ffi:malloc ffi:_uint64 'atomic))
  (define failure-code (ffi:malloc ffi:_uint32 'atomic))
  (define limit (ffi:malloc ffi:_uint64 'atomic))
  (define actual (ffi:malloc ffi:_uint64 'atomic))
  (define status
    ((force native-call)
     (hash-ref capability-kinds kind)
     generation
     token
     operation arg0 arg1 input (bytes-length input)
     output output-capacity output-length value failure-code limit actual))
  (define copied-length (ffi:ptr-ref output-length ffi:_uint64))
  (unless (<= copied-length output-capacity)
    (error 'scoped-capability-invoke
           "native capability returned an oversized result"))
  (scoped-capability-result
   status
   (bytes->immutable-bytes (subbytes output 0 copied-length))
   (ffi:ptr-ref value ffi:_uint64)
   (ffi:ptr-ref failure-code ffi:_uint32)
   (ffi:ptr-ref limit ffi:_uint64)
   (ffi:ptr-ref actual ffi:_uint64)))

(module+ test
  (require rackunit)

  (check-exn exn:fail:contract?
             (lambda () (call-with-scoped-capability 'unknown 1 1 void)))
  (define escaped #f)
  (call-with-scoped-capability
   'search 1 1 (lambda (capability) (set! escaped capability)))
  (check-exn exn:fail:contract?
             (lambda () (scoped-capability-invoke escaped 1 0 0 #"" 0))))
