#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (prefix-in host: "../../../src/hosting/structural-bridge.rkt")
         "../../../src/command/structural.rkt"
         (submod "../../../src/command/structural.rkt" test-support))

(provide native-structural-probe)

;; native-structural-probe drives adversarial structural boundary turns.
(define (native-structural-probe scenario generation token)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #f (string->bytes/utf-8 (exn-message failure))))])
    (define escaped-control #f)
    (define result
      (case scenario
        [(0) (cadr (native-structural-turn generation token))]
        [(1)
         (error 'native-structural-probe "requested structural command exception")]
        [(2)
         (call-with-structural-commands
          generation token
          (lambda (control) (set! escaped-control control)))
         (structural-current-scope escaped-control)]
        [(3)
         (call-with-structural-commands
          generation token
          (lambda (control) (collect-garbage) (structural-current-scope control)))]
        [(4)
         (call-with-structural-commands
          generation token
          (lambda (control)
            (define worker-result #f)
            (define worker
              (thread
               (lambda ()
                 (with-handlers ([exn? (lambda (failure) (set! worker-result failure))])
                   (set! worker-result (structural-current-scope control))))))
            (thread-wait worker)
            (if (exn? worker-result) (raise worker-result) worker-result)))]
        [(5)
         (let/ec leave
           (call-with-structural-commands
            generation token
            (lambda (control) (set! escaped-control control) (leave 'escaped))))
         (structural-current-scope escaped-control)]
        [(10) (call-with-structural-commands generation token structural-forward)]
        [(11) (call-with-structural-commands generation token structural-backward)]
        [(12) (call-with-structural-commands generation token structural-up)]
        [(13) (call-with-structural-commands generation token structural-down)]
        [(14) (call-with-structural-commands generation token structural-select)]
        [(15) (call-with-structural-commands generation token structural-indent)]
        [(21) (call-with-structural-commands generation token structural-definition)]
        [(16) (call-with-structural-commands generation token structural-inspect)]
        [(17)
         (call-with-structural-commands
          generation token
          (lambda (control)
            (host:structural-host-invoke
             (structural-command-control-host control)
             operation-forward 0 0 #"bad" outcome-record-bytes)))]
        [(18)
         (call-with-structural-commands
          generation token
          (lambda (control)
            (define scope (structural-current-scope control))
            (define request
              (encode-request (structural-request scope operation-forward 0 0 0 #f)))
            (write-u64! request (- request-record-bytes 8) 2)
            (host:structural-host-invoke
             (structural-command-control-host control)
             operation-forward 0 0 request outcome-record-bytes)))]
        [(19)
         (call-with-structural-commands
          generation token
          (lambda (control)
            (host:structural-host-invoke
             (structural-command-control-host control)
             operation-inspect 0 0 #"" (add1 maximum-inspection-bytes))))]
        [(20) (call-with-structural-commands generation token structural-inspect)]
        [else
         (raise-argument-error
          'native-structural-probe "0 through 5 or 10 through 21" scenario)]))
    (list #t result #"")))

(module+ test
  (require rackunit)
  (check-false (car (native-structural-probe 1 1 1))))
