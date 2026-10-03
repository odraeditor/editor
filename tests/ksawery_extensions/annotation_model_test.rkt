#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/command/api.rkt"
         (only-in "../../src/command/ksawery-annotation.rkt"
                  decode-ksawery-annotation-proposal
                  encode-ksawery-annotation-proposal
                  ksawery-annotation-proposal->datum
                  ksawery-annotation-proposal-value-annotations
                  ksawery-annotation-value-identity))

(define annotation-contribution
  (make-ksawery-contribution
   7 'annotations.repository-policy 'annotation
   #:observations '(status refs)
   #:authorities '(inspect present)))
(define contributor
  (make-ksawery-contributor
   'personal.repository-tools "Repository tools"
   "/tmp/config/odra/init.rkt" 5 (list annotation-contribution)))
(define main-target
  (make-ksawery-annotation-target 'ref 13 #"refs/heads/main"))
(define review-target
  (make-ksawery-annotation-target 'ref 13 #"refs/heads/review"))
(define protected
  (make-ksawery-annotation
   7 1 'annotation.protected main-target
   #:label "Protected"
   #:detail "Requires a reviewed update"
   #:severity 'warning
   #:style 'alert
   #:command (make-ksawery-annotation-command-reference 'command.open-history)))
(define review
  (make-ksawery-annotation
   7 2 'annotation.review review-target #:style 'information))
(define proposal
 (compose-ksawery-annotation-proposal
   contributor "/tmp/repository" 'refs 13 11 (list review protected)))

(check-equal?
 (decode-ksawery-annotation-proposal
  (ksawery-annotation-proposal->datum proposal))
 proposal)
(check-equal?
 (map ksawery-annotation-value-identity
      (ksawery-annotation-proposal-value-annotations proposal))
 '("annotation.protected" "annotation.review"))

(define encoded (encode-ksawery-annotation-proposal proposal))
(define (word offset)
  (integer-bytes->integer encoded #f #f offset (+ offset 8)))
(check-equal? (word 0) 1)
(check-equal? (word 8) (bytes-length encoded))
(check-equal? (word 16) 2)
(check-equal? (word 24) 5)
(check-equal? (word 32) 11)
(check-equal? (word 40) 2)
(check-equal? (word 48) 13)
(check-equal? (word 216) 3)
(check-equal? (word 224) 7)
(check-true (positive? (word 232)))
(check-equal? (word 240) (bytes-length #"command.open-history"))
(check-equal? (word 248) 3)
(check-equal? (word 368) 0)
(check-equal? (word 376) 8)
(check-equal? (word 384) 0)
(check-equal? (word 392) 0)
(check-equal? (word 400) 0)

(check-exn
 #rx"annotation content cannot be empty"
 (lambda ()
   (make-ksawery-annotation 7 3 'annotation.empty main-target)))
(check-exn
 #rx"annotation identities must be unique"
 (lambda ()
   (compose-ksawery-annotation-proposal
    contributor "/tmp/repository" 'refs 13 12 (list protected protected))))
(check-exn
 #rx"annotation target is stale"
 (lambda ()
   (compose-ksawery-annotation-proposal
    contributor "/tmp/repository" 'refs 14 12 (list protected))))
(check-exn
 #rx"incompatible with the observation"
 (lambda ()
   (compose-ksawery-annotation-proposal
    contributor "/tmp/repository" 'status 13 12 (list protected))))
(check-exn
 #rx"does not admit annotations"
 (lambda ()
   (compose-ksawery-annotation-proposal
    contributor "/tmp/repository" 'refs 13 12
    (list (make-ksawery-annotation 99 3 'annotation.unknown main-target
                                   #:style 'warning)))))
(check-exn
 #rx"target identity must be non-empty and bounded"
 (lambda () (make-ksawery-annotation-target 'ref 13 #"")))
