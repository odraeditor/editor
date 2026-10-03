#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         racket/string
         "contracts.rkt"
         "endpoint-transport.rkt"
         "integrity.rkt"
         "security-advisories.rkt")

(provide
 official-package-catalog-root-public-key
 official-package-catalog-root-key-id
 official-package-catalog-publisher-public-key
 official-package-catalog-publisher-key-id
 official-package-catalog-identity
 official-package-catalog-credential-reference
 official-package-catalog-bootstrap
 (struct-out odra-package-catalog-bootstrap)
 (contract-out
  [package-catalog-bootstrap-valid?
   (-> odra-package-catalog-bootstrap? boolean?)]))

(define maximum-bootstrap-text-bytes 4096)

(define (bounded-text? value)
  (and (string? value)
       (positive? (string-length value))
       (not (string-contains? value (string #\nul)))
       (<= (bytes-length (string->bytes/utf-8 value))
           maximum-bootstrap-text-bytes)))

(define (copied value)
  (if (string? value) (string->immutable-string value) value))

(define (profile-publisher-key-ids profile)
  (remove-duplicates
   (append*
    (for/list
        ([authorization
          (in-list (odra-package-catalog-profile-publishers profile))])
      (odra-package-catalog-publisher-authorization-key-ids authorization)))
   string=?))

(define (bootstrap-consistent? profile publisher-keys)
  (and (odra-package-catalog-profile? profile)
       (eq? #t (verify-package-catalog-profile-identity profile))
       (for/and
           ([root (in-list (odra-package-catalog-profile-roots profile))])
         (string=?
          (package-catalog-public-key-id
           (odra-package-catalog-root-key-public-key root))
          (odra-package-catalog-root-key-id root)))
       (list? publisher-keys)
       (pair? publisher-keys)
       (andmap odra-package-catalog-publisher-key? publisher-keys)
       (= (length publisher-keys)
          (length
           (remove-duplicates publisher-keys string=?
                              #:key odra-package-catalog-publisher-key-id)))
       (equal?
        (sort (map odra-package-catalog-publisher-key-id publisher-keys) string<?)
        (sort (profile-publisher-key-ids profile) string<?))
       (for/and ([key (in-list publisher-keys)])
         (string=?
          (package-catalog-public-key-id
           (odra-package-catalog-publisher-key-public-key key))
          (odra-package-catalog-publisher-key-id key)))))

(struct odra-package-catalog-bootstrap
  (profile publisher-keys governance-repository governance-path lifecycle
      formalization-required? transport-policy offline-grace-seconds automatic?
      interval-seconds advisory-response-policy)
  #:transparent
  #:guard
  (lambda (profile publisher-keys governance-repository governance-path lifecycle
                   formalization-required? transport-policy offline-grace-seconds
                   automatic? interval-seconds advisory-response-policy _)
    (unless
        (and (bootstrap-consistent? profile publisher-keys)
             (bounded-text? governance-repository)
             (regexp-match? #px"^https://" governance-repository)
             (bounded-text? governance-path)
             (eq? lifecycle 'public)
             (eq? formalization-required? #f)
             (odra-package-catalog-transport-policy? transport-policy)
             (exact-nonnegative-integer? offline-grace-seconds)
             (boolean? automatic?)
             (exact-positive-integer? interval-seconds)
             (odra-security-advisory-response-policy?
              advisory-response-policy))
      (raise-arguments-error
       'odra-package-catalog-bootstrap
       "invalid public package catalog bootstrap data"))
    (values profile publisher-keys (copied governance-repository)
            (copied governance-path) lifecycle formalization-required?
            transport-policy offline-grace-seconds automatic? interval-seconds
            advisory-response-policy)))

(define (package-catalog-bootstrap-valid? bootstrap)
  (and (bootstrap-consistent?
        (odra-package-catalog-bootstrap-profile bootstrap)
        (odra-package-catalog-bootstrap-publisher-keys bootstrap))
       #t))

;; Private counterparts remain outside every source repository and release.
(define official-package-catalog-root-public-key
  "219bd98e1cc54b8d48018685acec116fb160104e17ce2c9f8c9c83cb80c4e88c")
(define official-package-catalog-root-key-id
  "f07bdfd7a777894a885997f98d1207b2b35b3536a875f53d9b2e93cdc3bea1d4")
(define official-package-catalog-publisher-public-key
  "246db9a1715d4953247ef0d6571f0a64a6e071a00fbbfe9957cf6effb474cee1")
(define official-package-catalog-publisher-key-id
  "cb714b288aa5b31f345f4e7dce7ee6178aa2364af269f188bcce805f30c14985")
(define official-package-catalog-identity
  "8de9b8ba1be8e8f59f42b5bf8fd803f21a517c1d7f607822bb9bc312fa80343f")
(define official-package-catalog-credential-reference #f)

(define official-root
  (odra-package-catalog-root-key
   official-package-catalog-root-key-id 1 'ed25519
   official-package-catalog-root-public-key 0 #f))
(define official-publisher-key
  (odra-package-catalog-publisher-key
   official-package-catalog-publisher-key-id 'ed25519
   official-package-catalog-publisher-public-key))
(define official-policy
  (odra-package-catalog-policy
   "odra-official-default" 1 1
   "policy/package-eligibility.md"
   "policy/authority.md"
   "policy/assessment.md"
   "policy/decision.md"
   "policy/retention.md"))
(define official-curator
  (odra-package-catalog-curator-authorization
   "odra-official-curator" "adrianpk" 'human 0 #f
   '("odra-official-default")))
(define official-publisher
  (odra-package-catalog-publisher-authorization
   "odra-official-publisher" (list official-package-catalog-publisher-key-id)
   1 0 #f))
(define official-endpoint
  (odra-package-catalog-endpoint
   "odra-official-origin" official-package-catalog-identity
   "https://forge.adrianpk.com/odra/kasper/raw/branch/publication/current-snapshot.rktd"
   'https 'origin 0 #t))

(define-values (official-profile official-profile-rejection)
  (confirm-package-catalog-profile
   (odra-package-catalog-profile-proposal
    current-package-catalog-identity-format-version
    official-package-catalog-identity
    "Odra Official Catalog"
    (list official-root)
    (list official-curator)
    (list official-publisher)
    (list official-policy)
    (list official-endpoint))))

(when official-profile-rejection
  (error 'official-package-catalog-bootstrap
         "compiled official catalog profile is invalid: ~s"
         official-profile-rejection))

(define official-package-catalog-bootstrap
  (odra-package-catalog-bootstrap
   official-profile
   (list official-publisher-key)
   "https://forge.adrianpk.com/odra/kasper"
   "catalog.rkt"
   'public
   #f
   (odra-package-catalog-transport-policy
    (* 4 1024 1024) 60000 4 2 'direct)
   (* 24 60 60)
   #t
   3600
   (odra-security-advisory-response-policy
    "default-security" 1 '(warn)
    '(block-acquisition block-activation deactivate quarantine rollback warn)
    '(block-activation warn) '(warn) #t)))
