#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require json
         racket/cmdline
         racket/file
         racket/list
         racket/port
         racket/runtime-path
         racket/string
         "preview-identity.rkt")

(provide dispatch-input-errors
         latest-green-nightly
         dispatch-evidence-errors
         dispatch-summary)

(define canonical-tag-pattern
  #px"^v(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$")
(define full-commit-pattern #px"^[0-9a-f]{40}$")
(define nightly-workflow "nightly.yml")
(define accepted-nightly-events '("" "schedule" "workflow_dispatch"))
(define-runtime-path publication-workflow
  "../../.forgejo/workflows/publish-preview.yml")

(define (canonical-tag? value)
  (and (string? value) (regexp-match? canonical-tag-pattern value)))

(define (full-commit? value)
  (and (string? value) (regexp-match? full-commit-pattern value)))

(define (dispatch-input-errors tag confirmation source-ref run-attempt)
  (append
   (if (canonical-tag? tag)
       '()
       '("tag must use canonical vMAJOR.MINOR.PATCH form"))
   (if (and (canonical-tag? tag)
            (equal? confirmation (string-append "publish:" tag)))
       '()
       '("confirmation must equal publish:<tag>"))
   (if (equal? source-ref "refs/heads/main")
       '()
       '("dispatch source must be refs/heads/main"))
   (if (equal? run-attempt 1)
       '()
       '("dispatch must be a first attempt"))))

(define (green-nightly? run commit)
  (and (hash? run)
       (equal? (hash-ref run 'workflow_id #f) nightly-workflow)
       (member (hash-ref run 'event #f) accepted-nightly-events)
       (equal? (hash-ref run 'status #f) "success")
       (equal? (hash-ref run 'commit_sha #f) commit)
       (exact-nonnegative-integer? (hash-ref run 'id #f))))

(define (latest-green-nightly runs commit)
  (define candidates
    (filter (lambda (run) (green-nightly? run commit)) runs))
  (and (pair? candidates)
       (argmax (lambda (run) (hash-ref run 'id)) candidates)))

(define (dispatch-evidence-errors tag confirmation source-ref run-attempt
                                  tag-kind tag-commit main-commit
                                  source-date-epoch runs)
  (define identity
    (preview-identity tag
                      tag-commit
                      main-commit
                      source-date-epoch
                      preview-platform))
  (append
   (dispatch-input-errors tag confirmation source-ref run-attempt)
   (if (equal? tag-kind "tag")
       '()
       '("release tag must be an annotated tag object"))
   (preview-identity-errors identity)
   (if (and (full-commit? main-commit)
            (latest-green-nightly runs main-commit))
       '()
       '("a successful nightly run for the exact main commit is required"))))

(define (safe-run-url run)
  (define value (hash-ref run 'html_url "unavailable"))
  (if (and (string? value)
           (regexp-match? #px"^https://[^[:space:]]+$" value))
      value
      "unavailable"))

(define (dispatch-summary identity nightly)
  (hasheq
   'schema 1
   'release (preview-identity->jsexpr identity)
   'nightly_run
   (hasheq 'id (hash-ref nightly 'id)
           'url (safe-run-url nightly)
           'commit (hash-ref nightly 'commit_sha))))

(define (write-summary! directory identity nightly)
  (make-directory* directory)
  (define summary (dispatch-summary identity nightly))
  (call-with-output-file (build-path directory "preflight.json")
    #:exists 'truncate
    (lambda (output)
      (write-json summary output)
      (newline output)))
  (call-with-output-file (build-path directory "preflight.md")
    #:exists 'truncate
    (lambda (output)
      (fprintf output "# Linux Preview Publication Preflight\n\n")
      (fprintf output "Tag: `~a`\n\n" (preview-identity-tag identity))
      (fprintf output "Version: `~a`\n\n" (preview-version identity))
      (fprintf output "Commit: `~a`\n\n" (preview-identity-main-commit identity))
      (fprintf output "Nightly run: ~a\n\n" (safe-run-url nightly))
      (fprintf output "Archive: `~a`\n\n" (preview-archive-name identity))
      (fprintf output "Checksum: `~a`\n\n" (preview-checksum-name identity))
      (fprintf output "Preview terms: `~a`\n\n" (preview-terms-name identity))
      (fprintf output "Public notices: `~a`\n" (preview-notices-name identity)))))

(define (write-forgejo-outputs! path identity nightly)
  (call-with-output-file path
    #:exists 'append
    (lambda (output)
      (fprintf output "tag=~a\n" (preview-identity-tag identity))
      (fprintf output "version=~a\n" (preview-version identity))
      (fprintf output "commit=~a\n" (preview-identity-main-commit identity))
      (fprintf output "source_date_epoch=~a\n"
               (preview-identity-source-date-epoch identity))
      (fprintf output "nightly_run_id=~a\n" (hash-ref nightly 'id))
      (fprintf output "archive=~a\n" (preview-archive-name identity))
      (fprintf output "checksum=~a\n" (preview-checksum-name identity))
      (fprintf output "terms=~a\n" (preview-terms-name identity))
      (fprintf output "notices=~a\n" (preview-notices-name identity)))))

(define (print-errors-and-exit errors)
  (unless (null? errors)
    (for-each (lambda (error) (eprintf "preview dispatch: ~a\n" error)) errors)
    (exit 1)))

(module+ main
  (define inputs-only? #f)
  (define tag #f)
  (define confirmation #f)
  (define source-ref #f)
  (define run-attempt #f)
  (define tag-kind #f)
  (define tag-commit #f)
  (define main-commit #f)
  (define source-date-epoch #f)
  (define runs-path #f)
  (define summary-directory #f)
  (define forgejo-output #f)
  (command-line
   #:program "validate-preview-dispatch.rkt"
   #:once-each
   [("--inputs-only") "Validate untrusted dispatch inputs before Git use"
                        (set! inputs-only? #t)]
   [("--tag") value "Requested stable tag" (set! tag value)]
   [("--confirmation") value "Exact publication confirmation"
                              (set! confirmation value)]
   [("--source-ref") value "Forgejo dispatch source ref"
                            (set! source-ref value)]
   [("--run-attempt") value "Forgejo run attempt"
                             (set! run-attempt (string->number value))]
   [("--tag-kind") value "Git object kind for the release tag"
                          (set! tag-kind value)]
   [("--tag-commit") value "Commit selected by the release tag"
                            (set! tag-commit value)]
   [("--main-commit") value "Current main commit" (set! main-commit value)]
   [("--source-date-epoch") value "Release commit timestamp"
                                   (set! source-date-epoch
                                         (string->number value))]
   [("--runs") path "Forgejo Actions runs response" (set! runs-path path)]
   [("--summary-directory") path "Pre-upload summary directory"
                                  (set! summary-directory path)]
   [("--forgejo-output") path "Forgejo step output file"
                               (set! forgejo-output path)])
  (define input-errors
    (dispatch-input-errors tag confirmation source-ref run-attempt))
  (print-errors-and-exit input-errors)
  (if inputs-only?
      (printf "preview_dispatch_inputs=valid tag=~a\n" tag)
      (let ()
        (unless (and tag-kind tag-commit main-commit source-date-epoch
                     runs-path summary-directory forgejo-output)
          (raise-user-error 'preview-dispatch
                            "evidence validation arguments are incomplete"))
        (define runs-document (call-with-input-file runs-path read-json))
        (define runs (hash-ref runs-document 'workflow_runs '()))
        (define errors
          (dispatch-evidence-errors tag confirmation source-ref run-attempt
                                    tag-kind tag-commit main-commit
                                    source-date-epoch runs))
        (print-errors-and-exit errors)
        (define identity
          (preview-identity tag
                            tag-commit
                            main-commit
                            source-date-epoch
                            preview-platform))
        (define nightly (latest-green-nightly runs main-commit))
        (write-summary! summary-directory identity nightly)
        (write-forgejo-outputs! forgejo-output identity nightly)
        (printf "preview_dispatch=valid tag=~a commit=~a nightly=~a\n"
                tag main-commit (hash-ref nightly 'id)))))

(module+ test
  (require rackunit)

  (define commit "0123456789abcdef0123456789abcdef01234567")
  (define another-commit "1123456789abcdef0123456789abcdef01234567")
  (define valid-run
    (hasheq 'id 41
            'workflow_id nightly-workflow
            'event "schedule"
            'status "success"
            'commit_sha commit
            'html_url "https://forge.example/owner/repository/actions/runs/41"))

  (test-case "accepts explicit stable publication inputs"
    (check-equal?
     (dispatch-input-errors "v0.1.0" "publish:v0.1.0" "refs/heads/main" 1)
     '()))

  (test-case "rejects absent confirmation and branch dispatch"
    (define errors
      (dispatch-input-errors "v0.1.0" "" "refs/heads/dev" 1))
    (check-not-false (member "confirmation must equal publish:<tag>" errors))
    (check-not-false (member "dispatch source must be refs/heads/main" errors)))

  (test-case "rejects malformed tags and unsafe interpolation"
    (for ([tag (in-list '("0.1.0"
                          "v01.1.0"
                          "v0.1.0; touch injected"
                          "$(touch injected)"
                          "v0.1.0/../../main"))])
      (check-not-false
       (member "tag must use canonical vMAJOR.MINOR.PATCH form"
               (dispatch-input-errors tag
                                      (string-append "publish:" tag)
                                      "refs/heads/main"
                                      1)))))

  (test-case "rejects duplicate workflow attempts"
    (check-not-false
     (member "dispatch must be a first attempt"
             (dispatch-input-errors "v0.1.0"
                                    "publish:v0.1.0"
                                    "refs/heads/main"
                                    2))))

  (test-case "selects the latest exact successful nightly"
    (define runs
      (list valid-run
            (hash-set valid-run 'id 42)
            (hash-set* valid-run 'id 43 'status "failure")
            (hash-set* valid-run 'id 44 'commit_sha another-commit)))
    (check-equal? (hash-ref (latest-green-nightly runs commit) 'id) 42)
    (check-false
     (latest-green-nightly
      runs
      "2123456789abcdef0123456789abcdef01234567")))

  (test-case "accepts Forgejo nightly runs with an omitted event"
    (define forgejo-run (hash-set valid-run 'event ""))
    (check-equal? (latest-green-nightly (list forgejo-run) commit)
                  forgejo-run))

  (test-case "rejects wrong commit and missing green evidence"
    (define errors
      (dispatch-evidence-errors "v0.1.0"
                                "publish:v0.1.0"
                                "refs/heads/main"
                                1
                                "tag"
                                commit
                                another-commit
                                1798761600
                                (list valid-run)))
    (check-not-false
     (member "tag commit must equal the selected main commit" errors))
    (check-not-false
     (member "a successful nightly run for the exact main commit is required"
             errors)))

  (test-case "rejects lightweight release tags"
    (check-not-false
     (member
      "release tag must be an annotated tag object"
      (dispatch-evidence-errors "v0.1.0"
                                "publish:v0.1.0"
                                "refs/heads/main"
                                1
                                "commit"
                                commit
                                commit
                                1798761600
                                (list valid-run)))))

  (test-case "summarizes canonical artifacts without secret material"
    (define identity
      (preview-identity "v0.1.0" commit commit 1798761600 preview-platform))
    (define serialized
      (with-output-to-string
        (lambda () (write-json (dispatch-summary identity valid-run)))))
    (check-regexp-match #rx"odra-0.1.0-linux-x86_64.tar.zst" serialized)
    (check-false (regexp-match? #rx"token|secret" serialized)))

  (test-case "keeps publication manual serialized and safely interpolated"
    (define workflow
      (file->string publication-workflow))
    (check-regexp-match #rx"workflow_dispatch:" workflow)
    (check-regexp-match
     #rx"group: odra-preview-publication-\\$\\{\\{ inputs.tag \\}\\}"
     workflow)
    (check-regexp-match #rx"cancel-in-progress: false" workflow)
    (check-false (regexp-match? #px"(?m:^  push:)" workflow))
    (check-false (regexp-match? #px"(?m:^  schedule:)" workflow))
    (for ([line (in-list (string-split workflow "\n"))]
          #:when (regexp-match? #rx"\\$\\{\\{ inputs\\." line))
      (check-true
       (or (regexp-match? #rx"^  group:" line)
           (regexp-match? #rx"^      PREVIEW_(TAG|CONFIRMATION):" line))))))
