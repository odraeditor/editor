#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         racket/file
         "../../src/configuration/personal.rkt"
         (only-in "../../src/command/gutter-provider.rkt"
                  odra-gutter-provider?
                  odra-gutter-provider-generation)
         (only-in "../../src/hosting/personal-configuration-bridge.rkt"
                  runtime-personal-configuration-startup-batch
                  runtime-personal-generation-transition))

(define (write-configuration root body)
  (make-directory* root)
  (call-with-output-file (build-path root "init.rkt")
    (lambda (output) (display body output))
    #:exists 'truncate/replace))

(define valid-configuration
  (string-append
   "#lang racket/base\n"
   "(require odra/gutters)\n"
   "(provide odra-gutter-provider)\n"
   "(define odra-gutter-provider\n"
   "  (gutter-provider\n"
   "   \"Personal Notes\" 'personal-notes\n"
   "   (list (gutter-lane 'notes))\n"
   "   (list (gutter-marker 'review 'notes 5 \"◆\"\n"
   "                        #:fallback \"*\"\n"
   "                        #:style 'diagnostic-information\n"
   "                        #:detail \"Review this line\"\n"
   "                        #:actions '(gutter-inspect-markers)))))\n"))

  (test-case "config admits one public Gutter provider"
  (define root (make-temporary-file "odra-gutter-provider-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define configuration-root (build-path root "config" "odra"))
     (write-configuration configuration-root valid-configuration)
     (define observation
       (personal-config-load (personal-config-source configuration-root)))
     (check-eq? (odra-personal-config-observation-state observation) 'confirmed)
     (define provider
       (personal-config-observation-export observation 'odra-gutter-provider))
     (check-true (odra-gutter-provider? provider))
     (check-equal? (odra-gutter-provider-generation provider) 1)

     (define startup
       (runtime-personal-configuration-startup-batch (path->bytes configuration-root)))
     (check-true (car startup))
     (define batch (cadr startup))
     (define (read-word offset)
       (integer-bytes->integer batch #f #f offset (+ offset 8)))
     (check-equal? (read-word 0) 5)
     (check-true (> (read-word 168) 0))
     (check-equal? (bytes-length batch)
                   (+ 328 (read-word 40) (read-word 152) (read-word 160)
                      (read-word 168)))
     (check-equal? (runtime-personal-generation-transition 1 (read-word 24))
                   '(#t #t #"")))
   (lambda () (delete-directory/files root))))

  (test-case "bad Gutter definitions reject candidate"
  (define root (make-temporary-file "odra-gutter-provider-invalid-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define configuration-root (build-path root "config" "odra"))
     (write-configuration
      configuration-root
      (string-append
       "#lang racket/base\n"
       "(require odra/gutters)\n"
       "(provide odra-gutter-provider)\n"
       "(define odra-gutter-provider\n"
       "  (gutter-provider \"Broken\" 'broken\n"
       "                   (list (gutter-lane 'notes))\n"
       "                   (list (gutter-marker 'bad 'missing 1 \"!\"))))\n"))
     (define observation
       (personal-config-load (personal-config-source configuration-root)))
     (check-eq? (odra-personal-config-observation-state observation) 'rejected)
     (check-regexp-match
      #rx"unknown lane"
      (odra-personal-config-diagnostic-message
       (odra-personal-config-observation-diagnostic observation))))
   (lambda () (delete-directory/files root))))
