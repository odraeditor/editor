#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (prefix-in cap: "../../../src/hosting/scoped-capability.rkt")
         "../../../src/command/transaction.rkt"
         (submod "../../../src/command/transaction.rkt" test-support))

(provide native-transaction-probe native-transaction-command-probe)

;; native-transaction-probe drives adversarial transaction boundary turns.
(define (native-transaction-probe scenario generation token)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #f (string->bytes/utf-8 (exn-message failure))))])
    (define result
      (case scenario
        [(0) (cadr (native-transaction-turn generation token))]
        [(2)
         (call-with-native-transaction
          generation token
          (lambda (transaction)
            (collect-garbage)
            (define before (transaction-inspect transaction 0 3))
            (transaction-splice! transaction 1 2 #"X")
            (list before (transaction-inspect transaction 0 3))))]
        [(1)
         (define escaped #f)
         (call-with-native-transaction
          generation token (lambda (transaction) (set! escaped transaction)))
         (transaction-inspect escaped 0 1)]
        [(3)
         (call-with-native-transaction
          generation token
          (lambda (transaction)
            (define worker-result #f)
            (define worker
              (thread
               (lambda ()
                 (with-handlers ([exn? (lambda (failure) (set! worker-result failure))])
                   (set! worker-result (transaction-inspect transaction 0 1))))))
            (thread-wait worker)
            (if (exn? worker-result) (raise worker-result) worker-result)))]
        [(4) (error 'native-transaction-probe "requested transaction exception")]
        [(5)
         (define retained #f)
         (let/ec leave
           (call-with-native-transaction
            generation token
            (lambda (transaction)
              (set! retained transaction)
              (leave 'escaped))))
         (transaction-inspect retained 0 1)]
        [else
         (raise-argument-error
          'native-transaction-probe "an integer from 0 through 5" scenario)]))
    (list #t result #"")))

;; native-transaction-command-probe drives command result and mutation failures.
(define (native-transaction-command-probe
         scenario command-name generation token start end)
  (void command-name)
  (cond
    [(memv scenario '(2 5)) (list #t 'wrong-result #"")]
    [else
     (with-handlers ([exn?
                      (lambda (failure)
                        (list #f #f (string->bytes/utf-8 (exn-message failure))))])
       (when (= scenario 1)
         (error 'native-transaction-command-probe "requested command exception"))
       (define result
         (if (= scenario 15)
             (cap:call-with-scoped-capability
              'transaction generation token
              (lambda (capability)
                (call-with-transaction
                 token
                 (lambda (_token operation payload)
                   (native-dispatch capability operation payload))
                 (lambda (transaction)
                   (transaction-apply-batch!
                    transaction
                    (list (make-transaction-edit start start #"X")
                          (make-transaction-edit start start #"Y"))))
                 #:limits (make-transaction-limits #:batch-splices 1))))
             (call-with-native-transaction
              generation token
              (lambda (transaction)
                (when (= scenario 4) (collect-garbage))
                (case scenario
                  [(7)
                   (transaction-apply-batch!
                    transaction
                    (list (make-transaction-edit start (add1 start) #"X")
                          (make-transaction-edit (sub1 end) end #"Y")))]
                  [(8)
                   (transaction-splice! transaction start start #"X")
                   (transaction-inspect transaction start (add1 end))
                   (transaction-splice! transaction (add1 start) (+ start 2) #"Z")]
                  [(9)
                   (transaction-splice! transaction start start #"(")
                   (transaction-invoke-nested
                    transaction 'racket "insert-closing-delimiter"
                    (lambda (nested)
                      (transaction-splice! nested (add1 start) (add1 start) #")")))]
                  [(10)
                   (transaction-splice! transaction start start #"R")
                   (transaction-invoke-nested
                    transaction 'language-tool "handled-child"
                    (lambda (nested)
                      (transaction-splice! nested (add1 start) (add1 start) #"discard")
                      (transaction-reject 'out-of-range (hasheq 'actual 99))))
                   (transaction-splice! transaction (add1 start) (add1 start) #"K")]
                  [(11) (transaction-inspect transaction start end)]
                  [(12) (transaction-splice! transaction end (add1 end) #"!")]
                  [(13) (transaction-request-abort! transaction)]
                  [(14) (host-call transaction 'malformed-batch (hasheq))]
                  [else
                   (define source (transaction-inspect transaction start end))
                   (if (transaction-failure? source)
                       source
                       (let ([replacement
                              (cond
                                [(= scenario 3) #"\377"]
                                [(= scenario 6) (make-bytes 4097 (char->integer #\X))]
                                [else
                                 (string->bytes/utf-8
                                  (string-upcase (bytes->string/utf-8 source)))])])
                         (if (bytes=? source replacement)
                             (void)
                             (transaction-splice!
                              transaction start end replacement))))])))))
       (void result)
       (list #t #t #""))]))

(module+ test
  (require rackunit)
  (check-false (car (native-transaction-probe 4 1 1))))
