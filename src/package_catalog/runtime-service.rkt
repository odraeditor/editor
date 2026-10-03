#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/file
         racket/list
         racket/path
         racket/string
         "../command/package-catalogs.rkt"
         "../package/acquisition.rkt"
         "../package/credential-provider.rkt"
         "../package/resolution.rkt"
         "../storage/durable-file.rkt"
         "catalog-refresh.rkt"
         "contracts.rkt"
         "curation-publication.rkt"
         "curation-records.rkt"
         "curation-resolution.rkt"
         "endpoint-transport.rkt"
         "federated-resolution.rkt"
         "integrity.rkt"
         "official-bootstrap.rkt"
         "publication-metadata.rkt"
         "snapshot-records.rkt"
         "snapshot-reconciliation.rkt"
         "state-persistence.rkt"
         "state-records.rkt")

(provide
 (struct-out odra-package-catalog-runtime-result)
 (contract-out
  [package-catalog-runtime-preview-add
   (-> path-string? odra-package-catalog-configuration? path-string?
       odra-package-catalog-runtime-result?)]
  [package-catalog-runtime-add
   (-> path-string? odra-package-catalog-configuration? path-string?
       odra-package-catalog-runtime-result?)]
  [package-catalog-runtime-list
   (-> path-string? odra-package-catalog-configuration?
       odra-package-catalog-runtime-result?)]
  [package-catalog-runtime-set-enabled
   (-> path-string? odra-package-catalog-configuration? string? boolean?
       odra-package-catalog-runtime-result?)]
  [package-catalog-runtime-remove
   (-> path-string? odra-package-catalog-configuration? string?
       odra-package-catalog-runtime-result?)]
  [package-catalog-runtime-refresh
   (-> path-string? odra-package-catalog-configuration? string?
       odra-package-catalog-runtime-result?)]
  [package-catalog-runtime-search
   (-> path-string? odra-package-catalog-configuration? string?
       odra-package-catalog-runtime-result?)]
  [package-catalog-runtime-discover
   (-> path-string? odra-package-catalog-configuration? string?
       odra-package-catalog-runtime-result?)]
  [package-catalog-runtime-prepare-installation
   (->* (path-string? odra-package-catalog-configuration? string? string?)
        (#:acquisition-root path-string?)
        (or/c (list/c odra-package-installation-candidate?
                      odra-package-acquisition?)
              odra-package-installation-acquisition-failure?))]
  [package-catalog-runtime-describe
   (-> path-string? odra-package-catalog-configuration? string?
       odra-package-catalog-runtime-result?)]
  [package-catalog-runtime-doctor
   (-> path-string? odra-package-catalog-configuration?
       odra-package-catalog-runtime-result?)]))

(define state-root-id "default")
(define maximum-result-bytes (* 64 1024))

(struct odra-package-catalog-runtime-result
  (status generation item-count identity detail)
  #:transparent
  #:guard
  (lambda (status generation item-count identity detail _)
    (unless (and (memq status '(confirmation failure success))
                 (exact-nonnegative-integer? generation)
                 (exact-nonnegative-integer? item-count)
                 (string? identity)
                 (string? detail)
                 (<= (bytes-length (string->bytes/utf-8 detail))
                     maximum-result-bytes))
      (raise-arguments-error 'odra-package-catalog-runtime-result
                             "invalid bounded package catalog runtime result"))
    (values status generation item-count
            (string->immutable-string identity)
            (string->immutable-string detail))))

(define (success state detail [item-count 0] [identity ""])
  (odra-package-catalog-runtime-result
   'success (odra-package-catalog-state-generation state) item-count identity
   detail))

(define (failure state detail [identity ""])
  (odra-package-catalog-runtime-result
   'failure (odra-package-catalog-state-generation state) 0 identity detail))

(define (configuration-origin-action origin)
  (case origin
    [(administrator) 'administrator-action]
    [(built-in) 'built-in-bootstrap]
    [(project) 'project-configuration]
    [else 'user-action]))

(define (persist-state root state)
  (define publication (package-catalog-state-persist root state))
  (and (odra-record-publication? publication) state))

(define (startup-state root)
  (define startup (package-catalog-state-startup root state-root-id))
  (define state (odra-package-catalog-startup-state startup))
  (cond
    [(eq? (odra-package-catalog-startup-mode startup) 'blocked)
     (values state "Catalog state belongs to another configuration root")]
    [(eq? (odra-package-catalog-startup-mode startup) 'empty)
     (if (persist-state root state)
         (values state #f)
         (values state "Catalog state could not be initialized"))]
    [else (values state #f)]))

(define (find-registration state registration-id)
  (for/first
      ([registration (in-list (odra-package-catalog-state-registrations state))]
       #:when
       (string=? registration-id
                 (odra-package-catalog-registration-id registration)))
    registration))

(define (synchronize-configuration root state configuration)
  (for/fold ([current state] [problem #f] #:result (values current problem))
            ([configured
              (in-list
               (odra-package-catalog-configuration-registrations
                configuration))]
             #:break problem)
    (define registration-id
      (odra-package-catalog-config-registration-id configured))
    (define existing (find-registration current registration-id))
    (cond
      [existing
       (define-values (_configured-registration configured-endpoints)
         (package-catalog-registration-state configured))
       (define-values (candidate rejection)
         (package-catalog-state-reconcile-endpoint-credentials
          current registration-id configured-endpoints
          (odra-package-catalog-state-generation current)))
       (cond
         [rejection
          (values current
                  (format "Configured catalog ~a could not reconcile endpoint credentials: ~a"
                          registration-id
                          (odra-package-catalog-state-rejection-code rejection)))]
         [(eq? candidate current) (values current #f)]
         [(persist-state root candidate) (values candidate #f)]
         [else
          (values current
                  (format "Configured catalog ~a endpoint credentials could not be persisted"
                          registration-id))])]
      [else
       (define-values (registration endpoints)
         (package-catalog-registration-state configured))
       (define-values (candidate rejection)
         (package-catalog-state-register
          current registration endpoints
          (configuration-origin-action
           (odra-package-catalog-config-registration-configuration-origin
            configured))
          (odra-package-catalog-state-generation current)))
       (cond
         [rejection
          (values current
                  (format "Configured catalog ~a was rejected: ~a"
                          registration-id
                          (odra-package-catalog-state-rejection-code rejection)))]
         [(persist-state root candidate) (values candidate #f)]
         [else
          (values current
                  (format "Configured catalog ~a could not be persisted"
                          registration-id))])])))

(define (runtime-state root configuration)
  (define-values (state startup-problem) (startup-state root))
  (if startup-problem
      (values state startup-problem)
      (synchronize-configuration root state configuration)))

(define (publication-metadata-path value)
  (define complete (path->complete-path value))
  (if (directory-exists? complete)
      (build-path complete "catalog.rktd")
      complete))

(define (metadata-snapshot-path metadata-path)
  (build-path (path-only metadata-path) "snapshot.rktd"))

(define (metadata-assertion-path metadata-path)
  (build-path (path-only metadata-path) "assertions.rktd"))

(define (load-publication value)
  (define metadata-path (publication-metadata-path value))
  (define metadata
    (package-catalog-publication-metadata-module-load metadata-path))
  (cond
    [(not (odra-package-catalog-publication-metadata? metadata))
     (values #f #f #f metadata-path
             "Publication metadata is unavailable or invalid")]
    [else
     (define snapshot-path (metadata-snapshot-path metadata-path))
     (define assertion-path (metadata-assertion-path metadata-path))
     (define snapshot (package-catalog-snapshot-module-load snapshot-path))
     (define assertions
       (package-curation-assertion-set-module-load assertion-path))
     (define profile
       (odra-package-catalog-publication-metadata-profile metadata))
     (cond
       [(not (odra-package-catalog-snapshot? snapshot))
        (values #f #f #f metadata-path
                "Publication snapshot is unavailable or invalid")]
       [(not (and (list? assertions)
                  (andmap odra-package-curation-assertion? assertions)))
        (values #f #f #f metadata-path
                "Publication assertions are unavailable or invalid")]
       [(not
         (and
          (string=? (odra-package-catalog-profile-identity profile)
                    (odra-package-catalog-snapshot-catalog-id snapshot))
          (string=? (package-curation-assertion-set-digest assertions)
                    (odra-package-catalog-snapshot-assertion-set-digest
                     snapshot))))
        (values #f #f #f metadata-path
                "Publication snapshot and assertions do not match metadata")]
       [else (values metadata snapshot assertions metadata-path #f)])]))

(define (initial-root-id profile)
  (odra-package-catalog-root-key-id
   (for/first
       ([root (in-list (odra-package-catalog-profile-roots profile))]
        #:when (= (odra-package-catalog-root-key-generation root) 1))
     root)))

(define (local-registration-id catalog-id)
  (string-append "local-" (substring catalog-id 0 12)))

(define (metadata-cache-path root catalog-id)
  (build-path (path->complete-path root) "package-catalog" "metadata"
              (string-append catalog-id ".rktd")))

(define (cache-metadata root metadata)
  (define profile
    (odra-package-catalog-publication-metadata-profile metadata))
  (define target
    (metadata-cache-path root
                         (odra-package-catalog-profile-identity profile)))
  (define publication
    (durable-file-publish
     target
     (package-catalog-publication-metadata->module-bytes metadata)
     #:private-directories
     (list (path->complete-path root)
           (build-path (path->complete-path root) "package-catalog")
           (path-only target))))
  (or (odra-durable-file-publication? publication)
      (and (file-exists? target)
           (equal?
            (package-catalog-publication-metadata-module-load target)
            metadata))))

(define (load-metadata-for-registration root registration)
  (define catalog-id
    (odra-package-catalog-registration-catalog-id registration))
  (cond
    [(string=? catalog-id official-package-catalog-identity)
     (odra-package-catalog-publication-metadata
      current-package-catalog-publication-metadata-format-version
      (odra-package-catalog-bootstrap-profile official-package-catalog-bootstrap)
      (odra-package-catalog-bootstrap-publisher-keys
       official-package-catalog-bootstrap))]
    [else
     (define loaded
       (package-catalog-publication-metadata-module-load
        (metadata-cache-path root catalog-id)))
     (and (odra-package-catalog-publication-metadata? loaded) loaded)]))

(define (assertion-cache-path root snapshot)
  (build-path
   (path->complete-path root) "package-catalog" "assertions"
   (odra-package-catalog-snapshot-catalog-id snapshot)
   (format "~a-~a.rktd"
           (odra-package-catalog-snapshot-sequence snapshot)
           (odra-package-catalog-snapshot-id snapshot))))

(define (cache-assertions root snapshot assertions)
  (define target (assertion-cache-path root snapshot))
  (define bytes (package-curation-assertion-set->module-bytes assertions))
  (define publication
    (durable-file-publish
     target bytes
     #:private-directories
     (list (path->complete-path root)
           (build-path (path->complete-path root) "package-catalog")
           (build-path (path->complete-path root) "package-catalog"
                       "assertions")
           (path-only target))))
  (or (odra-durable-file-publication? publication)
      (and (file-exists? target) (bytes=? (file->bytes target) bytes))))

(define (package-catalog-runtime-preview-add root configuration value)
  (define-values (state problem) (runtime-state root configuration))
  (cond
    [problem (failure state problem)]
    [else
     (define-values (metadata snapshot assertions metadata-path load-problem)
       (load-publication value))
     (cond
       [load-problem (failure state load-problem)]
       [else
        (define profile
          (odra-package-catalog-publication-metadata-profile metadata))
        (define catalog-id (odra-package-catalog-profile-identity profile))
        (define registration-id (local-registration-id catalog-id))
        (if (find-registration state registration-id)
            (failure state "Catalog registration already exists" registration-id)
            (odra-package-catalog-runtime-result
             'confirmation
             (odra-package-catalog-state-generation state)
             (length assertions)
             registration-id
             (format "Add ~a as ~a from ~a (snapshot ~a, ~a package assertion(s))"
                     (odra-package-catalog-profile-display-name profile)
                     registration-id
                     (path->string (path-only metadata-path))
                     (odra-package-catalog-snapshot-id snapshot)
                     (length assertions))))])]))

(define (package-catalog-runtime-add root configuration value)
  (define-values (state problem) (runtime-state root configuration))
  (cond
    [problem (failure state problem)]
    [else
     (define-values (metadata snapshot assertions metadata-path load-problem)
       (load-publication value))
     (cond
       [load-problem (failure state load-problem)]
       [else
        (define profile
          (odra-package-catalog-publication-metadata-profile metadata))
        (define catalog-id (odra-package-catalog-profile-identity profile))
        (define registration-id (local-registration-id catalog-id))
        (define snapshot-path (metadata-snapshot-path metadata-path))
        (define endpoint
          (odra-package-catalog-endpoint
           (string-append registration-id "-origin") catalog-id
           (string-append "file://" (path->string snapshot-path))
           'file 'local 0 #t))
        (define registration
          (odra-package-catalog-registration
           current-package-catalog-state-format-version registration-id 1
           catalog-id 'user (initial-root-id profile)
           (list (odra-package-catalog-endpoint-id endpoint))
           100 'enforce #t 'never))
        (define endpoint-state
          (odra-package-catalog-state-endpoint
           current-package-catalog-state-format-version 1 endpoint #f))
        (define-values (candidate rejection)
          (package-catalog-state-register
           state registration (list endpoint-state) 'user-action
           (odra-package-catalog-state-generation state)))
        (cond
          [rejection
           (failure state
                    (format "Catalog registration was rejected: ~a"
                            (odra-package-catalog-state-rejection-code rejection))
                    registration-id)]
          [(not (cache-metadata root metadata))
           (failure state "Catalog trust metadata could not be persisted"
                    registration-id)]
          [(not (persist-state root candidate))
           (failure state "Catalog registration could not be persisted"
                    registration-id)]
          [else
           (define refreshed
             (package-catalog-runtime-refresh root configuration registration-id))
           (if (eq? (odra-package-catalog-runtime-result-status refreshed)
                    'success)
               refreshed
               (odra-package-catalog-runtime-result
                'failure
                (odra-package-catalog-runtime-result-generation refreshed)
                0 registration-id
                (string-append
                 "Catalog was registered, but its first refresh failed: "
                 (odra-package-catalog-runtime-result-detail refreshed))))])])]))

(define (registration-line registration)
  (format "~a | ~a | ~a | ~a"
          (odra-package-catalog-registration-id registration)
          (if (odra-package-catalog-registration-enabled? registration)
              "enabled" "disabled")
          (odra-package-catalog-registration-refresh-state registration)
          (substring
           (odra-package-catalog-registration-catalog-id registration) 0 12)))

(define (package-catalog-runtime-list root configuration)
  (define-values (state problem) (runtime-state root configuration))
  (cond
    [problem (failure state problem)]
    [else
     (define registrations (odra-package-catalog-state-registrations state))
     (success state
              (if (null? registrations)
                  "No package catalogs are registered"
                  (string-join (map registration-line registrations) "\n"))
              (length registrations)
              (if (= (length registrations) 1)
                  (odra-package-catalog-registration-id (car registrations))
                  ""))]))

(define (package-catalog-runtime-set-enabled root configuration registration-id
                                             enabled?)
  (define-values (state problem) (runtime-state root configuration))
  (cond
    [problem (failure state problem registration-id)]
    [else
     (define-values (candidate rejection)
       (package-catalog-state-set-enabled
        state registration-id enabled?
        (odra-package-catalog-state-generation state)))
     (cond
       [rejection
        (failure state
                 (format "Catalog state change was rejected: ~a"
                         (odra-package-catalog-state-rejection-code rejection))
                 registration-id)]
       [(persist-state root candidate)
        (success candidate
                 (format "Catalog ~a is ~a"
                         registration-id
                         (if enabled? "enabled" "disabled"))
                 1 registration-id)]
       [else
        (failure state "Catalog state change could not be persisted"
                 registration-id)])]))

(define (package-catalog-runtime-remove root configuration registration-id)
  (define-values (state problem) (runtime-state root configuration))
  (cond
    [problem (failure state problem registration-id)]
    [else
     (define-values (candidate rejection)
       (package-catalog-state-remove
        state registration-id (odra-package-catalog-state-generation state)))
     (cond
       [rejection
        (failure state
                 (format "Catalog removal was rejected: ~a"
                         (odra-package-catalog-state-rejection-code rejection))
                 registration-id)]
       [(persist-state root candidate)
        (success candidate
                 (format "Catalog ~a was removed; installed packages were unchanged"
                         registration-id)
                 1 registration-id)]
       [else
        (failure state "Catalog removal could not be persisted" registration-id)])]))

(define (registration-local-publication state registration)
  (define endpoint-ids
    (odra-package-catalog-registration-endpoint-ids registration))
  (for/first
      ([endpoint-state
        (in-list (odra-package-catalog-state-endpoints state))]
       #:do
       [(define endpoint
          (odra-package-catalog-state-endpoint-endpoint endpoint-state))]
       #:when
       (and (member (odra-package-catalog-endpoint-id endpoint)
                    endpoint-ids string=?)
            (eq? (odra-package-catalog-endpoint-transport endpoint) 'file)))
    (path-only
     (string->path
      (substring (odra-package-catalog-endpoint-uri endpoint) 7)))))

(define (registration-endpoint-state state registration endpoint-id)
  (for/first
      ([endpoint-state
        (in-list (odra-package-catalog-state-endpoints state))]
       #:do
       [(define endpoint
          (odra-package-catalog-state-endpoint-endpoint endpoint-state))]
       #:when
       (and (member endpoint-id
                    (odra-package-catalog-registration-endpoint-ids registration)
                    string=?)
            (string=? endpoint-id
                      (odra-package-catalog-endpoint-id endpoint))))
    endpoint-state))

(define (remote-assertion-uri endpoint snapshot)
  (define uri (odra-package-catalog-endpoint-uri endpoint))
  (and
   (eq? (odra-package-catalog-endpoint-transport endpoint) 'https)
   (regexp-match? #px"/[^/]+[.]rktd$" uri)
   (regexp-replace
    #px"/[^/]+[.]rktd$" uri
    (format "/assertions/~a.rktd"
            (odra-package-catalog-snapshot-assertion-set-digest snapshot)))))

(define (fetch-remote-assertions state registration result snapshot policy
                                 credential-resolver)
  (define endpoint-id
    (for/first
        ([candidate
          (in-list
           (odra-package-catalog-snapshot-reconciliation-endpoint-ids
            (odra-package-catalog-refresh-result-reconciliation result)))]
         #:when
         (for/or
             ([fetch-result
               (in-list
                (odra-package-catalog-refresh-result-endpoint-results result))])
           (and (odra-package-catalog-fetch-result? fetch-result)
                (string=? candidate
                          (odra-package-catalog-fetch-result-endpoint-id
                           fetch-result)))))
      candidate))
  (define endpoint-state
    (and endpoint-id
         (registration-endpoint-state state registration endpoint-id)))
  (define endpoint
    (and endpoint-state
         (odra-package-catalog-state-endpoint-endpoint endpoint-state)))
  (define uri (and endpoint (remote-assertion-uri endpoint snapshot)))
  (cond
    [(not uri)
     (values #f "Confirmed endpoint cannot locate its assertion artifact")]
    [else
     (define assertion-endpoint
       (odra-package-catalog-endpoint
        (odra-package-catalog-endpoint-id endpoint)
        (odra-package-catalog-endpoint-catalog-id endpoint)
        uri 'https
        (odra-package-catalog-endpoint-role endpoint)
        (odra-package-catalog-endpoint-priority endpoint)
        #t))
     (define assertion-endpoint-state
       (odra-package-catalog-state-endpoint
        (odra-package-catalog-state-endpoint-format-version endpoint-state)
        (odra-package-catalog-state-endpoint-generation endpoint-state)
        assertion-endpoint
        (odra-package-catalog-state-endpoint-credential-reference
         endpoint-state)))
     (define fetched
       (fetch-package-catalog-endpoint assertion-endpoint-state policy
                                       credential-resolver))
     (cond
       [(odra-package-catalog-fetch-failure? fetched)
        (values #f
                (format "Assertion artifact fetch failed: ~a"
                        (odra-package-catalog-fetch-failure-detail fetched)))]
       [else
        (define assertions
          (package-curation-assertion-set-module-parse
           (odra-package-catalog-fetch-result-bytes fetched)
           (string-append "endpoint:" endpoint-id ":assertions")))
        (cond
          [(not (list? assertions))
           (values #f "Assertion artifact is invalid")]
          [(not
            (string=?
             (package-curation-assertion-set-digest assertions)
             (odra-package-catalog-snapshot-assertion-set-digest snapshot)))
           (values #f "Assertion artifact digest does not match the snapshot")]
          [else (values assertions #f)])])]))

(define (record-assertion-refresh-failure root state registration detail)
  (define failure-record
    (odra-package-catalog-state-failure
     current-package-catalog-state-format-version
     (string-append
      (odra-package-catalog-registration-id registration) "-assertions")
     (odra-package-catalog-registration-catalog-id registration)
     'invalid-snapshot
     (add1 (odra-package-catalog-state-generation state))
     detail))
  (define-values (candidate rejection)
    (package-catalog-state-record-refresh
     state
     (odra-package-catalog-registration-id registration)
     'failed #f failure-record
     (odra-package-catalog-state-generation state)))
  (if (or rejection (not (persist-state root candidate))) state candidate))

(define (profile-for-registration state profile registration)
  (define endpoint-ids
    (odra-package-catalog-registration-endpoint-ids registration))
  (define endpoints
    (for/list
        ([endpoint-state
          (in-list (odra-package-catalog-state-endpoints state))]
         #:do
         [(define endpoint
            (odra-package-catalog-state-endpoint-endpoint endpoint-state))]
         #:when
         (member (odra-package-catalog-endpoint-id endpoint)
                 endpoint-ids string=?))
      endpoint))
  (define-values (candidate rejection)
    (confirm-package-catalog-profile
     (odra-package-catalog-profile-proposal
      (odra-package-catalog-profile-format-version profile)
      (odra-package-catalog-profile-identity profile)
      (odra-package-catalog-profile-display-name profile)
      (odra-package-catalog-profile-roots profile)
      (odra-package-catalog-profile-curators profile)
      (odra-package-catalog-profile-publishers profile)
      (odra-package-catalog-profile-policies profile)
      endpoints)))
  (and (not rejection) candidate))

(define (package-catalog-runtime-refresh root configuration registration-id)
  (define-values (state problem) (runtime-state root configuration))
  (define registration (and (not problem)
                            (find-registration state registration-id)))
  (cond
    [problem (failure state problem registration-id)]
    [(not registration)
     (failure state "Catalog registration is absent" registration-id)]
    [else
     (define metadata (load-metadata-for-registration root registration))
     (cond
       [(not metadata)
        (failure state "Catalog trust metadata is unavailable" registration-id)]
       [else
        (define local-root
          (registration-local-publication state registration))
        (define assertions #f)
        (define publication-problem #f)
        (when local-root
          (define-values (candidate-metadata snapshot candidate-assertions
                                             _metadata-path load-problem)
            (load-publication local-root))
          (cond
            [load-problem (set! publication-problem load-problem)]
            [(not
              (equal? candidate-metadata metadata))
             (set! publication-problem
                   "Local publication metadata changed from the confirmed trust root")]
            [else (set! assertions candidate-assertions)]))
        (cond
          [publication-problem
           (failure state publication-problem registration-id)]
          [else
           (define refresh-policy
             (odra-package-catalog-configuration-refresh-policy configuration))
           (define credential-resolver
             (package-credential-resolver
              (current-package-credential-provider)))
           (define runtime-profile
             (profile-for-registration
              state
              (odra-package-catalog-publication-metadata-profile metadata)
              registration))
           (define manager
             (make-package-catalog-refresh-manager
              root state
              (list runtime-profile)
              (odra-package-catalog-publication-metadata-publisher-keys metadata)
              (odra-package-catalog-refresh-policy-transport refresh-policy)
              credential-resolver
              #:offline-grace-seconds
              (odra-package-catalog-refresh-policy-offline-grace-seconds
               refresh-policy)))
           (define result
             (refresh-package-catalog-registration!
              manager registration-id (current-seconds)))
           (define refreshed-state
             (odra-package-catalog-refresh-result-state result))
           (define status (odra-package-catalog-refresh-result-status result))
           (when (and (eq? status 'current) (not assertions))
             (define snapshot
               (odra-package-catalog-snapshot-reconciliation-snapshot
                (odra-package-catalog-refresh-result-reconciliation result)))
             (define-values (remote-assertions remote-problem)
               (fetch-remote-assertions
                refreshed-state registration result snapshot
                (odra-package-catalog-refresh-policy-transport refresh-policy)
                credential-resolver))
             (set! assertions remote-assertions)
             (set! publication-problem remote-problem))
           (cond
             [publication-problem
              (failure
               (record-assertion-refresh-failure
                root refreshed-state registration publication-problem)
               publication-problem registration-id)]
             [(eq? status 'current)
              (define snapshot
                (odra-package-catalog-snapshot-reconciliation-snapshot
                 (odra-package-catalog-refresh-result-reconciliation result)))
              (if (cache-assertions root snapshot assertions)
                  (success refreshed-state
                           (format "Catalog ~a refreshed snapshot ~a"
                                   registration-id
                                   (odra-package-catalog-snapshot-sequence
                                    snapshot))
                           (length assertions) registration-id)
                  (failure refreshed-state
                           "Confirmed assertions could not be cached"
                           registration-id))]
             [else
              (failure refreshed-state
                       (odra-package-catalog-refresh-result-detail result)
                       registration-id)])])])]))

(define (confirmed-reference state catalog-id)
  (for/first
      ([reference
        (in-list (odra-package-catalog-state-confirmed-snapshots state))]
       #:when
       (string=?
        catalog-id
        (odra-package-catalog-confirmed-snapshot-reference-catalog-id
         reference)))
    reference))

(define (federated-sources root state)
  (filter
   values
   (for/list
       ([registration
         (in-list (odra-package-catalog-state-registrations state))]
        #:when
        (and (odra-package-catalog-registration-enabled? registration)
             (memq
              (odra-package-catalog-registration-refresh-state registration)
              '(current offline))))
     (define catalog-id
       (odra-package-catalog-registration-catalog-id registration))
     (define reference (confirmed-reference state catalog-id))
     (and reference
          (let* ([snapshot-path
                  (build-path
                   (path->complete-path root) "package-catalog"
                   (odra-package-catalog-confirmed-snapshot-reference-cache-reference
                    reference))]
                 [snapshot (package-catalog-snapshot-module-load snapshot-path)])
            (and
             (odra-package-catalog-snapshot? snapshot)
             (let ([assertions
                    (package-curation-assertion-set-module-load
                     (assertion-cache-path root snapshot))])
               (and
                (list? assertions)
                (string=?
                 (package-curation-assertion-set-digest assertions)
                 (odra-package-catalog-snapshot-assertion-set-digest snapshot))
                (odra-federated-package-source
                 registration reference
                 (odra-package-curated-source
                  catalog-id
                  (odra-package-catalog-snapshot-id snapshot)
                  (odra-package-catalog-registration-package-precedence
                   registration)
                  assertions))))))))))

(define (runtime-platform)
  (case (system-type 'os)
    [(macosx) 'darwin]
    [(windows) 'windows]
    [else 'linux]))

(define (runtime-architecture)
  (if (regexp-match? #px"(?:aarch64|arm64)" (path->string (system-library-subpath)))
      'aarch64
      'x86-64))

(define (search-line match)
  (define attribution
    (odra-federated-package-match-attribution match))
  (format "~a@~a | curated by ~a | ~a"
          (odra-federated-package-match-package-id match)
          (odra-federated-package-match-version match)
          (odra-federated-catalog-attribution-registration-id attribution)
          (odra-federated-package-match-curation-status match)))

(define (package-catalog-runtime-search root configuration query)
  (define-values (state problem) (runtime-state root configuration))
  (cond
    [problem (failure state problem)]
    [else
     (define matches
       (search-federated-packages
        (federated-sources root state) query (runtime-platform)
        (runtime-architecture) 64))
     (success state
              (if (null? matches)
                  "No confirmed package matches"
                  (string-join (map search-line matches) "\n"))
              (length matches))]))

(define (package-catalog-runtime-discover root configuration query)
  (define-values (state problem) (runtime-state root configuration))
  (cond
    [problem (failure state problem)]
    [(pair? (federated-sources root state))
     (package-catalog-runtime-search root configuration query)]
    [else
     (define registrations
       (filter odra-package-catalog-registration-enabled?
               (odra-package-catalog-state-registrations state)))
     (cond
       [(null? registrations)
        (failure state
                 "No enabled package catalogs are available for discovery")]
       [else
        (define refresh-failures
          (filter
           values
           (for/list ([registration (in-list registrations)])
             (define refreshed
               (package-catalog-runtime-refresh
                root configuration
                (odra-package-catalog-registration-id registration)))
             (and (eq? (odra-package-catalog-runtime-result-status refreshed)
                       'failure)
                  refreshed))))
        (define-values (refreshed-state refreshed-problem)
          (runtime-state root configuration))
        (cond
          [refreshed-problem (failure refreshed-state refreshed-problem)]
          [(pair? (federated-sources root refreshed-state))
           (package-catalog-runtime-search root configuration query)]
          [(pair? refresh-failures) (car refresh-failures)]
          [else
           (failure refreshed-state
                    "No confirmed package catalog snapshot is available")])])]))

(define (registration-for-catalog state catalog-id)
  (for/first
      ([registration
        (in-list (odra-package-catalog-state-registrations state))]
       #:when
       (and (odra-package-catalog-registration-enabled? registration)
            (string=? catalog-id
                      (odra-package-catalog-registration-catalog-id
                       registration))))
    registration))

(define (endpoint-state-for-registration state registration)
  (for*/first
      ([endpoint-id
        (in-list
         (odra-package-catalog-registration-endpoint-ids registration))]
       [endpoint-state
        (in-list (odra-package-catalog-state-endpoints state))]
       #:when
       (string=?
        endpoint-id
        (odra-package-catalog-endpoint-id
         (odra-package-catalog-state-endpoint-endpoint endpoint-state))))
    endpoint-state))

(define (artifact-location-resolver endpoint)
  (define endpoint-uri (odra-package-catalog-endpoint-uri endpoint))
  (lambda (location)
    (cond
      [(regexp-match? #px"^https://" location) location]
      [(absolute-path? (string->path location)) location]
      [(eq? (odra-package-catalog-endpoint-transport endpoint) 'file)
       (path->string
        (build-path
         (path-only (string->path (substring endpoint-uri 7))) location))]
      [else
       (regexp-replace #px"[^/]+$" endpoint-uri location)])))

(define (artifact-credential-bindings endpoint-state provider)
  (define endpoint
    (odra-package-catalog-state-endpoint-endpoint endpoint-state))
  (define reference
    (odra-package-catalog-state-endpoint-credential-reference endpoint-state))
  (define matched
    (regexp-match #px"^(https://[^/@?#]+(?::[0-9]+)?)/"
                  (odra-package-catalog-endpoint-uri endpoint)))
  (if (and reference matched)
      (list
       (package-artifact-credential-binding
        #:endpoint-id (odra-package-catalog-endpoint-id endpoint)
        #:origin (cadr matched)
        #:credential-reference reference
        #:provider-id (odra-package-credential-provider-id provider)
        #:provider-generation
        (odra-package-credential-provider-generation provider)))
      '()))

(define (package-catalog-runtime-prepare-installation
         root configuration package-id version
         #:acquisition-root [acquisition-root root])
  (define-values (state problem) (runtime-state root configuration))
  (cond
    [problem
     (odra-package-installation-acquisition-failure 'catalog problem)]
    [else
     (define federated
       (resolve-federated-package
        (federated-sources root state)
        (odra-package-resolution-request
         package-id version version (runtime-platform) (runtime-architecture) #f)
        '()
        (odra-package-catalog-configuration-advisory-response-policy
         configuration)
        (current-seconds) '()
        #:source-pins
        (odra-package-catalog-configuration-source-pins configuration)
        #:organization-overrides
        (odra-package-catalog-configuration-organization-overrides
         configuration)))
     (cond
       [(odra-federated-package-resolution-failure? federated)
        (odra-package-installation-acquisition-failure
         (odra-federated-package-resolution-failure-code federated)
         (format "No confirmed exact release is available for ~a@~a"
                 package-id version))]
       [else
        (define resolution
          (odra-federated-package-resolution-resolution federated))
        (define registration
          (registration-for-catalog
           state (odra-package-resolution-selected-catalog-id resolution)))
        (define endpoint-state
          (and registration
               (endpoint-state-for-registration state registration)))
        (cond
          [(not endpoint-state)
           (odra-package-installation-acquisition-failure
            'catalog "The selected catalog endpoint is unavailable")]
          [else
           (define endpoint
             (odra-package-catalog-state-endpoint-endpoint endpoint-state))
           (define provider (current-package-credential-provider))
           (acquire-curated-package-resolution
            acquisition-root resolution
            #:location-resolver (artifact-location-resolver endpoint)
            #:credential-provider provider
            #:credential-bindings
            (artifact-credential-bindings endpoint-state provider))])])]))

(define (package-catalog-runtime-describe root configuration registration-id)
  (define-values (state problem) (runtime-state root configuration))
  (define registration (and (not problem)
                            (find-registration state registration-id)))
  (cond
    [problem (failure state problem registration-id)]
    [(not registration)
     (failure state "Catalog registration is absent" registration-id)]
    [else
     (define metadata (load-metadata-for-registration root registration))
     (define reference
       (confirmed-reference
        state (odra-package-catalog-registration-catalog-id registration)))
     (success
      state
      (format
       "Catalog: ~a\nIdentity: ~a\nDesignation: ~a\nState: ~a\nSnapshot: ~a\nCuration and package authority remain separate"
       registration-id
       (odra-package-catalog-registration-catalog-id registration)
       (if (string=?
            (odra-package-catalog-registration-catalog-id registration)
            official-package-catalog-identity)
           "official" "independent")
       (odra-package-catalog-registration-refresh-state registration)
       (if reference
           (odra-package-catalog-confirmed-snapshot-reference-snapshot-id
            reference)
           "none"))
      (if metadata 1 0) registration-id)]))

(define (package-catalog-runtime-doctor root configuration)
  (define-values (state problem) (runtime-state root configuration))
  (cond
    [problem (failure state problem)]
    [else
     (define registrations (odra-package-catalog-state-registrations state))
     (define missing-metadata
       (for/list ([registration (in-list registrations)]
                  #:unless
                  (load-metadata-for-registration root registration))
         (odra-package-catalog-registration-id registration)))
     (define failures (odra-package-catalog-state-failures state))
     (success
      state
      (format
       "Catalog state generation: ~a\nRegistrations: ~a\nConfirmed snapshots: ~a\nRecorded failures: ~a\nMissing trust metadata: ~a"
       (odra-package-catalog-state-generation state)
       (length registrations)
       (length (odra-package-catalog-state-confirmed-snapshots state))
       (length failures)
       (if (null? missing-metadata)
           "none"
           (string-join missing-metadata ", ")))
      (length registrations))]))
