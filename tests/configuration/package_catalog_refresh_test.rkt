#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         rackunit
         "../../src/package_catalog/catalog-refresh.rkt"
         "../../src/package_catalog/contracts.rkt"
         "../../src/package_catalog/endpoint-transport.rkt"
         "../../src/package_catalog/integrity.rkt"
         "../../src/package_catalog/snapshot-records.rkt"
         "../../src/package_catalog/state-persistence.rkt"
         "../../src/package_catalog/state-records.rkt"
         (submod "../../src/package_catalog/endpoint-transport.rkt" test-support)
         (submod "../../src/package_catalog/integrity.rkt" test-support))

(define root-public-key
  "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
(define publisher-public-key
  "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c")
(define publisher-secret-key
  (string-append
   "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
   publisher-public-key))
(define root-id (package-catalog-public-key-id root-public-key))
(define publisher-key-id (package-catalog-public-key-id publisher-public-key))
(define trust-root
  (odra-package-catalog-root-key root-id 1 'ed25519 root-public-key 1 #f))
(define catalog-id (package-catalog-identity trust-root))
(define publisher-key
  (odra-package-catalog-publisher-key
   publisher-key-id 'ed25519 publisher-public-key))
(define publisher
  (odra-package-catalog-publisher-authorization
   "snapshot-publisher" (list publisher-key-id) 1 1 #f))
(define catalog-policy
  (odra-package-catalog-policy
   "policy-v1" 1 1 "eligible" "authority" "assessment" "decision"
   "retention"))
(define transport-policy
  (odra-package-catalog-transport-policy 4096 1000 1 0 'direct))

(define (signed-snapshot sequence previous assertion-digest)
  (let loop ([metadata-size 1])
    (define draft
      (odra-package-catalog-snapshot
       1 (make-string 64 #\0) catalog-id sequence previous "policy-v1"
       (* sequence 10) 200 assertion-digest (make-string 64 #\b) metadata-size
       "snapshot-publisher" '()))
    (define identified
      (struct-copy odra-package-catalog-snapshot draft
                   [id (package-catalog-snapshot-content-digest draft)]))
    (define message
      (package-catalog-signature-message
       package-catalog-publisher-signature-domain
       (package-catalog-snapshot-signing-payload identified)))
    (define signed
      (struct-copy
       odra-package-catalog-snapshot identified
       [signatures
        (list
         (odra-package-catalog-signature
          'ed25519 publisher-key-id package-catalog-publisher-signature-domain
          (sign-for-test message publisher-secret-key)))]))
    (define actual (bytes-length (package-catalog-snapshot->module-bytes signed)))
    (if (= actual metadata-size) signed (loop actual))))

(define first (signed-snapshot 1 #f (make-string 64 #\a)))
(define second
  (signed-snapshot 2 (odra-package-catalog-snapshot-id first)
                   (make-string 64 #\c)))
(define fork
  (signed-snapshot 2 (odra-package-catalog-snapshot-id first)
                   (make-string 64 #\d)))

(define (persist! root state)
  (define result (package-catalog-state-persist root state))
  (check-true (odra-record-publication? result) (format "~s" result)))

(define (with-catalog action #:configuration-origin [configuration-origin 'user])
  (define root (make-temporary-file "odra-catalog-refresh-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (define origin-path (build-path root "origin.rktd"))
  (define mirror-path (build-path root "mirror.rktd"))
  (define origin
    (odra-package-catalog-endpoint
     "origin" catalog-id (string-append "file://" (path->string origin-path))
     'file 'origin 0 #t))
  (define mirror
    (odra-package-catalog-endpoint
     "mirror" catalog-id (string-append "file://" (path->string mirror-path))
     'file 'mirror 1 #t))
  (define registration
    (odra-package-catalog-registration
     1 "independent" 1 catalog-id configuration-origin root-id
     '("mirror" "origin")
     10 'enforce #t 'never))
  (define endpoint-states
    (list (odra-package-catalog-state-endpoint 1 1 mirror #f)
          (odra-package-catalog-state-endpoint 1 1 origin #f)))
  (define-values (profile rejection)
    (confirm-package-catalog-profile
     (odra-package-catalog-profile-proposal
      1 catalog-id "Independent Catalog" (list trust-root) '()
      (list publisher) (list catalog-policy) (list origin mirror))))
  (check-false rejection)
  (define empty (package-catalog-empty-state "default"))
  (persist! root empty)
  (define-values (registered register-rejection)
    (package-catalog-state-register
     empty registration endpoint-states
     (if (eq? configuration-origin 'built-in)
         'built-in-bootstrap
         'user-action)
     1))
  (check-false register-rejection)
  (persist! root registered)
  (dynamic-wind
    void
    (lambda ()
      (action root origin-path mirror-path profile registered))
    (lambda () (delete-directory/files root))))

(define (manager root state profile [grace 200])
  (make-package-catalog-refresh-manager
   root state (list profile) (list publisher-key) transport-policy
   (lambda (_) #f) #:offline-grace-seconds grace))

(define (write-snapshot path snapshot)
  (call-with-output-file path
    (lambda (output)
      (write-bytes (package-catalog-snapshot->module-bytes snapshot) output))
    #:exists 'truncate/replace #:mode 'binary))

(test-case "origin and exact local mirror publish one confirmed snapshot"
  (with-catalog
   (lambda (root origin-path mirror-path profile state)
     (write-snapshot origin-path first)
     (write-snapshot mirror-path first)
     (define refresh-manager (manager root state profile))
     (define result
       (refresh-package-catalog-registration!
        refresh-manager "independent" 30))
     (check-eq? (odra-package-catalog-refresh-result-status result) 'current)
     (check-equal? (length (odra-package-catalog-refresh-result-endpoint-results
                            result))
                   2)
     (check-equal?
      (odra-package-catalog-confirmed-snapshot-reference-snapshot-id
       (car
        (odra-package-catalog-state-confirmed-snapshots
         (package-catalog-refresh-state refresh-manager))))
      (odra-package-catalog-snapshot-id first)))))

(test-case "built-in trust can bootstrap from the latest signed snapshot"
  (with-catalog
   (lambda (root origin-path mirror-path profile state)
     (write-snapshot origin-path second)
     (write-snapshot mirror-path second)
     (define refresh-manager (manager root state profile))
     (define result
       (refresh-package-catalog-registration!
        refresh-manager "independent" 30))
     (check-eq? (odra-package-catalog-refresh-result-status result) 'current)
     (check-equal?
      (odra-package-catalog-confirmed-snapshot-reference-sequence
       (car
        (odra-package-catalog-state-confirmed-snapshots
         (package-catalog-refresh-state refresh-manager))))
      2))
   #:configuration-origin 'built-in))

(test-case "endpoint failure retains confirmed snapshot for offline operation"
  (with-catalog
   (lambda (root origin-path mirror-path profile state)
     (write-snapshot origin-path first)
     (write-snapshot mirror-path first)
     (define refresh-manager (manager root state profile))
     (refresh-package-catalog-registration! refresh-manager "independent" 30)
     (delete-file origin-path)
     (delete-file mirror-path)
     (define result
       (refresh-package-catalog-registration!
        refresh-manager "independent" 100))
     (check-eq? (odra-package-catalog-refresh-result-status result) 'offline)
     (check-equal?
      (odra-package-catalog-confirmed-snapshot-reference-snapshot-id
       (car
        (odra-package-catalog-state-confirmed-snapshots
         (package-catalog-refresh-state refresh-manager))))
      (odra-package-catalog-snapshot-id first)))))

(test-case "expired offline grace marks stale without discarding confirmed state"
  (with-catalog
   (lambda (root origin-path mirror-path profile state)
     (write-snapshot origin-path first)
     (write-snapshot mirror-path first)
     (define refresh-manager (manager root state profile 10))
     (refresh-package-catalog-registration! refresh-manager "independent" 30)
     (delete-file origin-path)
     (delete-file mirror-path)
     (define result
       (refresh-package-catalog-registration!
        refresh-manager "independent" 211))
     (check-eq? (odra-package-catalog-refresh-result-status result) 'stale)
     (check-equal?
      (length
       (odra-package-catalog-state-confirmed-snapshots
        (package-catalog-refresh-state refresh-manager)))
      1))))

(test-case "signed mirror divergence preserves the previous confirmed snapshot"
  (with-catalog
   (lambda (root origin-path mirror-path profile state)
     (write-snapshot origin-path first)
     (write-snapshot mirror-path first)
     (define refresh-manager (manager root state profile))
     (refresh-package-catalog-registration! refresh-manager "independent" 30)
     (write-snapshot origin-path second)
     (write-snapshot mirror-path fork)
     (define result
       (refresh-package-catalog-registration!
        refresh-manager "independent" 40))
     (check-eq? (odra-package-catalog-refresh-result-status result) 'failed)
     (check-equal?
      (odra-package-catalog-confirmed-snapshot-reference-snapshot-id
       (car
        (odra-package-catalog-state-confirmed-snapshots
         (package-catalog-refresh-state refresh-manager))))
      (odra-package-catalog-snapshot-id first)))))

(test-case "concurrent refresh of one registration is excluded"
  (with-catalog
   (lambda (root origin-path mirror-path profile state)
     (write-snapshot origin-path first)
     (write-snapshot mirror-path first)
     (define entered (make-semaphore 0))
     (define release (make-semaphore 0))
     (define refresh-manager
       (make-package-catalog-refresh-manager
        root state (list profile) (list publisher-key) transport-policy
        (lambda (_) #f)
        #:offline-grace-seconds 200
        #:persistence
        (lambda (configuration-root candidate)
          (semaphore-post entered)
          (semaphore-wait release)
          (package-catalog-state-persist configuration-root candidate))))
     (define first-result #f)
     (define worker
       (thread
        (lambda ()
          (set! first-result
                (refresh-package-catalog-registration!
                 refresh-manager "independent" 30)))))
     (semaphore-wait entered)
     (define concurrent
       (refresh-package-catalog-registration!
        refresh-manager "independent" 30))
     (check-eq? (odra-package-catalog-refresh-result-status concurrent)
                'blocked)
     (check-equal? (odra-package-catalog-refresh-result-detail concurrent)
                   "Catalog refresh is already active")
     (semaphore-post release)
     (thread-wait worker)
     (check-eq? (odra-package-catalog-refresh-result-status first-result)
                'current))))

(test-case "offline confirmed state survives process restart"
  (with-catalog
   (lambda (root origin-path mirror-path profile state)
     (write-snapshot origin-path first)
     (write-snapshot mirror-path first)
     (define initial-manager (manager root state profile))
     (refresh-package-catalog-registration! initial-manager "independent" 30)
     (delete-file origin-path)
     (delete-file mirror-path)
     (define offline
       (refresh-package-catalog-registration!
        initial-manager "independent" 100))
     (check-eq? (odra-package-catalog-refresh-result-status offline) 'offline)
     (define startup (package-catalog-state-startup root "default"))
     (check-eq? (odra-package-catalog-startup-mode startup) 'confirmed)
     (define restarted-state (odra-package-catalog-startup-state startup))
     (check-eq?
      (odra-package-catalog-registration-refresh-state
       (car (odra-package-catalog-state-registrations restarted-state)))
      'offline)
     (check-equal?
      (odra-package-catalog-confirmed-snapshot-reference-snapshot-id
       (car
        (odra-package-catalog-state-confirmed-snapshots restarted-state)))
      (odra-package-catalog-snapshot-id first))
     (define restarted-manager (manager root restarted-state profile))
     (define retried
       (refresh-package-catalog-registration!
        restarted-manager "independent" 110))
     (check-eq? (odra-package-catalog-refresh-result-status retried) 'offline))))

(test-case "endpoint moves retain catalog identity and expose old cache cleanup"
  (with-catalog
   (lambda (root origin-path mirror-path profile state)
     (write-snapshot origin-path first)
     (write-snapshot mirror-path first)
     (define initial-manager (manager root state profile))
     (refresh-package-catalog-registration! initial-manager "independent" 30)
     (define first-state (package-catalog-refresh-state initial-manager))
     (define first-reference
       (car (odra-package-catalog-state-confirmed-snapshots first-state)))
     (define moved-origin-path (build-path root "moved-origin.rktd"))
     (define moved-mirror-path (build-path root "moved-mirror.rktd"))
     (write-snapshot moved-origin-path second)
     (write-snapshot moved-mirror-path second)
     (define moved-origin
       (odra-package-catalog-endpoint
        "origin" catalog-id
        (string-append "file://" (path->string moved-origin-path))
        'file 'origin 0 #t))
     (define moved-mirror
       (odra-package-catalog-endpoint
        "mirror" catalog-id
        (string-append "file://" (path->string moved-mirror-path))
        'file 'mirror 1 #t))
     (define-values (moved-profile rejection)
       (confirm-package-catalog-profile
        (odra-package-catalog-profile-proposal
         1 catalog-id "Independent Catalog" (list trust-root) '()
         (list publisher) (list catalog-policy)
         (list moved-origin moved-mirror))))
     (check-false rejection)
     (define current-registration
       (car (odra-package-catalog-state-registrations first-state)))
     (define moved-registration
       (struct-copy
        odra-package-catalog-registration current-registration
        [generation
         (add1
          (odra-package-catalog-registration-generation current-registration))]))
     (define moved-generation
       (add1 (odra-package-catalog-state-generation first-state)))
     (define moved-state
       (package-catalog-state-with-checksum
        (struct-copy
         odra-package-catalog-state first-state
         [generation moved-generation]
         [registrations (list moved-registration)]
         [endpoints
          (list
           (odra-package-catalog-state-endpoint
            1 moved-generation moved-mirror #f)
           (odra-package-catalog-state-endpoint
            1 moved-generation moved-origin #f))]
         [checksum (make-string 64 #\0)])))
     (persist! root moved-state)
     (define moved-manager (manager root moved-state moved-profile))
     (define refreshed
       (refresh-package-catalog-registration!
        moved-manager "independent" 40))
     (check-eq? (odra-package-catalog-refresh-result-status refreshed) 'current)
     (define final-state (package-catalog-refresh-state moved-manager))
     (define final-reference
       (car (odra-package-catalog-state-confirmed-snapshots final-state)))
     (check-equal?
      (odra-package-catalog-confirmed-snapshot-reference-snapshot-id
       final-reference)
      (odra-package-catalog-snapshot-id second))
     (check-equal?
      (package-catalog-state-cleanup-plan
       final-state
       (list
        (odra-package-catalog-confirmed-snapshot-reference-cache-reference
         first-reference)
        (odra-package-catalog-confirmed-snapshot-reference-cache-reference
         final-reference)))
      (list
       (odra-package-catalog-confirmed-snapshot-reference-cache-reference
        first-reference))))))

(test-case "private HTTPS refresh resolves credentials without retaining them"
  (define root (make-temporary-file "odra-private-refresh-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind
    void
    (lambda ()
      (define endpoint
        (odra-package-catalog-endpoint
         "private" catalog-id "https://catalog.example/private/snapshot.rktd"
         'https 'origin 0 #t))
      (define registration
        (odra-package-catalog-registration
         1 "private" 1 catalog-id 'user root-id '("private")
         10 'enforce #t 'never))
      (define endpoint-state
        (odra-package-catalog-state-endpoint
         1 1 endpoint "credential.catalog.private"))
      (define-values (profile rejection)
        (confirm-package-catalog-profile
         (odra-package-catalog-profile-proposal
          1 catalog-id "Private Catalog" (list trust-root) '()
          (list publisher) (list catalog-policy) (list endpoint))))
      (check-false rejection)
      (define empty (package-catalog-empty-state "default"))
      (persist! root empty)
      (define-values (registered register-rejection)
        (package-catalog-state-register
         empty registration (list endpoint-state) 'user-action 1))
      (check-false register-rejection)
      (persist! root registered)
      (define credential-available? #f)
      (define refresh-manager
        (make-package-catalog-refresh-manager
         root registered (list profile) (list publisher-key) transport-policy
         (lambda (reference)
           (check-equal? reference "credential.catalog.private")
           (and credential-available?
                (hash "authorization" "Bearer private-secret")))))
      (define missing-credential
        (refresh-package-catalog-registration!
         refresh-manager "private" 20))
      (check-eq? (odra-package-catalog-refresh-result-status missing-credential)
                 'failed)
      (check-regexp-match
       #px"sign-in is missing or was rejected"
       (odra-package-catalog-refresh-result-detail missing-credential))
      (check-regexp-match
       #px"installed packages are unchanged"
       (odra-package-catalog-refresh-result-detail missing-credential))
      (set! credential-available? #t)
      (define result
        (parameterize
            ([current-catalog-transport-open
              (lambda (_uri headers _proxy)
                (check-equal? (hash-ref headers "authorization")
                              "Bearer private-secret")
                (transport-response
                 200 (hash)
                 (open-input-bytes
                  (package-catalog-snapshot->module-bytes first))))])
          (refresh-package-catalog-registration!
           refresh-manager "private" 30)))
      (check-eq? (odra-package-catalog-refresh-result-status result) 'current)
      (check-false (regexp-match? #px"private-secret" (format "~s" result)))
      (set! credential-available? #f)
      (define unavailable
        (refresh-package-catalog-registration!
         refresh-manager "private" 100))
      (check-eq? (odra-package-catalog-refresh-result-status unavailable)
                 'offline)
      (check-equal?
       (odra-package-catalog-confirmed-snapshot-reference-snapshot-id
        (car
         (odra-package-catalog-state-confirmed-snapshots
          (package-catalog-refresh-state refresh-manager))))
       (odra-package-catalog-snapshot-id first)))
    (lambda () (delete-directory/files root))))
