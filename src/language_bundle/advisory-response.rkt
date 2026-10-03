#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         "../package_catalog/security-advisories.rkt"
         "../package_catalog/security-advisory-verification.rkt")

(provide
 (struct-out odra-security-advisory-subject)
 (struct-out odra-security-advisory-response-reference)
 (struct-out odra-security-advisory-response)
 (contract-out
  [evaluate-security-advisories
   (-> (listof odra-security-advisory?)
       odra-security-advisory-response-policy?
       odra-security-advisory-subject?
       (or/c 'acquisition 'activation 'inspection)
       exact-nonnegative-integer?
       (listof odra-security-advisory-policy-override?)
       odra-security-advisory-response?)]
  [make-security-advisory-evaluator
   (-> (listof odra-security-advisory?)
       odra-security-advisory-response-policy?
       exact-nonnegative-integer?
       (listof odra-security-advisory-policy-override?)
       procedure?)]))

(define digest-pattern #px"^[0-9a-f]{64}$")
(define identity-pattern #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")
(define response-actions
  '(block-acquisition block-activation deactivate quarantine rollback warn))

(define (identity? value)
  (and (string? value) (regexp-match? identity-pattern value)))

(define (digest? value)
  (and (string? value) (regexp-match? digest-pattern value)))

(define (canonical-actions? values)
  (and (list? values)
       (andmap (lambda (value) (and (memq value response-actions) #t)) values)
       (equal? values (sort (remove-duplicates values) symbol<?))))

(struct odra-security-advisory-subject
  (package-id release-id artifact-digests installed? active?)
  #:transparent
  #:guard
  (lambda (package-id release-id artifact-digests installed? active? _)
    (unless (and (identity? package-id)
                 (or (not release-id) (digest? release-id))
                 (list? artifact-digests) (andmap digest? artifact-digests)
                 (equal? artifact-digests
                         (sort (remove-duplicates artifact-digests string=?)
                               string<?))
                 (boolean? installed?) (boolean? active?)
                 (or installed? (not active?)))
      (raise-arguments-error 'odra-security-advisory-subject
                             "invalid exact package security subject"))
    (values (string->immutable-string package-id)
            (and release-id (string->immutable-string release-id))
            (map string->immutable-string artifact-digests)
            installed? active?)))

(struct odra-security-advisory-response-reference
  (issuer-id advisory-id generation advisory-digest evidence-state
      classification severity recommended-actions)
  #:transparent)

(struct odra-security-advisory-response
  (actions references overridden-references)
  #:transparent
  #:guard
  (lambda (actions references overridden-references _)
    (unless (and (canonical-actions? actions)
                 (list? references)
                 (andmap odra-security-advisory-response-reference? references)
                 (list? overridden-references)
                 (andmap odra-security-advisory-response-reference?
                         overridden-references))
      (raise-arguments-error 'odra-security-advisory-response
                             "invalid local advisory response"))
    (values actions references overridden-references)))

(define (policy-actions policy advisory)
  (case (odra-security-advisory-evidence-state advisory)
    [(suspected)
     (odra-security-advisory-response-policy-suspected-actions policy)]
    [(disputed)
     (odra-security-advisory-response-policy-disputed-actions policy)]
    [else
     (if (eq? (odra-security-advisory-classification advisory) 'malicious)
         (odra-security-advisory-response-policy-confirmed-malicious-actions
          policy)
         (odra-security-advisory-response-policy-confirmed-other-actions
          policy))]))

(define (advisory-reference advisory)
  (odra-security-advisory-response-reference
   (odra-security-advisory-issuer-id advisory)
   (odra-security-advisory-id advisory)
   (odra-security-advisory-generation advisory)
   (security-advisory-content-digest advisory)
   (odra-security-advisory-evidence-state advisory)
   (odra-security-advisory-classification advisory)
   (odra-security-advisory-severity advisory)
   (odra-security-advisory-recommended-actions advisory)))

(define (active-advisory? advisory)
  (memq (odra-security-advisory-state advisory) '(active corrected)))

(define (blocking-action phase)
  (case phase
    [(acquisition) 'block-acquisition]
    [(activation) 'block-activation]
    [else #f]))

(define (action-applicable? action subject phase)
  (case action
    [(block-acquisition) (eq? phase 'acquisition)]
    [(block-activation) (memq phase '(activation inspection))]
    [(deactivate rollback) (odra-security-advisory-subject-active? subject)]
    [(quarantine) (odra-security-advisory-subject-installed? subject)]
    [else #t]))

(define (matching-override? override advisory subject phase now)
  (and (eq? phase (odra-security-advisory-policy-override-phase override))
       (<= now (odra-security-advisory-policy-override-expires-at override))
       (string=? (odra-security-advisory-policy-override-issuer-id override)
                 (odra-security-advisory-issuer-id advisory))
       (string=? (odra-security-advisory-policy-override-advisory-id override)
                 (odra-security-advisory-id advisory))
       (= (odra-security-advisory-policy-override-advisory-generation override)
          (odra-security-advisory-generation advisory))
       (member
        (odra-security-advisory-policy-override-artifact-digest override)
        (odra-security-advisory-subject-artifact-digests subject)
        string=?)))

(define (evaluate-security-advisories advisories policy subject phase now overrides)
  (define matched
    (filter
     (lambda (advisory)
       (and (active-advisory? advisory)
            (security-advisory-matches-release?
             advisory
             (odra-security-advisory-subject-package-id subject)
             (odra-security-advisory-subject-release-id subject)
             (odra-security-advisory-subject-artifact-digests subject))))
     advisories))
  (define blocked-action (blocking-action phase))
  (define overridden '())
  (define actions
    (for/fold ([selected '()]) ([advisory (in-list matched)])
      (define reference (advisory-reference advisory))
      (define override?
        (and blocked-action
             (odra-security-advisory-response-policy-permit-overrides? policy)
             (ormap
              (lambda (override)
                (matching-override? override advisory subject phase now))
              overrides)))
      (when override? (set! overridden (cons reference overridden)))
      (define applicable
        (filter (lambda (action) (action-applicable? action subject phase))
                (policy-actions policy advisory)))
      (append
       (if override?
           (remove blocked-action applicable)
           applicable)
       selected)))
  (odra-security-advisory-response
   (sort (remove-duplicates actions) symbol<?)
   (map advisory-reference matched)
   (reverse overridden)))

(define (make-security-advisory-evaluator advisories policy now overrides)
  (lambda (phase package-id release-id artifact-digests installed? active?)
    (evaluate-security-advisories
     advisories policy
     (odra-security-advisory-subject
      package-id release-id artifact-digests installed? active?)
     phase now overrides)))
