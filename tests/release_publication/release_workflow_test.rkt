#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/list
         racket/port
         racket/runtime-path
         racket/string
         racket/system
         rackunit
         rackunit/text-ui
         "../../scripts/release/check-release-publication-workflow.rkt"
         "../../scripts/release/release-workflow-request.rkt")

(define-runtime-path workflow-path
  "../../.forgejo/workflows/publish-release.yml")
(define-runtime-path export-policy-path
  "../../release/public-source-policy.json")
(define-runtime-path build-environment-path
  "../../release/linux-x86_64/build-environment.json")

(define commit "0123456789abcdef0123456789abcdef01234567")
(define observed-at "2026-09-26T20:00:00Z")

(define (request-input mode confirmation)
  (workflow-request-input mode
                          "0.2.0"
                          commit
                          1798761600
                          confirmation
                          export-policy-path
                          build-environment-path
                          commit
                          observed-at))

(define (error-containing? errors text)
  (ormap (lambda (error) (string-contains? error text)) errors))

(define (replace-once text before after)
  (define replaced (string-replace text before after))
  (check-not-equal? replaced text)
  replaced)

(define (bash-syntax-valid? block)
  (define normalized
    (regexp-replace* #px"\\$\\{\\{[^}]+\\}\\}" block "forgejo-expression"))
  (define-values (process output input error)
    (subprocess #f #f #f "/usr/bin/bash" "-n"))
  (display normalized input)
  (close-output-port input)
  (define standard-output (port->string output))
  (define standard-error (port->string error))
  (subprocess-wait process)
  (values (zero? (subprocess-status process))
          standard-output
          standard-error))

(define workflow-tests
  (test-suite
   "Unified release publication workflow"

   (test-case "Accepts the owned manual workflow graph"
     (define workflow (file->string workflow-path))
     (check-equal? (release-workflow-errors workflow) '())
     (check-equal? (length (workflow-run-blocks workflow)) 27))

   (test-case "Rejects automatic triggers and removed mode authority"
     (define workflow (file->string workflow-path))
     (define automatic
       (replace-once workflow
                     "  workflow_dispatch:\n"
                     "  push:\n    branches: [main]\n  workflow_dispatch:\n"))
     (check-true
      (error-containing? (release-workflow-errors automatic)
                         "automatic trigger"))
     (define unconfirmed
       (replace-once workflow
                     "      publish_confirmation:\n"
                     "      omitted_confirmation:\n"))
     (check-true
      (error-containing? (release-workflow-errors unconfirmed)
                         "publish_confirmation")))

   (test-case "Rejects secret leakage and weakened publication dependencies"
     (define workflow (file->string workflow-path))
     (define secret-build
       (replace-once
        workflow
        "  build-and-validate:\n"
        (string-append
         "  build-and-validate:\n"
         "    env:\n"
         "      LEAK: ${{ secrets.ODRA_PREVIEW_PACKAGE_TOKEN }}\n")))
     (check-true
      (error-containing? (release-workflow-errors secret-build)
                         "build-and-validate must not receive"))
     (define missing-probe
       (replace-once workflow
                     "      - package-authority-probe\n"
                     "      - preflight\n"))
     (check-true
      (error-containing? (release-workflow-errors missing-probe)
                         "package-authority-probe")))

   (test-case "Requires scoped authority for the private User Guide source"
     (define workflow (file->string workflow-path))
     (define unauthenticated-guide
       (replace-once
        workflow
        "          GH_TOKEN: ${{ secrets.ODRA_USER_GUIDE_GITHUB_TOKEN }}\n"
        ""))
     (check-true
      (error-containing? (release-workflow-errors unauthenticated-guide)
                         "GH_TOKEN")))

   (test-case "Rejects changed timeouts, concurrency, and duplicate builds"
     (define workflow (file->string workflow-path))
     (define short-build
       (replace-once workflow
                     "    timeout-minutes: 150\n"
                     "    timeout-minutes: 15\n"))
     (check-true
      (error-containing? (release-workflow-errors short-build)
                         "timeout-minutes: 150"))
     (define cancellable
       (replace-once workflow
                     "  cancel-in-progress: false\n"
                     "  cancel-in-progress: true\n"))
     (check-true
      (error-containing? (release-workflow-errors cancellable)
                         "cancel-in-progress"))
     (define duplicate-build
       (string-append workflow "\n# snapshot-build.rkt\n"))
     (check-true
      (error-containing? (release-workflow-errors duplicate-build)
                         "exactly once")))

   (test-case "Rejects release checkouts through the public Forge endpoint"
     (define workflow (file->string workflow-path))
     (define public-checkout
       (replace-once
        workflow
        "          github-server-url: http://127.0.0.1:3000\n"
        ""))
     (check-true
      (error-containing? (release-workflow-errors public-checkout)
                         "runner-local Forgejo endpoint")))

   (test-case "Keeps artifact hygiene under the validated release adapter"
     (define workflow (file->string workflow-path))
     (define snapshot-owned-check
       (replace-once
        workflow
        "racket scripts/release/check-preview-artifact-hygiene.rkt"
        "racket .build/release/snapshot-checkout/scripts/release/check-preview-artifact-hygiene.rkt"))
     (check-true
      (error-containing? (release-workflow-errors snapshot-owned-check)
                         "snapshot-checkout/scripts/release/check-preview-artifact-hygiene.rkt")))

   (test-case "Creates the candidate retention workspace"
     (define workflow (file->string workflow-path))
     (define missing-workspace
       (replace-once workflow "          mkdir -p .build\n" ""))
     (check-true
      (error-containing? (release-workflow-errors missing-workspace)
                         "mkdir -p .build")))

   (test-case "Restores reused candidate summaries"
     (define workflow (file->string workflow-path))
     (define missing-restore
       (replace-once
        workflow
        "        if: steps.retention.outputs.disposition == 'reused'\n"
        "        if: steps.retention.outputs.disposition == 'missing'\n"))
     (check-true
      (error-containing? (release-workflow-errors missing-restore)
                         "if: steps.retention.outputs.disposition == 'reused'")))

   (test-case "Scopes retained candidates to the validated adapter"
     (define workflow (file->string workflow-path))
     (define shared-store
       (replace-once
        workflow
        "ODRA_RELEASE_CANDIDATE_STORE: ${{ vars.ODRA_RELEASE_CANDIDATE_STORE }}/${{ needs.preflight.outputs.adapter_commit }}"
        "ODRA_RELEASE_CANDIDATE_STORE: ${{ vars.ODRA_RELEASE_CANDIDATE_STORE }}"))
     (check-true
      (error-containing? (release-workflow-errors shared-store)
                         "adapter-scoped candidate store")))

   (test-case "Rejects consuming a step output inside its producer"
     (define workflow (file->string workflow-path))
     (define invalid-step
       (replace-once
        workflow
        "            start\n\n      - name: Retain the combined candidate summary"
        (string-append
         "            start\n"
         "          printf '%s\\n' \"${{ steps.retention.outputs.attempt }}\"\n\n"
         "      - name: Retain the combined candidate summary")))
     (check-true
      (error-containing? (release-workflow-errors invalid-step)
                         "consumes step outputs before availability")))

   (test-case "Rejects unavailable job outputs"
     (define workflow (file->string workflow-path))
     (define unknown-output
       (replace-once
        workflow
        "needs.preflight.outputs.adapter_commit"
        "needs.preflight.outputs.missing_commit"))
     (check-true
      (error-containing? (release-workflow-errors unknown-output)
                         "reads unknown output missing_commit from preflight")))

   (test-case "Parses every embedded shell block"
     (for ([block (in-list (workflow-run-blocks (file->string workflow-path)))]
           [index (in-naturals 1)])
       (define-values (valid? standard-output standard-error)
         (bash-syntax-valid? block))
       (check-true valid?
                   (format "shell block ~a failed syntax: ~a~a"
                           index standard-output standard-error))))

   (test-case "Keeps candidate and publish mode on one candidate identity"
     (define candidate (prepare-workflow-request (request-input 'candidate "")))
     (define publish
       (prepare-workflow-request (request-input 'publish "publish:0.2.0")))
     (check-equal? (hash-ref candidate 'candidate_id)
                   (hash-ref publish 'candidate_id))
     (check-not-equal? (hash-ref (hash-ref candidate 'request) 'mode)
                       (hash-ref (hash-ref publish 'request) 'mode))
     (check-exn exn:fail?
                (lambda ()
                  (prepare-workflow-request
                   (request-input 'publish "publish:0.2.1")))))))

(define failures (run-tests workflow-tests))
(unless (zero? failures)
  (exit 1))
