#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/sandbox)

(provide
 (struct-out terminal-event-handler-outcome)
 (contract-out
  [call-with-terminal-event-handler
   (-> string? exact-positive-integer? exact-positive-integer? procedure? list?
       terminal-event-handler-outcome?)]))

(struct terminal-event-handler-outcome (accepted? requests diagnostic)
  #:transparent)

(define maximum-terminal-handler-requests 256)

;; call-with-terminal-event-handler confines one event batch to its declared budget.
(define (call-with-terminal-event-handler name deadline-milliseconds memory-bytes
                                          handler events)
  (define handler-custodian (make-custodian))
  (define (rejected diagnostic)
    (terminal-event-handler-outcome #f '() diagnostic))
  (with-handlers
      ([exn:fail:resource?
        (lambda (failure)
          (rejected
           (if (eq? (exn:fail:resource-resource failure) 'time)
               "terminal event handler deadline exceeded"
               "terminal event handler memory limit exceeded")))]
       [exn?
        (lambda (_failure)
          (rejected "terminal event handler raised an exception"))])
    (define result
      (dynamic-wind
       void
       (lambda ()
         (call-with-limits
          (/ deadline-milliseconds 1000.0)
          (max 1 (quotient memory-bytes (* 1024 1024)))
          (lambda ()
            (parameterize ([current-custodian handler-custodian])
              (handler events)))))
       (lambda () (custodian-shutdown-all handler-custodian))))
    (cond
      [(void? result) (terminal-event-handler-outcome #t '() "")]
      [(and (list? result)
            (<= (length result) maximum-terminal-handler-requests)
            (null? result))
       (terminal-event-handler-outcome #t result "")]
      [else
       (rejected
        (format "terminal event handler ~a returned an invalid request batch" name))])))

(module+ test
  (require rackunit)

  (define memory-limit (* 8 1024 1024))
  (check-true
   (terminal-event-handler-outcome-accepted?
    (call-with-terminal-event-handler "ok" 25 memory-limit void '())))
  (check-false
   (terminal-event-handler-outcome-accepted?
    (call-with-terminal-event-handler
     "exception" 25 memory-limit (lambda (_events) (error 'handler "failed")) '())))
  (check-false
   (terminal-event-handler-outcome-accepted?
    (call-with-terminal-event-handler
     "timeout" 5 memory-limit (lambda (_events) (let loop () (loop))) '())))
  (check-false
   (terminal-event-handler-outcome-accepted?
    (call-with-terminal-event-handler
     "memory" 25 memory-limit
     (lambda (_events) (make-bytes (* 64 1024 1024))) '())))
  (check-false
   (terminal-event-handler-outcome-accepted?
    (call-with-terminal-event-handler
     "malformed" 25 memory-limit (lambda (_events) 'invalid) '()))))
