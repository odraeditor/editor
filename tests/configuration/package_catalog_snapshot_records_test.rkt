#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         rackunit
         "../../src/package_catalog/integrity.rkt"
         "../../src/package_catalog/snapshot-records.rkt"
         "../../src/storage/record-codec.rkt")

(define digest-a (make-string 64 #\a))
(define digest-b (make-string 64 #\b))
(define signature
  (odra-package-catalog-signature
   'ed25519 digest-b package-catalog-publisher-signature-domain
   (make-string 128 #\c)))

(define (snapshot #:id [id digest-a]
                  #:sequence [sequence 1]
                  #:previous [previous #f]
                  #:metadata-size [metadata-size 1024]
                  #:signatures [signatures (list signature)])
  (odra-package-catalog-snapshot
   1 id digest-b sequence previous "policy-v1" 10 30 digest-a digest-b
   metadata-size "snapshot-publisher" signatures))

(define (with-snapshot-file bytes action)
  (define path (make-temporary-file "odra-package-catalog-snapshot-~a.rktd"))
  (dynamic-wind
   (lambda ()
     (call-with-output-file path
       (lambda (output) (write-bytes bytes output))
       #:exists 'truncate/replace #:mode 'binary))
   (lambda () (action path))
   (lambda () (delete-file path))))

(test-case "snapshot records round-trip through the checked module codec"
  (define candidate (snapshot))
  (with-snapshot-file
   (package-catalog-snapshot->module-bytes candidate)
   (lambda (path)
     (check-equal? (package-catalog-snapshot-module-load path) candidate))))

(test-case "snapshot content identity excludes signatures and supplied identity"
  (define candidate (snapshot))
  (check-equal?
   (package-catalog-snapshot-content-digest candidate)
   (package-catalog-snapshot-content-digest
    (struct-copy odra-package-catalog-snapshot candidate
                 [id digest-b]
                 [signatures '()]))))

(test-case "snapshot text is retained as immutable copied state"
  (define mutable-policy (string-copy "policy-v1"))
  (define candidate
    (odra-package-catalog-snapshot
     1 digest-a digest-b 1 #f mutable-policy 10 30 digest-a digest-b 1024
     "snapshot-publisher" (list signature)))
  (string-set! mutable-policy 0 #\X)
  (check-equal? (odra-package-catalog-snapshot-policy-id candidate) "policy-v1")
  (check-true (immutable? (odra-package-catalog-snapshot-policy-id candidate))))

(test-case "successor records require one predecessor digest"
  (check-exn exn:fail? (lambda () (snapshot #:sequence 2)))
  (check-not-exn (lambda () (snapshot #:sequence 2 #:previous digest-a))))

(test-case "oversized metadata and malformed modules reject before admission"
  (check-exn
   exn:fail?
   (lambda ()
     (snapshot #:metadata-size
               (add1 maximum-package-catalog-snapshot-metadata-bytes))))
  (with-snapshot-file
   #"#lang odra/config\n(package-catalog-snapshot malformed)\n"
   (lambda (path)
     (check-true
      (odra-record-diagnostic? (package-catalog-snapshot-module-load path))))))
