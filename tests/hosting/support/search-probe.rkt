#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (prefix-in bridge: "../../../src/command/search-bridge.rkt")
         "../../../src/command/native-contracts.rkt"
         "../../../src/command/search.rkt")

(provide native-search-probe)

(define maximum-pattern-bytes
  (native-contract-value 'search 'maximum-pattern-bytes))

;; native-search-probe drives adversarial search boundary turns.
(define (native-search-probe scenario generation token)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f #f (string->bytes/utf-8 (exn-message failure))))])
    (define escaped-context #f)
    (define result
      (case scenario
        [(0) (cadr (native-search-turn generation token))]
        [(1)
         (call-with-search
          generation token (lambda (context) (set! escaped-context context)))
         (inspect-search-scope escaped-context)]
        [(2)
         (call-with-search
          generation token
          (lambda (context)
            (collect-garbage)
            (inspect-search-scope context)))]
        [(3)
         (call-with-search
          generation token
          (lambda (context)
            (define worker-result #f)
            (define worker
              (thread
               (lambda ()
                 (with-handlers ([exn? (lambda (failure) (set! worker-result failure))])
                   (set! worker-result (inspect-search-scope context))))))
            (thread-wait worker)
            (if (exn? worker-result) (raise worker-result) worker-result)))]
        [(4) (error 'native-search-probe "requested search exception")]
        [(5)
         (let/ec leave
           (call-with-search
            generation token
            (lambda (context) (set! escaped-context context) (leave 'escaped))))
         (inspect-search-scope escaped-context)]
        [(6)
         (call-with-search
          generation token
          (lambda (context)
            (list (inspect-search-policy context)
                  (inspect-search-state context
                                        #:occurrences 2
                                        #:captures 16
                                        #:text-bytes 128))))]
        [(7)
         (call-with-search
          generation token
          (lambda (context)
            (invoke-search-command!
             context
             (make-search-command
              'isearch-forward (make-search-pattern 'literal #"one")
              #:incremental-turn 'query-update
              #:query-id 1 #:search-generation 1))))]
        [(8)
         (call-with-search
          generation token
          (lambda (context) (inspect-search-state context #:occurrences 257)))]
        [(9)
         (call-with-search
          generation token
          (lambda (context)
            (invoke-search-command!
             context
             (make-search-command
              'isearch-forward (make-search-pattern 'literal #"one")
              #:incremental-turn 'query-update
              #:query-id 2 #:search-generation 2 #:cancelled? #t))))]
        [(10)
         (call-with-search
          generation token
          (lambda (context)
            (invoke-search-command!
             context
             (make-search-command
              'replace-string (make-search-pattern 'literal #"one")
              #:replacement (make-replacement-template #"ONE")
              #:query-id 3 #:search-generation 3
              #:scope (make-search-range 81 0 0 11)))))]
        [(11)
         (define copied #f)
         (call-with-search
          generation token
          (lambda (context) (set! copied (inspect-search-state context))))
         (collect-garbage)
         (and (search-state? copied)
              (immutable? (search-state-pattern copied))
              (bytes-length (search-state-pattern copied)))]
        [(12)
         (make-search-pattern 'literal (make-bytes (add1 maximum-pattern-bytes)))]
        [(13)
         (call-with-search
          generation token
          (lambda (context)
            (bridge:search-control-invoke!
             context 'query-replace
             #:pattern #"one" #:replacement #"ONE" #:direction 99
             #:query-action 1 #:query-id 4 #:search-generation 4
             #:semantic-group 4)))]
        [(14)
         (call-with-search
          generation token
          (lambda (context)
            (invoke-search-command!
             context
             (make-search-command
              'replace-string (make-search-pattern 'literal #"one")
              #:replacement (make-replacement-template #"ONE")
              #:query-id 5 #:search-generation 5
              #:scope (make-search-range 81 99 0 11)))))]
        [(15)
         (dynamic-wind
          (lambda ()
            (reload-search-policy!
             (lambda (current)
               (search-policy-replace
                current
                (hasheq 'case-mode 'sensitive 'wrap? #f)))))
          (lambda ()
            (call-with-search
             generation token
             (lambda (context)
               (list
                (invoke-search-command!
                 context
                 (make-search-command
                  'replace-string (make-search-pattern 'literal #"ONE")
                  #:replacement (make-replacement-template #"matched")
                  #:query-id 6 #:search-generation 6
                  #:scope (make-search-range 81 0 0 11)))
                (inspect-search-state context)))))
          reset-search-policy!)]
        [else
         (raise-argument-error
          'native-search-probe "an integer from 0 through 15" scenario)]))
    (list #t result #"")))

(module+ test
  (require rackunit)
  (check-false (car (native-search-probe 4 1 1))))
