#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         rackunit
         "../../src/package_catalog/curation-assessment-store.rkt"
         "../../src/package_catalog/curation-records.rkt"
         "../../src/package_catalog/curation-submissions.rkt")

(define (digest character) (make-string 64 character))
(define release
  (odra-package-release-reference
   1 "org.example.package" (digest #\a) "1.0.0" "org.example.publisher"
   "https://forge.example/org/package" (make-string 40 #\b) #f (digest #\c)
   (list (odra-package-artifact-reference
          'linux 'x86-64 '("package.tar.zst") (digest #\d) 1024 #f #f
          'unverified))
   (digest #\e) (digest #\f) (digest #\1) (digest #\2)))
(define submission
  (make-curation-submission (digest #\3) 'add "submitter-1" release #f '()
                            (make-string 40 #\4)))
(define inputs (list (digest #\5) (digest #\6)))

(define (assessment class identity outcome [generation 1])
  (make-curation-assessment
   (odra-curation-submission-id submission) generation class identity "v1"
   "rules/package-v1" inputs outcome '() '() #f 100))

(test-case "independent assessment classes remain attributable"
  (define first
    (record-curation-assessment
     (make-curation-review submission) inputs
     (assessment 'deterministic-tool "scanner.tool" 'pass)))
  (define second
    (record-curation-assessment
     first inputs (assessment 'ai-assisted "review.bot" 'findings)))
  (check-equal? (length (odra-curation-review-assessments second)) 2)
  (check-equal?
   (sort (map odra-curation-assessment-outcome
              (odra-curation-review-assessments second)) symbol<?)
   '(findings pass)))

(test-case "stale generation and input digests reject"
  (define review (make-curation-review submission))
  (check-eq?
   (odra-curation-assessment-ingestion-failure-code
    (record-curation-assessment
     review inputs (assessment 'deterministic-tool "scanner.tool" 'pass 2)))
   'stale-input)
  (check-eq?
   (odra-curation-assessment-ingestion-failure-code
    (record-curation-assessment
     review (list (digest #\7))
     (assessment 'deterministic-tool "scanner.tool" 'pass)))
   'stale-input))

(test-case "incomplete evidence cannot become reviewable"
  (define review
    (record-curation-assessment
     (make-curation-review submission) inputs
     (assessment 'deterministic-tool "scanner.tool" 'pass)))
  (define result
    (mark-curation-reviewable
     review '(deterministic-tool isolated-runtime human-review)))
  (check-eq? (odra-curation-assessment-ingestion-failure-code result)
             'incomplete-assessment))

(test-case "failed and disagreeing assessments remain reviewable evidence"
  (define first
    (record-curation-assessment
     (make-curation-review submission) inputs
     (assessment 'deterministic-tool "scanner.tool" 'fail)))
  (define second
    (record-curation-assessment
     first inputs (assessment 'human-review "reviewer.person" 'pass)))
  (define ready
    (mark-curation-reviewable second '(deterministic-tool human-review)))
  (check-true (odra-curation-review? ready))
  (check-eq?
   (odra-curation-submission-state
    (odra-curation-review-submission ready))
   'reviewable)
  (check-equal?
   (sort (map odra-curation-assessment-outcome
              (odra-curation-review-assessments ready)) symbol<?)
   '(fail pass)))

(test-case "immutable review record loads after restart"
  (define review
    (record-curation-assessment
     (make-curation-review submission) inputs
     (assessment 'isolated-runtime "sandbox.tool" 'inconclusive)))
  (define root (make-temporary-file "odra-curation-review-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind
    void
    (lambda ()
      (define path (curation-review-persist root review))
      (check-true (path? path) (format "~s" path))
      (check-equal? (curation-review-module-load path) review))
    (lambda () (delete-directory/files root))))
