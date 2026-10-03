#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         rackunit
         "../../src/command/language-bundles.rkt"
         "../../src/language_bundle/activation-candidate.rkt"
         "../../src/language_bundle/advisory-response.rkt"
         "../../src/language_bundle/lifecycle.rkt"
         "../../src/language_bundle/state-records.rkt"
         "../../src/package_catalog/integrity.rkt"
         "../../src/package_catalog/security-advisories.rkt")

(define digest-a (make-string 64 #\a))
(define digest-b (make-string 64 #\b))
(define digest-c (make-string 64 #\c))
(define signature
  (odra-package-catalog-signature
   'ed25519 digest-a package-catalog-advisory-signature-domain
   (make-string 128 #\d)))
(define policy
  (odra-security-advisory-response-policy
   "default-security" 1 '(warn)
   '(block-acquisition block-activation deactivate quarantine rollback warn)
   '(block-activation warn) '(warn) #f))

(define (make-advisory digest)
  (odra-security-advisory
   1 "odra-2026-001" "official-security" digest-c 1 'active 'malicious
   'critical 'confirmed '() '() (list digest)
   '(block-acquisition block-activation deactivate quarantine rollback warn)
   "Confirmed malicious lifecycle fixture." 20 #f (list signature)))

(define (evaluator digest)
  (make-security-advisory-evaluator
   (list (make-advisory digest)) policy 30 '()))

(define (make-request version manifest-digest)
  (define bundle
    (language-support-bundle
     #:id 'org.example.language #:display-name "Example Language"
     #:version version #:api-min "1.0.0" #:api-max "2.0.0"
     #:description "Advisory lifecycle fixture." #:publisher 'org.example
     #:source 'catalog.example #:targets '((linux x86-64))
     #:languages (list (language #:id 'example #:suffixes '(".example")))
     #:commands
     (list
      (language-command
       #:id 'example-command #:description "Run the example command."
       #:implementation 'example-command))))
  (odra-bundle-install-request
   (odra-bundle-preparation-input
    bundle 'package "org.example.language" '() (hasheq) (hasheq) 0)
   manifest-digest 'linux 'x86-64 "user grant" 512 0))

(define (with-root action)
  (define root (make-temporary-file "odra-advisory-lifecycle-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind void (lambda () (action root))
                (lambda () (delete-directory/files root))))

(define (record-for manager version)
  (for/first ([record
               (in-list
                (odra-language-bundle-state-bundles
                 (bundle-lifecycle-state manager)))]
              #:when (string=? version (odra-installed-bundle-version record)))
    record))

(test-case "exact malicious digest blocks installation while a near digest installs"
  (with-root
   (lambda (_root)
     (define manager
       (make-bundle-lifecycle-manager
        _root #:advisory-evaluator (evaluator digest-a)))
     (define blocked
       (bundle-lifecycle-install! manager (make-request "1.0.0" digest-a)))
     (check-eq? (odra-bundle-lifecycle-result-state blocked) 'rejected)
     (check-equal? (odra-language-bundle-state-bundles
                    (bundle-lifecycle-state manager))
                   '())
     (define installed
       (bundle-lifecycle-install! manager (make-request "1.0.1" digest-b)))
     (check-eq? (odra-bundle-lifecycle-result-state installed) 'installed))))

(test-case "new advisory suppresses restart and requires explicit deactivation"
  (with-root
   (lambda (root)
     (define request (make-request "1.0.0" digest-a))
     (define initial (make-bundle-lifecycle-manager root))
     (bundle-lifecycle-install! initial request)
     (bundle-lifecycle-enable! initial "org.example.language" "1.0.0")
     (define guarded
       (make-bundle-lifecycle-manager
        root #:inputs (list request) #:advisory-evaluator (evaluator digest-a)))
     (check-false (bundle-lifecycle-runtime-snapshot guarded))
     (define response
       (bundle-lifecycle-advisory-response
        guarded "org.example.language" "1.0.0"))
     (check-not-false
      (member 'deactivate (odra-security-advisory-response-actions response)))
     (check-eq?
      (odra-bundle-lifecycle-result-state
       (bundle-lifecycle-quarantine!
        guarded "org.example.language" "1.0.0"))
      'rejected)
     (check-eq?
      (odra-bundle-lifecycle-result-state
       (bundle-lifecycle-disable! guarded "org.example.language"))
      'disable)
     (check-eq?
      (odra-bundle-lifecycle-result-state
       (bundle-lifecycle-quarantine!
        guarded "org.example.language" "1.0.0"))
      'quarantined)
     (check-eq?
      (odra-installed-bundle-lifecycle (record-for guarded "1.0.0"))
      'quarantined))))

(test-case "quarantine survives restart and protects exact content from cleanup"
  (with-root
   (lambda (root)
     (define request (make-request "1.0.0" digest-a))
     (define manager (make-bundle-lifecycle-manager root))
     (bundle-lifecycle-install! manager request)
     (define guarded
       (make-bundle-lifecycle-manager
        root #:inputs (list request) #:advisory-evaluator (evaluator digest-a)))
     (bundle-lifecycle-quarantine!
      guarded "org.example.language" "1.0.0")
     (define restarted
       (make-bundle-lifecycle-manager
        root #:inputs (list request) #:advisory-evaluator (evaluator digest-a)))
     (check-eq?
      (odra-installed-bundle-lifecycle (record-for restarted "1.0.0"))
      'quarantined)
     (check-eq?
      (odra-bundle-lifecycle-result-state
       (bundle-lifecycle-enable!
        restarted "org.example.language" "1.0.0"))
      'rejected)
     (define deleted '())
     (bundle-lifecycle-garbage-collect!
      restarted (list digest-a digest-b)
      (lambda (digest) (set! deleted (cons digest deleted)) #t))
     (check-equal? deleted (list digest-b))
     (check-not-false
      (member digest-a
              (odra-language-bundle-state-quarantine
               (bundle-lifecycle-state restarted)))))))

(test-case "advisory blocks the active generation but preserves explicit benign rollback"
  (with-root
   (lambda (root)
     (define first (make-request "1.0.0" digest-a))
     (define second (make-request "1.1.0" digest-b))
     (define initial (make-bundle-lifecycle-manager root))
     (bundle-lifecycle-install! initial first)
     (bundle-lifecycle-enable! initial "org.example.language" "1.0.0")
     (bundle-lifecycle-update! initial second)
     (define guarded
       (make-bundle-lifecycle-manager
        root #:inputs (list first second)
        #:advisory-evaluator (evaluator digest-b)))
     (define rolled-back
       (bundle-lifecycle-rollback! guarded "org.example.language"))
     (check-eq? (odra-bundle-lifecycle-result-state rolled-back) 'rolled-back)
     (check-eq?
      (odra-installed-bundle-lifecycle (record-for guarded "1.0.0"))
      'active-confirmed))))
