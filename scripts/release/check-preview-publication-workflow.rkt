#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (except-in openssl/sha1 sha1)
         (only-in file/sha1 bytes->hex-string)
         racket/file
         racket/list
         racket/path
         racket/port
         racket/runtime-path
         racket/string
         racket/system
         "preview-identity.rkt"
         "publish-preview-package.rkt")

(provide publication-workflow-errors
         publication-generated-file-errors)

(define-runtime-path workflow-path
  "../../.forgejo/workflows/publish-preview.yml")

(define required-jobs '("preflight" "build-and-validate" "publish"))

(define (count-matches pattern text)
  (length (regexp-match* pattern text)))

(define (string-index text marker [start 0])
  (define match
    (regexp-match-positions (regexp (regexp-quote marker)) text start))
  (and match (caar match)))

(define (section text start-marker end-marker)
  (define start (string-index text start-marker))
  (define end (and start (string-index text end-marker start)))
  (and start end (substring text start end)))

(define (job-names jobs-section)
  (for/list ([line (in-list (string-split jobs-section "\n"))]
             #:do [(define match (regexp-match #px"^  ([a-z][a-z0-9-]*):$" line))]
             #:when match)
    (cadr match)))

(define (missing-fragment-errors owner text fragments)
  (for/list ([fragment (in-list fragments)]
             #:unless (string-contains? text fragment))
    (format "~a is missing required workflow fragment: ~a" owner fragment)))

(define (publication-workflow-errors workflow)
  (define trigger (or (section workflow "on:\n" "concurrency:\n") ""))
  (define jobs-position (string-index workflow "jobs:\n"))
  (define jobs (if jobs-position (substring workflow jobs-position) ""))
  (define preflight
    (or (section jobs "  preflight:\n" "  build-and-validate:\n") ""))
  (define build
    (or (section jobs "  build-and-validate:\n" "  publish:\n") ""))
  (define staging
    (or (section build
                 "      - name: Stage validated publication files\n"
                 "      - name: Transfer validated publication files\n")
        ""))
  (define publish-position (string-index jobs "  publish:\n"))
  (define publish
    (if publish-position (substring jobs publish-position) ""))
  (append
   (missing-fragment-errors
    "manual trigger"
    trigger
    '("  workflow_dispatch:"
      "      tag:"
      "      confirmation:"))
   (if (or (regexp-match? #px"(?m:^  push:)" trigger)
           (regexp-match? #px"(?m:^  schedule:)" trigger))
       '("publication workflow must not have an automatic trigger")
       '())
   (if (equal? (job-names jobs) required-jobs)
       '()
       (list (format "publication job order differs: ~a" (job-names jobs))))
   (missing-fragment-errors
    "concurrency"
    workflow
    '("group: odra-preview-publication-${{ inputs.tag }}"
      "cancel-in-progress: false"))
   (missing-fragment-errors
    "preflight"
    preflight
    '("validate-preview-dispatch.rkt"
      "--inputs-only"
      "actions/runs?limit=50"
      "git show-ref --verify \"refs/tags/$PREVIEW_TAG\""
      "adapter_commit=%s"
      "--tag-kind"
      "--tag-commit"
      "--main-commit"
      "--runs .build/release-dispatch/runs.json"
      "persist-credentials: false"))
   (if (string-contains? preflight "git fetch")
       '("preflight must resolve the tag from the credential-free checkout")
       '())
   (missing-fragment-errors
    "build-and-validate"
    build
    '("needs: preflight"
      "--adapter-commit \"$PREVIEW_ADAPTER_COMMIT\""
      "ref: ${{ needs.preflight.outputs.adapter_commit }}"
      "reproduce-preview.sh"
      "smoke-preview-artifact.rkt"
      "smoke_temporary_parent=\"$PWD/.build/publication/candidate/smoke-tmp\""
      "--temporary-parent \"$smoke_temporary_parent\""
      "check-preview-artifact-hygiene.rkt"
      "preview-candidate-${{ needs.preflight.outputs.tag }}-${{ forgejo.run_id }}"
      "persist-credentials: false"))
   (missing-fragment-errors
    "publication file staging"
    staging
    '("artifact_stem=\"${PREVIEW_ARCHIVE%.tar.zst}\""
      "install -m 0644 \"$artifact_root/$artifact_stem/PREVIEW_TERMS.md\""))
   (missing-fragment-errors
    "publish"
    publish
    '("      - preflight"
      "      - build-and-validate"
      "ref: ${{ needs.preflight.outputs.adapter_commit }}"
      "download-artifact@v3"
      "publish-preview-package.rkt"
      "--package odra-preview"
      "persist-credentials: false"))
   (if (or (string-contains?
            build
            "ref: ${{ needs.preflight.outputs.commit }}")
           (string-contains?
            publish
            "ref: ${{ needs.preflight.outputs.commit }}"))
       '("publication jobs must use the validated adapter commit")
       '())
   (if (= (count-matches #rx"\\$\\{\\{ secrets\\." workflow) 1)
       '()
       '("publication workflow must reference exactly one secret"))
   (if (and (string-contains? publish
                              "${{ secrets.ODRA_PREVIEW_PACKAGE_TOKEN }}")
            (not (string-contains? preflight "${{ secrets."))
            (not (string-contains? build "${{ secrets.")))
       '()
       '("publication secret must exist only in the final publish job"))
   (if (= (count-matches #rx"publish-preview-package\\.rkt" workflow) 1)
       '()
       '("publication adapter must run exactly once"))
   (if (regexp-match? #px"(?i:delete[[:space:]]+/api/packages|--request[[:space:]]+DELETE)"
                      workflow)
       '("publication workflow must not delete package data")
       '())
   (for/list ([match (in-list (regexp-match* #px"(?m:^        uses: ([^[:space:]]+))"
                                             workflow
                                             #:match-select cadr))]
              #:unless (string-prefix? match "https://data.forgejo.org/"))
     (format "workflow action is not fully qualified: ~a" match))
   (if (= (count-matches #rx"persist-credentials: false" workflow) 3)
       '()
       '("every checkout must discard retained credentials"))
   (missing-fragment-errors
    "artifact identity"
    workflow
    '("archive: ${{ steps.validate.outputs.archive }}"
      "checksum: ${{ steps.validate.outputs.checksum }}"
      "terms: ${{ steps.validate.outputs.terms }}"
      "notices: ${{ steps.validate.outputs.notices }}"))))

(define (run/capture executable arguments)
  (define program (find-executable-path executable))
  (unless program
    (raise-user-error 'preview-publication-acceptance
                      "command is unavailable: ~a"
                      executable))
  (define-values (process output input errors)
    (apply subprocess #f #f #f program arguments))
  (close-output-port input)
  (define standard-output (port->string output))
  (define standard-error (port->string errors))
  (subprocess-wait process)
  (values (subprocess-status process) standard-output standard-error))

(define (publication-generated-file-errors)
  (define-values (tracked-status tracked tracked-errors)
    (run/capture "git" '("ls-files" "*.tar.zst" "*.sha256")))
  (define-values (ignored-status ignored ignored-errors)
    (run/capture "git"
                 '("check-ignore"
                   ".build/release-dispatch/probe"
                   ".build/publication/files/probe")))
  (append
   (if (zero? tracked-status)
       '()
       (list (format "tracked-artifact query failed: ~a"
                     (string-trim tracked-errors))))
   (if (string=? (string-trim tracked) "")
       '()
       (list (format "generated release artifacts are tracked: ~a"
                     (string-trim tracked))))
   (if (and (zero? ignored-status)
            (= (length (string-split (string-trim ignored))) 2))
       '()
       (list (format "publication build storage is not ignored: ~a"
                     (string-trim ignored-errors))))))

(module+ main
  (define errors
    (append (publication-workflow-errors (file->string workflow-path))
            (publication-generated-file-errors)))
  (unless (null? errors)
    (for-each (lambda (error) (eprintf "preview workflow: ~a\n" error)) errors)
    (exit 1))
  (printf "preview_publication_workflow=valid jobs=3 authority=final-step\n"))

(module+ test
  (require rackunit)

  (define workflow (file->string workflow-path))
  (define commit "0123456789abcdef0123456789abcdef01234567")
  (define identity
    (preview-identity "v0.1.0" commit commit 1798761600 preview-platform))

  (define (sha256-file path)
    (call-with-input-file path
      (lambda (input) (bytes->hex-string (sha256-bytes input)))))

  (define (write-file path content)
    (make-parent-directory* path)
    (call-with-output-file path
      #:exists 'truncate
      (lambda (output) (display content output))))

  (define (with-publication-fixture procedure)
    (define root (make-temporary-file "preview-workflow-test-~a" 'directory))
    (dynamic-wind
     void
     (lambda ()
       (define archive-name (preview-archive-name identity))
       (define archive (build-path root archive-name))
       (define checksum (build-path root (preview-checksum-name identity)))
       (define terms (build-path root (preview-terms-name identity)))
       (define notices (build-path root (preview-notices-name identity)))
       (write-file archive "accepted candidate")
       (write-file checksum (format "~a  ~a\n" (sha256-file archive) archive-name))
       (write-file terms "# Preview Terms\n\nAccepted terms.\n")
       (write-file notices "# Third-Party Notices\n\nAccepted notices.\n")
       (define names
         (list archive-name
               (preview-checksum-name identity)
               (preview-terms-name identity)
               (preview-notices-name identity)))
       (define digests
         (for/hash ([name (in-list names)])
           (values name (sha256-file (build-path root name)))))
       (procedure root names digests))
     (lambda () (delete-directory/files root))))

  (test-case "accepts the manual least-privilege workflow"
    (check-equal? (publication-workflow-errors workflow) '()))

  (test-case "requires Docker-visible smoke storage"
    (check-true
     (pair?
      (publication-workflow-errors
       (string-replace
        workflow
        "            --temporary-parent \"$smoke_temporary_parent\""
        "")))))

  (test-case "requires staging-local artifact identity"
    (check-true
     (pair?
      (publication-workflow-errors
       (string-replace
        workflow
        "          artifact_stem=\"${PREVIEW_ARCHIVE%.tar.zst}\"\n"
        "")))))

  (test-case "rejects automatic triggers and missing dependency gates"
    (check-not-false
     (member "publication workflow must not have an automatic trigger"
             (publication-workflow-errors
              (string-replace workflow
                              "  workflow_dispatch:"
                              "  push:\n  workflow_dispatch:"))))
    (check-true
     (pair? (publication-workflow-errors
             (string-replace workflow "    needs: preflight\n" "")))))

  (test-case "rejects early secrets destructive recovery and unqualified actions"
    (check-not-false
     (member "publication secret must exist only in the final publish job"
             (publication-workflow-errors
              (string-replace
               workflow
               "    timeout-minutes: 150"
               "    timeout-minutes: 150\n    env:\n      LEAK: ${{ secrets.LEAK }}"))))
    (check-not-false
     (member "publication workflow must not delete package data"
             (publication-workflow-errors
              (string-append workflow "\n# --request DELETE /api/packages\n"))))
    (check-true
     (pair? (publication-workflow-errors
             (string-replace workflow
                             "https://data.forgejo.org/actions/checkout@v6"
                             "actions/checkout@v6")))))

  (test-case "dry-runs exact artifact transfer without network access"
    (with-publication-fixture
     (lambda (root names digests)
       (define uploads '())
       (define result
         (publish-preview-package!
          identity
          root
          "https://forge.example"
          "owner"
          "odra-preview"
          "dry-run-token"
          #:probe (lambda (_url _token) (values 404 #f))
          #:put (lambda (url supplied-token path)
                  (check-equal? supplied-token "dry-run-token")
                  (set! uploads
                        (cons (cons (path->string (file-name-from-path path)) url)
                              uploads))
                  201)
          #:public-probe
          (lambda (url supplied-token)
            (check-false supplied-token)
            (define name (last (string-split url "/")))
            (values 200 (hash-ref digests name #f)))))
       (check-equal? (publication-result-state result) 'published)
       (check-equal? (publication-result-files result) names)
       (check-equal? (length uploads) 4)
       (for ([upload (in-list uploads)])
         (check-true
          (string-contains?
           (cdr upload)
           "/api/packages/owner/generic/odra-preview/0.1.0/"))))))

  (test-case "keeps generated publication payloads out of Git"
    (check-equal? (publication-generated-file-errors) '())))
