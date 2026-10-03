#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/path
         rackunit
         "../../src/package_catalog/contracts.rkt"
         "../../src/package_catalog/state-records.rkt"
         "../../src/storage/record-codec.rkt")

(define catalog-id (make-string 64 #\a))
(define root-id (make-string 64 #\b))
(define snapshot-id (make-string 64 #\c))
(define snapshot-digest (make-string 64 #\d))
(define endpoint
  (odra-package-catalog-endpoint
   "origin" catalog-id "https://catalog.example/odra/index.rktd"
   'https 'origin 10 #t))
(define endpoint-state
  (odra-package-catalog-state-endpoint
   1 1 endpoint "secret-service/catalog-origin"))
(define registration
  (odra-package-catalog-registration
   1 "official" 1 catalog-id 'built-in root-id '("origin")
   10 'enforce #t 'current))
(define confirmed
  (odra-package-catalog-confirmed-snapshot-reference
   1 catalog-id snapshot-id 7 snapshot-digest
   "snapshots/official/7.rktd" 100))
(define failure
  (odra-package-catalog-state-failure
   1 "refresh-failure" catalog-id 'endpoint-unavailable 2
   "Origin unavailable; confirmed state retained"))

(define (make-state #:generation [generation 1]
                    #:registrations [registrations (list registration)]
                    #:endpoints [endpoints (list endpoint-state)]
                    #:confirmed-snapshots [confirmed-snapshots (list confirmed)]
                    #:failures [failures (list failure)])
  (package-catalog-state-with-checksum
   (odra-package-catalog-state
    1 "default" generation registrations endpoints confirmed-snapshots failures
    '("quarantine/candidate-a.rktd") (make-string 64 #\0))))

(define (with-record action)
  (define root (make-temporary-file "odra-package-catalog-state-~a" 'directory))
  (define path (build-path root "state.rktd"))
  (dynamic-wind void (lambda () (action path))
                (lambda () (delete-directory/files root))))

(define (write-record path bytes)
  (call-with-output-file path
    (lambda (output) (write-bytes bytes output))
    #:exists 'truncate/replace #:mode 'binary))

(test-case "versioned package catalog state round trips exactly"
  (with-record
   (lambda (path)
     (define state (make-state))
     (write-record path (package-catalog-state->module-bytes state))
     (check-equal? (package-catalog-state-module-format path) 1)
     (check-equal? (package-catalog-state-module-load path) state))))

(test-case "aggregate state retains immutable copies of caller text"
  (define mutable-detail (string-copy "Mutable detail"))
  (define copied-failure
    (odra-package-catalog-state-failure
     1 "copy-failure" catalog-id 'io 1 mutable-detail))
  (string-set! mutable-detail 0 #\X)
  (check-equal? (odra-package-catalog-state-failure-detail copied-failure)
                "Mutable detail")
  (check-true
   (immutable? (odra-package-catalog-state-failure-detail copied-failure))))

(test-case "confirmed snapshot survives removal of local registration state"
  (define state
    (make-state #:generation 2 #:registrations '() #:endpoints '()))
  (check-equal? (odra-package-catalog-state-confirmed-snapshots state)
                (list confirmed)))

(test-case "registration endpoint membership is exact and catalog scoped"
  (check-exn
   exn:fail?
   (lambda ()
     (make-state #:endpoints '())))
  (define foreign-endpoint
    (odra-package-catalog-state-endpoint
     1 1
     (odra-package-catalog-endpoint
      "origin" root-id "https://catalog.example/foreign/index.rktd"
      'https 'origin 10 #t)
     #f))
  (check-exn
   exn:fail?
   (lambda ()
     (make-state #:endpoints (list foreign-endpoint)))))

(test-case "file endpoints cannot persist credential references"
  (define local-endpoint
    (odra-package-catalog-endpoint
     "local" catalog-id "file:///tmp/catalog/index.rktd"
     'file 'local 10 #t))
  (check-exn
   exn:fail?
   (lambda ()
     (odra-package-catalog-state-endpoint
      1 1 local-endpoint "secret-service/local"))))

(test-case "tampered state checksum is rejected as a checked diagnostic"
  (with-record
   (lambda (path)
     (define bytes (package-catalog-state->module-bytes (make-state)))
     (write-record path
                   (regexp-replace #px#"[0-9a-f]{64}" bytes
                                   (string->bytes/utf-8 root-id)))
     (check-true
      (odra-record-diagnostic? (package-catalog-state-module-load path))))))

(test-case "unknown schema version is inspectable but not loadable"
  (with-record
   (lambda (path)
     (define bytes (package-catalog-state->module-bytes (make-state)))
     (write-record path
                   (regexp-replace
                    #px#"(#:format-version[^0-9]+)1" bytes
                    (lambda (_whole prefix) (bytes-append prefix #"2"))))
     (check-equal? (package-catalog-state-module-format path) 2)
     (check-false (package-catalog-state-compatible-format? 2))
     (check-true
      (odra-record-diagnostic? (package-catalog-state-module-load path))))))

(test-case "aggregate collection bounds reject excessive registration state"
  (define registrations
    (for/list ([index (in-range (add1 maximum-package-catalog-registrations))])
      (odra-package-catalog-registration
       1 (format "catalog-~a" index) 1 catalog-id 'user root-id '()
       index 'warn #f 'never)))
  (check-exn
   exn:fail?
   (lambda ()
     (make-state #:registrations registrations
                 #:endpoints '()
                 #:confirmed-snapshots '()
                 #:failures '()))))
