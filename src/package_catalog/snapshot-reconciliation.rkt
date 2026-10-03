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
         "contracts.rkt"
         "snapshot-records.rkt"
         "snapshot-verification.rkt"
         "state-records.rkt")

(provide
 (struct-out odra-package-catalog-snapshot-observation)
 odra-package-catalog-snapshot-reconciliation?
 odra-package-catalog-snapshot-reconciliation-mode
 odra-package-catalog-snapshot-reconciliation-snapshot
 odra-package-catalog-snapshot-reconciliation-endpoint-ids
 odra-package-catalog-snapshot-reconciliation-failures
 (struct-out odra-package-catalog-snapshot-cache-result)
 (struct-out odra-package-catalog-snapshot-cache-failure)
 (contract-out
  [reconcile-package-catalog-snapshots
   (->* (odra-package-catalog-profile?
         (listof odra-package-catalog-publisher-key?)
         (or/c #f odra-package-catalog-snapshot?)
         (listof odra-package-catalog-snapshot-observation?)
         exact-nonnegative-integer?)
        (#:allow-current? boolean?
         #:allow-bootstrap-latest? boolean?)
        odra-package-catalog-snapshot-reconciliation?)]
  [package-catalog-snapshot-cache-path
   (-> path-string? odra-package-catalog-snapshot? path?)]
  [package-catalog-snapshot-cache-persist
   (-> path-string? odra-package-catalog-snapshot-reconciliation?
       (or/c odra-package-catalog-snapshot-cache-result?
             odra-package-catalog-snapshot-cache-failure?))]
  [package-catalog-snapshot-confirmed-reference
   (-> odra-package-catalog-snapshot? string? exact-nonnegative-integer?
       odra-package-catalog-confirmed-snapshot-reference?)]))

(struct odra-package-catalog-snapshot-observation
  (endpoint state snapshot observed-metadata-size diagnostic)
  #:transparent
  #:guard
  (lambda (endpoint state snapshot observed-metadata-size diagnostic _)
    (unless
        (and (odra-package-catalog-endpoint? endpoint)
             (memq state '(available unavailable))
             (exact-nonnegative-integer? observed-metadata-size)
             (string? diagnostic)
             (<= (bytes-length (string->bytes/utf-8 diagnostic)) 4096)
             (if (eq? state 'available)
                 (and (odra-package-catalog-snapshot? snapshot)
                      (positive? observed-metadata-size))
                 (and (not snapshot) (zero? observed-metadata-size))))
      (raise-arguments-error 'odra-package-catalog-snapshot-observation
                             "invalid bounded snapshot endpoint observation"))
    (values endpoint state snapshot observed-metadata-size
            (string->immutable-string diagnostic))))

(struct odra-package-catalog-snapshot-reconciliation
  (mode snapshot endpoint-ids failures)
  #:transparent
  #:guard
  (lambda (mode snapshot endpoint-ids failures _)
    (unless
        (and (memq mode '(confirmed divergent offline rejected unavailable))
             (or (not snapshot) (odra-package-catalog-snapshot? snapshot))
             (list? endpoint-ids)
             (andmap string? endpoint-ids)
             (equal? endpoint-ids
                     (sort (remove-duplicates endpoint-ids string=?) string<?))
             (list? failures)
             (andmap odra-package-catalog-snapshot-failure? failures))
      (raise-arguments-error 'odra-package-catalog-snapshot-reconciliation
                             "invalid snapshot reconciliation result"))
    (values mode snapshot
            (map string->immutable-string endpoint-ids) failures)))

(struct odra-package-catalog-snapshot-cache-result
  (status path reference publication)
  #:transparent)
(struct odra-package-catalog-snapshot-cache-failure (code path detail)
  #:transparent)

(define (configured-endpoint profile observed)
  (define endpoint
    (odra-package-catalog-snapshot-observation-endpoint observed))
  (for/first
      ([candidate (in-list (odra-package-catalog-profile-endpoints profile))]
       #:when
       (string=? (odra-package-catalog-endpoint-id candidate)
                 (odra-package-catalog-endpoint-id endpoint)))
    candidate))

(define (endpoint-valid? profile observation)
  (define expected (configured-endpoint profile observation))
  (define observed
    (odra-package-catalog-snapshot-observation-endpoint observation))
  (and expected
       (equal? expected observed)
       (odra-package-catalog-endpoint-enabled? expected)
       (string=? (odra-package-catalog-profile-identity profile)
                 (odra-package-catalog-endpoint-catalog-id observed))))

(define (endpoint-failure observation)
  (odra-package-catalog-snapshot-failure
   'catalog-identity 'endpoint #f
   (odra-package-catalog-endpoint-id
    (odra-package-catalog-snapshot-observation-endpoint observation))))

(define (reconcile-package-catalog-snapshots
         profile publisher-keys previous observations now
         #:allow-current? [allow-current? #f]
         #:allow-bootstrap-latest? [allow-bootstrap-latest? #f])
  (when (> (length observations) maximum-package-catalog-snapshot-observations)
    (raise-arguments-error 'reconcile-package-catalog-snapshots
                           "snapshot observation limit exceeded"))
  (define available
    (filter
     (lambda (observation)
       (eq? (odra-package-catalog-snapshot-observation-state observation)
            'available))
     observations))
  (define checked
    (for/list ([observation (in-list available)])
      (define snapshot
        (odra-package-catalog-snapshot-observation-snapshot observation))
      (define result
        (if (endpoint-valid? profile observation)
            (if (and allow-current? previous (equal? snapshot previous)
                     (< now (odra-package-catalog-snapshot-expires-at snapshot))
                     (=
                      (odra-package-catalog-snapshot-observation-observed-metadata-size
                       observation)
                      (odra-package-catalog-snapshot-metadata-size snapshot)))
                #t
                (verify-package-catalog-snapshot
                 profile publisher-keys previous now
                 (odra-package-catalog-snapshot-observation-observed-metadata-size
                  observation)
                 snapshot
                 #:allow-bootstrap-latest? allow-bootstrap-latest?))
            (endpoint-failure observation)))
      (cons observation result)))
  (define valid
    (filter (lambda (entry) (eq? (cdr entry) #t)) checked))
  (define failures
    (for/list ([entry (in-list checked)]
               #:when (odra-package-catalog-snapshot-failure? (cdr entry)))
      (cdr entry)))
  (define distinct-snapshot-ids
    (remove-duplicates
     (for/list ([entry (in-list valid)])
       (odra-package-catalog-snapshot-id
        (odra-package-catalog-snapshot-observation-snapshot (car entry))))
     string=?))
  (cond
    [(> (length distinct-snapshot-ids) 1)
     (odra-package-catalog-snapshot-reconciliation
      'divergent previous
      (sort
       (for/list ([entry (in-list valid)])
         (odra-package-catalog-endpoint-id
          (odra-package-catalog-snapshot-observation-endpoint (car entry))))
       string<?)
      failures)]
    [(pair? valid)
     (odra-package-catalog-snapshot-reconciliation
      'confirmed
      (odra-package-catalog-snapshot-observation-snapshot (caar valid))
      (sort
       (for/list ([entry (in-list valid)])
         (odra-package-catalog-endpoint-id
          (odra-package-catalog-snapshot-observation-endpoint (car entry))))
       string<?)
      failures)]
    [(null? available)
     (odra-package-catalog-snapshot-reconciliation
      (if previous 'offline 'unavailable) previous '() '())]
    [else
     (odra-package-catalog-snapshot-reconciliation
      'rejected previous '() failures)]))

(define (snapshot-cache-reference snapshot)
  (path->string
   (build-path
    "snapshots"
    (odra-package-catalog-snapshot-catalog-id snapshot)
    (format "~a-~a.rktd"
            (odra-package-catalog-snapshot-sequence snapshot)
            (odra-package-catalog-snapshot-id snapshot)))))

(define (package-catalog-snapshot-cache-path root snapshot)
  (build-path (path->complete-path root) "package-catalog"
              (snapshot-cache-reference snapshot)))

(define (package-catalog-snapshot-cache-persist root reconciliation)
  (unless
      (and (eq? (odra-package-catalog-snapshot-reconciliation-mode
                 reconciliation)
                'confirmed)
           (odra-package-catalog-snapshot?
            (odra-package-catalog-snapshot-reconciliation-snapshot
             reconciliation)))
    (raise-arguments-error 'package-catalog-snapshot-cache-persist
                           "only a confirmed reconciliation can enter the cache"))
  (define snapshot
    (odra-package-catalog-snapshot-reconciliation-snapshot reconciliation))
  (define target (package-catalog-snapshot-cache-path root snapshot))
  (define reference (snapshot-cache-reference snapshot))
  (define expected-bytes (package-catalog-snapshot->module-bytes snapshot))
  (cond
    [(or (file-exists? target) (link-exists? target))
     (define target-failure (durable-file-check target))
     (cond
       [target-failure
        (odra-package-catalog-snapshot-cache-failure
         (odra-durable-file-failure-code target-failure)
         target
         (odra-durable-file-failure-message target-failure))]
       [else
        (define observed (package-catalog-snapshot-module-load target))
        (if (and (odra-package-catalog-snapshot? observed)
                 (equal? observed snapshot)
                 (bytes=? (file->bytes target) expected-bytes))
            (odra-package-catalog-snapshot-cache-result
             'already-present target reference #f)
            (odra-package-catalog-snapshot-cache-failure
             'cache-conflict target
             "Immutable snapshot cache content differs"))])]
    [else
     (define publication
       (durable-file-publish
        target expected-bytes
        #:private-directories
        (list (path->complete-path root)
              (build-path (path->complete-path root) "package-catalog")
              (build-path (path->complete-path root) "package-catalog" "snapshots")
              (path-only target))
        #:validate-stage
        (lambda (stage)
          (define decoded (package-catalog-snapshot-module-load stage))
          (unless (and (odra-package-catalog-snapshot? decoded)
                       (equal? decoded snapshot))
            (error 'package-catalog-snapshot-cache-persist
                   "staged snapshot cache validation failed")))))
     (if (odra-durable-file-publication? publication)
         (odra-package-catalog-snapshot-cache-result
          'published target reference publication)
         (odra-package-catalog-snapshot-cache-failure
          (odra-durable-file-failure-code publication)
          target
          (odra-durable-file-failure-message publication))) ]))

(define (package-catalog-snapshot-confirmed-reference
         snapshot cache-reference confirmed-at)
  (odra-package-catalog-confirmed-snapshot-reference
   current-package-catalog-state-format-version
   (odra-package-catalog-snapshot-catalog-id snapshot)
   (odra-package-catalog-snapshot-id snapshot)
   (odra-package-catalog-snapshot-sequence snapshot)
   (package-catalog-snapshot-module-digest snapshot)
   cache-reference confirmed-at))
