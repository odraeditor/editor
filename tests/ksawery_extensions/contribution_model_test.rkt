#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/command/api.rkt")

(define status-contribution
  (make-ksawery-contribution
   1 'status.ahead-behind 'status-section
   #:observations '(status refs)
   #:authorities '(inspect present)))

(define contributor
  (make-ksawery-contributor
   'personal.repository-tools "Repository tools"
   "/tmp/config/ksawery.rkt" 1 (list status-contribution)))

(check-true (ksawery-contributor? contributor))
(check-true (ksawery-contributor-compatible? contributor))
(check-equal? (decode-ksawery-contributor
               (ksawery-contributor->datum contributor))
              contributor)

(check-exn
 #rx"incompatible Ksawery extension API"
 (lambda ()
   (make-ksawery-contributor
    'personal.repository-tools "Repository tools"
    "/tmp/config/ksawery.rkt" 2 (list status-contribution)
    #:api-version 2)))

(check-exn
 #rx"duplicate contribution identity"
 (lambda ()
   (make-ksawery-contributor
    'personal.repository-tools "Repository tools"
    "/tmp/config/ksawery.rkt" 2
    (list status-contribution status-contribution))))

(check-exn
 #rx"provider-role is valid only"
 (lambda ()
   (make-ksawery-contribution
    2 'invalid.role 'command #:provider-role 'conflict-assistance)))

(check-exn
 #rx"non-reentrant"
 (lambda () (make-ksawery-extension-limits #:nesting-depth 2)))
