#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/list
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
(define inputs (list (digest #\5)))

(define (assessment class identity outcome [generation 1]
                    #:findings [findings '()] #:evidence [evidence #f])
  (make-curation-assessment
   (odra-curation-submission-id submission) generation class identity "v1"
   "rules/package-v1" inputs outcome findings '() evidence 100))

(test-case "submission transition table is closed and acceptance stays reserved"
  (define allowed
    '((proposed assessing) (proposed closed)
      (assessing reviewable) (assessing changes-requested)
      (assessing rejected) (assessing closed)
      (reviewable changes-requested) (reviewable rejected) (reviewable closed)
      (changes-requested proposed) (changes-requested closed)
      (rejected closed) (accepted closed)))
  (for ([transition (in-list allowed)])
    (define current (car transition))
    (define next (cadr transition))
    (define result
      (transition-curation-submission
       (struct-copy odra-curation-submission submission [state current]) next))
    (check-true (odra-curation-submission? result)
                (format "~a -> ~a" current next)))
  (define forbidden
    (transition-curation-submission submission 'accepted))
  (check-eq? (odra-curation-submission-failure-code forbidden)
             'human-decision-required))

(test-case "candidate mutation makes retained assessments stale"
  (define old-assessment
    (assessment 'deterministic-tool "scanner.tool" 'pass))
  (define changed
    (replace-curation-submission-candidate
     submission release '() (make-string 40 #\6)))
  (define result
    (record-curation-assessment
     (make-curation-review changed) inputs old-assessment))
  (check-eq? (odra-curation-assessment-ingestion-failure-code result)
             'stale-input))

(test-case "oversized and hidden reasoning evidence cannot enter records"
  (check-exn
   exn:fail?
   (lambda ()
     (odra-assessment-finding
      "oversized" 'low "manifest" (make-string 4097 #\x) 50)))
  (check-exn
   exn:fail?
   (lambda ()
     (odra-assessment-finding
      "reasoning" 'informational "" "<think>private rationale</think>" 50))))

(test-case "public assessment projection redacts local evidence paths"
  (define finding
    (odra-assessment-finding
     "source" 'medium "/private/work/package.rkt:12" "Observed change" 80))
  (define value
    (assessment 'human-review "reviewer.person" 'findings
                #:findings (list finding) #:evidence "/private/evidence/report"))
  (define public (curation-assessment-redacted value))
  (check-equal?
   (odra-assessment-finding-location
    (car (odra-curation-assessment-findings public)))
   "<local-path>")
  (check-equal? (odra-curation-assessment-evidence-ref public)
                "<local-evidence>"))

(test-case "failed timeout and inconclusive outcomes remain retained"
  (define review
    (for/fold ([current (make-curation-review submission)])
              ([entry
                (in-list
                 (list (list 'deterministic-tool "scanner.tool" 'fail)
                       (list 'isolated-runtime "sandbox.tool" 'timeout)
                       (list 'ai-assisted "review.bot" 'inconclusive)))])
      (record-curation-assessment
       current inputs (apply assessment entry))))
  (check-equal?
   (sort (map odra-curation-assessment-outcome
              (odra-curation-review-assessments review)) symbol<?)
   '(fail inconclusive timeout)))

(test-case "durable review publication leaves only its immutable record"
  (define review
    (record-curation-assessment
     (make-curation-review submission) inputs
     (assessment 'deterministic-tool "scanner.tool" 'pass)))
  (define root (make-temporary-file "odra-assessment-cleanup-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind
    void
    (lambda ()
      (define path (curation-review-persist root review))
      (check-true (path? path))
      (define files
        (filter file-exists?
                (find-files (lambda (_) #t)
                            (build-path root "package-curation" "reviews"))))
      (check-equal? files (list path))
      (check-equal? (curation-review-module-load path) review))
    (lambda () (delete-directory/files root))))
