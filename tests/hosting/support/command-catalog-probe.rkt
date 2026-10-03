#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require "../../../src/command/catalog.rkt"
         "../../../src/command/native-contracts.rkt"
         (submod "../../../src/hosting/command-catalog-bridge.rkt" test-support))

(provide runtime-command-catalog-batch-probe)

(define header-bytes
  (native-contract-value 'command-catalog 'header-bytes))
(define record-bytes
  (native-contract-value 'command-catalog 'record-bytes))
(define maximum-commands
  (native-contract-value 'command-catalog 'maximum-commands))

(define (read-u64 batch offset)
  (integer-bytes->integer batch #f #f offset (+ offset 8)))

(define (duplicate-command-batch batch)
  (define first-record header-bytes)
  (define second-record (+ header-bytes record-bytes))
  (define first-name-offset (read-u64 batch (+ first-record 48)))
  (define first-name-bytes (read-u64 batch (+ first-record 56)))
  (batch-with-u64
   (batch-with-u64 batch (+ second-record 48) first-name-offset)
   (+ second-record 56)
   first-name-bytes))

(define extra-command
  (make-command-definition
   "test-lowercase-line"
   'transaction
   'ordinary
   'prohibited
   '(buffer view text-mutation)
   "Lowercase one test line."
   (lambda (_transaction _start _end) (void))
   #:requirements '(active-buffer)
   #:provider "test"
   #:source "command-catalog-probe"))

(define (extended-catalog)
  (define factory (factory-command-catalog))
  (compose-command-catalog
   2
   (append (odra-command-catalog-definitions factory) (list extra-command))))

(define personal-command
  (make-command-definition
   "personal-normalize-heading"
   'personal
   'ordinary
   'prohibited
   '(buffer view text-mutation)
   "Normalize the active heading."
   (lambda (_context) (void))
   #:requirements '(active-buffer)
   #:provider "personal"
   #:source "modules/text.rkt"
   #:location "7:3"))

(define (personal-catalog)
  (compose-personal-command-catalog 2 (list personal-command)))

(define ksawery-extension-command
  (make-command-definition
   "personal.repository-tools/family.refs/action.push"
   'ksawery-extension
   'ordinary
   'prohibited
   '(lifecycle)
   "Push"
   (lambda (_context) (void))
   #:requirements '(active-buffer)
   #:provider "personal.repository-tools"
   #:source "modules/repository-tools.rkt"
   #:location "family.refs"))

(define (ksawery-extension-catalog)
  (compose-personal-command-catalog 2 '() (list ksawery-extension-command)))

;; runtime-command-catalog-batch-probe returns bounded adversarial catalog copies.
(define (runtime-command-catalog-batch-probe scenario registry-generation)
  (with-handlers ([exn?
                   (lambda (failure)
                     (list #f registry-generation #""
                           (string->bytes/utf-8 (exn-message failure))))])
    (define production (command-catalog-batch registry-generation))
    (define batch
      (case scenario
        [(1) (error 'runtime-command-catalog-batch-probe
                    "requested command catalog exception")]
        [(2) (batch-with-u64 production 0 99)]
        [(3) (duplicate-command-batch production)]
        [(4) (batch-with-u64 production (+ header-bytes 24) #x10)]
        [(5) (batch-with-u64 production 32 (add1 maximum-commands))]
        [(6) (batch-with-u64 production 16 (add1 registry-generation))]
        [(7) (command-catalog-batch registry-generation (extended-catalog))]
        [(8) (command-catalog-batch registry-generation (personal-catalog))]
        [(9) (command-catalog-batch registry-generation (ksawery-extension-catalog))]
        [else
         (raise-argument-error
          'runtime-command-catalog-batch-probe
          "an integer from 1 through 9"
          scenario)]))
    (list #t registry-generation batch #"")))

(module+ test
  (require rackunit)

  (for ([scenario (in-range 2 10)])
    (define result (runtime-command-catalog-batch-probe scenario 17))
    (check-true (car result))
    (check-equal? (cadr result) 17))
  (check-equal?
   (read-u64 (caddr (runtime-command-catalog-batch-probe 7 17)) 32)
   8)
  (check-equal?
   (read-u64 (caddr (runtime-command-catalog-batch-probe 8 17)) 32)
   8)
  (check-equal?
   (read-u64 (caddr (runtime-command-catalog-batch-probe 9 17)) 32)
   8))
