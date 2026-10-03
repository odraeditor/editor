#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/path
         rackunit
         "../../src/package_catalog/curation-records.rkt"
         "../../src/package_catalog/manual-records.rkt")

(define (digest character) (make-string 64 character))
(define artifact
  (odra-package-artifact-reference
   'linux 'x86-64 '("manual.tar.zst") (digest #\a) 1024 #f #f 'unverified))
(define release
  (odra-package-release-reference
   1 "org.example.manual" (digest #\b) "1.0.0" "org.example.publisher"
   "https://forge.example/org/manual" (make-string 40 #\c) #f
   (digest #\d) (list artifact) (digest #\e) (digest #\f)
   (digest #\1) (digest #\2)))

(define (manual kind source-ref revision)
  (make-manual-package-acquisition
   1 kind source-ref #f revision (digest #\a) (digest #\d) release))

(test-case "manual acquisition identity binds one explicit generation"
  (define first (manual 'local-artifact "/tmp/manual.tar.zst" #f))
  (define repeated (manual 'local-artifact "/tmp/manual.tar.zst" #f))
  (define refreshed
    (make-manual-package-acquisition
     2 'local-artifact "/tmp/manual.tar.zst" #f #f
     (digest #\a) (digest #\d) release))
  (check-equal? (odra-manual-package-acquisition-id first)
                (odra-manual-package-acquisition-id repeated))
  (check-not-equal? (odra-manual-package-acquisition-id first)
                    (odra-manual-package-acquisition-id refreshed)))

(test-case "Git provenance requires an exact resolved revision"
  (define value
    (manual 'git "https://forge.example/org/manual.git" (make-string 40 #\c)))
  (check-equal? (odra-manual-package-acquisition-resolved-source-revision value)
                (make-string 40 #\c))
  (check-exn
   exn:fail?
   (lambda ()
     (manual 'git "https://forge.example/org/manual.git" #f))))

(test-case "local source references are redacted at the export boundary"
  (check-equal?
   (manual-package-acquisition-redacted-source-ref
    (manual 'development-directory "/private/work/manual" #f))
   "<local-development-directory>")
  (check-equal?
   (manual-package-acquisition-redacted-source-ref
    (manual 'git "/private/work/manual" (make-string 40 #\c)))
   "<local-git-repository>"))

(test-case "remote Git references reject credentials and query material"
  (for ([source-ref '("https://user:secret@forge.example/org/manual.git"
                      "https://forge.example/org/manual.git?token=secret"
                      "ssh://user:secret@forge.example/org/manual.git")])
    (check-exn
     exn:fail?
     (lambda ()
       (manual 'git source-ref (make-string 40 #\c))))))

(test-case "curation state cannot fabricate an assertion match"
  (define value (manual 'local-artifact "/tmp/manual.tar.zst" #f))
  (check-eq? (odra-manual-package-acquisition-curation-state value)
             'manual-uncurated)
  (check-exn
   exn:fail?
   (lambda ()
     (manual-package-acquisition-with-curation
      value 'matches-curated-release '())))
  (define matched
    (manual-package-acquisition-with-curation
     value 'matches-curated-release (list (digest #\9))))
  (check-equal? (odra-manual-package-acquisition-matching-assertion-ids matched)
                (list (digest #\9))))

(test-case "release manifest and artifact identities are exact"
  (check-exn
   exn:fail?
   (lambda ()
     (make-manual-package-acquisition
      1 'local-artifact "/tmp/manual.tar.zst" #f #f
      (digest #\9) (digest #\d) release)))
  (check-exn
   exn:fail?
   (lambda ()
     (make-manual-package-acquisition
      1 'local-artifact "/tmp/manual.tar.zst" #f #f
      (digest #\a) (digest #\9) release))))
