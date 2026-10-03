#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.

(require rackunit
         racket/file
         racket/port
         racket/runtime-path
         racket/string
         racket/system
         "../../scripts/release/check-release-publication-workflow.rkt")

(define-runtime-path root "../..")
(define (workflow name)
  (file->string (build-path root ".forgejo/workflows" (string-append name ".yml"))))

;; Every native step is bounded and best-effort, including its checkouts.
(test-case "keeps evidence steps independent of product outcomes"
  (for ([name '("main-check" "nightly" "publish-release")])
    (define text (workflow name))
    (define steps (workflow-step-blocks text))
    (define evidence
      (filter (lambda (step)
                (or (string-contains? step "native verification evidence")
                    (string-contains? step "native evidence producer")
                    (string-contains? step "observed source identity")
                    (string-contains? step "native release evidence"))) steps))
    (check-equal? (length evidence) (if (equal? name "publish-release") 4 3))
    (for ([step evidence])
      (check-true (string-contains? step "        continue-on-error: true"))
      (check-true (string-contains? step "        timeout-minutes: 1"))
      (check-false (string-contains? step "secrets.")))
    (check-equal? (length (regexp-match* #rx"path: .build/verification-evidence/bundle/" text)) 1))
  (define nightly (workflow "nightly"))
  (for ([step (workflow-step-blocks nightly)]
        #:when (string-contains? step "native verification evidence"))
    (check-true (string-contains? step "steps.admission.outputs.admitted == 'yes'"))))

;; Product jobs never wait on evidence; this is an observer of all terminal outcomes.
(test-case "rejects evidence coupling and unbounded release collection"
  (define text (workflow "publish-release"))
  (check-equal? (release-workflow-errors text) '())
  (for ([mutated
         (list (string-replace text
                               "        id: producer\n        continue-on-error: true"
                               "        id: producer\n        continue-on-error: false")
               (string-replace text
                               "  preflight:\n"
                               "  preflight:\n    needs:\n      - verification-evidence\n"))])
    (check-not-equal? (release-workflow-errors mutated) '())))

;; Check executable YAML blocks without running a build or a remote workflow.
(test-case "retains valid shell syntax in every observed workflow"
  (for* ([name '("main-check" "nightly" "publish-release")]
         [block (workflow-run-blocks (workflow name))])
    (define shell (regexp-replace* #px"\\$\\{\\{[^}]+\\}\\}" block "forgejo-expression"))
    (define-values (process output input errors)
      (subprocess #f #f #f (find-executable-path "bash") "-n"))
    (display shell input)
    (close-output-port input)
    (port->string output)
    (define diagnostic (port->string errors))
    (subprocess-wait process)
    (check-equal? (subprocess-status process) 0 diagnostic)))
