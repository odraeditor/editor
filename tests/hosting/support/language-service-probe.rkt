#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require "../../../src/command/language-services.rkt"
         "../../../src/hosting/language-service-bridge.rkt")

(provide native-language-service-probe)

;; native-language-service-probe drives adversarial service boundary turns.
(define (native-language-service-probe scenario generation token)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #f (string->bytes/utf-8 (exn-message failure))))])
    (define escaped-control #f)
    (define result
      (case scenario
        [(0) (cadr (native-language-service-turn generation token))]
        [(1)
         (error 'native-language-service-probe
                "requested language-service host exception")]
        [(2)
         (call-with-language-service-host-control
          generation token
          (lambda (control) (set! escaped-control control)))
         (language-service-host-scope escaped-control)]
        [(3)
         (call-with-language-service-host-control
          generation token
          (lambda (control) (collect-garbage) (language-service-host-scope control)))]
        [(4)
         (call-with-language-service-host-control
          generation token
          (lambda (control)
            (define worker-result #f)
            (define worker
              (thread
               (lambda ()
                 (with-handlers ([exn? (lambda (failure) (set! worker-result failure))])
                   (set! worker-result (language-service-host-scope control))))))
            (thread-wait worker)
            (if (exn? worker-result) (raise worker-result) worker-result)))]
        [(5)
         (let/ec leave
           (call-with-language-service-host-control
            generation token
            (lambda (control) (set! escaped-control control) (leave 'escaped))))
         (language-service-host-scope escaped-control)]
        [(6) (language-services-programmable-turn generation token)]
        [else
         (raise-argument-error
          'native-language-service-probe "an integer from 0 through 6" scenario)]))
    (list #t result #"")))

;; language-services-programmable-turn traverses the real provider lifecycle.
(define (language-services-programmable-turn generation token)
  (call-with-language-services
   generation token language-services-programmable-turn/control))

(define (language-services-programmable-turn/control control)
  (define limits
    (service-limits
     64 64 32 256 4096 4096 64 (* 64 1024) 64 (* 64 1024)
     (* 16 1024) (* 32 1024) (* 1024 1024) (* 8 1024) 64
     (* 16 1024 1024) (* 32 1024 1024) 1024 4096 4096
     (* 64 1024 1024) 4096 (* 64 1024 1024) 4096 65536 32
     (* 64 1024) 32 (* 128 1024 1024) 65536 (* 64 1024 1024)
     (* 1024 1024) (* 256 1024) (* 512 1024 1024) (* 128 1024 1024)))
  (define policy
    (service-policy
     500000000 10000000000 5000000000 1000000000 50000000
     30000000000 3000000000 1000000000 1 30000000000))
  (define definition
    (service-definition
     3 "fixture-language-server" "racket" '() '() 1 "/work/fixture"
     '("fixture") '() 59 2 2 limits policy))
  (define proposed (language-services-propose control definition))
  (unless (service-outcome? proposed)
    (error 'language-services-programmable-turn "proposal failed"))
  (define confirmed
    (language-services-confirm control (service-outcome-definition proposed)))
  (unless (service-outcome? confirmed)
    (error 'language-services-programmable-turn "confirmation failed"))
  (define selected
    (language-services-select control (service-outcome-definition confirmed)))
  (unless (service-outcome? selected)
    (error 'language-services-programmable-turn "selection failed"))
  (define disabled
    (language-services-disable control (service-outcome-provider selected)))
  (unless (service-outcome? disabled)
    (error 'language-services-programmable-turn "disable failed"))
  (define restored (language-services-restore control))
  (unless (service-outcome? restored)
    (error 'language-services-programmable-turn "factory restoration failed"))
  (define replaced
    (language-services-replace
     control
     (service-scope-active-definition (service-outcome-scope restored))
     definition))
  (unless (service-outcome? replaced)
    (error 'language-services-programmable-turn "replacement failed"))
  (define final (language-services-restore control))
  (unless (service-outcome? final)
    (error 'language-services-programmable-turn "final restoration failed"))
  (define diagnostic
    (language-services-invoke-diagnostic-command
     control "list-language-diagnostics" 17 19))
  (unless (service-diagnostic-command-outcome? diagnostic)
    (error 'language-services-programmable-turn "diagnostic command failed"))
  (list proposed confirmed selected disabled restored replaced final diagnostic))

(module+ test
  (require rackunit)
  (check-false (car (native-language-service-probe 1 1 1))))
