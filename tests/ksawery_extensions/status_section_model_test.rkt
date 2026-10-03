#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/command/api.rkt"
         (only-in "../../src/command/ksawery-status-section.rkt"
                  decode-ksawery-status-proposal
                  encode-ksawery-status-proposal
                  ksawery-status-proposal->datum
                  ksawery-status-proposal-value-sections
                  ksawery-status-section-value-identity))

(define status-contribution
  (make-ksawery-contribution
   7 'status.ahead-behind 'status-section
   #:observations '(status refs)
   #:authorities '(inspect present)))
(define contributor
  (make-ksawery-contributor
   'personal.repository-tools "Repository tools"
   "/tmp/config/odra/init.rkt" 5 (list status-contribution)))
(define ahead
  (make-ksawery-status-item
   1 'branch.ahead "Ahead 3"
   #:detail "Local commits not on upstream"
   #:style 'warning
   #:command (make-ksawery-status-command-reference 'ksawery-history)
   #:metadata
   (list (make-ksawery-status-metadata 'revision.count "3"))))
(define behind
  (make-ksawery-status-item 2 'branch.behind "Behind 1" #:style 'information))
(define section
  (make-ksawery-status-section
   7 'status.tracking "Tracking" (list ahead behind)))
(define proposal
  (compose-ksawery-status-proposal
   contributor "/tmp/repository" 13 11 (list section)))

(check-equal?
 (decode-ksawery-status-proposal (ksawery-status-proposal->datum proposal))
 proposal)
(define encoded (encode-ksawery-status-proposal proposal))
(define (word offset)
  (integer-bytes->integer encoded #f #f offset (+ offset 8)))
(check-equal? (word 0) 1)
(check-equal? (word 8) (bytes-length encoded))
(check-equal? (word 16) 1)
(check-equal? (word 24) 2)
(check-equal? (word 32) 1)
(check-equal? (word 48) 5)
(check-equal? (word 56) 11)
(check-equal? (word 64) 13)

(define later
  (make-ksawery-status-section 7 'status.zeta "Later" '()))
(define earlier
  (make-ksawery-status-section 7 'status.alpha "Earlier" '()))
(define ordered
  (compose-ksawery-status-proposal
   contributor "/tmp/repository" 13 12 (list later earlier)))
(check-equal?
 (map ksawery-status-section-value-identity
      (ksawery-status-proposal-value-sections ordered))
 '("status.alpha" "status.zeta"))

(check-exn
 #rx"declared Status contribution"
 (lambda ()
   (compose-ksawery-status-proposal
    contributor "/tmp/repository" 13 12
    (list (make-ksawery-status-section 99 'status.invalid "Invalid" '())))))
(check-exn
 #rx"section identities must be unique"
 (lambda ()
   (compose-ksawery-status-proposal
    contributor "/tmp/repository" 13 12 (list section section))))
(check-exn
 #rx"metadata keys must be unique"
 (lambda ()
   (make-ksawery-status-item
    3 'branch.duplicate "Duplicate"
    #:metadata
    (list (make-ksawery-status-metadata 'key.value "a")
          (make-ksawery-status-metadata 'key.value "b")))))
(check-exn
 #rx"semantic role"
 (lambda ()
   (make-ksawery-status-item 4 'branch.invalid "Invalid" #:style 'raw-terminal-red)))
