#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/list
         racket/runtime-path
         racket/string)

(provide release-workflow-errors
         workflow-run-blocks
         workflow-step-blocks)

(define-runtime-path workflow-path
  "../../.forgejo/workflows/publish-release.yml")

(define product-jobs
  '("preflight"
    "snapshot-authority-probe"
    "package-authority-probe"
    "guide-authority-probe"
    "source-snapshot"
    "build-and-validate"
    "prepare-user-guide"
    "retain-candidate"
    "candidate-complete"
    "publish-source"
    "publish-bundle"
    "publish-user-guide"
    "public-verification"))

(define required-jobs (append product-jobs '("verification-evidence")))

(define secret-free-jobs
  '("preflight"
    "build-and-validate"
    "retain-candidate"
    "candidate-complete"
    "public-verification"
    "verification-evidence"))

(define (string-index text marker [start 0])
  (define match
    (regexp-match-positions (regexp (regexp-quote marker)) text start))
  (and match (caar match)))

(define (job-positions workflow)
  (for/list ([position
              (in-list
               (regexp-match-positions* #px"(?m:^  [a-z][a-z0-9-]*:$)"
                                        workflow))])
    (cons (substring workflow (+ (car position) 2) (sub1 (cdr position)))
          (car position))))

(define (job-section workflow name)
  (define positions (job-positions workflow))
  (define current (assoc name positions))
  (and current
       (let* ([start (cdr current)]
              [later (filter (lambda (entry) (> (cdr entry) start)) positions)]
              [end (if (null? later) (string-length workflow) (cdar later))])
         (substring workflow start end))))

(define (job-names workflow)
  (map car (job-positions workflow)))

(define (missing-errors owner text fragments)
  (for/list ([fragment (in-list fragments)]
             #:unless (and text (string-contains? text fragment)))
    (format "~a is missing required workflow fragment: ~a" owner fragment)))

(define (unexpected-errors owner text fragments)
  (for/list ([fragment (in-list fragments)]
             #:when (and text (string-contains? text fragment)))
    (format "~a contains forbidden workflow fragment: ~a" owner fragment)))

(define (workflow-step-blocks workflow)
  (define lines (string-split workflow "\n" #:trim? #f))
  (let loop ([remaining lines] [blocks '()])
    (cond
      [(null? remaining) (reverse blocks)]
      [(regexp-match? #px"^      - name: " (car remaining))
       (define-values (body tail)
         (let collect ([source (cdr remaining)] [body (list (car remaining))])
           (if (and (pair? source)
                    (not (regexp-match? #px"^      - name: " (car source))))
               (collect (cdr source) (cons (car source) body))
               (values (string-join (reverse body) "\n") source))))
       (loop tail (cons body blocks))]
      [else (loop (cdr remaining) blocks)])))

(define (step-id block)
  (define match
    (regexp-match #px"(?m:^        id: ([a-z][a-z0-9-]*)$)" block))
  (and match (cadr match)))

(define (step-output-references text)
  (remove-duplicates
   (regexp-match* #px"steps\\.([a-z][a-z0-9-]*)\\.outputs\\."
                  text
                  #:match-select cadr)))

(define (step-output-errors workflow)
  (append-map
   (lambda (job-name)
     (define section (job-section workflow job-name))
     (define blocks (workflow-step-blocks section))
     (define declared (filter values (map step-id blocks)))
     (append
      (for/list ([reference (in-list (step-output-references section))]
                 #:unless (member reference declared))
        (format "job ~a references unknown step outputs: ~a"
                job-name reference))
      (let loop ([remaining blocks] [available '()] [errors '()])
        (if (null? remaining)
            (reverse errors)
            (let* ([block (car remaining)]
                   [identifier (step-id block)]
                   [premature
                    (for/list ([reference
                                (in-list (step-output-references block))]
                               #:unless (member reference available))
                      (format "job ~a consumes step outputs before availability: ~a"
                              job-name reference))])
              (loop (cdr remaining)
                    (if identifier (cons identifier available) available)
                    (append (reverse premature) errors)))))))
   required-jobs))

(define (job-dependencies section)
  (regexp-match* #px"(?m:^      - ([a-z][a-z0-9-]+)$)"
                 section
                 #:match-select cadr))

(define (needs-output-references section)
  (regexp-match* #px"needs\\.([a-z][a-z0-9-]*)\\.outputs\\.([a-z][a-z0-9_]*)"
                 section
                 #:match-select (lambda (match)
                                  (list (cadr match) (caddr match)))))

(define (declared-job-outputs section)
  (define output-marker (string-index section "    outputs:\n"))
  (define next-marker (and output-marker
                           (string-index section "    env:\n" output-marker)))
  (if output-marker
      (regexp-match* #px"(?m:^      ([a-z][a-z0-9_]*):)"
                     (substring section
                                output-marker
                                (or next-marker (string-length section)))
                     #:match-select cadr)
      '()))

(define (needs-output-errors workflow)
  (append-map
   (lambda (job-name)
     (define section (job-section workflow job-name))
     (define dependencies (job-dependencies section))
     (append-map
      (lambda (reference)
        (define producer (car reference))
        (define output (cadr reference))
        (cond
          [(not (member producer dependencies))
           (list (format "job ~a reads outputs from undeclared dependency: ~a"
                         job-name producer))]
          [(not (member output
                        (declared-job-outputs
                         (job-section workflow producer))))
           (list (format "job ~a reads unknown output ~a from ~a"
                         job-name output producer))]
          [else '()]))
      (needs-output-references section)))
   required-jobs))

(define (release-workflow-errors workflow)
  (define trigger-start (string-index workflow "on:\n"))
  (define trigger-end (string-index workflow "concurrency:\n"))
  (define trigger
    (if (and trigger-start trigger-end)
        (substring workflow trigger-start trigger-end)
        ""))
  (define preflight (job-section workflow "preflight"))
  (define snapshot-probe (job-section workflow "snapshot-authority-probe"))
  (define package-probe (job-section workflow "package-authority-probe"))
  (define guide-probe (job-section workflow "guide-authority-probe"))
  (define snapshot (job-section workflow "source-snapshot"))
  (define build (job-section workflow "build-and-validate"))
  (define guide (job-section workflow "prepare-user-guide"))
  (define retention (job-section workflow "retain-candidate"))
  (define candidate (job-section workflow "candidate-complete"))
  (define publish-source (job-section workflow "publish-source"))
  (define publish-bundle (job-section workflow "publish-bundle"))
  (define publish-guide (job-section workflow "publish-user-guide"))
  (define verify (job-section workflow "public-verification"))
  (define evidence (job-section workflow "verification-evidence"))
  (append
   (if (equal? (job-dependencies evidence) product-jobs)
       '() '("verification evidence must observe exactly the product jobs"))
   (for/list ([job product-jobs]
              #:when (member "verification-evidence" (job-dependencies (job-section workflow job))))
     (format "product job ~a must not depend on verification evidence" job))
   (missing-errors
    "verification evidence" evidence
    '("if: always() && needs.preflight.result == 'success'"
      "timeout-minutes: 10"
      "ODRA_EVIDENCE_NEEDS: ${{ toJSON(needs) }}"
      "ref: ${{ inputs.source_commit }}"
      "if: steps.producer.outcome == 'success' && steps.source.outcome == 'success'"
      "scripts/evidence/release-producer.rkt"
      "path: .build/verification-evidence/bundle/"))
   (if (= (length (workflow-step-blocks evidence)) 4)
       '() '("verification evidence must have four bounded steps"))
   (append-map
    (lambda (step)
      (missing-errors "verification evidence step" step
                      '("        continue-on-error: true" "        timeout-minutes: 1")))
    (workflow-step-blocks evidence))
   (missing-errors
    "manual trigger" trigger
    '("  workflow_dispatch:"
      "      version:"
      "      source_commit:"
      "      source_branch:"
      "          - dev"
      "          - main"
      "      mode:"
      "          - candidate"
      "          - publish"
      "      publish_confirmation:"))
   (if (or (regexp-match? #px"(?m:^  push:)" trigger)
           (regexp-match? #px"(?m:^  schedule:)" trigger)
           (regexp-match? #px"(?m:^  pull_request:)" trigger))
       '("release workflow must not have an automatic trigger")
       '())
   (if (equal? (job-names workflow) required-jobs)
       '()
       (list (format "release job order differs: ~a" (job-names workflow))))
   (missing-errors
    "concurrency" workflow
    '("group: odra-release-${{ inputs.version }}-${{ inputs.source_commit }}"
      "cancel-in-progress: false"))
   (missing-errors
    "preflight" preflight
    '("timeout-minutes: 10"
      "persist-credentials: false"
      "docker info >/dev/null"
      "check-build-environment.rkt"
      "ref: ${{ forgejo.sha }}"
      "path: .build/release/adapter"
      "sparse-checkout: scripts/release"
      ".build/release/adapter/scripts/release/release-workflow-request.rkt"
      "ref: ${{ inputs.source_branch }}"
      "fetch-depth: 1"
      "release_line=\"**Release: v$RELEASE_VERSION**\""
      "grep -Fxc -- \"$release_line\" README.md"
      "--publish-confirmation \"$RELEASE_PUBLISH_CONFIRMATION\""
      "ODRA_RELEASE_CANDIDATE_STORE: ${{ vars.ODRA_RELEASE_CANDIDATE_STORE }}/${{ forgejo.sha }}"
      "--candidate-store \"$ODRA_RELEASE_CANDIDATE_STORE\""
      "release-request-${{ steps.request.outputs.candidate_id }}-${{ forgejo.run_id }}"))
   (missing-errors
    "snapshot authority probe" snapshot-probe
    '("timeout-minutes: 5"
      "ODRA_SNAPSHOT_REPOSITORY_TOKEN: ${{ secrets.ODRA_SNAPSHOT_REPOSITORY_TOKEN }}"
      "ls-remote --refs"))
   (missing-errors
    "package authority probe" package-probe
    '("if: inputs.mode == 'publish'"
      "ODRA_PREVIEW_PACKAGE_TOKEN: ${{ secrets.ODRA_PREVIEW_PACKAGE_TOKEN }}"
      "/api/v1/packages/$PACKAGE_OWNER"))
   (missing-errors
    "guide authority probe" guide-probe
    '("if: inputs.mode == 'publish'"
      "GH_TOKEN: ${{ secrets.ODRA_USER_GUIDE_GITHUB_TOKEN }}"
      "gh api \"repos/$USER_GUIDE_REPOSITORY\""))
   (missing-errors
    "source snapshot" snapshot
    '("      - snapshot-authority-probe"
      "ref: ${{ needs.preflight.outputs.adapter_commit }}"
      "path: .build/release/adapter"
      "sparse-checkout: scripts/release"
      ".build/release/adapter/scripts/release/public-source-export.rkt"
      ".build/release/adapter/scripts/release/check-public-source-snapshot.rkt"
      ".build/release/adapter/scripts/release/candidate-store-command.rkt"
      "jq -cS '.request | del(.mode)'"
      "--sort=name --mtime=\"@$RELEASE_SOURCE_DATE_EPOCH\""
      ".build/release/adapter/scripts/release/snapshot-repository.rkt"
      "--phase export"
      "--phase snapshot-transfer"
      "-c pack.threads=1 bundle create"
      "jq -cS 'del(.state)'"
      "artifacts/snapshot/repository.bundle"
      "artifacts/snapshot/publication-identity.json"
      "persist-credentials: false"))
   (missing-errors
    "build and validate" build
    '("timeout-minutes: 150"
      "RELEASE_ADAPTER_COMMIT: ${{ needs.preflight.outputs.adapter_commit }}"
      "snapshot-build.rkt"
      "--adapter-commit \"$RELEASE_ADAPTER_COMMIT\""
      "git clone --quiet --no-checkout"
      "smoke-preview-artifact.rkt"
      "racket scripts/release/check-preview-artifact-hygiene.rkt"
      "--phase bundle-validation"
      "artifacts/linux/$stem.tar.zst"
      "persist-credentials: false"))
   (missing-errors
    "User Guide preparation" guide
    '("SPORE_COMMIT: ${{ vars.ODRA_SPORE_COMMIT }}"
      "SPORE_REPOSITORY_URL: ${{ vars.ODRA_SPORE_REPOSITORY_URL }}"
      "GH_TOKEN: ${{ secrets.ODRA_USER_GUIDE_GITHUB_TOKEN }}"
      "GIT_CONFIG_KEY_0=http.https://github.com/.extraheader"
      "authorization=$(printf 'git:%s' \"$GH_TOKEN\" | base64 -w 0)"
      "GIT_CONFIG_VALUE_0=\"Authorization: Basic $authorization\""
      "GOTOOLCHAIN=local go -C .build/release/spore build -trimpath"
      "--sort=name --mtime=\"@$RELEASE_SOURCE_DATE_EPOCH\""
      "git clone --quiet --no-checkout"
      "prepare-release-guide.sh"
      "candidate"
      "--snapshot-ref \"$SNAPSHOT_COMMIT\""
      "spore_manifest=.build/release/guide-candidate/publication/.spore-manifest.json"
      "'.built_at = $built_at'"
      "--phase guide-preparation"
      "artifacts/guide/candidate.tar.zst"
      "persist-credentials: false"))
   (missing-errors
    "candidate retention" retention
    '("      - build-and-validate"
      "      - prepare-user-guide"
      "mkdir -p .build"
      "--phase candidate-retention"
      "if: steps.retention.outputs.disposition != 'reused'"
      "if: steps.retention.outputs.disposition == 'reused'"
      "artifacts/manifests/candidate-summary.json"
      "select(.name != \"candidate-summary\")"
      "artifacts/manifests/candidate-summary.json"
      "release-candidate-${{ needs.preflight.outputs.candidate_id }}-${{ forgejo.run_id }}"))
   (if (= (length
           (regexp-match*
            #rx"ODRA_RELEASE_CANDIDATE_STORE: \\$\\{\\{ vars\\.ODRA_RELEASE_CANDIDATE_STORE \\}\\}/\\$\\{\\{ needs\\.preflight\\.outputs\\.adapter_commit \\}\\}"
            workflow))
          9)
       '()
       '("every post-preflight job must use the adapter-scoped candidate store"))
   (missing-errors
    "candidate completion" candidate
    '("if: ${{ inputs.mode == 'candidate' }}"
      "if: steps.verification.outputs.disposition != 'reused'"
      "--phase public-verification"
      "--state unavailable"))
   (missing-errors
    "source publication" publish-source
    '("if: ${{ inputs.mode == 'publish' }}"
      "      - snapshot-authority-probe"
      "snapshot-repository.rkt"
      "publish > .build/release/source-publication.json"))
   (missing-errors
    "bundle publication" publish-bundle
    '("if: ${{ inputs.mode == 'publish' }}"
      "      - package-authority-probe"
      "publish-preview-package.rkt"
      "ODRA_PREVIEW_PACKAGE_TOKEN: ${{ secrets.ODRA_PREVIEW_PACKAGE_TOKEN }}"))
   (missing-errors
    "User Guide publication" publish-guide
    '("if: ${{ inputs.mode == 'publish' }}"
      "      - guide-authority-probe"
      "publish-release-guide.sh"
      "gh workflow run publish-pages.yml"
      "gh run watch \"$run_id\""
      "GH_TOKEN: ${{ secrets.ODRA_USER_GUIDE_GITHUB_TOKEN }}"))
   (missing-errors
    "public verification" verify
    '("      - publish-source"
      "      - publish-bundle"
      "      - publish-user-guide"
      "refs/tags/v$RELEASE_VERSION"
      "if: steps.verification.outputs.disposition != 'reused'"
      "--phase public-verification"
      "--state passed"))
   (append*
    (for/list ([name (in-list secret-free-jobs)])
      (define job (job-section workflow name))
      (if (and job (string-contains? job "${{ secrets."))
          (list (format "~a must not receive publication secrets" name))
          '())))
   (if (and (= (length (regexp-match* #rx"snapshot-build\\.rkt" workflow)) 1)
            (= (length (regexp-match* #rx"prepare-release-guide\\.sh" workflow)) 1)
            (= (length (regexp-match* #rx"publish-preview-package\\.rkt" workflow)) 1)
            (= (length (regexp-match* #rx"gh workflow run publish-pages\\.yml"
                                      workflow))
               1))
       '()
       '("each expensive or publishing adapter must run exactly once"))
   (if (= (length (regexp-match* #rx"actions/checkout@" workflow))
          (length
           (regexp-match* #rx"github-server-url: http://127\\.0\\.0\\.1:3000"
                          workflow)))
       '()
       '("every release checkout must use the runner-local Forgejo endpoint"))
   (step-output-errors workflow)
   (needs-output-errors workflow)
   (unexpected-errors
    "release workflow" workflow
    '("cancel-in-progress: true"
      ".build/release/snapshot-checkout/scripts/release/check-preview-artifact-hygiene.rkt"
      "git push --force"
      "git push -f"
      "--request DELETE"
      "x-access-token:"))))

(define (workflow-run-blocks workflow)
  (define lines (string-split workflow "\n" #:trim? #f))
  (let loop ([remaining lines] [blocks '()])
    (cond
      [(null? remaining) (reverse blocks)]
      [(regexp-match? #px"^        run: \\|$" (car remaining))
       (define-values (body tail)
         (let collect ([source (cdr remaining)] [body '()])
           (if (and (pair? source)
                    (or (string-prefix? (car source) "          ")
                        (string=? (car source) "")))
               (collect (cdr source)
                        (cons (if (string-prefix? (car source) "          ")
                                  (substring (car source) 10)
                                  "")
                              body))
               (values (string-join (reverse body) "\n") source))))
       (loop tail (cons body blocks))]
      [else (loop (cdr remaining) blocks)])))

(module+ main
  (define workflow (file->string workflow-path))
  (define errors (release-workflow-errors workflow))
  (unless (null? errors)
    (for ([error (in-list errors)])
      (eprintf "release-publication-workflow: ~a\n" error))
    (exit 1))
  (printf "release-publication-workflow: valid jobs=~a shell-blocks=~a\n"
          (length required-jobs)
          (length (workflow-run-blocks workflow))))
