#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require "../../../src/hosting/layout-bridge.rkt")

(provide native-layout-probe)

;; native-layout-probe drives adversarial layout boundary turns.
(define (native-layout-probe scenario generation token)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #f (string->bytes/utf-8 (exn-message failure))))])
    (define escaped-control #f)
    (define result
      (case scenario
        [(0) (cadr (native-layout-turn generation token))]
        [(1)
         (call-with-layout-control
          generation token (lambda (control) (set! escaped-control control)))
         (layout-inspect escaped-control)]
        [(2)
         (call-with-layout-control
          generation token
          (lambda (control) (collect-garbage) (layout-inspect control)))]
        [(3)
         (call-with-layout-control
          generation token
          (lambda (control)
            (define worker-result #f)
            (define worker
              (thread
               (lambda ()
                 (with-handlers ([exn? (lambda (failure) (set! worker-result failure))])
                   (set! worker-result (layout-inspect control))))))
            (thread-wait worker)
            (if (exn? worker-result) (raise worker-result) worker-result)))]
        [(4) (error 'native-layout-probe "requested layout exception")]
        [(5)
         (let/ec leave
           (call-with-layout-control
            generation token
            (lambda (control) (set! escaped-control control) (leave 'escaped))))
         (layout-inspect escaped-control)]
        [(6) (call-with-layout-control generation token layout-inspect)]
        [(7)
         (call-with-layout-control
          generation token
          (lambda (control)
            (define before (layout-inspect control))
            (define mutation
              (layout-split-below control (layout-snapshot-active-pane before)))
            (list before mutation (layout-inspect control))))]
        [(8)
         (call-with-layout-control
          generation token
          (lambda (control)
            (define before (layout-inspect control))
            (layout-split-below control (layout-snapshot-active-pane before))
            (layout-focus control (layout-snapshot-active-pane before))))]
        [(9)
         (call-with-layout-control
          generation token
          (lambda (control)
            (define before (layout-inspect control))
            (layout-set-dedication
             control (layout-snapshot-active-pane before) 1)))]
        [else
         (raise-argument-error
          'native-layout-probe "an integer from 0 through 9" scenario)]))
    (list #t result #"")))

(module+ test
  (require rackunit)
  (check-false (car (native-layout-probe 4 1 1))))
