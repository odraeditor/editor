#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         rackunit
         "../../src/package_catalog/integrity.rkt"
         "../../src/package_catalog/security-advisories.rkt")

(define (digest character) (make-string 64 character))
(define signature
  (odra-package-catalog-signature
   'ed25519 (digest #\a) package-catalog-advisory-signature-domain
   (make-string 128 #\b)))
(define advisory
  (odra-security-advisory
   1 "odra-2026-001" "official-security" (digest #\c) 1 'active 'malicious
   'critical 'confirmed '("org.example.package") (list (digest #\d))
   (list (digest #\e))
   '(block-acquisition block-activation deactivate quarantine rollback warn)
   "Confirmed malicious content requires containment." 100 #f
   (list signature)))

(test-case "signed advisories retain exact bounded selectors"
  (check-equal? (odra-security-advisory-affected-artifact-digests advisory)
                (list (digest #\e)))
  (check-equal? (odra-security-advisory-classification advisory) 'malicious)
  (check-equal? (string-length (security-advisory-content-digest advisory)) 64))

(test-case "advisory module records round-trip through checked data"
  (define path (make-temporary-file "odra-security-advisory-~a.rktd"))
  (dynamic-wind
    (lambda ()
      (call-with-output-file path
        (lambda (output) (write-bytes (security-advisory->module-bytes advisory)
                                      output))
        #:exists 'truncate/replace #:mode 'binary))
    (lambda () (check-equal? (security-advisory-module-load path) advisory))
    (lambda () (delete-file path))))

(test-case "corrections require an exact predecessor generation"
  (check-exn
   exn:fail?
   (lambda () (struct-copy odra-security-advisory advisory [generation 2])))
  (check-not-exn
   (lambda ()
     (struct-copy
      odra-security-advisory advisory
      [generation 2]
      [state 'corrected]
      [supersedes
       (odra-security-advisory-generation-reference
        "odra-2026-001" 1 (security-advisory-content-digest advisory))]))))

(test-case "confirmed malicious defaults are explicit local policy"
  (define policy
    (odra-security-advisory-response-policy
     "default-security" 1 '(warn)
     '(block-acquisition block-activation deactivate quarantine rollback warn)
     '(block-activation warn) '(warn) #t))
  (check-not-false
   (member 'block-acquisition
           (odra-security-advisory-response-policy-confirmed-malicious-actions
            policy))))

(test-case "local overrides bind one advisory generation and exact digest"
  (define rationale "Temporary expert exception in an isolated environment.")
  (check-not-exn
   (lambda ()
     (make-security-advisory-policy-override
      "official-security" "odra-2026-001" 1 (digest #\e) 'activation
      "human.operator" rationale 200))))

(test-case "advisories cannot omit every affected selector"
  (check-exn
   exn:fail?
   (lambda ()
     (struct-copy odra-security-advisory advisory
                  [affected-package-ids '()]
                  [affected-release-ids '()]
                  [affected-artifact-digests '()]))))
