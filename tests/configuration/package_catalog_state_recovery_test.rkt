#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/path
         rackunit
         "../../src/package_catalog/contracts.rkt"
         "../../src/package_catalog/state-persistence.rkt"
         "../../src/package_catalog/state-records.rkt"
         "../../src/storage/record-codec.rkt"
         (submod "../../src/storage/durable-file.rkt" test-support))

(define catalog-id (make-string 64 #\a))
(define root-key-id (make-string 64 #\b))
(define snapshot-id (make-string 64 #\c))
(define snapshot-digest (make-string 64 #\d))
(define endpoint
  (odra-package-catalog-endpoint
   "origin" catalog-id "https://catalog.example/odra/index.rktd"
   'https 'origin 10 #t))
(define endpoint-state
  (odra-package-catalog-state-endpoint 1 1 endpoint #f))
(define registration
  (odra-package-catalog-registration
   1 "official" 1 catalog-id 'built-in root-key-id '("origin")
   10 'enforce #t 'never))
(define confirmed
  (odra-package-catalog-confirmed-snapshot-reference
   1 catalog-id snapshot-id 1 snapshot-digest
   "snapshots/official/1.rktd" 100))

(define (with-root action)
  (define root (make-temporary-file "odra-package-catalog-recovery-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind void (lambda () (action root))
                (lambda () (delete-directory/files root))))

(define (persist! root state)
  (define result (package-catalog-state-persist root state))
  (check-true (odra-record-publication? result) (format "~s" result))
  result)

(define (registered-state)
  (define-values (state rejection)
    (package-catalog-state-register
     (package-catalog-empty-state "default") registration
     (list endpoint-state) 'built-in-bootstrap 1))
  (check-false rejection)
  state)

(define (stage-files root)
  (define directory (path-only (package-catalog-state-path root)))
  (if (directory-exists? directory)
      (filter
       (lambda (path)
         (regexp-match? #px"^[.]odra-stage-"
                        (path->string (file-name-from-path path))))
       (directory-list directory #:build? #t))
      '()))

(define (write-private-file path bytes)
  (make-directory* (path-only path))
  (file-or-directory-permissions (path-only path) #o700)
  (call-with-output-file path
    (lambda (output) (write-bytes bytes output))
    #:exists 'truncate/replace #:mode 'binary #:permissions #o600)
  (file-or-directory-permissions path #o600))

(test-case "allocation and prepublication I/O faults retain no staging state"
  (for
      ([fault
        (in-list
         (list
          (cons
           'create-failed
           (lambda (root state)
             (parameterize
                 ([current-durable-file-open
                   (lambda (_path)
                     (raise
                      (exn:fail:out-of-memory
                       "simulated allocation failure"
                       (current-continuation-marks))))])
               (package-catalog-state-persist root state))))
          (cons
           'write-failed
           (lambda (root state)
             (parameterize
                 ([current-durable-file-write
                   (lambda (bytes output)
                     (write-bytes
                      (subbytes bytes 0 (quotient (bytes-length bytes) 2))
                      output)
                     (error 'write "simulated partial write"))])
               (package-catalog-state-persist root state))))
          (cons
           'file-sync-failed
           (lambda (root state)
             (parameterize ([current-durable-file-sync (lambda (_output) 5)])
               (package-catalog-state-persist root state))))
          (cons
           'rename-failed
           (lambda (root state)
             (parameterize
                 ([current-durable-file-rename
                   (lambda (_source _target) 5)])
               (package-catalog-state-persist root state))))))])
    (with-root
     (lambda (root)
       (define result ((cdr fault) root (package-catalog-empty-state "default")))
       (check-true (odra-record-publication-failure? result))
       (check-eq? (odra-record-publication-failure-code result) (car fault))
       (check-false (file-exists? (package-catalog-state-path root)))
       (check-equal? (stage-files root) '())))))

(test-case "directory synchronization failure reports visible uncertain state"
  (with-root
   (lambda (root)
     (define state (package-catalog-empty-state "default"))
     (define result
       (parameterize ([current-durable-directory-sync (lambda (_directory) 5)])
         (package-catalog-state-persist root state)))
     (check-true (odra-record-publication-failure? result))
     (check-eq? (odra-record-publication-failure-code result)
                'directory-sync-failed)
     (check-eq? (odra-record-publication-failure-publication result)
                'published-durability-uncertain)
     (check-equal?
      (package-catalog-state-module-load (package-catalog-state-path root))
      state))))

(test-case "truncated and tampered state is quarantined on restart"
  (for
      ([damage
        (in-list
         (list
          (lambda (bytes) (subbytes bytes 0 (quotient (bytes-length bytes) 2)))
          (lambda (bytes)
            (regexp-replace #px#"[0-9a-f]{64}" bytes
                            (string->bytes/utf-8 root-key-id)))))])
    (with-root
     (lambda (root)
       (define state (registered-state))
       (define path (package-catalog-state-path root))
       (write-private-file path (damage (package-catalog-state->module-bytes state)))
       (define startup (package-catalog-state-startup root "default"))
       (check-eq? (odra-package-catalog-startup-mode startup) 'quarantined)
       (check-true
        (odra-record-diagnostic?
         (odra-package-catalog-startup-diagnostic startup)))
       (check-false (file-exists? path))
       (check-equal? (length
                      (odra-package-catalog-startup-quarantine-paths startup))
                     1)
       (check-true
        (file-exists?
         (car (odra-package-catalog-startup-quarantine-paths startup))))))))

(test-case "orphan staging files are quarantined without replacing current state"
  (with-root
   (lambda (root)
     (define state (package-catalog-empty-state "default"))
     (persist! root state)
     (define directory (path-only (package-catalog-state-path root)))
     (define orphan (build-path directory ".odra-stage-fixture.tmp"))
     (write-private-file orphan #"partial")
     (define startup (package-catalog-state-startup root "default"))
     (check-eq? (odra-package-catalog-startup-mode startup) 'confirmed)
     (check-equal? (odra-package-catalog-startup-state startup) state)
     (check-false (file-exists? orphan))
     (check-equal?
      (length (odra-package-catalog-startup-quarantine-paths startup)) 1))))

(test-case "root mismatch blocks startup without rewriting valid foreign state"
  (with-root
   (lambda (root)
     (define state (package-catalog-empty-state "foreign"))
     (persist! root state)
     (define path (package-catalog-state-path root))
     (define before (file->bytes path))
     (define startup (package-catalog-state-startup root "default"))
     (check-eq? (odra-package-catalog-startup-mode startup) 'blocked)
     (check-eq? (odra-package-catalog-startup-diagnostic startup)
                'root-identity-mismatch)
     (check-equal? (file->bytes path) before)
     (check-equal? (odra-package-catalog-startup-quarantine-paths startup)
                   '()))))

(test-case "disabled restart and registration removal leave package state untouched"
  (with-root
   (lambda (root)
     (define package-state-path
       (build-path root "language-bundles" "installed-state.rktd"))
     (write-private-file package-state-path #"independent installed package state")
     (persist! root (package-catalog-empty-state "default"))
     (define registered (registered-state))
     (persist! root registered)
     (define-values (with-confirmed confirm-rejection)
       (package-catalog-state-confirm-snapshot registered confirmed 2))
     (check-false confirm-rejection)
     (persist! root with-confirmed)
     (define-values (disabled disable-rejection)
       (package-catalog-state-set-enabled with-confirmed "official" #f 3))
     (check-false disable-rejection)
     (persist! root disabled)
     (define disabled-startup
       (package-catalog-state-startup root "default"))
     (check-false
      (odra-package-catalog-registration-enabled?
       (car
        (odra-package-catalog-state-registrations
         (odra-package-catalog-startup-state disabled-startup)))))
     (define-values (removed remove-rejection)
       (package-catalog-state-remove disabled "official" 4))
     (check-false remove-rejection)
     (persist! root removed)
     (define restarted
       (odra-package-catalog-startup-state
        (package-catalog-state-startup root "default")))
     (check-equal? (odra-package-catalog-state-registrations restarted) '())
     (check-equal? (odra-package-catalog-state-confirmed-snapshots restarted)
                   (list confirmed))
     (check-equal? (file->bytes package-state-path)
                   #"independent installed package state"))))
