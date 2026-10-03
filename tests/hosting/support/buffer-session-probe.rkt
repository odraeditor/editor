#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require "../../../src/command/buffers.rkt"
         (submod "../../../src/command/buffers.rkt" test-support))

(provide native-buffer-session-probe)

;; native-buffer-session-probe drives adversarial buffer-session turns.
(define (native-buffer-session-probe scenario generation token)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #f (string->bytes/utf-8 (exn-message failure))))])
    (define escaped-session #f)
    (define result
      (case scenario
        [(0) (cadr (native-buffer-session-turn generation token))]
        [(1)
         (call-with-buffer-session
          generation token (lambda (session) (set! escaped-session session)))
         (define escaped-result (buffer-session-usage escaped-session))
         (when (buffer-session-failure? escaped-result)
           (error 'native-buffer-session-probe
                  "escaped buffer session reached the native boundary"))
         escaped-result]
        [(2)
         (call-with-buffer-session
          generation token
          (lambda (session) (collect-garbage) (buffer-session-scope session)))]
        [(3)
         (call-with-buffer-session
          generation token
          (lambda (session)
            (define worker-result #f)
            (define worker
              (thread
               (lambda ()
                 (with-handlers ([exn? (lambda (failure) (set! worker-result failure))])
                   (set! worker-result (buffer-session-usage session))))))
            (thread-wait worker)
            (cond
              [(exn? worker-result) (raise worker-result)]
              [(buffer-session-failure? worker-result)
               (error 'native-buffer-session-probe
                      "cross-thread buffer session reached the native boundary")]
              [else worker-result])))]
        [(4) (error 'native-buffer-session-probe "requested buffer session exception")]
        [(5)
         (let/ec leave
           (call-with-buffer-session
            generation token
            (lambda (session) (set! escaped-session session) (leave 'escaped))))
         (define continuation-result (buffer-session-usage escaped-session))
         (when (buffer-session-failure? continuation-result)
           (error 'native-buffer-session-probe
                  "continuation-escaped buffer session reached the native boundary"))
         continuation-result]
        [(6)
         (call-with-buffer-session
          generation token
          (lambda (session)
            (list (buffer-session-scope session)
                  (buffer-session-descriptors session))))]
        [(7)
         (call-with-buffer-session
          generation token
          (lambda (session)
            (define created (buffer-session-create! session "racket-created"))
            (list created (buffer-session-descriptors session)
                  (buffer-session-usage session))))]
        [(8)
         (call-with-buffer-session
          generation token
          (lambda (session)
            (define stale (buffer-session-scope-bytes session))
            (buffer-session-create! session "stale-scope-buffer")
            (set-buffer-session-scope-bytes! session stale)
            (buffer-session-descriptors session)))]
        [(9)
         (call-with-buffer-session
          generation token
          (lambda (session)
            (buffer-session-native-invoke
             (buffer-session-control session) operation-create 0 0 #"bad"
             outcome-record-bytes)))]
        [(10)
         (call-with-buffer-session
          generation token
          (lambda (session)
            (buffer-session-descriptors session #:count 257)))]
        [(11)
         (call-with-buffer-session
          generation token
          (lambda (session)
            (buffer-session-descriptors session #:count 16 #:label-bytes 1024)))]
        [else
         (raise-argument-error
          'native-buffer-session-probe "an integer from 0 through 11" scenario)]))
    (list #t result #"")))

(module+ test
  (require rackunit)
  (check-false (car (native-buffer-session-probe 4 1 1))))
