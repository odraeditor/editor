#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         (prefix-in bundle: "../../src/language_bundle/state-records.rkt")
         "../../src/package/language-bundle-state-adapter.rkt"
         "../../src/package/state-records.rkt")

(define digest-a (make-string 64 #\a))
(define digest-b (make-string 64 #\b))
(define digest-c (make-string 64 #\c))
(define digest-d (make-string 64 #\d))
(define digest-e (make-string 64 #\e))
(define digest-f (make-string 64 #\f))
(define bundle-runtime
  (bundle:odra-installed-bundle
   "org.example.runtime" "1.0.0" digest-a (list digest-b) '()
   "catalog.example" "example.publisher" 'linux 'x86-64
   '("racket-extension") "legacy user grant" 'active-confirmed 4 #f #f))
(define bundle-language
  (bundle:odra-installed-bundle
   "org.example.language" "2.0.0" digest-c (list digest-d)
   '("org.example.runtime") "catalog.example" "example.publisher"
   'linux 'x86-64 '("native-grammar") "legacy user grant"
   'active-confirmed 7 #f #t))
(define bundle-lock
  (bundle:activation-lock-with-checksum
   (bundle:odra-activation-lock
    3 5
    (hash "org.example.language" "2.0.0"
          "org.example.runtime" "1.0.0")
    (list digest-a digest-b digest-c digest-d)
    digest-e digest-f
    (hash "org.example.language" 7 "org.example.runtime" 4)
    (make-string 64 #\0))))
(define bundle-state
  (bundle:language-bundle-state-with-checksum
   (bundle:odra-language-bundle-state
    2 "default" 5 3 (list bundle-language bundle-runtime) bundle-lock #f
    '() '() (bundle:odra-bundle-accounting 2 2 1024 8192 0)
    (make-string 64 #\0))))

(define extension-provenance
  (odra-package-provenance
   'catalog digest-a digest-b digest-f
   "example.publisher" (make-string 40 #\a)))

(define extension-package
  (odra-installed-package
   "org.example.extension" 'extension "1.0.0" 5 digest-e #f (list digest-f)
   '() extension-provenance 'linux 'x86-64 '(racket-extension)
   '(racket-extension) "user grant" 'installed-disabled 0 #f #f #t #f ""))

(test-case "language-bundle state adapts into the generic package owner"
  (define-values (state rejection)
    (language-bundle-state->package-state bundle-state))
  (check-false rejection)
  (check-eq? (odra-package-state-migration-source state) 'language-bundle-v2)
  (check-equal? (map odra-installed-package-id
                     (odra-package-state-packages state))
                '("org.example.language" "org.example.runtime"))
  (define language
    (package-state-find state "org.example.language" "2.0.0"))
  (check-eq? (odra-installed-package-kind language) 'language-support)
  (check-equal? (odra-installed-package-dependencies language)
                (list (odra-package-release "org.example.runtime" "1.0.0")))
  (check-equal? (odra-installed-package-requested-authorities language)
                '(native-grammar))
  (check-equal? (odra-installed-package-granted-authorities language)
                '(native-grammar))
  (check-equal?
   (odra-package-activation-lock-content (odra-package-state-lock state))
   (list digest-a digest-b digest-c digest-d)))

(test-case "ordinary extensions and language support share one state owner"
  (define-values (adapted rejection)
    (language-bundle-state->package-state bundle-state))
  (check-false rejection)
  (define packages
    (sort (cons extension-package (odra-package-state-packages adapted))
          string<? #:key (lambda (package)
                           (format "~a@~a"
                                   (odra-installed-package-id package)
                                   (odra-installed-package-version package)))))
  (define combined
    (struct-copy odra-package-state adapted
                 [packages packages]
                 [accounting (odra-package-accounting 3 3 1536 12288 0)]))
  (check-eq? (odra-installed-package-kind
              (package-state-find combined "org.example.extension" "1.0.0"))
             'extension)
  (check-eq? (odra-installed-package-kind
              (package-state-find combined "org.example.language" "2.0.0"))
             'language-support))

(test-case "migration rejects an ambiguous dependency without partial state"
  (define second-runtime
    (struct-copy bundle:odra-installed-bundle bundle-runtime
                 [version "1.1.0"]
                 [lifecycle 'installed-disabled]
                 [contribution-generation 0]))
  (define ambiguous
    (struct-copy bundle:odra-language-bundle-state bundle-state
                 [bundles (list bundle-language bundle-runtime second-runtime)]
                 [accounting (bundle:odra-bundle-accounting 3 3 1024 8192 0)]
                 [checksum (make-string 64 #\0)]))
  (define-values (state rejection)
    (language-bundle-state->package-state ambiguous))
  (check-false state)
  (check-eq? (odra-package-state-adapter-rejection-code rejection)
             'ambiguous-dependency)
  (check-equal? (odra-package-state-adapter-rejection-package-id rejection)
                "org.example.language"))

(test-case "reachability includes installed, locked, pending, and quarantined content"
  (define-values (adapted rejection)
    (language-bundle-state->package-state bundle-state))
  (check-false rejection)
  (define operation
    (odra-package-operation
     "install-extension" 'install 'verify 5 3
     (list (odra-package-release "org.example.extension" "1.0.0"))
     (list digest-e) '("staging/install-extension") 'pending #f ""))
  (define state
    (struct-copy odra-package-state adapted
                 [operations (list operation)]
                 [quarantine (list digest-f)]
                 [accounting (odra-package-accounting 2 2 1024 8192 1)]))
  (check-equal? (package-state-reachable-content state)
                (list digest-a digest-b digest-c digest-d digest-e digest-f))
  (check-equal?
   (package-state-garbage-collection-plan
    state (list digest-a digest-b digest-c digest-d digest-e digest-f
                (make-string 64 #\9)))
   (list (make-string 64 #\9))))

(test-case "duplicate releases and inconsistent accounting are rejected"
  (define-values (adapted rejection)
    (language-bundle-state->package-state bundle-state))
  (check-false rejection)
  (check-exn
   exn:fail?
   (lambda ()
     (struct-copy odra-package-state adapted
                  [packages
                   (append (odra-package-state-packages adapted)
                           (list (car (odra-package-state-packages adapted))))]
                  [accounting (odra-package-accounting 3 3 1024 8192 0)])))
  (check-exn
   exn:fail?
   (lambda ()
     (struct-copy odra-package-state adapted
                  [accounting (odra-package-accounting 2 1 1024 8192 0)]))))
