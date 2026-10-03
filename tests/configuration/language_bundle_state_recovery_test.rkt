#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/list
         racket/path
         rackunit
         "../../src/language_bundle/state-persistence.rkt"
         "../../src/language_bundle/state-records.rkt"
         (submod "../../src/language_bundle/state-records.rkt" test-support)
         (submod "../../src/storage/durable-file.rkt" test-support))

(define (digest character) (make-string 64 character))
(define digest-a (digest #\a))
(define digest-b (digest #\b))
(define digest-c (digest #\c))
(define digest-d (digest #\d))
(define digest-e (digest #\e))
(define digest-f (digest #\f))
(define digest-1 (digest #\1))
(define digest-2 (digest #\2))
(define digest-3 (digest #\3))
(define digest-4 (digest #\4))
(define digest-5 (digest #\5))
(define digest-6 (digest #\6))

(define active-bundle
  (odra-installed-bundle
   "org.example.active" "1.0.0" digest-a (list digest-b) '()
   "catalog.example" "org.example" 'linux 'x86-64 '()
   "factory grant" 'active-confirmed 7 #f #f))

(define (make-lock generation state-generation
                   #:bundles [bundles (hash "org.example.active" "1.0.0")]
                   #:content [content (list digest-a digest-b)])
  (activation-lock-with-checksum
   (odra-activation-lock
    generation state-generation bundles content digest-c digest-d
    (if (zero? (hash-count bundles))
        (hash)
        (hash "org.example.active" 7))
    (make-string 64 #\0))))

(define (make-state #:generation [generation 1]
                    #:bundles [bundles (list active-bundle)]
                    #:lock [lock (make-lock 1 generation)]
                    #:previous-lock [previous-lock #f]
                    #:operations [operations '()]
                    #:quarantine [quarantine '()])
  (language-bundle-state-with-checksum
   (odra-language-bundle-state
    2 "default" generation
    (if lock (odra-activation-lock-generation lock) 0)
    bundles lock previous-lock operations quarantine
    (odra-bundle-accounting
     (length bundles)
     (for/sum ([bundle (in-list bundles)])
       (length (odra-installed-bundle-artifacts bundle)))
     0 0 (length quarantine))
    (make-string 64 #\0))))

(define (with-root action)
  (define root (make-temporary-file "odra-bundle-recovery-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind void (lambda () (action root))
                (lambda () (delete-directory/files root))))

(define (write-private-file path bytes)
  (make-directory* (path-only path))
  (file-or-directory-permissions (path-only path) #o700)
  (call-with-output-file path
    (lambda (output) (write-bytes bytes output))
    #:exists 'truncate/replace #:mode 'binary #:permissions #o600)
  (file-or-directory-permissions path #o600))

(define (stage-files root)
  (define directory (build-path root "language-bundles"))
  (if (directory-exists? directory)
      (filter (lambda (path)
                (regexp-match? #px"[.]odra-stage-" (path->string path)))
              (directory-list directory #:build? #t))
      '()))

(test-case "allocation and prepublication I/O faults retain no staging files"
  (for ([fault
         (in-list
          (list
           (cons 'create-failed
                 (lambda (root state)
                   (parameterize
                       ([current-durable-file-open
                         (lambda (_)
                           (raise
                            (exn:fail:out-of-memory
                             "simulated allocation failure"
                             (current-continuation-marks))))])
                     (language-bundle-state-persist root state))))
           (cons 'write-failed
                 (lambda (root state)
                   (parameterize
                       ([current-durable-file-write
                         (lambda (bytes output)
                           (write-bytes
                            (subbytes bytes 0 (quotient (bytes-length bytes) 2))
                            output)
                           (error 'write "simulated partial write"))])
                     (language-bundle-state-persist root state))))
           (cons 'file-sync-failed
                 (lambda (root state)
                   (parameterize ([current-durable-file-sync (lambda (_) 5)])
                     (language-bundle-state-persist root state))))
           (cons 'rename-failed
                 (lambda (root state)
                   (parameterize
                       ([current-durable-file-rename (lambda (_source _target) 5)])
                     (language-bundle-state-persist root state))))))])
    (with-root
     (lambda (root)
       (define result ((cdr fault) root (make-state)))
       (check-true (odra-record-publication-failure? result))
       (check-eq? (odra-record-publication-failure-code result) (car fault))
       (check-false (file-exists? (language-bundle-state-path root)))
       (check-equal? (stage-files root) '())))))

(test-case "directory synchronization failure reports a visible uncertain generation"
  (with-root
   (lambda (root)
     (define state (make-state))
     (define result
       (parameterize ([current-durable-directory-sync (lambda (_) 5)])
         (language-bundle-state-persist root state)))
     (check-true (odra-record-publication-failure? result))
     (check-eq? (odra-record-publication-failure-code result)
                'directory-sync-failed)
     (check-eq? (odra-record-publication-failure-publication result)
                'published-durability-uncertain)
     (check-equal? (language-bundle-state-module-load
                    (language-bundle-state-path root))
                   state))))

(test-case "truncated and tampered records are retained outside authoritative state"
  (for ([damage
         (in-list
          (list
           (lambda (bytes) (subbytes bytes 0 (quotient (bytes-length bytes) 2)))
           (lambda (bytes)
             (regexp-replace #px#"[0-9a-f]{64}" bytes
                             (string->bytes/utf-8 digest-d)))))])
    (with-root
     (lambda (root)
       (define state (make-state))
       (check-true (odra-record-publication?
                    (language-bundle-state-persist root state)))
       (define path (language-bundle-state-path root))
       (write-private-file path (damage (file->bytes path)))
       (define startup (language-bundle-state-startup root))
       (check-eq? (odra-language-bundle-startup-mode startup) 'factory-only)
       (check-false (file-exists? path))
       (check-true (file-exists?
                    (odra-language-bundle-startup-quarantine-path startup)))))))

(test-case "stale and skipped generations preserve the authoritative bytes"
  (with-root
   (lambda (root)
     (check-true (odra-record-publication?
                  (language-bundle-state-persist root (make-state))))
     (define path (language-bundle-state-path root))
     (define authoritative (file->bytes path))
     (for ([generation '(1 3)])
       (define result
         (language-bundle-state-persist
          root (make-state #:generation generation
                           #:lock (make-lock 1 generation))))
       (check-true (odra-record-publication-failure? result))
       (check-eq? (odra-record-publication-failure-code result)
                  'invalid-generation)
       (check-equal? (file->bytes path) authoritative)
       (check-equal? (stage-files root) '())))))

(test-case "version one state migrates through one durable replacement"
  (with-root
   (lambda (root)
     (define lock (make-lock 1 1))
     (define path (language-bundle-state-path root))
     (write-private-file
      path (legacy-state->module-bytes "default" 1 (list active-bundle) lock))
     (define startup (language-bundle-state-startup root))
     (define migrated (odra-language-bundle-startup-state startup))
     (check-eq? (odra-language-bundle-startup-mode startup) 'confirmed)
     (check-equal? (language-bundle-state-module-format path) 2)
     (check-equal? (odra-language-bundle-state-generation migrated) 2)
     (check-equal? (odra-activation-lock-state-generation
                    (odra-language-bundle-state-lock migrated))
                   2))))

(test-case "failed migration preserves the readable prior generation exactly"
  (with-root
   (lambda (root)
     (define lock (make-lock 1 1))
     (define path (language-bundle-state-path root))
     (write-private-file
      path (legacy-state->module-bytes "default" 1 (list active-bundle) lock))
     (define prior (file->bytes path))
     (define startup
       (parameterize ([current-durable-file-rename (lambda (_source _target) 5)])
         (language-bundle-state-startup root)))
     (check-eq? (odra-language-bundle-startup-mode startup) 'factory-only)
     (check-true (odra-record-publication-failure?
                  (odra-language-bundle-startup-diagnostic startup)))
     (check-equal? (file->bytes path) prior)
     (check-equal? (language-bundle-state-module-format path) 1)
     (check-equal? (stage-files root) '()))))

(test-case "safe mode does not trigger a pending state migration"
  (with-root
   (lambda (root)
     (define lock (make-lock 1 1))
     (define path (language-bundle-state-path root))
     (write-private-file
      path (legacy-state->module-bytes "default" 1 (list active-bundle) lock))
     (define prior (file->bytes path))
     (define startup (language-bundle-state-startup root #:safe-mode? #t))
     (check-eq? (odra-language-bundle-startup-mode startup) 'factory-only)
     (check-equal? (file->bytes path) prior)
     (check-equal? (language-bundle-state-module-format path) 1))))

(test-case "garbage collection excludes every durable and transactional reference"
  (define removed
    (odra-installed-bundle
     "org.example.old" "0.9.0" digest-e (list digest-f) '()
     "catalog.example" "org.example" 'linux 'x86-64 '()
     "user grant" 'removed 0 #f #f))
  (define pinned
    (odra-installed-bundle
     "org.example.pinned" "0.8.0" digest-1 (list digest-2) '()
     "catalog.example" "org.example" 'linux 'x86-64 '()
     "user grant" 'removed 0 #f #t))
  (define operation
    (odra-bundle-operation
     "update-active" 'update 'acquire 1 1 (list digest-3)
     '() 'pending #f ""))
  (define previous
    (make-lock 1 1 #:bundles (hash) #:content (list digest-4)))
  (define state
    (make-state
     #:bundles (list active-bundle removed pinned)
     #:previous-lock previous
     #:operations (list operation)
     #:quarantine (list digest-5)))
  (check-equal?
   (language-bundle-state-garbage-collection-plan
    state
    (list digest-a digest-b digest-e digest-f digest-1 digest-2
          digest-3 digest-4 digest-5 digest-6))
   (sort (list digest-6 digest-e digest-f) string<?)))
