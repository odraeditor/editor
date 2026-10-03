#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require "../../../src/hosting/ui-role-bridge.rkt"
         (submod "../../../src/hosting/ui-role-bridge.rkt" test-support))

(provide native-ui-role-probe)

;; native-ui-role-probe drives adversarial UI-role boundary turns.
(define (native-ui-role-probe scenario generation token)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #f (string->bytes/utf-8 (exn-message failure))))])
    (define escaped-control #f)
    (define result
      (case scenario
        [(0) (cadr (native-ui-role-turn generation token))]
        [(1)
         (call-with-ui-role-control
          generation token (lambda (control) (set! escaped-control control)))
         (ui-role-current-scope escaped-control 'startup)]
        [(2)
         (call-with-ui-role-control
          generation token (lambda (control) (ui-role-inspect control 'startup)))]
        [(3)
         (call-with-ui-role-control
          generation token
          (lambda (control)
            (ui-role-propose
             control
             (ui-role-proposal
              'startup "compact startup" "example/ui"
              '(cell-geometry clipping unicode-profile atomic-generation)
              #"startup compact" #"open" 32))))]
        [(4) (error 'native-ui-role-probe "requested UI role exception")]
        [(5)
         (call-with-ui-role-control
          generation token
          (lambda (control)
            (define scope (ui-role-current-scope control 'status))
            (ui-role-rollback control (ui-role-scope-role scope))))]
        [(6)
         (call-with-ui-role-control
          generation token
          (lambda (control)
            (for/list ([role (in-hash-keys role-codes)])
              (ui-role-inspect control role))))]
        [(7)
         (call-with-ui-role-control
          generation token
          (lambda (control)
            (run-fixture control (bytes-length #"compact package presentation"))))]
        [(8)
         (call-with-ui-role-control
          generation token
          (lambda (control)
            (define stale-scope (ui-role-current-scope control 'startup))
            (define proposed (ui-role-propose control (fixture-proposal 'startup)))
            (define provider (ui-role-outcome-provider proposed))
            (hash-set! (ui-role-control-scopes control) 'startup stale-scope)
            (define rejected (ui-role-activate control provider))
            (ui-role-current-scope control 'startup)
            (ui-role-teardown control provider)
            rejected))]
        [(9) (error 'native-ui-role-probe "requested package exception")]
        [(10)
         (call-with-ui-role-control
          generation token
          (lambda (control)
            (define proposed (ui-role-propose control (fixture-proposal 'startup)))
            (ui-role-activate control (ui-role-outcome-provider proposed))
            (error 'compact-provider "requested active provider exception")))]
        [(11)
         (call-with-ui-role-control
          generation token
          (lambda (control)
            (define proposed
              (ui-role-propose control (fixture-proposal 'startup 1)))
            (define provider (ui-role-outcome-provider proposed))
            (ui-role-activate control provider)
            (ui-role-invoke-command control provider #"open")))]
        [(12)
         (call-with-ui-role-control
          generation token
          (lambda (control) (run-fixture control (* 4 1024))))]
        [(13)
         (call-with-ui-role-control
          generation token
          (lambda (control) (run-fixture control (* 1024 1024))))]
        [(14)
         (call-with-ui-role-control
          generation token
          (lambda (control) (run-fixture control maximum-fixture-content-bytes)))]
        [else
         (raise-argument-error
          'native-ui-role-probe "an integer from 0 through 14" scenario)]))
    (list #t result #"")))

(module+ test
  (require rackunit)
  (check-false (car (native-ui-role-probe 4 1 1))))
