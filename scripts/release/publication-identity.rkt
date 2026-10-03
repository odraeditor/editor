#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require json
         (except-in openssl/sha1 sha1)
         (only-in file/sha1 bytes->hex-string)
         racket/list
         racket/path
         racket/port
         racket/string)

(provide publication-manifest-schema
         publication-platform
         maximum-source-date-epoch
         publication-phases
         phase-states
         (struct-out release-request)
         (struct-out snapshot-identity)
         (struct-out artifact-identity)
         (struct-out phase-record)
         (struct-out publication-manifest)
         release-request-errors
         release-request-valid?
         snapshot-identity-errors
         snapshot-identity-valid?
         artifact-identity-errors
         artifact-identity-valid?
         phase-record-errors
         phase-record-valid?
         publication-manifest-errors
         publication-manifest-valid?
         release-tag
         snapshot-candidate-ref
         release-request->jsexpr
         release-request->identity-jsexpr
         release-candidate-identity
         snapshot-identity->jsexpr
         artifact-identity->jsexpr
         phase-record->jsexpr
         publication-manifest->jsexpr
         canonical-json-bytes
         canonical-json-string
         canonical-jsexpr-sha256)

(define publication-manifest-schema 1)
(define publication-platform "linux-x86_64")
(define maximum-source-date-epoch (sub1 (expt 2 63)))

(define publication-phases
  '(request
    preflight
    export
    snapshot-transfer
    snapshot-validation
    bundle-build
    bundle-validation
    guide-preparation
    candidate-retention
    source-publication
    bundle-publication
    guide-publication
    public-verification))

