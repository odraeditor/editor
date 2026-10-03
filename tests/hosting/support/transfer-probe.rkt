#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (prefix-in cap: "../../../src/hosting/scoped-capability.rkt")
         "../../../src/command/transfer.rkt"
         (submod "../../../src/command/transfer.rkt" test-support))

(provide native-transfer-probe)

;; native-transfer-probe drives adversarial transfer boundary turns.
(define (native-transfer-probe scenario generation token)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #f (string->bytes/utf-8 (exn-message failure))))])
    (define escaped-session #f)
    (define result
      (case scenario
        [(0) (cadr (native-transfer-turn generation token))]
        [(1)
         (call-with-text-transfer
          generation token (lambda (session) (set! escaped-session session)))
         (transfer-scope escaped-session)]
        [(2)
         (call-with-text-transfer
          generation token
          (lambda (session)
            (collect-garbage)
            (transfer-scope session)))]
        [(3)
         (call-with-text-transfer
          generation token
          (lambda (session)
            (define worker-result #f)
            (define worker
              (thread
               (lambda ()
                 (with-handlers ([exn? (lambda (failure) (set! worker-result failure))])
                   (set! worker-result (transfer-scope session))))))
            (thread-wait worker)
            (if (exn? worker-result) (raise worker-result) worker-result)))]
        [(4) (error 'native-transfer-probe "requested transfer exception")]
        [(5)
         (let/ec leave
           (call-with-text-transfer
            generation token
            (lambda (session)
              (set! escaped-session session)
              (leave 'escaped))))
         (transfer-scope escaped-session)]
        [(6)
         (call-with-text-transfer
          generation token
          (lambda (session)
            (define ring (text-transfer-ring session #:entries 2))
            (define text
              (and (ring-snapshot? ring)
                   (pair? (ring-snapshot-entries ring))
                   (text-transfer-entry-text
                    session
                    (ring-entry-id (car (ring-snapshot-entries ring))))))
            (list (text-transfer-region session) ring text)))]
        [(7)
         (call-with-text-transfer
          generation token
          (lambda (session)
            (define completion (text-transfer-command! session 'copy-region))
            (list completion (text-transfer-ring session #:entries 1))))]
        [(8)
         (call-with-text-transfer
          generation token
          (lambda (session)
            (text-transfer-command! session 'deactivate-mark)
            (list (text-transfer-command! session 'deactivate-mark)
                  (text-transfer-region session))))]
        [(9)
         (call-with-text-transfer
          generation token
          (lambda (session)
            (text-transfer-command! session 'cursor-next-grapheme)))]
        [(10)
         (call-with-text-transfer
          generation token
          (lambda (session)
            (native-invoke session operation-scope 0 0 #"" 1)))]
        [(11)
         (call-with-text-transfer
          generation token
          (lambda (session)
            (text-transfer-ring session #:entries 257)))]
        [(12 13)
         (call-with-text-transfer
          generation token
          (lambda (session)
            (define rejected
              (cap:scoped-capability-invoke/identity
               (transfer-session-capability session)
               (if (= scenario 12) 'search 'transfer)
               (if (= scenario 13) (add1 generation) generation)
               token
               operation-scope 0 0 #"" scope-record-bytes))
            (unless (= (cap:scoped-capability-result-status rejected) 2)
              (error 'native-transfer-probe
                     "native transport accepted a mismatched identity"))
            'identity-rejected))]
        [else
         (raise-argument-error
          'native-transfer-probe "an integer from 0 through 13" scenario)]))
    (list #t result #"")))

(module+ test
  (require rackunit)
  (check-false (car (native-transfer-probe 4 1 1))))
