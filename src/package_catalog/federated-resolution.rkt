#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         racket/string
         "../language_bundle/advisory-response.rkt"
         "curation-records.rkt"
         "curation-resolution.rkt"
         "security-advisories.rkt"
         "state-records.rkt")

(provide
 maximum-federated-package-search-results
 (struct-out odra-package-source-pin)
 (struct-out odra-package-organization-override)
 (struct-out odra-federated-package-source)
 (struct-out odra-federated-catalog-attribution)
 (struct-out odra-federated-package-match)
 (struct-out odra-federated-package-resolution)
 (struct-out odra-federated-package-resolution-failure)
 (contract-out
  [search-federated-packages
   (-> (listof odra-federated-package-source?) string? symbol? symbol?
       exact-positive-integer? (listof odra-federated-package-match?))]
  [resolve-federated-package
   (->* ((listof odra-federated-package-source?)
         odra-package-resolution-request?
         (listof odra-security-advisory?)
         odra-security-advisory-response-policy?
         exact-nonnegative-integer?
         (listof odra-security-advisory-policy-override?))
        (#:source-pins (listof odra-package-source-pin?)
         #:organization-overrides
         (listof odra-package-organization-override?))
        (or/c odra-federated-package-resolution?
              odra-federated-package-resolution-failure?))]))

