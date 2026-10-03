#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/path
         rackunit
         "../../src/language_bundle/state-persistence.rkt"
         "../../src/language_bundle/state-records.rkt"
         "../../src/storage/record-codec.rkt")

(define digest-a (make-string 64 #\a))
(define digest-b (make-string 64 #\b))
(define digest-c (make-string 64 #\c))
(define digest-d (make-string 64 #\d))

(define active-bundle
  (odra-installed-bundle
   "org.example.language" "1.0.0" digest-a (list digest-b)
   '() "catalog.example" "org.example" 'linux 'x86-64
   '("native-grammar") "user grant" 'active-confirmed 7 #f #f))

(define (make-lock generation state-generation)
  (activation-lock-with-checksum
   (odra-activation-lock
    generation state-generation
    (hash "org.example.language" "1.0.0")
    (list digest-a digest-b) digest-c digest-d
    (hash "org.example.language" 7) (make-string 64 #\0))))

(define (make-state #:generation [generation 1]
                    #:lock [lock (make-lock 1 generation)]
                    #:previous-lock [previous-lock #f]
                    #:operations [operations '()])
  (language-bundle-state-with-checksum
   (odra-language-bundle-state
    2 "default" generation
    (if lock (odra-activation-lock-generation lock) 0)
    (list active-bundle) lock previous-lock operations '()
    (odra-bundle-accounting 1 1 512 4096 0)
    (make-string 64 #\0))))

(define (with-root action)
  (define root (make-temporary-file "odra-bundle-state-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind void (lambda () (action root))
                (lambda () (delete-directory/files root))))

(define (persist! root state)
  (define result (language-bundle-state-persist root state))
  (check-true (odra-record-publication? result))
  result)

(test-case "durable installed state reconstructs a confirmed generation"
  (with-root
   (lambda (root)
     (define state (make-state))
     (define publication (persist! root state))
     (check-true (odra-record-publication-file-synced? publication))
     (check-true (odra-record-publication-directory-synced? publication))
     (define startup (language-bundle-state-startup root))
     (check-eq? (odra-language-bundle-startup-mode startup) 'confirmed)
     (check-equal? (odra-language-bundle-startup-state startup) state))))

(test-case "safe mode preserves durable installed state while omitting activation"
  (with-root
   (lambda (root)
     (define state (make-state))
     (persist! root state)
     (define path (language-bundle-state-path root))
     (define before (file->bytes path))
     (define startup (language-bundle-state-startup root #:safe-mode? #t))
     (check-eq? (odra-language-bundle-startup-mode startup) 'factory-only)
     (check-equal? (odra-language-bundle-startup-state startup) state)
     (check-equal? (file->bytes path) before))))

(test-case "startup resumes only an idempotent pending operation"
  (with-root
   (lambda (root)
     (define operation
       (odra-bundle-operation
        "verify-language" 'verify 'verify 1 1 (list digest-b)
        '() 'pending #f ""))
     (persist! root (make-state #:operations (list operation)))
     (check-eq?
      (odra-language-bundle-startup-mode (language-bundle-state-startup root))
      'resume-operation))))

(test-case "ambiguous publication rolls back and durably rebinds the previous lock"
  (with-root
   (lambda (root)
     (define previous (make-lock 4 1))
     (persist! root (make-state #:lock previous))
     (define current (make-lock 5 2))
     (define operation
       (odra-bundle-operation
        "enable-language" 'enable 'publish 2 5 (list digest-b)
        '() 'pending #f ""))
     (persist! root
               (make-state #:generation 2
                           #:lock current
                           #:previous-lock previous
                           #:operations (list operation)))
     (define startup (language-bundle-state-startup root))
     (define recovered (odra-language-bundle-startup-state startup))
     (check-eq? (odra-language-bundle-startup-mode startup) 'rollback-previous)
     (check-equal? (odra-language-bundle-state-generation recovered) 3)
     (check-equal? (odra-activation-lock-generation
                    (odra-language-bundle-state-lock recovered))
                   5)
     (check-equal? (odra-activation-lock-state-generation
                    (odra-language-bundle-state-lock recovered))
                   3)
     (check-false (odra-language-bundle-state-previous-lock recovered))
     (check-equal? (odra-language-bundle-state-operations recovered) '())
     (check-equal? (language-bundle-state-module-load
                    (language-bundle-state-path root))
                   recovered))))

(test-case "malformed installed state is retained in quarantine"
  (with-root
   (lambda (root)
     (define path (language-bundle-state-path root))
     (make-directory* (path-only path))
     (file-or-directory-permissions (path-only path) #o700)
     (call-with-output-file path
       (lambda (output) (write-bytes #"truncated" output))
       #:exists 'truncate/replace #:mode 'binary #:permissions #o600)
     (define startup (language-bundle-state-startup root))
     (check-eq? (odra-language-bundle-startup-mode startup) 'factory-only)
     (check-true (odra-record-diagnostic?
                  (odra-language-bundle-startup-diagnostic startup)))
     (check-false (file-exists? path))
     (check-true (file-exists?
                  (odra-language-bundle-startup-quarantine-path startup))))))

(test-case "missing immutable content prevents installed activation"
  (with-root
   (lambda (root)
     (persist! root (make-state))
     (define startup
       (language-bundle-state-startup root #:content-exists? (lambda (_) #f)))
     (check-eq? (odra-language-bundle-startup-mode startup) 'factory-only)
     (check-eq? (odra-language-bundle-startup-diagnostic startup)
                'invalid-activation-lock))))
