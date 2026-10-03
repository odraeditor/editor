#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         "../command/native-contracts.rkt"
         (only-in "../configuration/platform-roots.rkt"
                  runtime-platform-roots-reset!)
         (only-in "personal-command-runtime.rkt"
                  personal-command-runtime-reset!)
         (only-in "personal-command-containment.rkt"
                  personal-command-containment-reset!))

(provide
 (contract-out
  [runtime-call (-> exact-integer? list?)]
  [runtime-start (-> bytes? (or/c symbol? bytes?))]
  [runtime-stop (-> symbol?)]))

(define minimum-signed-64 (- (expt 2 63)))
(define maximum-signed-64 (sub1 (expt 2 63)))

;; runtime-start validates every native record contract before exposing facades.
(define (runtime-start schema)
  (with-handlers ([exn?
                   (lambda (failure)
                     (string->bytes/utf-8 (exn-message failure)))])
    (validate-native-contract-schema! schema)
    'odra-runtime-ready))

;; runtime-stop completes built-in Racket cleanup before native shutdown.
(define (runtime-stop)
  (personal-command-runtime-reset!)
  (personal-command-containment-reset!)
  (runtime-platform-roots-reset!)
  'odra-runtime-stopped)

;; runtime-call executes one production scalar turn and returns a checked envelope.
(define (runtime-call value)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f 0 (string->bytes/utf-8 (exn-message failure))))])
    (define result (add1 value))
    (unless (and (exact-integer? result)
                 (<= minimum-signed-64 result maximum-signed-64))
      (raise-result-error 'runtime-call "signed 64-bit integer" result))
    (list #t result #"")))

(module+ test
  (require rackunit
           "../command/personal.rkt"
           (only-in "personal-command-runtime.rkt"
                    personal-command-runtime-activate!
                    personal-command-runtime-call
                    personal-command-runtime-prepare!))

  (check-true (bytes? (runtime-start #"")))
  (personal-command-runtime-prepare!
   2
   (list (make-command 'runtime-stop-command (lambda (_context) 'called)))
   #f)
  (personal-command-runtime-activate! 2)
  (check-eq?
   (personal-command-runtime-call
    2 1 "runtime-stop-command" (lambda (implementation) (implementation #f)))
   'called)
  (check-eq? (runtime-stop) 'odra-runtime-stopped)
  (check-exn
   #rx"unavailable"
   (lambda ()
     (personal-command-runtime-call
      2 1 "runtime-stop-command" (lambda (_implementation) (void)))))
  (check-equal? (runtime-call 41) '(#t 42 #"")))
