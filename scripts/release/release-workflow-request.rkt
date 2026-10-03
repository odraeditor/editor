#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (except-in openssl/sha1 sha1)
         (only-in file/sha1 bytes->hex-string)
         json
         racket/cmdline
         racket/file
         racket/path
         racket/string
         "candidate-store.rkt"
         "publication-identity.rkt")

(provide documentation-contract-version
         (struct-out workflow-request-input)
         workflow-request-errors
         prepare-workflow-request)

(define documentation-contract-version "snapshot-guide-v2")
(define commit-pattern #px"^[0-9a-f]{40}$")

(struct workflow-request-input
  (mode version source-commit source-date-epoch publish-confirmation
        export-policy build-environment adapter-commit observed-at)
  #:transparent)

(define (file-sha256 path)
  (and (path-string? path)
       (file-exists? path)
       (call-with-input-file path
         (lambda (input) (bytes->hex-string (sha256-bytes input))))))

(define (publish-confirmation-errors input)
  (define mode (workflow-request-input-mode input))
  (define confirmation (workflow-request-input-publish-confirmation input))
  (cond
    [(eq? mode 'candidate)
     (if (equal? confirmation "")
         '()
         '("candidate mode must not carry publish confirmation"))]
    [(eq? mode 'publish)
     (if (equal? confirmation
                 (string-append "publish:"
                                (workflow-request-input-version input)))
         '()
         '("publish mode requires exact version confirmation"))]
    [else '("mode must be candidate or publish")]))

(define (workflow-request-errors input)
  (append
   (publish-confirmation-errors input)
   (if (and (string? (workflow-request-input-source-commit input))
            (regexp-match? commit-pattern
                           (workflow-request-input-source-commit input)))
       '()
       '("source commit must be a full lowercase Git object ID"))
   (if (and (exact-nonnegative-integer?
             (workflow-request-input-source-date-epoch input))
            (< (workflow-request-input-source-date-epoch input) (expt 2 63)))
       '()
       '("source date epoch must be an unsigned 63-bit integer"))
   (if (file-sha256 (workflow-request-input-export-policy input))
       '()
       '("export policy must be an available file"))
   (if (file-sha256 (workflow-request-input-build-environment input))
       '()
       '("build environment must be an available file"))
   (if (and (string? (workflow-request-input-adapter-commit input))
            (regexp-match? commit-pattern
                           (workflow-request-input-adapter-commit input)))
       '()
       '("adapter commit must be a full lowercase Git object ID"))
   (if (and (string? (workflow-request-input-observed-at input))
            (regexp-match?
             #px"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"
             (workflow-request-input-observed-at input)))
       '()
       '("observation time must be an RFC3339 UTC timestamp"))))

(define (prepare-workflow-request input)
  (define errors (workflow-request-errors input))
  (unless (null? errors)
    (raise-arguments-error 'prepare-workflow-request
                           "invalid workflow request"
                           "errors" errors))
  (define request
    (release-request
     (workflow-request-input-mode input)
     (workflow-request-input-version input)
     "odra/odra"
     (workflow-request-input-source-commit input)
     (workflow-request-input-source-date-epoch input)
     "odra/editor"
     (list publication-platform)
     "public-source-policy-v1"
     (file-sha256 (workflow-request-input-export-policy input))
     (file-sha256 (workflow-request-input-build-environment input))
     documentation-contract-version))
  (unless (release-request-valid? request)
    (raise-arguments-error 'prepare-workflow-request
                           "invalid release identity"
                           "errors" (release-request-errors request)))
  (define candidate-id (release-candidate-identity request))
  (hasheq 'schema 1
          'model "odra-release-workflow-request"
          'candidate_id candidate-id
          'request_sha256 candidate-id
          'adapter_commit (workflow-request-input-adapter-commit input)
          'observed_at (workflow-request-input-observed-at input)
          'request (release-request->jsexpr request)))

(module+ main
  (define mode #f)
  (define version #f)
  (define source-commit #f)
  (define source-date-epoch #f)
  (define publish-confirmation "")
  (define export-policy #f)
  (define build-environment #f)
  (define adapter-commit #f)
  (define observed-at #f)
  (define candidate-store-root #f)
  (define output #f)
  (define forgejo-output #f)
  (command-line
   #:program "release-workflow-request.rkt"
   #:once-each
   [("--mode") value "candidate or publish"
                      (set! mode (string->symbol value))]
   [("--version") value "Canonical release version" (set! version value)]
   [("--source-commit") value "Exact canonical source commit"
                              (set! source-commit value)]
   [("--source-date-epoch") value "Canonical source timestamp"
                                  (set! source-date-epoch
                                        (string->number value))]
   [("--publish-confirmation") value "Explicit publish confirmation"
                                      (set! publish-confirmation value)]
   [("--export-policy") path "Public source export policy"
                             (set! export-policy path)]
   [("--build-environment") path "Linux build environment manifest"
                                  (set! build-environment path)]
   [("--adapter-commit") value "Exact workflow adapter commit"
                               (set! adapter-commit value)]
   [("--observed-at") value "RFC3339 UTC observation timestamp"
                            (set! observed-at value)]
   [("--candidate-store") path "Private candidate store root"
                                (set! candidate-store-root path)]
   [("--output") path "Canonical request output" (set! output path)]
   [("--forgejo-output") path "Forgejo output file"
                               (set! forgejo-output path)])
  (unless (and mode version source-commit source-date-epoch export-policy
               build-environment adapter-commit observed-at
               candidate-store-root output forgejo-output)
    (raise-user-error 'release-workflow-request
                      "all request, store, output, and Forgejo output arguments are required"))
  (define prepared
    (prepare-workflow-request
     (workflow-request-input mode version source-commit source-date-epoch
                             publish-confirmation export-policy
                             build-environment adapter-commit observed-at)))
  (define store (open-candidate-store candidate-store-root))
  (void
   (initialize-candidate! store
                          (hash-ref prepared 'candidate_id)
                          version
                          (hash-ref prepared 'request_sha256)
                          observed-at))
  (make-parent-directory* output)
  (call-with-output-file output
    #:exists 'truncate/replace
    (lambda (port)
      (write-bytes (canonical-json-bytes prepared) port)
      (newline port)))
  (call-with-output-file forgejo-output
    #:exists 'append
    (lambda (port)
      (for ([entry (in-list
                    (list
                     (cons "adapter_commit" adapter-commit)
                     (cons "candidate_id" (hash-ref prepared 'candidate_id))
                     (cons "mode" (symbol->string mode))
                     (cons "source_commit" source-commit)
                     (cons "source_date_epoch"
                           (number->string source-date-epoch))
                     (cons "version" version)))])
        (fprintf port "~a=~a\n" (car entry) (cdr entry)))))
  (printf "release-workflow-request: valid candidate=~a mode=~a\n"
          (hash-ref prepared 'candidate_id)
          mode))
