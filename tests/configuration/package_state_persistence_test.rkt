#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/path
         rackunit
         (prefix-in bundle: "../../src/language_bundle/state-persistence.rkt")
         (prefix-in bundle: "../../src/language_bundle/state-records.rkt")
         "../../src/package/state-persistence.rkt"
         "../../src/package/state-records.rkt"
         "../../src/storage/record-codec.rkt"
         (submod "../../src/storage/durable-file.rkt" test-support))

(define digest-a (make-string 64 #\a))
(define digest-b (make-string 64 #\b))
(define digest-c (make-string 64 #\c))
(define digest-d (make-string 64 #\d))
(define provenance
  (odra-package-provenance
   'catalog digest-a digest-c digest-d
   "example.publisher" (make-string 40 #\e)))
(define active-package
  (odra-installed-package
   "org.example.extension" 'extension "1.0.0" 1 digest-a #f
   (list digest-b) '() provenance 'linux 'x86-64 '(racket-extension)
   '(racket-extension) "user grant" 'active-confirmed 3 #f #f #t #f ""))

(define (make-lock generation state-generation)
  (package-activation-lock-with-checksum
   (odra-package-activation-lock
    generation state-generation
    (hash "org.example.extension" "1.0.0")
    (list digest-a digest-b) digest-c digest-d
    (hash "org.example.extension" 1)
    (hash "org.example.extension" 3)
    1 (make-string 64 #\0))))

(define (make-state #:generation [generation 1]
                    #:lock [lock (make-lock 1 generation)]
                    #:previous-lock [previous-lock #f]
                    #:operations [operations '()])
  (package-state-with-checksum
   (odra-package-state
    1 "default" generation
    (if lock (odra-package-activation-lock-generation lock) 0)
    (list active-package) lock previous-lock operations '()
    (odra-package-accounting 1 1 512 4096 0) #f
    (make-string 64 #\0))))

(define (legacy-state)
  (define installed
    (bundle:odra-installed-bundle
     "org.example.language" "1.0.0" digest-a (list digest-b) '()
     "catalog.example" "example.publisher" 'linux 'x86-64
     '("native-grammar") "legacy grant" 'active-confirmed 2 #f #f))
  (define lock
    (bundle:activation-lock-with-checksum
     (bundle:odra-activation-lock
      1 1 (hash "org.example.language" "1.0.0")
      (list digest-a digest-b) digest-c digest-d
      (hash "org.example.language" 2) (make-string 64 #\0))))
  (bundle:language-bundle-state-with-checksum
   (bundle:odra-language-bundle-state
    2 "default" 1 1 (list installed) lock #f '() '()
    (bundle:odra-bundle-accounting 1 1 512 4096 0)
    (make-string 64 #\0))))

(define (with-root action)
  (define root (make-temporary-file "odra-package-state-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind void (lambda () (action root))
                (lambda () (delete-directory/files root))))

(define (persist! root state)
  (define result (package-state-persist root state))
  (check-true (odra-record-publication? result) (format "~s" result))
  result)

(define (stage-files root)
  (define directory (path-only (package-state-path root)))
  (if (directory-exists? directory)
      (filter
       (lambda (path)
         (regexp-match? #px"^[.]odra-stage-"
                        (path->string (file-name-from-path path))))
       (directory-list directory #:build? #t))
      '()))

(test-case "generic package state has deterministic checksummed round trips"
  (define state (make-state))
  (check-equal? (package-state-checksum state)
                (odra-package-state-checksum state))
  (check-equal? (package-state->module-bytes state)
                (package-state->module-bytes state))
  (with-root
   (lambda (root)
     (persist! root state)
     (check-equal? (package-state-module-load (package-state-path root)) state)
     (check-eq? (odra-package-startup-mode (package-state-startup root))
                'confirmed))))

(test-case "partial writes fail cleanly without publishing or retaining staging"
  (with-root
   (lambda (root)
     (define result
       (parameterize
           ([current-durable-file-write
             (lambda (bytes output)
               (write-bytes (subbytes bytes 0 (quotient (bytes-length bytes) 2))
                            output)
               (error 'write "simulated interrupted write"))])
         (package-state-persist root (make-state))))
     (check-true (odra-record-publication-failure? result))
     (check-eq? (odra-record-publication-failure-code result) 'write-failed)
     (check-false (file-exists? (package-state-path root)))
     (check-equal? (stage-files root) '()))))

(test-case "truncated state is quarantined and never becomes current"
  (with-root
   (lambda (root)
     (define path (package-state-path root))
     (make-directory* (path-only path))
     (file-or-directory-permissions (path-only path) #o700)
     (define bytes (package-state->module-bytes (make-state)))
     (call-with-output-file path
       (lambda (output)
         (write-bytes (subbytes bytes 0 (quotient (bytes-length bytes) 2)) output))
       #:exists 'truncate/replace #:mode 'binary #:permissions #o600)
     (define startup (package-state-startup root))
     (check-eq? (odra-package-startup-mode startup) 'quarantined)
     (check-true (odra-record-diagnostic?
                  (odra-package-startup-diagnostic startup)))
     (check-false (file-exists? path))
     (check-true (file-exists?
                  (odra-package-startup-quarantine-path startup))))))

(test-case "unfinished idempotent work resumes without advancing state"
  (with-root
   (lambda (root)
     (define operation
       (odra-package-operation
        "verify-extension" 'verify 'verify 1 1
        (list (odra-package-release "org.example.extension" "1.0.0"))
        (list digest-b) '() 'pending #f ""))
     (define state (make-state #:operations (list operation)))
     (persist! root state)
     (define startup (package-state-startup root))
     (check-eq? (odra-package-startup-mode startup) 'resume-operation)
     (check-equal? (odra-package-startup-state startup) state))))

(test-case "ambiguous publication rebinds the previous confirmed lock"
  (with-root
   (lambda (root)
     (define previous (make-lock 1 1))
     (persist! root (make-state #:lock previous))
     (define current (make-lock 2 2))
     (define operation
       (odra-package-operation
        "enable-extension" 'enable 'publish 2 2
        (list (odra-package-release "org.example.extension" "1.0.0"))
        (list digest-a digest-b) '() 'pending #f ""))
     (define candidate
       (make-state #:generation 2 #:lock current #:previous-lock previous
                   #:operations (list operation)))
     (persist! root candidate)
     (define startup (package-state-startup root))
     (define recovered (odra-package-startup-state startup))
     (check-eq? (odra-package-startup-mode startup) 'rollback-previous)
     (check-equal? (odra-package-state-generation recovered) 3)
     (check-false (odra-package-state-previous-lock recovered))
     (check-equal? (odra-package-state-operations recovered) '())
     (check-equal? (package-state-module-load (package-state-path root))
                   recovered))))

(test-case "language-bundle migration is atomic idempotent and retains its source"
  (with-root
   (lambda (root)
     (define publication (bundle:language-bundle-state-persist root (legacy-state)))
     (check-true (bundle:odra-record-publication? publication))
     (define legacy-path (bundle:language-bundle-state-path root))
     (define legacy-before (file->bytes legacy-path))
     (define first (package-state-startup root))
     (check-eq? (odra-package-startup-mode first) 'migrated)
     (check-true (file-exists? (package-state-path root)))
     (check-equal? (file->bytes legacy-path) legacy-before)
     (check-eq? (odra-package-state-migration-source
                 (odra-package-startup-state first))
                'language-bundle-v2)
     (define second (package-state-startup root))
     (check-eq? (odra-package-startup-mode second) 'confirmed)
     (check-equal? (odra-package-startup-state second)
                   (odra-package-startup-state first)))))

(test-case "missing migration content preserves legacy state and publishes nothing"
  (with-root
   (lambda (root)
     (define publication (bundle:language-bundle-state-persist root (legacy-state)))
     (check-true (bundle:odra-record-publication? publication))
     (define startup
       (package-state-startup root #:content-exists? (lambda (_) #f)))
     (check-eq? (odra-package-startup-mode startup) 'recovery-only)
     (check-eq? (odra-package-startup-diagnostic startup)
                'missing-migration-content)
     (check-false (file-exists? (package-state-path root)))
     (check-true (file-exists? (bundle:language-bundle-state-path root))))))