(define maximum-federated-package-search-results 4096)
(define identity-pattern #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")
(define digest-pattern #px"^[0-9a-f]{64}$")

(define (identity? value)
  (and (string? value)
       (<= 1 (bytes-length (string->bytes/utf-8 value)) 128)
       (regexp-match? identity-pattern value)))

(define (digest? value)
  (and (string? value) (regexp-match? digest-pattern value)))

(define (copied value)
  (if (string? value) (string->immutable-string value) value))

(struct odra-package-source-pin (package-id catalog-id)
  #:transparent
  #:guard
  (lambda (package-id catalog-id _)
    (unless (and (identity? package-id) (digest? catalog-id))
      (raise-arguments-error 'odra-package-source-pin
                             "invalid exact package source pin"))
    (values (copied package-id) (copied catalog-id))))

(struct odra-package-organization-override (organization-id catalog-id)
  #:transparent
  #:guard
  (lambda (organization-id catalog-id _)
    (unless (and (identity? organization-id) (digest? catalog-id))
      (raise-arguments-error 'odra-package-organization-override
                             "invalid package organization override"))
    (values (copied organization-id) (copied catalog-id))))

(struct odra-federated-package-source (registration confirmed-snapshot source)
  #:transparent
  #:guard
  (lambda (registration confirmed-snapshot source _)
    (define registration-catalog
      (and (odra-package-catalog-registration? registration)
           (odra-package-catalog-registration-catalog-id registration)))
    (unless
        (and registration-catalog
             (odra-package-catalog-confirmed-snapshot-reference?
              confirmed-snapshot)
             (odra-package-curated-source? source)
             (odra-package-catalog-registration-enabled? registration)
             (memq
              (odra-package-catalog-registration-refresh-state registration)
              '(current offline))
             (string=?
              registration-catalog
              (odra-package-catalog-confirmed-snapshot-reference-catalog-id
               confirmed-snapshot))
             (string=? registration-catalog
                       (odra-package-curated-source-catalog-id source))
             (string=?
              (odra-package-catalog-confirmed-snapshot-reference-snapshot-id
               confirmed-snapshot)
              (odra-package-curated-source-snapshot-id source))
             (=
              (odra-package-catalog-registration-package-precedence registration)
              (odra-package-curated-source-precedence source)))
      (raise-arguments-error
       'odra-federated-package-source
       "source must match one enabled current or offline confirmed registration"))
    (values registration confirmed-snapshot source)))

(struct odra-federated-catalog-attribution
  (registration-id catalog-id snapshot-id freshness)
  #:transparent)

(struct odra-federated-package-match
  (package-id version release-id artifact-digest curation-status attribution
      assertion)
  #:transparent)

(struct odra-federated-package-resolution
  (resolution effective-catalog-pin pin-origin catalog-attributions
      advisory-response)
  #:transparent)

(struct odra-federated-package-resolution-failure
  (code package-id catalog-ids digests effective-catalog-pin pin-origin
      advisory-response)
  #:transparent)

(define (source-attribution federated)
  (define registration
    (odra-federated-package-source-registration federated))
  (define source (odra-federated-package-source-source federated))
  (odra-federated-catalog-attribution
   (odra-package-catalog-registration-id registration)
   (odra-package-curated-source-catalog-id source)
   (odra-package-curated-source-snapshot-id source)
   (odra-package-catalog-registration-refresh-state registration)))

(define (search-match federated assertion platform architecture)
  (define release (odra-package-curation-assertion-release assertion))
  (define artifact (package-release-artifact release platform architecture))
  (and artifact
       (memq (odra-package-curation-assertion-status assertion)
             '(admitted deprecated))
       (odra-federated-package-match
        (odra-package-release-reference-package-id release)
        (odra-package-release-reference-version release)
        (odra-package-release-reference-release-id release)
        (odra-package-artifact-reference-digest artifact)
        (odra-package-curation-assertion-status assertion)
        (source-attribution federated)
        assertion)))

(define (match<? left right)
  (define left-attribution
    (odra-federated-package-match-attribution left))
  (define right-attribution
    (odra-federated-package-match-attribution right))
  (define left-key
    (list (odra-federated-package-match-package-id left)
          (odra-federated-package-match-version left)
          (odra-federated-catalog-attribution-catalog-id left-attribution)
          (odra-federated-package-match-release-id left)))
  (define right-key
    (list (odra-federated-package-match-package-id right)
          (odra-federated-package-match-version right)
          (odra-federated-catalog-attribution-catalog-id right-attribution)
          (odra-federated-package-match-release-id right)))
  (string<? (string-join left-key "\u0000")
            (string-join right-key "\u0000")))

(define (search-federated-packages sources query platform architecture maximum)
  (unless (and (<= (bytes-length (string->bytes/utf-8 query)) 128)
               (memq platform '(darwin linux windows))
               (memq architecture '(aarch64 x86-64))
               (<= maximum maximum-federated-package-search-results))
    (raise-arguments-error 'search-federated-packages
                           "invalid bounded federated package search"))
  (define matches
    (sort
     (for*/list ([federated (in-list sources)]
                 [assertion
                  (in-list
                   (odra-package-curated-source-assertions
                    (odra-federated-package-source-source federated)))]
                 #:do
                 [(define match
                    (search-match federated assertion platform architecture))]
                 #:when
                 (and match
                      (string-prefix?
                       (odra-federated-package-match-package-id match) query)))
       match)
     match<?))
  (take matches (min maximum (length matches))))

(define (canonical-policy? values key)
  (= (length values) (length (remove-duplicates values string=? #:key key))))

(define (organization-matches? organization-id package-id)
  (or (string=? organization-id package-id)
      (string-prefix? package-id (string-append organization-id "."))))

(define (effective-pin request source-pins organization-overrides)
  (define request-pin
    (odra-package-resolution-request-catalog-pin request))
  (define package-id
    (odra-package-resolution-request-package-id request))
  (cond
    [request-pin (values request-pin 'request)]
    [(for/first ([pin (in-list source-pins)]
                 #:when
                 (string=? package-id
                           (odra-package-source-pin-package-id pin)))
       pin)
     => (lambda (pin)
          (values (odra-package-source-pin-catalog-id pin) 'package))]
    [else
     (define matching
       (filter
        (lambda (override)
          (organization-matches?
           (odra-package-organization-override-organization-id override)
           package-id))
        organization-overrides))
     (if (null? matching)
         (values #f 'none)
         (let ([selected
                (car
                 (sort matching >
                       #:key
                       (lambda (override)
                         (string-length
                          (odra-package-organization-override-organization-id
                           override)))))])
           (values
            (odra-package-organization-override-catalog-id selected)
            'organization)))]))

(define (resolution-failure failure pin pin-origin [advisory-response #f])
  (odra-federated-package-resolution-failure
   (odra-package-resolution-failure-code failure)
   (odra-package-resolution-failure-package-id failure)
   (odra-package-resolution-failure-catalog-ids failure)
   (odra-package-resolution-failure-digests failure)
   pin pin-origin advisory-response))

(define (resolve-federated-package
         sources request advisories advisory-policy now advisory-overrides
         #:source-pins [source-pins '()]
         #:organization-overrides [organization-overrides '()])
  (define package-id
    (odra-package-resolution-request-package-id request))
  (cond
    [(or (not (canonical-policy? source-pins odra-package-source-pin-package-id))
         (not
          (canonical-policy?
           organization-overrides
           odra-package-organization-override-organization-id)))
     (odra-federated-package-resolution-failure
      'invalid-policy package-id '() '() #f 'none #f)]
    [else
     (define-values (pin pin-origin)
       (effective-pin request source-pins organization-overrides))
     (define pinned-request
       (struct-copy odra-package-resolution-request request [catalog-pin pin]))
     (define resolution
       (resolve-curated-package
        (map odra-federated-package-source-source sources) pinned-request))
     (cond
       [(odra-package-resolution-failure? resolution)
        (resolution-failure resolution pin pin-origin)]
       [else
        (define release (odra-package-resolution-release resolution))
        (define artifact (odra-package-resolution-artifact resolution))
        (define response
          (evaluate-security-advisories
           advisories advisory-policy
           (odra-security-advisory-subject
            package-id
            (odra-package-release-reference-release-id release)
            (list (odra-package-artifact-reference-digest artifact))
            #f #f)
           'acquisition now advisory-overrides))
        (define catalog-ids (odra-package-resolution-catalog-ids resolution))
        (if (member 'block-acquisition
                    (odra-security-advisory-response-actions response))
            (odra-federated-package-resolution-failure
             'advisory-blocked package-id catalog-ids
             (list (odra-package-artifact-reference-digest artifact))
             pin pin-origin response)
            (odra-federated-package-resolution
             resolution pin pin-origin
             (sort
              (for/list ([federated (in-list sources)]
                         #:when
                         (member
                          (odra-package-curated-source-catalog-id
                           (odra-federated-package-source-source federated))
                          catalog-ids string=?))
                (source-attribution federated))
              string<? #:key odra-federated-catalog-attribution-catalog-id)
             response))])]))
