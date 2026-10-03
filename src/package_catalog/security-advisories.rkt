#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/contract/base
         racket/list
         racket/match
         racket/string
         "../storage/record-codec.rkt"
         "integrity.rkt")

(provide
 current-security-advisory-format-version
 maximum-security-advisory-selectors
 maximum-security-advisory-rationale-bytes
 (struct-out odra-security-advisory-issuer)
 (struct-out odra-security-advisory-generation-reference)
 (struct-out odra-security-advisory)
 (struct-out odra-security-advisory-response-policy)
 (struct-out odra-security-advisory-policy-override)
 security-advisory-signing-payload
 security-advisory-content-digest
 security-advisory->module-bytes
 (contract-out
  [make-security-advisory-policy-override
   (-> string? string? exact-positive-integer? string?
       (or/c 'acquisition 'activation) string? string? exact-nonnegative-integer?
       odra-security-advisory-policy-override?)]
  [security-advisory-module-load
   (-> path-string? (or/c odra-security-advisory? odra-record-diagnostic?))]))

(define current-security-advisory-format-version 1)
(define maximum-security-advisory-selectors 4096)
(define maximum-security-advisory-rationale-bytes 4096)
(define maximum-advisory-signatures 16)
(define digest-pattern #px"^[0-9a-f]{64}$")
(define identity-pattern #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")
(define advisory-states '(active corrected draft superseded withdrawn))
(define advisory-classifications
  '(compromised malicious policy-risk vulnerability))
(define advisory-severities '(critical high low medium none))
(define evidence-states '(confirmed disputed suspected))
(define advisory-actions
  '(block-acquisition block-activation deactivate quarantine rollback warn))

(define (digest? value)
  (and (string? value) (regexp-match? digest-pattern value)))

(define (identity? value)
  (and (string? value)
       (<= 1 (bytes-length (string->bytes/utf-8 value)) 128)
       (regexp-match? identity-pattern value)))

(define (bounded-text? value maximum)
  (and (string? value) (positive? (string-length value))
       (not (string-contains? value (string #\nul)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(define (canonical-list? values maximum predicate less?)
  (and (list? values) (<= (length values) maximum) (andmap predicate values)
       (equal? values (sort (remove-duplicates values equal?) less?))))

(define (canonical-identities? values)
  (canonical-list? values maximum-security-advisory-selectors identity? string<?))

(define (canonical-digests? values)
  (canonical-list? values maximum-security-advisory-selectors digest? string<?))

(define (canonical-actions? values)
  (canonical-list? values (length advisory-actions)
                   (lambda (value) (and (memq value advisory-actions) #t))
                   symbol<?))

(define (copied value)
  (if (string? value) (record-copied-text value) value))

(struct odra-security-advisory-issuer
  (identity catalog-identity key-ids threshold valid-from valid-until status)
  #:transparent
  #:guard
  (lambda (id catalog-id key-ids threshold valid-from valid-until status _)
    (unless (and (identity? id) (digest? catalog-id)
                 (canonical-list? key-ids 16 digest? string<?) (pair? key-ids)
                 (exact-positive-integer? threshold) (<= threshold (length key-ids))
                 (exact-nonnegative-integer? valid-from)
                 (or (not valid-until)
                     (and (exact-nonnegative-integer? valid-until)
                          (<= valid-from valid-until)))
                 (memq status '(revoked trusted)))
      (raise-arguments-error 'odra-security-advisory-issuer
                             "invalid issuer-specific advisory trust"))
    (values (copied id) (copied catalog-id) (map copied key-ids) threshold
            valid-from valid-until status)))

(struct odra-security-advisory-generation-reference
  (advisory-id generation digest)
  #:transparent
  #:guard
  (lambda (advisory-id generation digest _)
    (unless (and (identity? advisory-id) (exact-positive-integer? generation)
                 (digest? digest))
      (raise-arguments-error 'odra-security-advisory-generation-reference
                             "invalid exact advisory generation reference"))
    (values (copied advisory-id) generation (copied digest))))

(struct odra-security-advisory
  (format-version id issuer-id issuer-catalog-id generation state classification
      severity evidence-state affected-package-ids affected-release-ids
      affected-artifact-digests recommended-actions rationale issued-at
      supersedes signatures)
  #:transparent
  #:guard
  (lambda (format-version id issuer-id issuer-catalog-id generation state
                          classification severity evidence-state package-ids
                          release-ids artifact-digests actions rationale issued-at
                          supersedes signatures _)
    (unless
        (and (= format-version current-security-advisory-format-version)
             (identity? id) (identity? issuer-id) (digest? issuer-catalog-id)
             (exact-positive-integer? generation) (memq state advisory-states)
             (memq classification advisory-classifications)
             (memq severity advisory-severities) (memq evidence-state evidence-states)
             (canonical-identities? package-ids) (canonical-digests? release-ids)
             (canonical-digests? artifact-digests)
             (or (pair? package-ids) (pair? release-ids) (pair? artifact-digests))
             (canonical-actions? actions) (pair? actions)
             (bounded-text? rationale maximum-security-advisory-rationale-bytes)
             (exact-nonnegative-integer? issued-at)
             (if (= generation 1) (not supersedes)
                 (odra-security-advisory-generation-reference? supersedes))
             (list? signatures) (<= (length signatures) maximum-advisory-signatures)
             (andmap odra-package-catalog-signature? signatures)
             (equal? signatures
                     (sort (remove-duplicates
                            signatures string=?
                            #:key odra-package-catalog-signature-key-id)
                           string<? #:key odra-package-catalog-signature-key-id))
             (if (eq? state 'draft) #t (pair? signatures)))
      (raise-arguments-error 'odra-security-advisory
                             "invalid bounded signed security advisory"))
    (values format-version (copied id) (copied issuer-id)
            (copied issuer-catalog-id) generation state classification severity
            evidence-state (map copied package-ids) (map copied release-ids)
            (map copied artifact-digests) actions (copied rationale) issued-at
            supersedes signatures)))

(struct odra-security-advisory-response-policy
  (id generation suspected-actions confirmed-malicious-actions
      confirmed-other-actions disputed-actions permit-overrides?)
  #:transparent
  #:guard
  (lambda (id generation suspected confirmed-malicious confirmed-other disputed
              permit-overrides? _)
    (unless (and (identity? id) (exact-positive-integer? generation)
                 (andmap canonical-actions?
                         (list suspected confirmed-malicious confirmed-other disputed))
                 (boolean? permit-overrides?))
      (raise-arguments-error 'odra-security-advisory-response-policy
                             "invalid bounded local advisory response policy"))
    (values (copied id) generation suspected confirmed-malicious confirmed-other
            disputed permit-overrides?)))

(define (override-content issuer-id advisory-id generation artifact-digest phase
                          authorized-by rationale expires-at)
  (list 'security-advisory-policy-override issuer-id advisory-id generation
        artifact-digest phase authorized-by rationale expires-at))

(struct odra-security-advisory-policy-override
  (id issuer-id advisory-id advisory-generation artifact-digest phase
      authorized-by rationale expires-at)
  #:transparent
  #:guard
  (lambda (id issuer-id advisory-id generation artifact-digest phase
              authorized-by rationale expires-at _)
    (define expected
      (bytes->hex-string
       (sha256-bytes
        (open-input-bytes
         (record-datum->module-bytes
          (override-content issuer-id advisory-id generation artifact-digest
                            phase authorized-by rationale expires-at))))))
    (unless (and (digest? id) (identity? issuer-id) (identity? advisory-id)
                 (exact-positive-integer? generation) (digest? artifact-digest)
                 (memq phase '(acquisition activation)) (identity? authorized-by)
                 (bounded-text? rationale maximum-security-advisory-rationale-bytes)
                 (exact-nonnegative-integer? expires-at) (string=? id expected))
      (raise-arguments-error 'odra-security-advisory-policy-override
                             "invalid exact local advisory override"))
    (values (copied id) (copied issuer-id) (copied advisory-id) generation
            (copied artifact-digest) phase (copied authorized-by)
            (copied rationale) expires-at)))

(define (make-security-advisory-policy-override issuer-id advisory-id generation
                                                artifact-digest phase authorized-by
                                                rationale expires-at)
  (define id
    (bytes->hex-string
     (sha256-bytes
      (open-input-bytes
       (record-datum->module-bytes
        (override-content issuer-id advisory-id generation artifact-digest phase
                          authorized-by rationale expires-at))))))
  (odra-security-advisory-policy-override
   id issuer-id advisory-id generation artifact-digest phase authorized-by
   rationale expires-at))

(define (generation-reference->datum value)
  (and value
       (list (odra-security-advisory-generation-reference-advisory-id value)
             (odra-security-advisory-generation-reference-generation value)
             (odra-security-advisory-generation-reference-digest value))))

(define (signature->datum value)
  (list (odra-package-catalog-signature-algorithm value)
        (odra-package-catalog-signature-key-id value)
        (odra-package-catalog-signature-domain value)
        (odra-package-catalog-signature-value value)))

(define (security-advisory-signing-payload value)
  (list 'package-security-advisory
        (odra-security-advisory-format-version value)
        (odra-security-advisory-id value)
        (odra-security-advisory-issuer-id value)
        (odra-security-advisory-issuer-catalog-id value)
        (odra-security-advisory-generation value)
        (odra-security-advisory-state value)
        (odra-security-advisory-classification value)
        (odra-security-advisory-severity value)
        (odra-security-advisory-evidence-state value)
        (odra-security-advisory-affected-package-ids value)
        (odra-security-advisory-affected-release-ids value)
        (odra-security-advisory-affected-artifact-digests value)
        (odra-security-advisory-recommended-actions value)
        (odra-security-advisory-rationale value)
        (odra-security-advisory-issued-at value)
        (generation-reference->datum (odra-security-advisory-supersedes value))))

(define (security-advisory-content-digest value)
  (bytes->hex-string
   (sha256-bytes
    (open-input-bytes
     (record-datum->module-bytes (security-advisory-signing-payload value))))))

(define (security-advisory->module-bytes value)
  (record-datum->module-bytes
   (append (security-advisory-signing-payload value)
           (list (map signature->datum
                      (odra-security-advisory-signatures value))))))

(define (decode-reference value)
  (and value (apply odra-security-advisory-generation-reference value)))

(define (decode-advisory value)
  (match value
    [(list 'package-security-advisory format id issuer catalog generation state
           classification severity evidence packages releases artifacts actions
           rationale issued-at supersedes signatures)
     (odra-security-advisory
      format id issuer catalog generation state classification severity evidence
      packages releases artifacts actions rationale issued-at
      (decode-reference supersedes)
      (map (lambda (signature) (apply odra-package-catalog-signature signature))
           signatures))]
    [_ (raise-arguments-error 'package-security-advisory
                              "unsupported advisory schema")]))

(define (security-advisory-module-load path)
  (record-module-load path decode-advisory))
