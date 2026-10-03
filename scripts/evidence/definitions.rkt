#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.

(require racket/list
         racket/runtime-path
         "vendor/canonical-json.rkt")

(provide evidence-contract-commit
         subjects-path workflows-path
         workflow-definition operation-definition producer-definition
         release-job-names)

(define evidence-contract-commit "9fc02187596112605dd1b3bb764be2e8b68eaf32")
(define-runtime-path subjects-path "vendor/subjects.json")
(define-runtime-path workflows-path "vendor/workflows.json")

(define operations
  (hasheq
   'odra/main-check
   '(("source-hygiene" "test" "source-hygiene-check")
     ("documentation" "test" "docs-check")
     ("build" "build" "build")
     ("project-workspace-migration" "test" "project-workspace-migration-terminal-test"))
   'odra/nightly
   '(("source-hygiene" "test" "source-hygiene-check")
     ("compile-checks" "test" "check")
     ("ui-migration" "test" "ui-migration-check")
     ("test-suite" "test" "internal-test")
     ("hosting" "test" "hosting-test")
     ("documentation" "test" "docs-check"))
   'odra/release
   '(("preflight" "test" "request")
     ("snapshot-authority-probe" "test" "snapshot-authority")
     ("package-authority-probe" "test" "package-authority")
     ("guide-authority-probe" "test" "guide-authority")
     ("source-snapshot" "build" "snapshot-transfer")
     ("build-and-validate" "build" "build-validation")
     ("prepare-user-guide" "build" "guide-render")
     ("retain-candidate" "publication" "candidate-retention")
     ("candidate-complete" "test" "candidate-admission")
     ("publish-source" "publication" "source-publication")
     ("publish-bundle" "publication" "package-publication")
     ("publish-user-guide" "publication" "guide-publication")
     ("public-verification" "test" "public-verification"))))

(define release-job-names (map car (hash-ref operations 'odra/release)))

(define producer-definition
  (hasheq 'identity "odra/native-workflow-producer" 'version 1
          'contract_commit evidence-contract-commit
          'input_policy "source-tools-configuration-artifact-inputs-v1"
          'resources "gnu-time-cpu-rss-and-pressure-v1"
          'release_observation "job-results-and-retained-phase-inputs-v1"
          'operations operations))

(define (workflow-definition identity)
  (or (findf (lambda (value) (equal? (hash-ref value 'workflow_id) identity))
             (hash-ref (read-json-file workflows-path) 'workflows))
      (raise-user-error 'native-evidence "unknown workflow identity")))

;; Display labels and shell block position are deliberately absent from identity.
(define (operation-definition workflow stage)
  (define operation (assoc stage (hash-ref operations (string->symbol workflow) '())))
  (unless operation (raise-user-error 'native-evidence "unknown workflow stage"))
  (hasheq 'step_id (string-append workflow "/" stage)
          'definition_version 1 'operation_class (cadr operation)
          'operation (caddr operation)))
