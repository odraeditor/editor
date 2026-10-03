#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
         "../../src/package_catalog/curation-records.rkt")

(define (digest character) (make-string 64 character))
(define artifact
  (odra-package-artifact-reference
   'linux 'x86-64 '("artifacts/example.tar.zst") (digest #\a) 4096
   "official-builder" "attestations/example.rktd" 'reproduced))
(define release
  (odra-package-release-reference
   1 "org.example.package" (digest #\b) "1.2.3" "org.example.publisher"
   "https://forge.example/org/package" (make-string 40 #\c) "v1.2.3"
   (digest #\d) (list artifact) (digest #\e) (digest #\f) (digest #\1)
   (digest #\2)))
(define assertion
  (odra-package-curation-assertion
   1 (digest #\3) (digest #\4) 1 release "decision-1" "policy-v1"
   'admitted "" '("assessment-1") 1 1))

(test-case "release identity is independent of catalog identity"
  (define other-catalog
    (struct-copy odra-package-curation-assertion assertion
                 [catalog-id (digest #\5)]
                 [decision-id "decision-2"]))
  (check-true
   (same-package-release?
    (odra-package-curation-assertion-release assertion)
    (odra-package-curation-assertion-release other-catalog))))

(test-case "artifact selection is exact by platform and architecture"
  (check-equal? (package-release-artifact release 'linux 'x86-64) artifact)
  (check-false (package-release-artifact release 'darwin 'aarch64)))

(test-case "release records copy mutable provenance text"
  (define mutable-label (string-copy "v1.2.3"))
  (define copied-release
    (struct-copy odra-package-release-reference release
                 [source-label mutable-label]))
  (string-set! mutable-label 0 #\X)
  (check-equal?
   (odra-package-release-reference-source-label copied-release) "v1.2.3")
  (check-true
   (immutable? (odra-package-release-reference-source-label copied-release))))

(test-case "artifact selectors are unique within one release"
  (check-exn
   exn:fail?
   (lambda ()
     (struct-copy odra-package-release-reference release
                  [artifact-set (list artifact artifact)]))))

(test-case "curation state outside admitted requires a reason"
  (for ([status '(deprecated quarantined withdrawn)])
    (check-exn
     exn:fail?
     (lambda ()
       (struct-copy odra-package-curation-assertion assertion
                    [status status]
                    [status-reason ""]))))
  (check-not-exn
   (lambda ()
     (struct-copy odra-package-curation-assertion assertion
                  [status 'deprecated]
                  [status-reason "superseded"]))))

(test-case "curation evidence remains ordered and bounded"
  (check-exn
   exn:fail?
   (lambda ()
     (struct-copy odra-package-curation-assertion assertion
                  [assessment-summary '("assessment-b" "assessment-a")])))
  (check-exn
   exn:fail?
   (lambda ()
     (struct-copy odra-package-curation-assertion assertion
                  [assessment-summary
                   (for/list ([index
                               (in-range (add1 maximum-package-assessment-summary))])
                     (format "assessment-~a" index))]))))

(test-case "source revisions and artifact digests must be immutable identities"
  (check-exn
   exn:fail?
   (lambda ()
     (struct-copy odra-package-release-reference release
                  [source-revision "main"])))
  (check-exn
   exn:fail?
   (lambda ()
     (struct-copy odra-package-artifact-reference artifact
                  [digest "mutable-tag"]))))
