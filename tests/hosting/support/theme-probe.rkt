#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/list
         (prefix-in cap: "../../../src/hosting/scoped-capability.rkt")
         "../../../src/command/native-contracts.rkt"
         "../../../src/hosting/theme-bridge.rkt"
         (submod "../../../src/hosting/theme-bridge.rkt" test-support))

(provide native-theme-probe)

(define (contract item) (native-contract-value 'theme item))
(define operation-inspect (contract 'operation-inspect))
(define maximum-inspection-bytes (contract 'maximum-inspection-bytes))

;; native-theme-probe drives adversarial theme boundary turns.
(define (native-theme-probe scenario generation token)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f 0 (string->bytes/utf-8 (exn-message failure))))])
    (define result
      (case scenario
        [(0) (cadr (native-theme-turn generation token))]
        [(1) (error 'native-theme-probe "requested theme capability failure")]
        [(2)
         (define escaped #f)
         (call-with-theme-control
          generation token (lambda (control) (set! escaped control)))
         (theme-current-scope escaped)]
        [(3)
         (call-with-theme-control
          generation token
          (lambda (control)
            (define snapshot (theme-inspect control))
            (when (theme-failure? snapshot)
              (error 'native-theme-probe (theme-failure-diagnostic snapshot)))
            (define proposal (theme-probe-proposal snapshot "Racket Fixture"))
            (define proposed (theme-propose control proposal))
            (define confirmed (theme-confirm control (theme-outcome-definition proposed)))
            (define selected (theme-select control (theme-outcome-definition confirmed)))
            (define replaced
              (theme-replace
               control
               (theme-outcome-definition selected)
               (struct-copy theme-proposal proposal
                            [display-name "Racket Fixture Replaced"])))
            (theme-restore control)
            (theme-select-baseline control)
            (define definition (theme-outcome-definition replaced))
            (theme-teardown
             control
             (theme-provider-handle
              (theme-definition-handle-provider-id definition)
              (theme-definition-handle-provider-generation definition)))))]
        [(4)
         (call-with-theme-control
          generation token
          (lambda (control)
            (define scope (theme-current-scope control))
            (set-theme-control-scope!
             control
             (struct-copy theme-scope scope
                          [selection-generation
                           (add1 (theme-scope-selection-generation scope))]))
            (theme-inspect control)))]
        [(5)
         (call-with-theme-control
          generation token
          (lambda (control)
            (define malformed
              (theme-control-invoke
               control operation-inspect 0 0 #"" maximum-inspection-bytes))
            (unless (= (cap:scoped-capability-result-status malformed) 2)
              (error 'native-theme-probe "malformed theme request was accepted"))
            (error 'native-theme-probe "malformed theme request was contained")))]
        [(6)
         (call-with-theme-control
          generation token
          (lambda (control)
            (for/fold ([result #f])
                      ([_ (in-range (add1 (contract 'maximum-operations-per-turn)))])
              (theme-current-scope control))))]
        [(7)
         (call-with-theme-control
          generation token
          (lambda (control)
            (define snapshot (theme-inspect control))
            (define proposed
              (theme-propose control (theme-probe-proposal snapshot "Racket Failure")))
            (define confirmed (theme-confirm control (theme-outcome-definition proposed)))
            (theme-select control (theme-outcome-definition confirmed))
            (error 'native-theme-probe "requested active theme provider failure")))]
        [else
         (raise-argument-error
          'native-theme-probe "an integer from 0 through 7" scenario)]))
    (list #t result #"")))

(define (theme-probe-proposal snapshot display-name)
  (theme-proposal
   "racket-fixture" display-name "racket-fixture-provider"
   "theme-test-support"
   (snapshot-first-definition-styles snapshot)))

(define (snapshot-first-definition-styles snapshot)
  (define definition (car (theme-snapshot-definitions snapshot)))
  (take
   (drop (theme-snapshot-styles snapshot)
         (theme-definition-first-style definition))
   (theme-definition-style-count definition)))

(module+ test
  (require rackunit)
  (check-false (car (native-theme-probe 1 1 1))))
