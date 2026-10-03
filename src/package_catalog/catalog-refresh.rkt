#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         "contracts.rkt"
         "endpoint-transport.rkt"
         "snapshot-reconciliation.rkt"
         "snapshot-records.rkt"
         "state-persistence.rkt"
         "state-records.rkt")

(provide
 (struct-out odra-package-catalog-refresh-result)
 package-catalog-refresh-manager?
 (contract-out
  [make-package-catalog-refresh-manager
   (->* (path-string?
         odra-package-catalog-state?
         (listof odra-package-catalog-profile?)
         (listof odra-package-catalog-publisher-key?)
         odra-package-catalog-transport-policy?
         procedure?)
        (#:offline-grace-seconds exact-nonnegative-integer?
         #:persistence procedure?)
        package-catalog-refresh-manager?)]
  [package-catalog-refresh-state
   (-> package-catalog-refresh-manager? odra-package-catalog-state?)]
  [refresh-package-catalog-registration!
   (->* (package-catalog-refresh-manager? string? exact-nonnegative-integer?)
        (#:cancelled? procedure?)
        odra-package-catalog-refresh-result?)]))

(struct odra-package-catalog-refresh-result
  (status state registration-id endpoint-results reconciliation detail)
  #:transparent
  #:guard
  (lambda (status state registration-id endpoint-results reconciliation detail _)
    (unless (and (memq status '(blocked current failed offline stale))
                 (odra-package-catalog-state? state)
                 (string? registration-id)
                 (list? endpoint-results)
                 (andmap
                  (lambda (value)
                    (or (odra-package-catalog-fetch-result? value)
                        (odra-package-catalog-fetch-failure? value)))
                  endpoint-results)
                 (or (not reconciliation)
                     (odra-package-catalog-snapshot-reconciliation?
                      reconciliation))
                 (string? detail)
                 (<= (bytes-length (string->bytes/utf-8 detail)) 4096))
      (raise-arguments-error 'odra-package-catalog-refresh-result
                             "invalid bounded catalog refresh result"))
    (values status state (string->immutable-string registration-id)
            endpoint-results reconciliation (string->immutable-string detail))))

(struct package-catalog-refresh-manager
  (root state profiles publisher-keys transport-policy credential-resolver
        offline-grace-seconds persistence busy guard)
  #:transparent #:mutable)

(define (make-package-catalog-refresh-manager
         root state profiles publisher-keys transport-policy credential-resolver
         #:offline-grace-seconds [offline-grace-seconds 0]
         #:persistence [persistence package-catalog-state-persist])
  (define profile-identities
    (map odra-package-catalog-profile-identity profiles))
  (unless (= (length profile-identities)
             (length (remove-duplicates profile-identities string=?)))
    (raise-arguments-error 'make-package-catalog-refresh-manager
                           "catalog profiles must have unique identities"))
  (package-catalog-refresh-manager
   (path->complete-path root) state profiles publisher-keys transport-policy
   credential-resolver offline-grace-seconds persistence (make-hash)
   (make-semaphore 1)))

(define (package-catalog-refresh-state manager)
  (package-catalog-refresh-manager-state manager))

(define (find-registration state registration-id)
  (for/first
      ([registration (in-list (odra-package-catalog-state-registrations state))]
       #:when
       (string=? registration-id
                 (odra-package-catalog-registration-id registration)))
    registration))

(define (find-profile manager catalog-id)
  (for/first
      ([profile (in-list (package-catalog-refresh-manager-profiles manager))]
       #:when
       (string=? catalog-id (odra-package-catalog-profile-identity profile)))
    profile))

(define (registration-endpoints state registration)
  (define admitted
    (odra-package-catalog-registration-endpoint-ids registration))
  (sort
   (filter
    (lambda (endpoint-state)
      (define endpoint
        (odra-package-catalog-state-endpoint-endpoint endpoint-state))
      (and (odra-package-catalog-endpoint-enabled? endpoint)
           (member (odra-package-catalog-endpoint-id endpoint)
                   admitted string=?)))
    (odra-package-catalog-state-endpoints state))
   (lambda (left right)
     (define left-endpoint
       (odra-package-catalog-state-endpoint-endpoint left))
     (define right-endpoint
       (odra-package-catalog-state-endpoint-endpoint right))
     (or (< (odra-package-catalog-endpoint-priority left-endpoint)
            (odra-package-catalog-endpoint-priority right-endpoint))
         (and (= (odra-package-catalog-endpoint-priority left-endpoint)
                 (odra-package-catalog-endpoint-priority right-endpoint))
              (string<? (odra-package-catalog-endpoint-id left-endpoint)
                        (odra-package-catalog-endpoint-id right-endpoint)))))))

(define (confirmed-reference state catalog-id)
  (for/first
      ([reference
        (in-list (odra-package-catalog-state-confirmed-snapshots state))]
       #:when
       (string=?
        catalog-id
        (odra-package-catalog-confirmed-snapshot-reference-catalog-id reference)))
    reference))

(define (load-confirmed-snapshot manager reference)
  (cond
    [(not reference) (values #f #f)]
    [else
     (define path
       (build-path
        (package-catalog-refresh-manager-root manager) "package-catalog"
        (odra-package-catalog-confirmed-snapshot-reference-cache-reference
         reference)))
     (define loaded (package-catalog-snapshot-module-load path))
     (if (and (odra-package-catalog-snapshot? loaded)
              (string=?
               (odra-package-catalog-snapshot-catalog-id loaded)
               (odra-package-catalog-confirmed-snapshot-reference-catalog-id
                reference))
              (string=?
               (odra-package-catalog-snapshot-id loaded)
               (odra-package-catalog-confirmed-snapshot-reference-snapshot-id
                reference))
              (=
               (odra-package-catalog-snapshot-sequence loaded)
               (odra-package-catalog-confirmed-snapshot-reference-sequence
                reference))
              (string=?
               (package-catalog-snapshot-module-digest loaded)
               (odra-package-catalog-confirmed-snapshot-reference-digest
                reference)))
         (values loaded #f)
         (values #f "Confirmed snapshot cache is unavailable or invalid"))]))

(define (endpoint-observation endpoint-state fetch-result)
  (define endpoint
    (odra-package-catalog-state-endpoint-endpoint endpoint-state))
  (cond
    [(odra-package-catalog-fetch-result? fetch-result)
     (define decoded
       (package-catalog-snapshot-module-parse
        (odra-package-catalog-fetch-result-bytes fetch-result)
        (string-append
         "endpoint:"
         (odra-package-catalog-fetch-result-endpoint-id fetch-result))))
     (if (odra-package-catalog-snapshot? decoded)
         (odra-package-catalog-snapshot-observation
          endpoint 'available decoded
          (odra-package-catalog-fetch-result-observed-bytes fetch-result) "")
         (odra-package-catalog-snapshot-observation
          endpoint 'unavailable #f 0 "Endpoint returned an invalid snapshot record"))]
    [else
     (odra-package-catalog-snapshot-observation
      endpoint 'unavailable #f 0
      (odra-package-catalog-fetch-failure-detail fetch-result))]))

(define (refresh-failure state registration code detail)
  (odra-package-catalog-state-failure
   current-package-catalog-state-format-version
   (string-append (odra-package-catalog-registration-id registration) "-refresh")
   (odra-package-catalog-registration-catalog-id registration)
   code (add1 (odra-package-catalog-state-generation state)) detail))

(define (persist-refresh! manager registration status reference failure
                          endpoint-results reconciliation detail)
  (define state (package-catalog-refresh-manager-state manager))
  (define-values (candidate rejection)
    (package-catalog-state-record-refresh
     state (odra-package-catalog-registration-id registration) status reference
     failure (odra-package-catalog-state-generation state)))
  (cond
    [rejection
     (odra-package-catalog-refresh-result
      'failed state (odra-package-catalog-registration-id registration)
      endpoint-results reconciliation "Refresh state transition was rejected")]
    [else
     (define publication
       ((package-catalog-refresh-manager-persistence manager)
        (package-catalog-refresh-manager-root manager) candidate))
     (if (odra-record-publication? publication)
         (begin
           (set-package-catalog-refresh-manager-state! manager candidate)
           (odra-package-catalog-refresh-result
            status candidate (odra-package-catalog-registration-id registration)
            endpoint-results reconciliation detail))
         (odra-package-catalog-refresh-result
          'failed state (odra-package-catalog-registration-id registration)
          endpoint-results reconciliation "Catalog state publication failed"))]))

(define (record-failed-refresh! manager registration status code detail
                                endpoint-results reconciliation)
  (define state (package-catalog-refresh-manager-state manager))
  (persist-refresh!
   manager registration status #f
   (refresh-failure state registration code detail)
   endpoint-results reconciliation detail))

(define (endpoint-unavailable-detail endpoint-results)
  (define failures
    (filter odra-package-catalog-fetch-failure? endpoint-results))
  (define (has-code? code)
    (for/or ([failure (in-list failures)])
      (eq? code (odra-package-catalog-fetch-failure-code failure))))
  (cond
    [(has-code? 'credential)
     (string-append
      "Package catalog sign-in is missing or was rejected. "
      "Provide the catalog authorization and retry; installed packages are unchanged.")]
    [(has-code? 'http-status)
     (string-append
      "The package catalog server rejected the request. "
      "Check its authorization or availability and retry; installed packages are unchanged.")]
    [(or (has-code? 'deadline) (has-code? 'io) (has-code? 'transport))
     (string-append
      "Odra could not reach the package catalog. "
      "Check the network connection and retry; installed packages are unchanged.")]
    [else
     (string-append
      "Odra could not refresh the package catalog. "
      "Check its connection and authorization, then retry; installed packages are unchanged.")]))

(define (claim-refresh! manager registration-id)
  (call-with-semaphore
   (package-catalog-refresh-manager-guard manager)
   (lambda ()
     (if (hash-ref (package-catalog-refresh-manager-busy manager)
                   registration-id #f)
         #f
         (begin
           (hash-set! (package-catalog-refresh-manager-busy manager)
                      registration-id #t)
           #t)))))

(define (release-refresh! manager registration-id)
  (call-with-semaphore
   (package-catalog-refresh-manager-guard manager)
   (lambda ()
     (hash-remove! (package-catalog-refresh-manager-busy manager)
                   registration-id))))

(define (perform-refresh manager registration-id now cancelled?)
  (define state (package-catalog-refresh-manager-state manager))
  (define registration (find-registration state registration-id))
  (cond
    [(not registration)
     (odra-package-catalog-refresh-result
      'blocked state registration-id '() #f "Catalog registration is absent")]
    [(not (odra-package-catalog-registration-enabled? registration))
     (odra-package-catalog-refresh-result
      'blocked state registration-id '() #f "Catalog registration is disabled")]
    [else
     (define catalog-id
       (odra-package-catalog-registration-catalog-id registration))
     (define profile (find-profile manager catalog-id))
     (cond
       [(not profile)
        (record-failed-refresh!
         manager registration 'failed 'invalid-snapshot
         "Catalog trust profile is unavailable" '() #f)]
       [else
        (define reference (confirmed-reference state catalog-id))
        (define-values (previous previous-failure)
          (load-confirmed-snapshot manager reference))
        (cond
          [previous-failure
           (record-failed-refresh!
            manager registration 'failed 'corrupt-state previous-failure '() #f)]
          [else
           (define endpoints (registration-endpoints state registration))
           (define endpoint-results
             (for/list ([endpoint-state (in-list endpoints)])
               (fetch-package-catalog-endpoint
                endpoint-state
                (package-catalog-refresh-manager-transport-policy manager)
                (package-catalog-refresh-manager-credential-resolver manager)
                #:cancelled? cancelled?)))
           (define observations
             (map endpoint-observation endpoints endpoint-results))
           (define reconciliation
             (reconcile-package-catalog-snapshots
              profile (package-catalog-refresh-manager-publisher-keys manager)
              previous observations now
              #:allow-current? #t
              #:allow-bootstrap-latest?
              (and (not previous)
                   (eq?
                    (odra-package-catalog-registration-configuration-origin
                     registration)
                    'built-in))))
           (case (odra-package-catalog-snapshot-reconciliation-mode
                  reconciliation)
             [(confirmed)
              (define cached
                (package-catalog-snapshot-cache-persist
                 (package-catalog-refresh-manager-root manager) reconciliation))
              (if (odra-package-catalog-snapshot-cache-failure? cached)
                  (record-failed-refresh!
                   manager registration 'failed 'publication
                   "Confirmed snapshot cache publication failed"
                   endpoint-results reconciliation)
                  (persist-refresh!
                   manager registration 'current
                   (package-catalog-snapshot-confirmed-reference
                    (odra-package-catalog-snapshot-reconciliation-snapshot
                     reconciliation)
                    (odra-package-catalog-snapshot-cache-result-reference cached)
                    now)
                   #f endpoint-results reconciliation ""))]
             [(offline)
              (define within-grace?
                (and previous
                     (< now
                        (+ (odra-package-catalog-snapshot-expires-at previous)
                           (package-catalog-refresh-manager-offline-grace-seconds
                            manager)))))
              (record-failed-refresh!
               manager registration (if within-grace? 'offline 'stale)
               'endpoint-unavailable
               (if within-grace?
                   "Configured endpoints are unavailable; confirmed state is retained"
                   "Confirmed snapshot exceeded the offline expiry policy")
               endpoint-results reconciliation)]
             [(unavailable)
              (record-failed-refresh!
               manager registration 'failed 'endpoint-unavailable
               (endpoint-unavailable-detail endpoint-results)
               endpoint-results reconciliation)]
             [else
              (record-failed-refresh!
               manager registration 'failed 'invalid-snapshot
               (if (eq? (odra-package-catalog-snapshot-reconciliation-mode
                         reconciliation)
                        'divergent)
                   "Configured endpoints returned divergent signed snapshots"
                   "Fetched snapshot failed identity or history verification")
               endpoint-results reconciliation)])])])]))

(define (refresh-package-catalog-registration!
         manager registration-id now #:cancelled? [cancelled? (lambda () #f)])
  (cond
    [(not (claim-refresh! manager registration-id))
     (odra-package-catalog-refresh-result
      'blocked (package-catalog-refresh-manager-state manager) registration-id
      '() #f "Catalog refresh is already active")]
    [else
     (dynamic-wind
       void
       (lambda () (perform-refresh manager registration-id now cancelled?))
       (lambda () (release-refresh! manager registration-id)))]))
