#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         racket/file
         "../../src/command/recovery.rkt"
         "../../src/configuration/personal.rkt")

(define (with-configuration-root action)
  (define root
    (make-temporary-file "odra-recovery-configuration-~a" 'directory))
  (dynamic-wind
   void
   (lambda () (action root))
   (lambda () (delete-directory/files root))))

(define (write-init! root content)
  (call-with-output-file
   (build-path root "init.rkt")
   #:exists 'truncate/replace
   (lambda (output) (display content output))))

(test-case "factory recovery policy is safe and enabled"
  (check-true (odra-recovery-policy-enabled? factory-recovery-policy))
  (check-eq? (odra-recovery-policy-strategy factory-recovery-policy) 'hybrid)
  (check-equal?
   (odra-recovery-policy-debounce-milliseconds factory-recovery-policy)
   300)
  (check-equal?
   (odra-recovery-policy-maximum-interval-milliseconds
    factory-recovery-policy)
   5000)
  (check-eq? (odra-recovery-policy-source-autosave factory-recovery-policy)
             'disabled))

(test-case "personal recovery policy reload preserves the last confirmed generation"
  (with-configuration-root
   (lambda (root)
     (write-init!
      root
      (string-append
       "#lang racket/base\n"
       "(require odra/recovery)\n"
       "(provide odra-recovery-policy)\n"
       "(define odra-recovery-policy\n"
       "  (recovery-policy #:enabled? #f #:startup 'inspect))\n"))
     (define source (personal-config-source root))
     (define confirmed
       (personal-config-reload (personal-config-initialize) 1 source))
     (check-eq? (odra-personal-config-result-status confirmed) 'confirmed)
     (define confirmed-state (odra-personal-config-result-state confirmed))
     (check-equal?
      (odra-personal-config-state-confirmed-generation confirmed-state)
      2)
     (define confirmed-policy
       (personal-config-proposal-export
        (odra-personal-config-state-proposal confirmed-state)
        'odra-recovery-policy))
     (check-false (odra-recovery-policy-enabled? confirmed-policy))
     (check-eq? (odra-recovery-policy-startup confirmed-policy) 'inspect)

     (write-init!
      root
      (string-append
       "#lang racket/base\n"
       "(provide odra-recovery-policy)\n"
       "(define odra-recovery-policy 'invalid)\n"))
     (define rejected
       (personal-config-reload confirmed-state 2 source))
     (check-eq? (odra-personal-config-result-status rejected) 'rejected)
     (define rejected-state (odra-personal-config-result-state rejected))
     (check-equal?
      (odra-personal-config-state-confirmed-generation rejected-state)
      2)
     (check-equal?
      (personal-config-proposal-export
       (odra-personal-config-state-proposal rejected-state)
       'odra-recovery-policy)
      confirmed-policy)
     (check-equal?
      (odra-personal-config-state-rejected-generation rejected-state)
      1))))

(test-case "recovery policy constructors reject unsafe limits"
  (check-exn exn:fail?
             (lambda ()
               (recovery-retention #:records-per-buffer 32
                                   #:total-records 16)))
  (check-exn exn:fail?
             (lambda ()
               (recovery-storage-limits
                #:buffer-storage-bytes (* 4 1024 1024 1024)
                #:store-storage-bytes (* 2 1024 1024 1024))))
  (check-exn exn:fail?
             (lambda ()
               (recovery-policy #:strategy 'unknown))))
