#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require json
         racket/file
         racket/list
         racket/path
         racket/string)

(provide (struct-out guide-candidate-request)
         (struct-out guide-candidate-plan)
         (struct-out guide-candidate-evidence)
         guide-candidate-request-errors
         prepare-guide-candidate-plan
         read-guide-candidate-evidence
         guide-publish-command)

(struct guide-candidate-request
  (guide-repository
   snapshot-repository
   snapshot-repository-identity
   snapshot-commit
   snapshot-tree
   canonical-source-commit
   version
   latest-binary-version
   channel
   output
   spore-executable)
  #:transparent)

(struct guide-candidate-plan
  (request command output)
  #:transparent)

(struct guide-candidate-evidence
  (candidate-id
   snapshot-commit
   snapshot-tree
   canonical-source-commit
   source-manifest-sha256
   projection-manifest-sha256
   site-tree-sha256)
  #:transparent)

(define commit-pattern #px"^[0-9a-f]{40}$")
(define digest-pattern #px"^[0-9a-f]{64}$")
(define semver-pattern
  #px"^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$")
(define repository-pattern
  #px"^[a-z0-9][a-z0-9._-]*/[a-z0-9][a-z0-9._-]*$")

(define (matches? pattern value)
  (and (string? value) (regexp-match? pattern value)))

(define (complete-directory value)
  (and (path-string? value) (path->complete-path value)))

(define (path-string->string value)
  (if (path? value) (path->string value) value))

(define (guide-candidate-request-errors request)
  (define guide
    (complete-directory (guide-candidate-request-guide-repository request)))
  (define snapshot
    (complete-directory (guide-candidate-request-snapshot-repository request)))
  (define output
    (and (path-string? (guide-candidate-request-output request))
         (path->complete-path (guide-candidate-request-output request))))
  (append
   (if (and guide
            (directory-exists? guide)
            (file-exists?
             (build-path guide "scripts" "prepare-release-guide.sh")))
       '()
       '("guide repository must expose prepare-release-guide.sh"))
   (if (and snapshot (directory-exists? snapshot))
       '()
       '("snapshot repository must be an available directory"))
   (if (matches? repository-pattern
                 (guide-candidate-request-snapshot-repository-identity request))
       '()
       '("snapshot repository identity must use owner/name form"))
   (if (matches? commit-pattern
                 (guide-candidate-request-snapshot-commit request))
       '()
       '("snapshot commit must be a full lowercase Git object ID"))
   (if (matches? commit-pattern
                 (guide-candidate-request-snapshot-tree request))
       '()
       '("snapshot tree must be a full lowercase Git object ID"))
   (if (matches? commit-pattern
                 (guide-candidate-request-canonical-source-commit request))
       '()
       '("canonical source commit must be a full lowercase Git object ID"))
   (if (matches? semver-pattern (guide-candidate-request-version request))
       '()
       '("release version must use canonical MAJOR.MINOR.PATCH form"))
   (if (matches? semver-pattern
                 (guide-candidate-request-latest-binary-version request))
       '()
       '("latest binary version must use canonical MAJOR.MINOR.PATCH form"))
   (if (member (guide-candidate-request-channel request) '(stable development))
       '()
       '("guide channel must be stable or development"))
   (if output '() '("candidate output must be a path"))
   (if (and (path-string? (guide-candidate-request-spore-executable request))
            (not (string=?
                  (path-string->string
                   (guide-candidate-request-spore-executable request))
                  "")))
       '()
       '("Spore executable must be a non-empty path"))))

(define (prepare-guide-candidate-plan request)
  (define errors (guide-candidate-request-errors request))
  (unless (null? errors)
    (raise-arguments-error 'prepare-guide-candidate-plan
                           "invalid User Guide candidate request"
                           "errors" errors))
  (define guide
    (path->complete-path (guide-candidate-request-guide-repository request)))
  (define output
    (path->complete-path (guide-candidate-request-output request)))
  (define command
    (list "bash"
          (path->string
           (build-path guide "scripts" "prepare-release-guide.sh"))
          "candidate"
          "--snapshot-repository"
          (path->string
           (path->complete-path
            (guide-candidate-request-snapshot-repository request)))
          "--snapshot-identity"
          (guide-candidate-request-snapshot-repository-identity request)
          "--snapshot-ref"
          (guide-candidate-request-snapshot-commit request)
          "--version"
          (guide-candidate-request-version request)
          "--latest-binary-version"
          (guide-candidate-request-latest-binary-version request)
          "--channel"
          (symbol->string (guide-candidate-request-channel request))
          "--output"
          (path->string output)
          "--spore-executable"
          (path-string->string
           (guide-candidate-request-spore-executable request))))
  (guide-candidate-plan request command output))

(define (required-hash table key owner)
  (define value (and (hash? table) (hash-ref table key #f)))
  (or value
      (raise-user-error 'read-guide-candidate-evidence
                        "candidate manifest lacks ~a.~a"
                        owner key)))

(define (read-guide-candidate-evidence plan)
  (define request (guide-candidate-plan-request plan))
  (define manifest-path
    (build-path (guide-candidate-plan-output plan) "candidate-manifest.json"))
  (unless (file-exists? manifest-path)
    (raise-user-error 'read-guide-candidate-evidence
                      "candidate manifest is unavailable: ~a"
                      manifest-path))
  (define manifest (call-with-input-file manifest-path read-json))
  (define release (required-hash manifest 'release "manifest"))
  (define snapshot (required-hash manifest 'snapshot "manifest"))
  (define canonical (required-hash manifest 'canonical_source "manifest"))
  (define site (required-hash manifest 'site "manifest"))
  (define candidate-id (required-hash manifest 'candidate_id "manifest"))
  (define source-sha (required-hash manifest 'source_manifest_sha256 "manifest"))
  (define projection-sha
    (required-hash manifest 'projection_manifest_sha256 "manifest"))
  (define site-sha (required-hash site 'tree_sha256 "site"))
  (unless
      (and (equal? (hash-ref manifest 'schema_version #f) 1)
           (equal? (hash-ref manifest 'model #f) "odra-user-guide-candidate")
           (matches? digest-pattern candidate-id)
           (equal? (required-hash release 'version "release")
                   (guide-candidate-request-version request))
           (equal? (required-hash release 'status "release") "candidate")
           (equal? (required-hash snapshot 'repository "snapshot")
                   (guide-candidate-request-snapshot-repository-identity request))
           (equal? (required-hash snapshot 'commit "snapshot")
                   (guide-candidate-request-snapshot-commit request))
           (equal? (required-hash snapshot 'tree "snapshot")
                   (guide-candidate-request-snapshot-tree request))
           (equal? (required-hash canonical 'commit "canonical_source")
                   (guide-candidate-request-canonical-source-commit request))
           (andmap (lambda (value) (matches? digest-pattern value))
                   (list source-sha projection-sha site-sha)))
    (raise-user-error 'read-guide-candidate-evidence
                      "candidate evidence differs from the requested snapshot"))
  (guide-candidate-evidence
   candidate-id
   (hash-ref snapshot 'commit)
   (hash-ref snapshot 'tree)
   (hash-ref canonical 'commit)
   source-sha
   projection-sha
   site-sha))

(define (guide-publish-command plan evidence)
  (define guide
    (path->complete-path
     (guide-candidate-request-guide-repository
      (guide-candidate-plan-request plan))))
  (list "bash"
        (path->string (build-path guide "scripts" "prepare-release-guide.sh"))
        "publish"
        "--candidate"
        (path->string (guide-candidate-plan-output plan))
        "--candidate-id"
        (guide-candidate-evidence-candidate-id evidence)
        "--destination"
        (path->string guide)))
