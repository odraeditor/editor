#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/list
         racket/path
         rackunit
         "../../src/package_catalog/contracts.rkt"
         "../../src/package_catalog/integrity.rkt"
         "../../src/package_catalog/snapshot-records.rkt"
         "../../src/package_catalog/snapshot-reconciliation.rkt"
         "../../src/package_catalog/snapshot-verification.rkt"
         (submod "../../src/package_catalog/integrity.rkt" test-support)
         (submod "../../src/storage/durable-file.rkt" test-support))

(define root-public-key
  "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
(define publisher-public-key
  "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c")
(define publisher-secret-key
  (string-append
   "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
   publisher-public-key))
(define root-key-id (package-catalog-public-key-id root-public-key))
(define publisher-key-id (package-catalog-public-key-id publisher-public-key))
(define root-key
  (odra-package-catalog-root-key
   root-key-id 1 'ed25519 root-public-key 1 #f))
(define catalog-id (package-catalog-identity root-key))
(define publisher-key
  (odra-package-catalog-publisher-key
   publisher-key-id 'ed25519 publisher-public-key))
(define publisher
  (odra-package-catalog-publisher-authorization
   "snapshot-publisher" (list publisher-key-id) 1 1 #f))
(define policy
  (odra-package-catalog-policy
   "policy-v1" 1 1 "eligible" "authority" "assessment" "decision"
   "retention"))
(define origin
  (odra-package-catalog-endpoint
   "origin" catalog-id "https://catalog.example/snapshots" 'https 'origin 0 #t))
(define-values
  (profile profile-rejection)
  (confirm-package-catalog-profile
   (odra-package-catalog-profile-proposal
    1 catalog-id "Catalog" (list root-key) '() (list publisher) (list policy)
    (list origin))))

(define (signed-snapshot sequence previous issued-at expires-at)
  (define draft
    (odra-package-catalog-snapshot
     1 (make-string 64 #\0) catalog-id sequence previous "policy-v1"
     issued-at expires-at (make-string 64 #\a) (make-string 64 #\b) 1024
     "snapshot-publisher" '()))
  (define identified
    (struct-copy odra-package-catalog-snapshot draft
                 [id (package-catalog-snapshot-content-digest draft)]))
  (define message
    (package-catalog-signature-message
     package-catalog-publisher-signature-domain
     (package-catalog-snapshot-signing-payload identified)))
  (struct-copy
   odra-package-catalog-snapshot identified
   [signatures
    (list
     (odra-package-catalog-signature
      'ed25519 publisher-key-id package-catalog-publisher-signature-domain
      (sign-for-test message publisher-secret-key)))]))

(define first (signed-snapshot 1 #f 10 100))
(define second
  (signed-snapshot 2 (odra-package-catalog-snapshot-id first) 20 120))

(define (available snapshot)
  (odra-package-catalog-snapshot-observation origin 'available snapshot 1024 ""))
(define unavailable
  (odra-package-catalog-snapshot-observation
   origin 'unavailable #f 0 "endpoint unavailable"))

(define confirmed
  (reconcile-package-catalog-snapshots
   profile (list publisher-key) first (list (available second)) 30))

(define (with-root action)
  (define root-path
    (make-temporary-file "odra-package-catalog-snapshot-failure-~a" 'directory))
  (file-or-directory-permissions root-path #o700)
  (dynamic-wind void (lambda () (action root-path))
                (lambda () (delete-directory/files root-path))))

(define (stage-files root-path)
  (filter
   (lambda (path)
     (regexp-match? #px"^[.]odra-stage-"
                    (path->string (file-name-from-path path))))
   (find-files file-exists? root-path)))

(test-case "expired and rollback observations preserve the prior snapshot"
  (for ([candidate
         (list (signed-snapshot 2 (odra-package-catalog-snapshot-id first) 20 25)
               first)])
    (define result
      (reconcile-package-catalog-snapshots
       profile (list publisher-key) first (list (available candidate)) 30))
    (check-eq? (odra-package-catalog-snapshot-reconciliation-mode result)
               'rejected)
    (check-equal?
     (odra-package-catalog-snapshot-reconciliation-snapshot result) first)))

(test-case "unconfigured endpoint impersonation rejects"
  (define impostor
    (odra-package-catalog-endpoint
     "origin" catalog-id "https://impostor.example/snapshots"
     'https 'origin 0 #t))
  (define result
    (reconcile-package-catalog-snapshots
     profile (list publisher-key) first
     (list
      (odra-package-catalog-snapshot-observation
       impostor 'available second 1024 ""))
     30))
  (check-eq? (odra-package-catalog-snapshot-reconciliation-mode result)
             'rejected)
  (check-eq?
   (odra-package-catalog-snapshot-failure-code
    (car (odra-package-catalog-snapshot-reconciliation-failures result)))
   'catalog-identity))

(test-case "observation bounds reject before endpoint work"
  (check-exn
   exn:fail?
   (lambda ()
     (reconcile-package-catalog-snapshots
      profile (list publisher-key) first
      (make-list (add1 maximum-package-catalog-snapshot-observations)
                 unavailable)
      30))))

(test-case "unconfirmed results cannot enter the immutable cache"
  (define offline
    (reconcile-package-catalog-snapshots
     profile (list publisher-key) first (list unavailable) 30))
  (with-root
   (lambda (root-path)
     (check-exn
      exn:fail?
      (lambda ()
        (package-catalog-snapshot-cache-persist root-path offline))))))

(test-case "cache write sync and rename faults leave no target or staging file"
  (for
      ([fault
        (list
         (cons
          'write-failed
          (lambda (action)
            (parameterize
                ([current-durable-file-write
                  (lambda (bytes output)
                    (write-bytes (subbytes bytes 0 16) output)
                    (error 'write "simulated partial write"))])
              (action))))
         (cons
          'file-sync-failed
          (lambda (action)
            (parameterize ([current-durable-file-sync (lambda (_output) 5)])
              (action))))
         (cons
          'rename-failed
          (lambda (action)
            (parameterize
                ([current-durable-file-rename
                  (lambda (_source _target) 5)])
              (action)))))])
    (with-root
     (lambda (root-path)
       (define result
         ((cdr fault)
          (lambda ()
            (package-catalog-snapshot-cache-persist root-path confirmed))))
       (check-true (odra-package-catalog-snapshot-cache-failure? result))
       (check-eq? (odra-package-catalog-snapshot-cache-failure-code result)
                  (car fault))
       (check-false
        (file-exists? (package-catalog-snapshot-cache-path root-path second)))
       (check-equal? (stage-files root-path) '())))))

(test-case "corrupt or unsafe existing cache content is never overwritten"
  (for ([unsafe? '(#f #t)])
    (with-root
     (lambda (root-path)
       (define target (package-catalog-snapshot-cache-path root-path second))
       (make-directory* (path-only target))
       (file-or-directory-permissions (build-path root-path "package-catalog") #o700)
       (file-or-directory-permissions
        (build-path root-path "package-catalog" "snapshots") #o700)
       (file-or-directory-permissions (path-only target) #o700)
       (call-with-output-file target
         (lambda (output) (write-bytes #"corrupt" output))
         #:exists 'truncate/replace #:mode 'binary #:permissions #o600)
       (file-or-directory-permissions target (if unsafe? #o644 #o600))
       (define before (file->bytes target))
       (define result
         (package-catalog-snapshot-cache-persist root-path confirmed))
       (check-true (odra-package-catalog-snapshot-cache-failure? result))
       (check-eq? (odra-package-catalog-snapshot-cache-failure-code result)
                  (if unsafe? 'unsafe-permissions 'cache-conflict))
       (check-equal? (file->bytes target) before)))))
