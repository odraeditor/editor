#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         rackunit
         "../../src/language_bundle/acquisition.rkt"
         "../../src/language_bundle/advisory-response.rkt"
         "../../src/package_catalog/integrity.rkt"
         "../../src/package_catalog/security-advisories.rkt")

(define catalog-id (make-string 64 #\c))
(define artifact-digest (make-string 64 #\e))
(define other-digest (make-string 64 #\f))
(define signature
  (odra-package-catalog-signature
   'ed25519 (make-string 64 #\a) package-catalog-advisory-signature-domain
   (make-string 128 #\b)))
(define policy
  (odra-security-advisory-response-policy
   "default-security" 1 '(warn)
   '(block-acquisition block-activation deactivate quarantine rollback warn)
   '(block-activation warn) '(warn) #t))

(define (advisory #:id [id "odra-2026-001"]
                  #:issuer [issuer "official-security"]
                  #:generation [generation 1]
                  #:state [state 'active]
                  #:classification [classification 'malicious]
                  #:evidence [evidence 'confirmed]
                  #:digest [digest artifact-digest])
  (odra-security-advisory
   1 id issuer catalog-id generation state classification 'critical evidence
   '() '() (list digest)
   '(block-acquisition block-activation deactivate quarantine rollback warn)
   "Bounded security response fixture." 20
   (and (> generation 1)
        (odra-security-advisory-generation-reference
         id (sub1 generation) (make-string 64 #\d)))
   (list signature)))

(define (subject digest installed? active?)
  (odra-security-advisory-subject
   "org.example.language" #f (list digest) installed? active?))

(test-case "suspected and disputed evidence can only trigger local warning policy"
  (for ([evidence '(suspected disputed)])
    (define response
      (evaluate-security-advisories
       (list (advisory #:evidence evidence)) policy
       (subject artifact-digest #f #f) 'acquisition 30 '()))
    (check-equal? (odra-security-advisory-response-actions response) '(warn))))

(test-case "confirmed malicious responses are contextual local decisions"
  (define acquisition
    (evaluate-security-advisories
     (list (advisory)) policy (subject artifact-digest #f #f)
     'acquisition 30 '()))
  (check-equal? (odra-security-advisory-response-actions acquisition)
                '(block-acquisition warn))
  (define installed
    (evaluate-security-advisories
     (list (advisory)) policy (subject artifact-digest #t #f)
     'activation 30 '()))
  (check-equal? (odra-security-advisory-response-actions installed)
                '(block-activation quarantine warn))
  (define active
    (evaluate-security-advisories
     (list (advisory)) policy (subject artifact-digest #t #t)
     'inspection 30 '()))
  (check-equal? (odra-security-advisory-response-actions active)
                '(block-activation deactivate quarantine rollback warn)))

(test-case "corrected advisories enforce while withdrawn generations do not"
  (define response
    (evaluate-security-advisories
     (list (advisory #:generation 2 #:state 'corrected)
           (advisory #:id "odra-2026-002" #:state 'withdrawn))
     policy (subject artifact-digest #f #f) 'acquisition 30 '()))
  (check-equal? (odra-security-advisory-response-actions response)
                '(block-acquisition warn))
  (check-equal? (length (odra-security-advisory-response-references response)) 1))

(test-case "conflicting issuers preserve evidence and apply the stricter local result"
  (define response
    (evaluate-security-advisories
     (list (advisory)
           (advisory #:issuer "community-security" #:evidence 'disputed))
     policy (subject artifact-digest #f #f) 'acquisition 30 '()))
  (check-equal? (odra-security-advisory-response-actions response)
                '(block-acquisition warn))
  (check-equal? (length (odra-security-advisory-response-references response)) 2))

(test-case "expert override binds issuer generation phase digest and expiry"
  (define exact
    (make-security-advisory-policy-override
     "official-security" "odra-2026-001" 1 artifact-digest 'acquisition
     "human.operator" "Isolated expert investigation." 40))
  (define allowed
    (evaluate-security-advisories
     (list (advisory)) policy (subject artifact-digest #f #f)
     'acquisition 30 (list exact)))
  (check-equal? (odra-security-advisory-response-actions allowed) '(warn))
  (check-equal?
   (length (odra-security-advisory-response-overridden-references allowed)) 1)
  (define overrides-disabled
    (evaluate-security-advisories
     (list (advisory))
     (struct-copy odra-security-advisory-response-policy policy
                  [permit-overrides? #f])
     (subject artifact-digest #f #f) 'acquisition 30 (list exact)))
  (check-not-false
   (member 'block-acquisition
           (odra-security-advisory-response-actions overrides-disabled)))
  (for ([candidate
         (list
          (make-security-advisory-policy-override
           "community-security" "odra-2026-001" 1 artifact-digest 'acquisition
           "human.operator" "Wrong issuer." 40)
          (make-security-advisory-policy-override
           "official-security" "odra-2026-001" 1 other-digest 'acquisition
           "human.operator" "Wrong digest." 40)
          (make-security-advisory-policy-override
           "official-security" "odra-2026-001" 1 artifact-digest 'acquisition
           "human.operator" "Expired exception." 29))])
    (define blocked
      (evaluate-security-advisories
       (list (advisory)) policy (subject artifact-digest #f #f)
       'acquisition 30 (list candidate)))
    (check-not-false
     (member 'block-acquisition
             (odra-security-advisory-response-actions blocked)))))

(test-case "retained advisories block offline acquisition before filesystem mutation"
  (define evaluator
    (make-security-advisory-evaluator (list (advisory)) policy 30 '()))
  (define request
    (odra-bundle-archive-request
     "org.example.language" '("/unreachable/archive.tar.zst")
     artifact-digest 1
     (list
      (odra-bundle-archive-member
       "bundle/main.rkt" other-digest 1 'racket-module #f))
     1 1))
  (define parent
    (make-temporary-file "odra-advisory-offline-~a" 'directory))
  (define root (build-path parent "must-not-exist"))
  (dynamic-wind
    void
    (lambda ()
      (define result
        (acquire-language-bundle
         root request #:offline? #t #:advisory-evaluator evaluator))
      (check-eq? (odra-bundle-acquisition-failure-code result)
                 'security-advisory)
      (check-false (directory-exists? root)))
    (lambda () (delete-directory/files parent))))
