#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/command/context.rkt"
         "../../src/command/personal-limits.rkt"
         "../../src/command/transaction.rkt")

(define ordinary-source (string->bytes/utf-8 "ask αsk\nnext\n"))
(define demanding-source (make-bytes (* 8 1024 1024) 97))

(define (measure name source command
                 #:point [point 0]
                 #:region-start [region-start #f]
                 #:region-end [region-end #f]
                 #:line-end [line-end (bytes-length source)])
  (collect-garbage)
  (define memory-before (current-memory-use))
  (define started (current-inexact-monotonic-milliseconds))
  (call-with-transaction
   1
   (lambda (_token operation payload)
     (case operation
       [(inspect)
        (list 'ok
              (subbytes source
                        (hash-ref payload 'start)
                        (hash-ref payload 'end)))]
       [(splice apply-batch abort) (list 'ok #t)]))
   (lambda (transaction)
     (call-with-command-context
      transaction 1 point region-start region-end 0 line-end
      (bytes-length source) '(buffer view text-mutation) (lambda () #f)
      command))
   #:limits
   (make-transaction-limits
    #:inspection-bytes
    (personal-command-limits-inspection-bytes
     default-personal-command-limits)
    #:batch-splices
    (personal-command-limits-splices default-personal-command-limits)
    #:text-bytes
    (personal-command-limits-replacement-bytes
     default-personal-command-limits)
    #:nested-depth
    (personal-command-limits-nested-operations
     default-personal-command-limits)))
  (define elapsed
    (- (current-inexact-monotonic-milliseconds) started))
  (define allocated (max 0 (- (current-memory-use) memory-before)))
  (printf "study=personal-command profile=~a valid=true elapsed_ms=~a allocated_bytes=~a source_bytes=~a\n"
          name (inexact->exact (ceiling elapsed)) allocated (bytes-length source)))

(measure 'no-op ordinary-source void)
(measure 'current-line ordinary-source
         (lambda (context)
           (command-context-read context (command-context-current-line context))))
(measure 'active-region ordinary-source
         (lambda (context)
           (command-context-read context (command-context-active-region context)))
         #:region-start 4 #:region-end 8 #:line-end 8)
(measure 'complete-buffer demanding-source
         (lambda (context)
           (command-context-read context (command-context-buffer-range context))))
(measure 'unicode ordinary-source
         (lambda (context)
           (define line (command-context-current-line context))
           (command-context-replace! context line "pytaj λ"))
         #:line-end 8)
(measure 'batch ordinary-source
         (lambda (context)
           (define line (command-context-current-line context))
           (command-context-replace-batch!
            context
            (list (make-text-edit line "ASK")
                  (make-text-edit
                   (let ([buffer (command-context-buffer-range context)])
                     ;; Obtain a distinct range through the active region.
                     (command-context-active-region context))
                   "NEXT"))))
         #:region-start 9 #:region-end 13 #:line-end 8)

(check-exn
 #rx"work-limit"
 (lambda ()
   (measure 'rejected
            (make-bytes (add1
                         (personal-command-limits-inspection-bytes
                          default-personal-command-limits))
                        97)
            (lambda (context)
              (command-context-read context
                                    (command-context-buffer-range context))))))

(printf
 "study=personal-command profile=policy valid=true deadline_ms=~a custodian_memory_bytes=~a inspection_bytes=~a replacement_bytes=~a splices=~a temporary_native_bytes=~a nested_operations=~a diagnostic_bytes=~a\n"
 (personal-command-limits-deadline-milliseconds default-personal-command-limits)
 (personal-command-limits-custodian-memory-bytes default-personal-command-limits)
 (personal-command-limits-inspection-bytes default-personal-command-limits)
 (personal-command-limits-replacement-bytes default-personal-command-limits)
 (personal-command-limits-splices default-personal-command-limits)
 (personal-command-limits-temporary-native-bytes default-personal-command-limits)
 (personal-command-limits-nested-operations default-personal-command-limits)
 (personal-command-limits-diagnostic-bytes default-personal-command-limits))
