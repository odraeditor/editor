#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         rackunit
         "../../src/command/language-bundles.rkt"
         "../../src/language_bundle/activation-candidate.rkt"
         "../../src/language_bundle/lifecycle.rkt"
         "../../src/language_bundle/state-persistence.rkt"
         "../../src/language_bundle/state-records.rkt")

(define digest-a (make-string 64 #\a))
(define digest-b (make-string 64 #\b))
(define digest-c (make-string 64 #\c))
(define target '((linux x86-64)))

(define (make-request version digest)
  (define value
    (language-support-bundle
     #:id 'org.example.language #:display-name "Example Language"
     #:version version #:api-min "1.0.0" #:api-max "2.0.0"
     #:description "Lifecycle fixture." #:publisher 'org.example
     #:source 'catalog.example #:targets target
     #:languages (list (language #:id 'example #:suffixes '(".example")))
     #:commands
     (list (language-command #:id 'example-command
                             #:description "Run the example command."
                             #:implementation 'example-command))))
  (odra-bundle-install-request
   (odra-bundle-preparation-input value 'package "org.example.language"
                                  '() (hasheq) (hasheq) 0)
   digest 'linux 'x86-64 "user grant" 512 0))

(define (with-manager action)
  (define root (make-temporary-file "odra-bundle-lifecycle-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind
    void
    (lambda () (action root (make-bundle-lifecycle-manager root)))
    (lambda () (delete-directory/files root))))

(define (record-state manager version)
  (odra-installed-bundle-lifecycle
   (for/first ([record
                (in-list
                 (odra-language-bundle-state-bundles
                  (bundle-lifecycle-state manager)))]
               #:when (string=? version (odra-installed-bundle-version record)))
     record)))

(test-case "install enable disable and verify use durable exact generations"
  (with-manager
   (lambda (root manager)
     (define request (make-request "1.0.0" digest-a))
     (define installed (bundle-lifecycle-install! manager request))
     (check-eq? (odra-bundle-lifecycle-result-state installed)
                'installed
                (odra-bundle-lifecycle-result-detail installed))
     (check-eq? (record-state manager "1.0.0") 'installed-disabled)
     (check-eq? (odra-bundle-lifecycle-result-state
                 (bundle-lifecycle-enable! manager "org.example.language" "1.0.0"))
                'enable)
     (check-eq? (record-state manager "1.0.0") 'active-confirmed)
     (check-eq? (odra-bundle-lifecycle-result-state
                 (bundle-lifecycle-verify! manager "org.example.language" "1.0.0"))
                'verified)
     (check-eq? (odra-bundle-lifecycle-result-state
                 (bundle-lifecycle-disable! manager "org.example.language"))
                'disable)
     (check-eq? (record-state manager "1.0.0") 'installed-disabled)
     (check-eq? (odra-language-bundle-startup-mode
                 (language-bundle-state-startup root))
                'confirmed))))

(test-case "update retains one rollback generation and rollback reactivates it"
  (with-manager
   (lambda (_ manager)
     (define first (make-request "1.0.0" digest-a))
     (define second (make-request "1.1.0" digest-b))
     (bundle-lifecycle-install! manager first)
     (bundle-lifecycle-enable! manager "org.example.language" "1.0.0")
     (define updated (bundle-lifecycle-update! manager second))
     (check-eq? (odra-bundle-lifecycle-result-state updated)
                'updated
                (odra-bundle-lifecycle-result-detail updated))
     (check-eq? (record-state manager "1.0.0") 'rollback-available)
     (check-eq? (record-state manager "1.1.0") 'active-confirmed)
     (check-true (odra-activation-lock?
                  (odra-language-bundle-state-previous-lock
                   (bundle-lifecycle-state manager))))
     (check-eq? (odra-bundle-lifecycle-result-state
                 (bundle-lifecycle-rollback! manager "org.example.language"))
                'rolled-back)
     (check-eq? (record-state manager "1.0.0") 'active-confirmed))))

(test-case "remove precedes garbage collection and never deletes reachable content"
  (with-manager
   (lambda (_ manager)
     (define request (make-request "1.0.0" digest-a))
     (bundle-lifecycle-install! manager request)
     (define removed
       (bundle-lifecycle-remove! manager "org.example.language" "1.0.0"))
     (check-eq? (odra-bundle-lifecycle-result-state removed)
                'removed
                (odra-bundle-lifecycle-result-detail removed))
     (define deleted '())
     (define collected
       (bundle-lifecycle-garbage-collect!
        manager (list digest-a digest-b digest-c)
        (lambda (digest) (set! deleted (cons digest deleted)) #t)))
     (check-eq? (odra-bundle-lifecycle-result-state collected) 'garbage-collected)
     (check-equal? (sort deleted string<?) (list digest-a digest-b digest-c))
     (check-equal? (odra-language-bundle-state-bundles
                    (bundle-lifecycle-state manager))
                   '()))))