(define phase-states '(pending running passed failed unavailable))

(define semver-pattern
  #px"^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$")
(define commit-pattern #px"^[0-9a-f]{40}$")
(define digest-pattern #px"^[0-9a-f]{64}$")
(define repository-pattern
  #px"^[a-z0-9][a-z0-9._-]*/[a-z0-9][a-z0-9._-]*$")
(define policy-version-pattern
  #px"^[a-z0-9][a-z0-9._-]*$")
(define relative-path-pattern #px"^[^/][^[:cntrl:]]*$")
(define timestamp-pattern
  #px"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\\.[0-9]+)?(?:Z|[+-][0-9]{2}:[0-9]{2})$")

(struct release-request
  (mode
   version
   source-repository
   source-commit
   source-date-epoch
   snapshot-repository
   platforms
   export-policy-version
   export-policy-sha256
   build-environment-sha256
   documentation-contract-version)
  #:transparent)

(struct snapshot-identity
  (candidate-ref
   snapshot-commit
   snapshot-tree
   inventory-sha256
   export-policy-sha256
   release-tag)
  #:transparent)

(struct artifact-identity
  (name media-type byte-size sha256 phase relative-path)
  #:transparent)

(struct phase-record
  (phase
   state
   input-sha256
   attempt
   started-at
   finished-at
   evidence
   failure)
  #:transparent)

(struct publication-manifest
  (request candidate-id snapshot artifacts phases publication)
  #:transparent)

(define (matches? pattern value)
  (and (string? value) (regexp-match? pattern value)))

(define (canonical-semver? value)
  (matches? semver-pattern value))

(define (full-commit? value)
  (matches? commit-pattern value))

(define (digest? value)
  (matches? digest-pattern value))

(define (repository-identity? value)
  (matches? repository-pattern value))

(define (source-date-epoch? value)
  (and (exact-nonnegative-integer? value)
       (<= value maximum-source-date-epoch)))

(define (safe-relative-path? value)
  (and (matches? relative-path-pattern value)
       (relative-path? (string->path value))
       (not (member ".." (string-split value "/")))
       (not (string-contains? value "\\"))))

(define (timestamp? value)
  (matches? timestamp-pattern value))

(define (release-tag request)
  (unless (release-request-valid? request)
    (raise-arguments-error 'release-tag
                           "invalid release request"
                           "errors" (release-request-errors request)))
  (string-append "v" (release-request-version request)))

(define (snapshot-candidate-ref request)
  (string-append "refs/heads/candidates/" (release-tag request)))

(define (release-request-errors request)
  (append
   (if (member (release-request-mode request) '(candidate publish))
       '()
       '("mode must be candidate or publish"))
   (if (canonical-semver? (release-request-version request))
       '()
       '("version must use canonical MAJOR.MINOR.PATCH form"))
   (if (repository-identity? (release-request-source-repository request))
       '()
       '("source repository must use a canonical owner/name identity"))
   (if (full-commit? (release-request-source-commit request))
       '()
       '("source commit must be a full lowercase hexadecimal commit"))
   (if (source-date-epoch? (release-request-source-date-epoch request))
       '()
       '("source date epoch must be an unsigned 63-bit integer"))
   (if (repository-identity? (release-request-snapshot-repository request))
       '()
       '("snapshot repository must use a canonical owner/name identity"))
   (if (equal? (release-request-platforms request)
               (list publication-platform))
       '()
       (list (format "platforms must contain exactly ~a"
                     publication-platform)))
   (if (matches? policy-version-pattern
                 (release-request-export-policy-version request))
       '()
       '("export policy version must be a stable identifier"))
   (if (digest? (release-request-export-policy-sha256 request))
       '()
       '("export policy digest must be a lowercase SHA-256 digest"))
   (if (digest? (release-request-build-environment-sha256 request))
       '()
       '("build environment digest must be a lowercase SHA-256 digest"))
   (if (matches? policy-version-pattern
                 (release-request-documentation-contract-version request))
       '()
       '("documentation contract version must be a stable identifier"))))

(define (release-request-valid? request)
  (null? (release-request-errors request)))

(define (snapshot-identity-errors identity)
  (append
   (if (and (string? (snapshot-identity-candidate-ref identity))
            (regexp-match?
             #px"^refs/heads/candidates/v(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$"
             (snapshot-identity-candidate-ref identity)))
       '()
       '("candidate ref must use refs/heads/candidates/vMAJOR.MINOR.PATCH"))
   (if (full-commit? (snapshot-identity-snapshot-commit identity))
       '()
       '("snapshot commit must be a full lowercase hexadecimal commit"))
   (if (full-commit? (snapshot-identity-snapshot-tree identity))
       '()
       '("snapshot tree must be a full lowercase hexadecimal object ID"))
   (if (digest? (snapshot-identity-inventory-sha256 identity))
       '()
       '("inventory digest must be a lowercase SHA-256 digest"))
   (if (digest? (snapshot-identity-export-policy-sha256 identity))
       '()
       '("snapshot export policy digest must be a lowercase SHA-256 digest"))
   (if (or (not (snapshot-identity-release-tag identity))
           (and (string? (snapshot-identity-release-tag identity))
                (regexp-match?
                 #px"^v(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$"
                 (snapshot-identity-release-tag identity))))
       '()
       '("release tag must be absent or use canonical vMAJOR.MINOR.PATCH form"))))

(define (snapshot-identity-valid? identity)
  (null? (snapshot-identity-errors identity)))

(define (artifact-identity-errors artifact)
  (append
   (if (and (string? (artifact-identity-name artifact))
            (not (string=? (artifact-identity-name artifact) "")))
       '()
       '("artifact name must be non-empty"))
   (if (and (string? (artifact-identity-media-type artifact))
            (regexp-match? #px"^[a-z0-9!#$&^_.+-]+/[a-z0-9!#$&^_.+-]+$"
                           (artifact-identity-media-type artifact)))
       '()
       '("artifact media type must be canonical"))
   (if (exact-nonnegative-integer? (artifact-identity-byte-size artifact))
       '()
       '("artifact byte size must be a non-negative integer"))
   (if (digest? (artifact-identity-sha256 artifact))
       '()
       '("artifact digest must be a lowercase SHA-256 digest"))
   (if (member (artifact-identity-phase artifact) publication-phases)
       '()
       '("artifact phase must be a publication phase"))
   (if (safe-relative-path? (artifact-identity-relative-path artifact))
       '()
       '("artifact path must be a safe normalized relative path"))))

(define (artifact-identity-valid? artifact)
  (null? (artifact-identity-errors artifact)))

(define (phase-record-errors record)
  (append
   (if (member (phase-record-phase record) publication-phases)
       '()
       '("phase must be a publication phase"))
   (if (member (phase-record-state record) phase-states)
       '()
       '("state must be a publication phase state"))
   (if (digest? (phase-record-input-sha256 record))
       '()
       '("phase input digest must be a lowercase SHA-256 digest"))
   (if (exact-positive-integer? (phase-record-attempt record))
       '()
       '("phase attempt must be a positive integer"))
   (if (timestamp? (phase-record-started-at record))
       '()
       '("phase start must be an RFC3339 timestamp"))
   (if (if (member (phase-record-state record) '(passed failed unavailable))
           (timestamp? (phase-record-finished-at record))
           (or (not (phase-record-finished-at record))
               (timestamp? (phase-record-finished-at record))))
       '()
       '("terminal phases require an RFC3339 finish timestamp"))
   (if (and (list? (phase-record-evidence record))
            (andmap artifact-identity-valid? (phase-record-evidence record)))
       '()
       '("phase evidence must contain valid artifact identities"))
   (if (if (eq? (phase-record-state record) 'failed)
           (hash? (phase-record-failure record))
           (not (phase-record-failure record)))
       '()
       '("only failed phases carry a structured failure"))))

(define (phase-record-valid? record)
  (null? (phase-record-errors record)))

(define (write-canonical-json-value value output)
  (cond
    [(hash? value)
     (display #\{ output)
     (define keys
       (sort (hash-keys value)
             string<?
             #:key (lambda (key)
                     (if (symbol? key) (symbol->string key) key))))
     (for ([key (in-list keys)]
           [index (in-naturals)])
       (unless (zero? index) (display #\, output))
       (write-json (if (symbol? key) (symbol->string key) key) output)
       (display #\: output)
       (write-canonical-json-value (hash-ref value key) output))
     (display #\} output)]
    [(or (list? value) (vector? value))
     (display #\[ output)
     (for ([item (in-sequences value)]
           [index (in-naturals)])
       (unless (zero? index) (display #\, output))
       (write-canonical-json-value item output))
     (display #\] output)]
    [else (write-json value output)]))

(define (canonical-json-bytes value)
  (call-with-output-bytes
   (lambda (output)
     (write-canonical-json-value value output))))

(define (canonical-json-string value)
  (bytes->string/utf-8 (canonical-json-bytes value)))

(define (canonical-jsexpr-sha256 value)
  (bytes->hex-string
   (sha256-bytes (open-input-bytes (canonical-json-bytes value)))))

(define (release-request->identity-jsexpr request)
  (unless (release-request-valid? request)
    (raise-arguments-error 'release-request->identity-jsexpr
                           "invalid release request"
                           "errors" (release-request-errors request)))
  (hasheq
   'schema publication-manifest-schema
   'version (release-request-version request)
   'source
   (hasheq 'repository (release-request-source-repository request)
           'commit (release-request-source-commit request)
           'source_date_epoch (release-request-source-date-epoch request))
   'snapshot_repository (release-request-snapshot-repository request)
   'platforms (release-request-platforms request)
   'export_policy
   (hasheq 'version (release-request-export-policy-version request)
           'sha256 (release-request-export-policy-sha256 request))
   'build_environment_sha256
   (release-request-build-environment-sha256 request)
   'documentation_contract_version
   (release-request-documentation-contract-version request)))

(define (release-candidate-identity request)
  (canonical-jsexpr-sha256 (release-request->identity-jsexpr request)))

(define (release-request->jsexpr request)
  (hash-set (release-request->identity-jsexpr request)
            'mode
            (symbol->string (release-request-mode request))))

(define (snapshot-identity->jsexpr identity)
  (unless (snapshot-identity-valid? identity)
    (raise-arguments-error 'snapshot-identity->jsexpr
                           "invalid snapshot identity"
                           "errors" (snapshot-identity-errors identity)))
  (hasheq 'candidate_ref (snapshot-identity-candidate-ref identity)
          'commit (snapshot-identity-snapshot-commit identity)
          'tree (snapshot-identity-snapshot-tree identity)
          'inventory_sha256 (snapshot-identity-inventory-sha256 identity)
          'export_policy_sha256
          (snapshot-identity-export-policy-sha256 identity)
          'release_tag (or (snapshot-identity-release-tag identity) #f)))

(define (artifact-identity->jsexpr artifact)
  (unless (artifact-identity-valid? artifact)
    (raise-arguments-error 'artifact-identity->jsexpr
                           "invalid artifact identity"
                           "errors" (artifact-identity-errors artifact)))
  (hasheq 'name (artifact-identity-name artifact)
          'media_type (artifact-identity-media-type artifact)
          'byte_size (artifact-identity-byte-size artifact)
          'sha256 (artifact-identity-sha256 artifact)
          'phase (symbol->string (artifact-identity-phase artifact))
          'path (artifact-identity-relative-path artifact)))

(define (phase-record->jsexpr record)
  (unless (phase-record-valid? record)
    (raise-arguments-error 'phase-record->jsexpr
                           "invalid phase record"
                           "errors" (phase-record-errors record)))
  (hasheq 'phase (symbol->string (phase-record-phase record))
          'state (symbol->string (phase-record-state record))
          'input_sha256 (phase-record-input-sha256 record)
          'attempt (phase-record-attempt record)
          'started_at (phase-record-started-at record)
          'finished_at (or (phase-record-finished-at record) #f)
          'evidence (map artifact-identity->jsexpr
                         (phase-record-evidence record))
          'failure (or (phase-record-failure record) #f)))

(define forbidden-field-pattern
  #px"(?i:token|secret|authorization|credential|password|private[_-]?key)")
(define credential-url-pattern #px"^[a-z][a-z0-9+.-]*://[^/@[:space:]]+@")
(define sensitive-query-pattern
  #px"(?i:[?&](?:token|access_token|key|password|signature)=)")

(define (manifest-sensitive-errors value [path "manifest"])
  (cond
    [(hash? value)
     (append*
      (for/list ([(key item) (in-hash value)])
        (define name (if (symbol? key) (symbol->string key) key))
        (define child-path (format "~a.~a" path name))
        (append
         (if (regexp-match? forbidden-field-pattern name)
             (list (format "~a uses a credential-bearing field name" child-path))
             '())
         (manifest-sensitive-errors item child-path))))]
    [(or (list? value) (vector? value))
     (append*
      (for/list ([item (in-sequences value)]
                 [index (in-naturals)])
        (manifest-sensitive-errors item (format "~a[~a]" path index))))]
    [(string? value)
     (append
      (if (regexp-match? credential-url-pattern value)
          (list (format "~a contains URL user information" path))
          '())
      (if (regexp-match? sensitive-query-pattern value)
          (list (format "~a contains a sensitive URL query" path))
          '()))]
    [else '()]))

(define (duplicates values)
  (remove-duplicates
   (for/list ([value (in-list values)]
              #:when (> (count (lambda (candidate) (equal? candidate value))
                               values)
                        1))
     value)))

(define (publication-manifest-errors manifest)
  (define request (publication-manifest-request manifest))
  (define artifacts (publication-manifest-artifacts manifest))
  (define phases (publication-manifest-phases manifest))
  (define valid-artifacts?
    (and (list? artifacts) (andmap artifact-identity-valid? artifacts)))
  (define valid-phases?
    (and (list? phases) (andmap phase-record-valid? phases)))
  (append
   (release-request-errors request)
   (if (equal? (publication-manifest-candidate-id manifest)
               (and (release-request-valid? request)
                    (release-candidate-identity request)))
       '()
       '("candidate identity differs from the release request"))
   (if (or (not (publication-manifest-snapshot manifest))
           (snapshot-identity-valid? (publication-manifest-snapshot manifest)))
       '()
       '("snapshot identity is invalid"))
   (if valid-artifacts?
       '()
       '("artifacts must contain valid artifact identities"))
   (if (or (not valid-artifacts?)
           (null? (duplicates (map artifact-identity-name artifacts))))
       '()
       '("artifact names must be unique"))
   (if (or (not valid-artifacts?)
           (null? (duplicates
                   (map artifact-identity-relative-path artifacts))))
       '()
       '("artifact paths must be unique"))
   (if valid-phases?
       '()
       '("phases must contain valid phase records"))
   (if (or (not valid-phases?)
           (null? (duplicates (map phase-record-phase phases))))
       '()
       '("a manifest contains at most one effective record per phase"))
   (if (hash? (publication-manifest-publication manifest))
       '()
       '("publication results must be a hash"))
   (manifest-sensitive-errors
    (publication-manifest-publication manifest)
    "manifest.publication")
   (if valid-phases?
       (append*
        (for/list ([record (in-list phases)])
          (manifest-sensitive-errors
           (or (phase-record-failure record) (hasheq))
           (format "manifest.phases.~a.failure"
                   (phase-record-phase record)))))
       '())))

(define (publication-manifest-valid? manifest)
  (null? (publication-manifest-errors manifest)))

(define (publication-manifest->jsexpr manifest)
  (unless (publication-manifest-valid? manifest)
    (raise-arguments-error 'publication-manifest->jsexpr
                           "invalid publication manifest"
                           "errors" (publication-manifest-errors manifest)))
  (define sorted-artifacts
    (sort (publication-manifest-artifacts manifest)
          string<?
          #:key artifact-identity-name))
  (define sorted-phases
    (sort (publication-manifest-phases manifest)
          <
          #:key (lambda (record)
                  (index-of publication-phases (phase-record-phase record)))))
  (hasheq 'schema publication-manifest-schema
          'candidate_id (publication-manifest-candidate-id manifest)
          'request (release-request->jsexpr
                    (publication-manifest-request manifest))
          'snapshot
          (if (publication-manifest-snapshot manifest)
              (snapshot-identity->jsexpr
               (publication-manifest-snapshot manifest))
              #f)
          'artifacts (map artifact-identity->jsexpr sorted-artifacts)
          'phases (map phase-record->jsexpr sorted-phases)
          'publication (publication-manifest-publication manifest)))
