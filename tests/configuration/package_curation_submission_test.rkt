#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require rackunit
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
(define change
  (odra-package-change-summary 'publisher 'changed 'high
                               "org.example.old" "org.example.publisher"))
(define submission
  (make-curation-submission (digest #\3) 'add "submitter-1" release #f
                            (list change) (make-string 40 #\4)))

(test-case "submission owns one exact candidate generation"
  (check-equal? (odra-curation-submission-generation submission) 1)
  (check-equal? (odra-curation-submission-release submission) release)
  (check-eq? (odra-curation-submission-state submission) 'proposed))

(test-case "non-add submissions require a prior assertion"
  (check-exn
   exn:fail?
   (lambda ()
     (make-curation-submission (digest #\3) 'update "submitter-1"
                               release #f '() #f))))

(test-case "assessment records retain class outcome findings and limitations"
  (define finding
    (odra-assessment-finding "capability-change" 'high "manifest:12"
                             "Adds process execution" 95))
  (define assessment
    (make-curation-assessment
     (odra-curation-submission-id submission) 1 'ai-assisted "assessor.bot"
     "model-2026-09" "rules/package-v1" (list (digest #\5)) 'findings
     (list finding) '("dynamic-analysis-unavailable") "evidence/assessment-1" 100))
  (check-eq? (odra-curation-assessment-outcome assessment) 'findings)
  (check-equal? (odra-curation-assessment-limitations assessment)
                '("dynamic-analysis-unavailable")))

(test-case "ordinary state transitions cannot create acceptance"
  (define assessing (transition-curation-submission submission 'assessing))
  (check-eq? (odra-curation-submission-state assessing) 'assessing)
  (define result (transition-curation-submission assessing 'accepted))
  (check-eq? (odra-curation-submission-failure-code result)
             'human-decision-required))

(test-case "candidate mutation increments generation and clears evidence"
  (define with-evidence
    (struct-copy odra-curation-submission submission
                 [assessment-ids (list (digest #\6))]
                 [state 'reviewable]))
  (define changed
    (replace-curation-submission-candidate
     with-evidence release (list change) (make-string 40 #\5)))
  (check-equal? (odra-curation-submission-generation changed) 2)
  (check-equal? (odra-curation-submission-assessment-ids changed) '())
  (check-eq? (odra-curation-submission-state changed) 'proposed))
