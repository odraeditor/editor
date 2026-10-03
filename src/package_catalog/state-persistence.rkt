#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/file
         racket/list
         racket/path
         "../storage/durable-file.rkt"
         "../storage/record-codec.rkt"
         "../storage/record-store.rkt"
         "contracts.rkt"
         "state-records.rkt")

(provide
 (struct-out odra-package-catalog-startup)
 (struct-out odra-package-catalog-state-rejection)
 (struct-out odra-record-publication)
 (struct-out odra-record-publication-failure)
 (contract-out
  [package-catalog-state-path (-> path-string? path?)]
  [package-catalog-state-persist
   (-> path-string? odra-package-catalog-state?
       (or/c odra-record-publication? odra-record-publication-failure?))]
  [package-catalog-state-startup
   (-> path-string? string? odra-package-catalog-startup?)]
  [package-catalog-state-register
   (-> odra-package-catalog-state?
       odra-package-catalog-registration?
       (listof odra-package-catalog-state-endpoint?)
       symbol?
       exact-positive-integer?
       (values odra-package-catalog-state?
               (or/c #f odra-package-catalog-state-rejection?)))]
  [package-catalog-state-reconcile-endpoint-credentials
   (-> odra-package-catalog-state? string?
       (listof odra-package-catalog-state-endpoint?)
       exact-positive-integer?
       (values odra-package-catalog-state?
               (or/c #f odra-package-catalog-state-rejection?)))]
  [package-catalog-state-set-enabled
   (-> odra-package-catalog-state? string? boolean? exact-positive-integer?
       (values odra-package-catalog-state?
               (or/c #f odra-package-catalog-state-rejection?)))]
  [package-catalog-state-remove
   (-> odra-package-catalog-state? string? exact-positive-integer?
       (values odra-package-catalog-state?
               (or/c #f odra-package-catalog-state-rejection?)))]
  [package-catalog-state-confirm-snapshot
   (-> odra-package-catalog-state?
       odra-package-catalog-confirmed-snapshot-reference?
       exact-positive-integer?
       (values odra-package-catalog-state?
               (or/c #f odra-package-catalog-state-rejection?)))]
  [package-catalog-state-record-refresh
   (-> odra-package-catalog-state? string?
       (or/c 'blocked 'current 'failed 'offline 'stale)
       (or/c #f odra-package-catalog-confirmed-snapshot-reference?)
       (or/c #f odra-package-catalog-state-failure?)
       exact-positive-integer?
       (values odra-package-catalog-state?
               (or/c #f odra-package-catalog-state-rejection?)))]
  [package-catalog-state-reachable-references
   (-> odra-package-catalog-state? (listof string?))]
  [package-catalog-state-cleanup-plan
   (-> odra-package-catalog-state? (listof string?) (listof string?))]))

(define explicit-enrollment-origins
  (hash 'administrator-action 'administrator
        'built-in-bootstrap 'built-in
        'project-configuration 'project
        'user-action 'user))

(struct odra-package-catalog-startup
  (mode state diagnostic quarantine-paths)
  #:transparent)

(struct odra-package-catalog-state-rejection (code field expected actual)
  #:transparent
  #:guard
  (lambda (code field expected actual _)
    (unless (and (memq code '(duplicate-registration identity-change
                                                     invalid-generation
                                                     invalid-registration
                                                     invalid-refresh
                                                     missing-registration
                                                     catalog-disabled
                                                     stale-generation
                                                     stale-snapshot
                                                     transitive-enrollment
                                                     unregistered-catalog))
                 (symbol? field))
      (raise-arguments-error 'odra-package-catalog-state-rejection
                             "invalid package catalog state rejection"))
    (values code field expected actual)))

(define (reject code field [expected #f] [actual #f])
  (odra-package-catalog-state-rejection code field expected actual))

(define (package-catalog-state-path configuration-root)
  (build-path (path->complete-path configuration-root)
              "package-catalog" "state.rktd"))

(define (validate-state-generation target candidate _load _generation-of)
  (cond
    [(file-exists? target)
     (define current (package-catalog-state-module-load target))
     (when (odra-record-diagnostic? current)
       (record-publication-reject
        'validation-failed "Existing catalog state cannot be validated" target))
     (unless (string=? (odra-package-catalog-state-root-id current)
                       (odra-package-catalog-state-root-id candidate))
       (record-publication-reject
        'invalid-root "Catalog state root identity differs" target))
     (unless (= (odra-package-catalog-state-generation candidate)
                (add1 (odra-package-catalog-state-generation current)))
       (record-publication-reject
        'invalid-generation "Catalog state generation must increment once" target))]
    [(not (= (odra-package-catalog-state-generation candidate) 1))
     (record-publication-reject
      'invalid-generation "New catalog state begins at generation one" target)]))

(define (package-catalog-state-persist configuration-root state)
  (record-persist
   'package-catalog-state
   (package-catalog-state-path configuration-root)
   state
   package-catalog-state->module-bytes
   package-catalog-state-module-load
   odra-package-catalog-state-generation
   #:owned-root configuration-root
   #:validate-generation validate-state-generation))

(define (find-registration state registration-id)
  (for/first
      ([registration (in-list (odra-package-catalog-state-registrations state))]
       #:when
       (string=? registration-id
                 (odra-package-catalog-registration-id registration)))
    registration))

(define (endpoint-id endpoint-state)
  (odra-package-catalog-endpoint-id
   (odra-package-catalog-state-endpoint-endpoint endpoint-state)))

(define (find-endpoint endpoints target-id)
  (for/first ([endpoint-state (in-list endpoints)]
              #:when (string=? target-id (endpoint-id endpoint-state)))
    endpoint-state))

(define (next-state state registrations endpoints confirmed-snapshots
                    [failures (odra-package-catalog-state-failures state)])
  (package-catalog-state-with-checksum
   (struct-copy
    odra-package-catalog-state state
    [generation (add1 (odra-package-catalog-state-generation state))]
    [registrations (sort registrations string<?
                         #:key odra-package-catalog-registration-id)]
    [endpoints
     (sort endpoints string<?
           #:key
           (lambda (value)
             (odra-package-catalog-endpoint-id
              (odra-package-catalog-state-endpoint-endpoint value))))]
    [confirmed-snapshots
     (sort confirmed-snapshots string<?
           #:key odra-package-catalog-confirmed-snapshot-reference-catalog-id)]
    [failures
     (sort failures string<? #:key odra-package-catalog-state-failure-id)]
    [checksum (make-string 64 #\0)])))

(define (state-generation-rejection state expected)
  (and (not (= expected (odra-package-catalog-state-generation state)))
       (reject 'stale-generation 'catalog-state
               (odra-package-catalog-state-generation state) expected)))

(define (package-catalog-state-register
         state registration endpoints source expected-generation)
  (define stale (state-generation-rejection state expected-generation))
  (define expected-origin (hash-ref explicit-enrollment-origins source #f))
  (cond
    [stale (values state stale)]
    [(not expected-origin)
     (values state
             (reject 'transitive-enrollment 'source
                     (sort (hash-keys explicit-enrollment-origins) symbol<?)
                     source))]
    [(not (eq? expected-origin
               (odra-package-catalog-registration-configuration-origin
                registration)))
     (values state
             (reject 'invalid-registration 'configuration-origin expected-origin
                     (odra-package-catalog-registration-configuration-origin
                      registration)))]
    [(not (= (odra-package-catalog-registration-generation registration) 1))
     (values state
             (reject 'invalid-generation 'registration 1
                     (odra-package-catalog-registration-generation registration)))]
    [(or (find-registration state
                            (odra-package-catalog-registration-id registration))
         (for/or
             ([current
               (in-list (odra-package-catalog-state-registrations state))])
           (string=?
            (odra-package-catalog-registration-catalog-id current)
            (odra-package-catalog-registration-catalog-id registration))))
     (values state
             (reject 'duplicate-registration 'registration #f
                     (odra-package-catalog-registration-id registration)))]
    [else
     (with-handlers ([exn:fail?
                      (lambda (_failure)
                        (values state
                                (reject 'invalid-registration 'registration)))])
       (values
        (next-state
         state
         (cons registration
               (odra-package-catalog-state-registrations state))
         (append endpoints (odra-package-catalog-state-endpoints state))
         (odra-package-catalog-state-confirmed-snapshots state))
        #f))]))

(define (replace-registration registrations replacement)
  (for/list ([registration (in-list registrations)])
    (if (string=? (odra-package-catalog-registration-id registration)
                  (odra-package-catalog-registration-id replacement))
        replacement
        registration)))

(define (package-catalog-state-set-enabled
         state registration-id enabled? expected-generation)
  (define stale (state-generation-rejection state expected-generation))
  (define current (find-registration state registration-id))
  (cond
    [stale (values state stale)]
    [(not current)
     (values state (reject 'missing-registration 'registration-id #f
                           registration-id))]
    [else
     (define replacement
       (struct-copy
        odra-package-catalog-registration current
        [generation
         (add1 (odra-package-catalog-registration-generation current))]
        [enabled? enabled?]
        [refresh-state
         (if enabled?
             (odra-package-catalog-registration-refresh-state current)
             'blocked)]))
     (values
      (next-state
       state
       (replace-registration
        (odra-package-catalog-state-registrations state) replacement)
       (odra-package-catalog-state-endpoints state)
       (odra-package-catalog-state-confirmed-snapshots state))
     #f)]))

(define (package-catalog-state-reconcile-endpoint-credentials
         state registration-id configured-endpoints expected-generation)
  (define stale (state-generation-rejection state expected-generation))
  (define registration (find-registration state registration-id))
  (define current-endpoints (odra-package-catalog-state-endpoints state))
  (define expected-endpoint-ids
    (and registration
         (odra-package-catalog-registration-endpoint-ids registration)))
  (define configured-endpoint-ids
    (sort (map endpoint-id configured-endpoints) string<?))
  (define endpoints-match?
    (and registration
         (equal? expected-endpoint-ids configured-endpoint-ids)
         (for/and ([configured (in-list configured-endpoints)])
           (define current
             (find-endpoint current-endpoints (endpoint-id configured)))
           (and current
                (equal?
                 (odra-package-catalog-state-endpoint-endpoint current)
                 (odra-package-catalog-state-endpoint-endpoint configured))))))
  (cond
    [stale (values state stale)]
    [(not registration)
     (values state (reject 'missing-registration 'registration-id #f
                           registration-id))]
    [(not endpoints-match?)
     (values state
             (reject 'invalid-registration 'endpoints expected-endpoint-ids
                     configured-endpoint-ids))]
    [else
     (define changed? #f)
     (define replacements
       (for/list ([current (in-list current-endpoints)])
         (define configured
           (find-endpoint configured-endpoints (endpoint-id current)))
         (cond
           [(not configured) current]
           [(equal?
             (odra-package-catalog-state-endpoint-credential-reference current)
             (odra-package-catalog-state-endpoint-credential-reference
              configured))
            current]
           [else
            (set! changed? #t)
            (struct-copy
             odra-package-catalog-state-endpoint current
             [generation
              (add1
               (odra-package-catalog-state-endpoint-generation current))]
             [credential-reference
              (odra-package-catalog-state-endpoint-credential-reference
               configured)])])))
     (values
      (if changed?
          (next-state
           state
           (odra-package-catalog-state-registrations state)
           replacements
           (odra-package-catalog-state-confirmed-snapshots state))
          state)
      #f)]))

(define (same-confirmed-snapshot? left right)
  (and (string=?
        (odra-package-catalog-confirmed-snapshot-reference-snapshot-id left)
        (odra-package-catalog-confirmed-snapshot-reference-snapshot-id right))
       (string=?
        (odra-package-catalog-confirmed-snapshot-reference-digest left)
        (odra-package-catalog-confirmed-snapshot-reference-digest right))
       (=
        (odra-package-catalog-confirmed-snapshot-reference-sequence left)
        (odra-package-catalog-confirmed-snapshot-reference-sequence right))))

(define (package-catalog-state-record-refresh
         state registration-id refresh-state reference failure expected-generation)
  (define stale (state-generation-rejection state expected-generation))
  (define registration (find-registration state registration-id))
  (define previous
    (and registration
         (for/first
             ([candidate
               (in-list
                (odra-package-catalog-state-confirmed-snapshots state))]
              #:when
              (string=?
               (odra-package-catalog-registration-catalog-id registration)
               (odra-package-catalog-confirmed-snapshot-reference-catalog-id
                candidate)))
           candidate)))
  (define reference-valid?
    (or
     (not reference)
     (and registration
          (string=?
           (odra-package-catalog-registration-catalog-id registration)
           (odra-package-catalog-confirmed-snapshot-reference-catalog-id
            reference))
          (or (not previous)
              (same-confirmed-snapshot? previous reference)
              (>
               (odra-package-catalog-confirmed-snapshot-reference-sequence
                reference)
               (odra-package-catalog-confirmed-snapshot-reference-sequence
                previous))))))
  (define failure-valid?
    (or (not failure)
        (and registration
             (string=?
              (odra-package-catalog-registration-catalog-id registration)
              (odra-package-catalog-state-failure-catalog-id failure)))))
  (cond
    [stale (values state stale)]
    [(not registration)
     (values state
             (reject 'missing-registration 'registration-id #f registration-id))]
    [(not (odra-package-catalog-registration-enabled? registration))
     (values state (reject 'catalog-disabled 'registration-id #t #f))]
    [(or (and (eq? refresh-state 'current) (not reference))
         (and (not (eq? refresh-state 'current)) reference)
         (and (memq refresh-state '(failed stale)) (not failure))
         (and (eq? refresh-state 'current) failure)
         (not reference-valid?)
         (not failure-valid?))
     (values state (reject 'invalid-refresh 'refresh-state #f refresh-state))]
    [else
     (define replacement
       (struct-copy
        odra-package-catalog-registration registration
        [generation
         (add1 (odra-package-catalog-registration-generation registration))]
        [refresh-state refresh-state]))
     (define confirmed
       (if reference
           (cons
            reference
            (filter
             (lambda (candidate)
               (not
                (string=?
                 (odra-package-catalog-registration-catalog-id registration)
                 (odra-package-catalog-confirmed-snapshot-reference-catalog-id
                  candidate))))
             (odra-package-catalog-state-confirmed-snapshots state)))
           (odra-package-catalog-state-confirmed-snapshots state)))
     (define retained-failures
       (filter
        (lambda (candidate)
          (not
           (string=?
            (odra-package-catalog-registration-catalog-id registration)
            (odra-package-catalog-state-failure-catalog-id candidate))))
        (odra-package-catalog-state-failures state)))
     (values
      (next-state
       state
       (replace-registration
        (odra-package-catalog-state-registrations state) replacement)
       (odra-package-catalog-state-endpoints state)
       confirmed
       (if failure (cons failure retained-failures) retained-failures))
      #f)]))

(define (package-catalog-state-remove state registration-id expected-generation)
  (define stale (state-generation-rejection state expected-generation))
  (define current (find-registration state registration-id))
  (cond
    [stale (values state stale)]
    [(not current)
     (values state (reject 'missing-registration 'registration-id #f
                           registration-id))]
    [else
     (define removed-endpoint-ids
       (odra-package-catalog-registration-endpoint-ids current))
     (values
      (next-state
       state
       (filter
        (lambda (registration)
          (not (string=? registration-id
                         (odra-package-catalog-registration-id registration))))
        (odra-package-catalog-state-registrations state))
       (filter
        (lambda (endpoint-state)
          (not
           (member
            (odra-package-catalog-endpoint-id
             (odra-package-catalog-state-endpoint-endpoint endpoint-state))
            removed-endpoint-ids string=?)))
        (odra-package-catalog-state-endpoints state))
       (odra-package-catalog-state-confirmed-snapshots state))
      #f)]))

(define (package-catalog-state-confirm-snapshot
         state reference expected-generation)
  (define stale (state-generation-rejection state expected-generation))
  (define registration
    (for/first
        ([candidate
          (in-list (odra-package-catalog-state-registrations state))]
         #:when
         (string=?
          (odra-package-catalog-registration-catalog-id candidate)
          (odra-package-catalog-confirmed-snapshot-reference-catalog-id
           reference)))
      candidate))
  (define previous
    (for/first
        ([candidate
          (in-list (odra-package-catalog-state-confirmed-snapshots state))]
         #:when
         (string=?
          (odra-package-catalog-confirmed-snapshot-reference-catalog-id candidate)
          (odra-package-catalog-confirmed-snapshot-reference-catalog-id
           reference)))
      candidate))
  (cond
    [stale (values state stale)]
    [(not registration)
     (values state
             (reject
              'unregistered-catalog 'catalog-id #f
              (odra-package-catalog-confirmed-snapshot-reference-catalog-id
               reference)))]
    [(and previous
          (<= (odra-package-catalog-confirmed-snapshot-reference-sequence
               reference)
              (odra-package-catalog-confirmed-snapshot-reference-sequence
               previous)))
     (values state
             (reject
              'stale-snapshot 'sequence
              (add1
               (odra-package-catalog-confirmed-snapshot-reference-sequence
                previous))
              (odra-package-catalog-confirmed-snapshot-reference-sequence
               reference)))]
    [else
     (values
      (next-state
       state
       (odra-package-catalog-state-registrations state)
       (odra-package-catalog-state-endpoints state)
       (cons
        reference
        (filter
         (lambda (candidate)
           (not
            (string=?
             (odra-package-catalog-confirmed-snapshot-reference-catalog-id
              candidate)
             (odra-package-catalog-confirmed-snapshot-reference-catalog-id
              reference))))
         (odra-package-catalog-state-confirmed-snapshots state))))
      #f)]))

(define (package-catalog-state-reachable-references state)
  (sort
   (remove-duplicates
    (append
     (map odra-package-catalog-confirmed-snapshot-reference-cache-reference
          (odra-package-catalog-state-confirmed-snapshots state))
     (odra-package-catalog-state-quarantine state))
    string=?)
   string<?))

(define (package-catalog-state-cleanup-plan state candidates)
  (define reachable (package-catalog-state-reachable-references state))
  (sort
   (filter (lambda (candidate) (not (member candidate reachable string=?)))
           (remove-duplicates candidates string=?))
   string<?))

(define (stage-path? path)
  (regexp-match? #px"^[.]odra-stage-.*[.]tmp$"
                 (path->string (file-name-from-path path))))

(define (catalog-state-stage-paths root)
  (define directory (path-only (package-catalog-state-path root)))
  (if (directory-exists? directory)
      (filter stage-path? (directory-list directory #:build? #t))
      '()))

(define (quarantine-path root source label)
  (with-handlers ([exn:fail? (lambda (_failure) #f)])
    (define quarantine-root
      (build-path (path->complete-path root) "package-catalog" "quarantine"))
    (make-directory* quarantine-root)
    (file-or-directory-permissions quarantine-root #o700)
    (define destination
      (build-path
       quarantine-root
       (format "~a-~a-~a.rktd" label
               (inexact->exact (floor (current-inexact-milliseconds)))
               (random 4294967087))))
    (rename-file-or-directory source destination #f)
    (durable-directory-synchronize quarantine-root)
    (durable-directory-synchronize (path-only source))
    destination))

(define (quarantine-stages root)
  (filter values
          (for/list ([stage (in-list (catalog-state-stage-paths root))])
            (quarantine-path root stage "orphan-stage"))))

(define (package-catalog-state-startup root root-id)
  (define complete-root (path->complete-path root))
  (define path (package-catalog-state-path complete-root))
  (define stage-quarantine (quarantine-stages complete-root))
  (cond
    [(not (file-exists? path))
     (odra-package-catalog-startup
      'empty (package-catalog-empty-state root-id) #f stage-quarantine)]
    [else
     (define loaded (package-catalog-state-module-load path))
     (cond
       [(odra-record-diagnostic? loaded)
        (define quarantined (quarantine-path complete-root path "invalid-state"))
        (odra-package-catalog-startup
         'quarantined
         (package-catalog-empty-state root-id)
         loaded
         (append stage-quarantine (filter values (list quarantined))))]
       [(not (string=? root-id (odra-package-catalog-state-root-id loaded)))
        (odra-package-catalog-startup
         'blocked loaded 'root-identity-mismatch stage-quarantine)]
       [else
        (odra-package-catalog-startup
         'confirmed loaded #f stage-quarantine)])]))
