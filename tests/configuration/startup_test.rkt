#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         racket/file
         "../../src/hosting/personal-configuration-bridge.rkt")

(define schema-version 10)
(define header-bytes 464)
(define result-confirmed 1)
(define result-rejected 2)
(define observation-absent 1)
(define observation-confirmed 2)
(define observation-rejected 3)

(define (with-root action)
  (define root (make-temporary-file "odra-startup-config-~a" 'directory))
  (dynamic-wind void (lambda () (action root))
                (lambda () (delete-directory/files root))))

(define (configuration-root root)
  (build-path root "config" "odra"))

(define (write-init root content)
  (define config-root (configuration-root root))
  (make-directory* config-root)
  (call-with-output-file (build-path config-root "init.rkt")
    (lambda (output) (display content output))
    #:exists 'truncate/replace))

(define (startup-batch root)
  (define result
    (runtime-personal-configuration-startup-batch
     (path->bytes (configuration-root root))))
  (check-true (car result))
  (cadr result))

(define (word batch offset)
  (integer-bytes->integer batch #f #f offset (+ offset 8)))

  (test-case "startup accepts missing init silently"
  (with-root
   (lambda (root)
     (define batch (startup-batch root))
     (check-equal? (word batch 0) schema-version)
     (check-equal? (word batch 8) result-confirmed)
     (check-equal? (word batch 16) observation-absent)
     (check-equal? (word batch 24) 2)
     (check-equal? (word batch 32) 0)
     (check-equal? (word batch 40) 0)
     (check-equal? (word batch 48) 1)
     (check-equal? (word batch 56) 1)
     (check-equal? (word batch 64) #x1f)
     (check-equal? (bytes-length batch)
                   (+ header-bytes
                      (word batch 40)
                      (word batch 152)
                      (word batch 160)
                      (word batch 168)
                      (word batch 328)
                      (word batch 336)
                      (word batch 344)
                      (word batch 456))))))

(test-case "startup batch confirms a valid personal init"
  (with-root
   (lambda (root)
     (write-init root "#lang racket/base\n(define selected-theme 'wroclaw-night)\n")
     (define batch (startup-batch root))
     (check-equal? (word batch 8) result-confirmed)
     (check-equal? (word batch 16) observation-confirmed)
     (check-equal? (word batch 24) 2)
     (check-equal? (word batch 32) 0)
     (check-equal? (word batch 40) 0))))

  (test-case "startup rejects init and keeps defaults"
  (with-root
   (lambda (root)
     (write-init root "#lang racket/base\n(define broken\n")
     (define batch (startup-batch root))
     (check-equal? (word batch 8) result-rejected)
     (check-equal? (word batch 16) observation-rejected)
     (check-equal? (word batch 24) 1)
     (check-equal? (word batch 32) 1)
     (check-true (> (word batch 40) 0))
     (check-true (> (bytes-length batch) header-bytes)))))
