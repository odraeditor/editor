#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/command/api.rkt"
         (only-in "../../src/command/ksawery-operation.rkt"
                  encode-ksawery-operation-plan
                  ksawery-operation-plan-environment
                  ksawery-operation-plan-refresh))

(define (word encoded index)
  (integer-bytes->integer encoded #f #f (* index 8) (* (add1 index) 8)))

(define operation-contribution
  (make-ksawery-contribution
   7 'operations.review 'external-operation
   #:observations '(status refs process)
   #:authorities '(inspect submit-external-operation)))
(define contributor
  (make-ksawery-contributor
   'personal.repository-tools "Repository tools" "modules/repository-tools.rkt"
   5 (list operation-contribution)))
(define ref-target
  (make-ksawery-annotation-target 'ref 19 #"refs/heads/main"))
(define verifier
  (make-ksawery-operation-verifier
   'target-present #:observation 'refs #:target ref-target))
(define plan
  (make-ksawery-operation-plan
   contributor 7 11 'operations.clean-status "Inspect repository status" 17
   (make-ksawery-operation-git) '("status" "--porcelain=v2")
   'read-only '(status refs) verifier))
(define encoded (encode-ksawery-operation-plan plan))

(check-true (ksawery-operation-plan? plan))
(check-equal? (ksawery-operation-plan-environment plan) 'core-repository)
(check-equal? (ksawery-operation-plan-refresh plan) '(status refs))
(check-equal? (word encoded 0) 1)
(check-equal? (word encoded 1) (bytes-length encoded))
(check-equal? (word encoded 2) 5)
(check-equal? (word encoded 3) 7)
(check-equal? (word encoded 4) 11)
(check-equal? (word encoded 5) 17)
(check-equal? (word encoded 6) 1)
(check-equal? (word encoded 7) #b101)
(check-equal? (word encoded 8) 1)
(check-equal? (word encoded 10) 1)
(check-equal? (word encoded 11) 2)
(check-equal? (word encoded 19) 3)
(check-equal? (word encoded 20) 0)
(check-equal? (word encoded 21) 0)

(define configured-plan
  (make-ksawery-operation-plan
   contributor 7 12 'operations.inspect-object "Inspect one object" 18
   (make-ksawery-operation-executable 'tools.inspector "/opt/odra/bin/inspect")
   '("--object" "HEAD") 'read-only '(refs process)
   (make-ksawery-operation-verifier 'observation-available #:observation 'process)
   #:diagnostic-policy 'suppressed))
(define configured-encoded (encode-ksawery-operation-plan configured-plan))

(check-equal? (word configured-encoded 10) 2)
(check-true (positive? (word configured-encoded 19)))
(check-true (positive? (word configured-encoded 21)))
(check-equal? (subbytes configured-encoded
                        (+ 192 32 56 (* 2 16) (word configured-encoded 18))
                        (+ 192 32 56 (* 2 16)
                           (word configured-encoded 18) (word configured-encoded 19)))
              #"tools.inspector")

(define opaque-target
  (make-ksawery-annotation-target 'ref 21 #"refs/heads/\377private"))
(check-not-exn
 (lambda ()
   (encode-ksawery-operation-plan
    (make-ksawery-operation-plan
     contributor 7 14 'operations.opaque-target "Inspect opaque target" 20
     (make-ksawery-operation-git) '("show-ref") 'read-only '(refs)
     (make-ksawery-operation-verifier
      'target-present #:observation 'refs #:target opaque-target)))))

;; The public constructor admits only fixed policy keywords, never process injection fields.
(define-values (required-keywords accepted-keywords)
  (procedure-keywords make-ksawery-operation-plan))
(check-equal? required-keywords '())
(check-equal? accepted-keywords '(#:diagnostic-policy #:limits))

(check-exn #rx"configured executable path must be absolute"
           (lambda ()
             (make-ksawery-operation-executable 'tools.inspector "bin/inspect")))
(check-exn #rx"text exceeds immutable policy"
           (lambda ()
             (make-ksawery-operation-plan
              contributor 7 13 'operations.invalid "Invalid argument" 19
              (make-ksawery-operation-git) (list "status\u0000--short")
              'read-only '(status)
              (make-ksawery-operation-verifier
               'observation-available #:observation 'status))))
(check-exn #rx"symbol list is invalid"
           (lambda ()
             (make-ksawery-operation-plan
              contributor 7 13 'operations.invalid "Duplicate refresh" 19
              (make-ksawery-operation-git) '("status") 'read-only '(status status)
              (make-ksawery-operation-verifier
               'observation-available #:observation 'status))))
(check-exn #rx"exceed immutable policy"
           (lambda ()
             (make-ksawery-operation-limits #:deadline-milliseconds 600001)))
(check-exn #rx"verifier fields are inconsistent"
           (lambda ()
             (make-ksawery-operation-verifier
              'target-present #:observation 'history #:target ref-target)))
(check-exn #rx"executable or verifier is not admitted"
           (lambda ()
             (make-ksawery-operation-plan
              contributor 7 13 'operations.invalid "Missing refresh" 19
              (make-ksawery-operation-git) '("status") 'read-only '(status)
              verifier)))

(define missing-authority-contributor
  (make-ksawery-contributor
   'personal.read-only "Read only" "modules/read-only.rkt" 3
   (list
    (make-ksawery-contribution
     9 'operations.read-only 'external-operation
     #:observations '(status) #:authorities '(inspect)))))
(check-exn #rx"contribution does not admit"
           (lambda ()
             (make-ksawery-operation-plan
              missing-authority-contributor 9 1 'operations.denied "Denied" 1
              (make-ksawery-operation-git) '("status") 'read-only '(status)
              (make-ksawery-operation-verifier
               'observation-available #:observation 'status))))

(define command-contributor
  (make-ksawery-contributor
   'personal.commands "Commands" "modules/commands.rkt" 3
   (list
    (make-ksawery-contribution
     9 'commands.status 'command-family
     #:observations '(status) #:authorities '(inspect request-core-action)))))
(check-exn #rx"contribution does not admit"
           (lambda ()
             (make-ksawery-operation-plan
              command-contributor 9 1 'operations.denied "Wrong kind" 1
              (make-ksawery-operation-git) '("status") 'read-only '(status)
              (make-ksawery-operation-verifier
               'observation-available #:observation 'status))))
