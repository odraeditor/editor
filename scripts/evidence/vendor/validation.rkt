#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.

(require json
         racket/contract
         racket/file
         racket/list
         racket/match
         racket/path
         racket/port
         racket/set
         racket/string
         "canonical-json.rkt")

(provide
 (contract-out
  [struct validation-issue
    ([path string?]
     [code symbol?]
     [message string?])]
  [validate-run (-> any/c (listof validation-issue?))]
  [validate-step (-> any/c (listof validation-issue?))]
  [validate-bundle-manifest (-> any/c (listof validation-issue?))]
  [validate-subject-registry (-> any/c (listof validation-issue?))]
  [validate-workflow-registry
   (-> any/c any/c (listof validation-issue?))]
  [validate-bundle-directory
   (-> path-string? path-string? path-string? (listof validation-issue?))]))

(struct validation-issue (path code message) #:transparent)

(define sha256-pattern #px"^[0-9a-f]{64}$")
(define git-object-pattern #px"^[0-9a-f]{40,64}$")
(define identity-pattern #px"^[A-Za-z0-9][A-Za-z0-9._:/@+\u002d]*$")
(define namespaced-identity-pattern #px"^[a-z0-9][a-z0-9._/\u002d]*$")
(define timestamp-pattern
  #px"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\\.[0-9]+)?Z$")

(define run-required
  '(schema run_id attempt_id subject_id workflow_id workflow_version
           workflow_digest source execution_input_digest environment producer
           started_at finished_at duration_ms outcome evidence_state
           steps_digest artifacts))

(define run-allowed (list->seteq run-required))

(define step-required
  '(ordinal step_id definition_version operation_class input_digest
            operation_digest outcome reuse artifacts))

(define step-allowed
  (list->seteq
   (append step-required
           '(parent_step_id outcome_reason started_offset_ms duration_ms
                            exit_code termination
                            resource_observation failure))))

(define outcomes
  '(passed failed timed-out crashed cancelled skipped unavailable))

(define (issue path code message)
  (validation-issue path code message))

(define (field-path base key)
  (if (string=? base "$" )
      (format "$.~a" key)
      (format "~a.~a" base key)))

(define (index-path base index)
  (format "~a[~a]" base index))

(define (object? value)
  (and (hash? value)
       (for/and ([key (in-hash-keys value)])
         (symbol? key))))

(define (required-issues value path fields)
  (if (object? value)
      (for/list ([field (in-list fields)]
                 #:unless (hash-has-key? value field))
        (issue (field-path path field)
               'required
               "required field is missing"))
      (list (issue path 'type "expected a JSON object"))))

(define (unknown-field-issues value path allowed)
  (if (object? value)
      (for/list ([field (in-hash-keys value)]
                 #:unless (set-member? allowed field))
        (issue (field-path path field)
               'unknown-field
               "field is not admitted by this schema version"))
      '()))

(define (value-issue value path predicate code message)
  (if (predicate value) '() (list (issue path code message))))

(define (hash-value value key [default #f])
  (if (and (hash? value) (hash-has-key? value key))
      (hash-ref value key)
      default))

(define (bounded-string? value maximum)
  (and (string? value)
       (positive? (string-length value))
       (<= (string-length value) maximum)))

(define (matching-string? pattern maximum)
  (lambda (value)
    (and (bounded-string? value maximum)
         (regexp-match? pattern value))))

(define sha256? (matching-string? sha256-pattern 64))
(define git-object? (matching-string? git-object-pattern 64))
(define identity? (matching-string? identity-pattern 160))
(define namespaced-identity?
  (matching-string? namespaced-identity-pattern 160))
(define timestamp? (matching-string? timestamp-pattern 40))

(define (nonnegative-integer? value)
  (and (exact-integer? value) (>= value 0)))

(define (positive-integer? value)
  (and (exact-integer? value) (positive? value)))

(define (enum? values)
  (lambda (value)
    (and (string? value)
         (member (string->symbol value) values)
         #t)))

(define (array? value maximum)
  (and (list? value) (<= (length value) maximum)))

(define (validate-source value path)
  (define required '(repository commit ref dirty))
  (define allowed (list->seteq (append required '(tree patch_digest))))
  (append
   (required-issues value path required)
   (unknown-field-issues value path allowed)
   (if (object? value)
       (append
        (value-issue (hash-value value 'repository)
                     (field-path path 'repository)
                     namespaced-identity?
                     'format
                     "expected a namespaced repository identity")
        (value-issue (hash-value value 'commit)
                     (field-path path 'commit)
                     git-object?
                     'format
                     "expected a lowercase Git object identity")
        (value-issue (hash-value value 'ref)
                     (field-path path 'ref)
                     (lambda (item) (bounded-string? item 256))
                     'format
                     "expected a bounded source ref")
        (value-issue (hash-value value 'dirty)
                     (field-path path 'dirty)
                     boolean?
                     'type
                     "expected a boolean")
        (if (hash-has-key? value 'tree)
            (value-issue (hash-ref value 'tree)
                         (field-path path 'tree)
                         git-object?
                         'format
                         "expected a lowercase Git object identity")
            '())
        (cond
          [(eq? (hash-value value 'dirty) #t)
           (value-issue (hash-value value 'patch_digest)
                        (field-path path 'patch_digest)
                        sha256?
                        'required
                        "dirty source requires a patch digest")]
          [(hash-has-key? value 'patch_digest)
           (list (issue (field-path path 'patch_digest)
                        'forbidden
                        "clean source cannot carry a patch digest"))]
          [else '()]))
       '())))

(define (validate-toolchains value path)
  (cond
    [(not (object? value))
     (list (issue path 'type "expected a JSON object"))]
    [(or (zero? (hash-count value)) (> (hash-count value) 32))
     (list (issue path 'limit "toolchain count must be between 1 and 32"))]
    [else
     (append*
      (for/list ([(name version) (in-hash value)])
        (append
         (value-issue (symbol->string name)
                      (field-path path name)
                      identity?
                      'format
                      "expected a bounded toolchain identity")
         (value-issue version
                      (field-path path name)
                      (lambda (item) (bounded-string? item 160))
                      'format
                      "expected a bounded toolchain version"))))]))

(define (validate-environment value path)
  (define identity-fields
    '(platform architecture kernel_family cpu_capacity_class
               memory_capacity_class))
  (define allowed (list->seteq (append identity-fields '(toolchains))))
  (append
   (unknown-field-issues value path allowed)
   (if (object? value)
       (append
        (for/fold ([issues '()])
                  ([field (in-list identity-fields)])
          (if (hash-has-key? value field)
              (append issues
                      (value-issue (hash-ref value field)
                                   (field-path path field)
                                   identity?
                                   'format
                                   "expected a bounded environment identity"))
              issues))
        (if (hash-has-key? value 'toolchains)
            (validate-toolchains (hash-ref value 'toolchains)
                                 (field-path path 'toolchains))
            '()))
       '())))

(define (validate-producer value path)
  (define required '(kind identity version definition_digest limitations))
  (append
   (required-issues value path required)
   (unknown-field-issues value path (list->seteq required))
   (if (object? value)
       (append
        (value-issue (hash-value value 'kind)
                     (field-path path 'kind)
                     (enum? '(native forgejo-adapter))
                     'enum
                     "expected native or forgejo-adapter")
        (value-issue (hash-value value 'identity)
                     (field-path path 'identity)
                     namespaced-identity?
                     'format
                     "expected a namespaced producer identity")
        (value-issue (hash-value value 'version)
                     (field-path path 'version)
                     positive-integer?
                     'range
                     "expected a positive definition version")
        (value-issue (hash-value value 'definition_digest)
                     (field-path path 'definition_digest)
                     sha256?
                     'format
                     "expected a SHA-256 digest")
        (let ([limitations (hash-value value 'limitations)])
          (cond
            [(not (array? limitations 64))
             (list (issue (field-path path 'limitations)
                          'limit
                          "expected at most 64 limitation identities"))]
            [else
             (append*
              (for/list ([item (in-list limitations)]
                         [index (in-naturals)])
                (value-issue item
                             (index-path (field-path path 'limitations) index)
                             namespaced-identity?
                             'format
                             "expected a namespaced limitation identity")))])))
       '())))

(define (validate-artifact-reference value path)
  (define required '(artifact_id kind))
  (append
   (required-issues value path required)
   (unknown-field-issues value path (list->seteq required))
   (if (object? value)
       (append
        (value-issue (hash-value value 'artifact_id)
                     (field-path path 'artifact_id)
                     identity?
                     'format
                     "expected a bounded artifact identity")
        (value-issue (hash-value value 'kind)
                     (field-path path 'kind)
                     namespaced-identity?
                     'format
                     "expected a namespaced artifact kind"))
       '())))

(define (logical-storage-reference? value)
  (and (bounded-string? value 512)
       (regexp-match? #px"^[A-Za-z0-9][A-Za-z0-9._:/+\u002d]*$" value)
       (not (regexp-match? #px"://" value))
       (not (regexp-match? #px"(^|/)\\.\\.(/|$)" value))))

(define (validate-artifact value path)
  (define required
    '(artifact_id kind media_type size_bytes storage availability))
  (define allowed (list->seteq (append required '(sha256 retention_until))))
  (append
   (required-issues value path required)
   (unknown-field-issues value path allowed)
   (if (object? value)
       (append
        (value-issue (hash-value value 'artifact_id)
                     (field-path path 'artifact_id)
                     identity?
                     'format
                     "expected a bounded artifact identity")
        (value-issue (hash-value value 'kind)
                     (field-path path 'kind)
                     namespaced-identity?
                     'format
                     "expected a namespaced artifact kind")
        (value-issue (hash-value value 'media_type)
                     (field-path path 'media_type)
                     (lambda (item) (bounded-string? item 128))
                     'format
                     "expected a bounded media type")
        (value-issue (hash-value value 'size_bytes)
                     (field-path path 'size_bytes)
                     nonnegative-integer?
                     'range
                     "expected a non-negative artifact size")
        (value-issue (hash-value value 'availability)
                     (field-path path 'availability)
                     (enum? '(available expired missing quarantined))
                     'enum
                     "unsupported artifact availability")
        (let ([storage (hash-value value 'storage)])
          (define storage-path (field-path path 'storage))
          (define storage-required '(provider reference))
          (append
           (required-issues storage storage-path storage-required)
           (unknown-field-issues storage storage-path
                                 (list->seteq storage-required))
           (if (object? storage)
               (append
                (value-issue (hash-value storage 'provider)
                             (field-path storage-path 'provider)
                             namespaced-identity?
                             'format
                             "expected a logical storage provider")
                (value-issue (hash-value storage 'reference)
                             (field-path storage-path 'reference)
                             logical-storage-reference?
                             'privacy
                             "expected a non-credential logical storage reference"))
               '())))
        (if (equal? (hash-value value 'media_type)
                    "application/x-logical-reference")
            '()
            (value-issue (hash-value value 'sha256)
                         (field-path path 'sha256)
                         sha256?
                         'required
                         "byte artifact requires a SHA-256 digest"))
        (if (hash-has-key? value 'retention_until)
            (value-issue (hash-ref value 'retention_until)
                         (field-path path 'retention_until)
                         timestamp?
                         'format
                         "expected a UTC RFC3339 timestamp")
            '()))
       '())))

(define (validate-run value)
  (append
   (required-issues value "$" run-required)
   (unknown-field-issues value "$" run-allowed)
   (if (object? value)
       (append
        (value-issue (hash-value value 'schema)
                     "$.schema"
                     (lambda (item) (equal? item "odra-evidence/run/v1"))
                     'schema
                     "unsupported run schema")
        (for/fold ([issues '()])
                  ([field (in-list '(run_id workflow_digest
                                            execution_input_digest steps_digest))])
          (append issues
                  (value-issue (hash-value value field)
                               (field-path "$" field)
                               sha256?
                               'format
                               "expected a SHA-256 digest")))
        (for/fold ([issues '()])
                  ([field (in-list '(attempt_id))])
          (append issues
                  (value-issue (hash-value value field)
                               (field-path "$" field)
                               identity?
                               'format
                               "expected a bounded identity")))
        (for/fold ([issues '()])
                  ([field (in-list '(subject_id workflow_id))])
          (append issues
                  (value-issue (hash-value value field)
                               (field-path "$" field)
                               namespaced-identity?
                               'format
                               "expected a namespaced identity")))
        (value-issue (hash-value value 'workflow_version)
                     "$.workflow_version"
                     positive-integer?
                     'range
                     "expected a positive workflow version")
        (validate-source (hash-value value 'source) "$.source")
        (validate-environment (hash-value value 'environment) "$.environment")
        (validate-producer (hash-value value 'producer) "$.producer")
        (for/fold ([issues '()])
                  ([field (in-list '(started_at finished_at))])
          (append issues
                  (value-issue (hash-value value field)
                               (field-path "$" field)
                               timestamp?
                               'format
                               "expected a UTC RFC3339 timestamp")))
        (value-issue (hash-value value 'duration_ms)
                     "$.duration_ms"
                     nonnegative-integer?
                     'range
                     "expected a non-negative duration")
        (value-issue (hash-value value 'outcome)
                     "$.outcome"
                     (enum? outcomes)
                     'enum
                     "unsupported run outcome")
        (value-issue (hash-value value 'evidence_state)
                     "$.evidence_state"
                     (enum? '(complete partial rejected))
                     'enum
                     "unsupported evidence state")
        (let ([artifacts (hash-value value 'artifacts)])
          (if (array? artifacts 128)
              (append*
               (for/list ([artifact (in-list artifacts)]
                          [index (in-naturals)])
                 (validate-artifact
                  artifact
                  (index-path "$.artifacts" index))))
              (list (issue "$.artifacts"
                           'limit
                           "expected at most 128 artifact references"))))
        (if (and (hash-has-key? value 'run_id)
                 (sha256? (hash-ref value 'run_id)))
            (let ([expected
                   (jsexpr-sha256 (hash-remove value 'run_id))])
              (if (string=? expected (hash-ref value 'run_id))
                  '()
                  (list (issue "$.run_id"
                               'digest
                               "run identity does not match canonical envelope"))))
            '()))
       '())))

(define (validate-resource value path)
  (define fields
    '(wall_ms cpu_user_ms cpu_system_ms peak_rss_bytes io_read_bytes
             io_write_bytes processes_peak pressure))
  (append
   (if (object? value)
       '()
       (list (issue path 'type "expected a JSON object")))
   (unknown-field-issues value path (list->seteq fields))
   (if (object? value)
       (append
        (if (zero? (hash-count value))
            (list (issue path 'required "resource observation cannot be empty"))
            '())
        (for/fold ([issues '()])
                  ([field (in-list (remove 'pressure fields))])
          (if (hash-has-key? value field)
              (append issues
                      (value-issue (hash-ref value field)
                                   (field-path path field)
                                   nonnegative-integer?
                                   'range
                                   "expected a non-negative observation"))
              issues))
        (if (hash-has-key? value 'pressure)
            (let ([pressure (hash-ref value 'pressure)])
              (cond
                [(not (object? pressure))
                 (list (issue (field-path path 'pressure)
                              'type
                              "expected a JSON object"))]
                [(> (hash-count pressure) 12)
                 (list (issue (field-path path 'pressure)
                              'limit
                              "expected at most 12 pressure observations"))]
                [else
                 (append*
                  (for/list ([(name observation) (in-hash pressure)])
                    (value-issue observation
                                 (field-path (field-path path 'pressure) name)
                                 nonnegative-integer?
                                 'range
                                 "expected a non-negative pressure observation")))]))
            '()))
       '())))

(define (validate-reuse value path)
  (define allowed '(classification artifact_id input_digest reason))
  (define classification (hash-value value 'classification))
  (append
   (required-issues value path '(classification))
   (unknown-field-issues value path (list->seteq allowed))
   (if (object? value)
       (append
        (value-issue classification
                     (field-path path 'classification)
                     (enum? '(built reused missed not-applicable unknown))
                     'enum
                     "unsupported reuse classification")
        (if (member classification '("built" "reused" "missed"))
            (value-issue (hash-value value 'input_digest)
                         (field-path path 'input_digest)
                         sha256?
                         'required
                         "classification requires an input digest")
            '())
        (if (member classification '("missed" "unknown"))
            (value-issue (hash-value value 'reason)
                         (field-path path 'reason)
                         namespaced-identity?
                         'required
                         "classification requires a reason")
            '()))
       '())))

(define (validate-failure value path)
  (define required '(category fingerprint summary diagnostics))
  (define allowed
    (list->seteq (append required '(first_failed_assertion reproducer))))
  (append
   (required-issues value path required)
   (unknown-field-issues value path allowed)
   (if (object? value)
       (append
        (value-issue (hash-value value 'category)
                     (field-path path 'category)
                     namespaced-identity?
                     'format
                     "expected a failure category")
        (value-issue (hash-value value 'fingerprint)
                     (field-path path 'fingerprint)
                     sha256?
                     'format
                     "expected a failure fingerprint")
        (value-issue (hash-value value 'summary)
                     (field-path path 'summary)
                     (lambda (item) (bounded-string? item 1024))
                     'format
                     "expected a bounded failure summary")
        (let ([diagnostics (hash-value value 'diagnostics)])
          (if (array? diagnostics 32)
              (append*
               (for/list ([diagnostic (in-list diagnostics)]
                          [index (in-naturals)])
                 (validate-artifact-reference
                  diagnostic
                  (index-path (field-path path 'diagnostics) index))))
              (list (issue (field-path path 'diagnostics)
                           'limit
                           "expected at most 32 diagnostic references"))))
        (if (hash-has-key? value 'reproducer)
            (validate-artifact-reference
             (hash-ref value 'reproducer)
             (field-path path 'reproducer))
            '()))
       '())))

(define (validate-step value)
  (define outcome (hash-value value 'outcome))
  (append
   (required-issues value "$" step-required)
   (unknown-field-issues value "$" step-allowed)
   (if (object? value)
       (append
        (value-issue (hash-value value 'ordinal)
                     "$.ordinal"
                     (lambda (item)
                       (and (nonnegative-integer? item) (<= item 4095)))
                     'range
                     "expected an ordinal between 0 and 4095")
        (value-issue (hash-value value 'step_id)
                     "$.step_id"
                     namespaced-identity?
                     'format
                     "expected a namespaced step identity")
        (value-issue (hash-value value 'definition_version)
                     "$.definition_version"
                     positive-integer?
                     'range
                     "expected a positive definition version")
        (value-issue (hash-value value 'operation_class)
                     "$.operation_class"
                     (enum? '(command test build publication))
                     'enum
                     "unsupported operation class")
        (for/fold ([issues '()])
                  ([field (in-list '(input_digest operation_digest))])
          (append issues
                  (value-issue (hash-value value field)
                               (field-path "$" field)
                               sha256?
                               'format
                               "expected a SHA-256 digest")))
        (value-issue outcome
                     "$.outcome"
                     (enum? outcomes)
                     'enum
                     "unsupported step outcome")
        (for/fold ([issues '()])
                  ([field (in-list '(started_offset_ms duration_ms))])
          (if (hash-has-key? value field)
              (append issues
                      (value-issue (hash-ref value field)
                                   (field-path "$" field)
                                   nonnegative-integer?
                                   'range
                                   "expected a non-negative measurement"))
              issues))
        (cond
          [(member outcome '("skipped" "unavailable"))
           (value-issue (hash-value value 'outcome_reason)
                        "$.outcome_reason"
                        namespaced-identity?
                        'required
                        "outcome requires a structured reason")]
          [(hash-has-key? value 'outcome_reason)
           (list (issue "$.outcome_reason"
                        'forbidden
                        "outcome reason is admitted only for skipped or unavailable outcomes"))]
          [else '()])
        (validate-reuse (hash-value value 'reuse) "$.reuse")
        (if (hash-has-key? value 'resource_observation)
            (validate-resource (hash-ref value 'resource_observation)
                               "$.resource_observation")
            '())
        (cond
          [(member outcome '("failed" "timed-out" "crashed"))
           (validate-failure (hash-value value 'failure) "$.failure")]
          [(hash-has-key? value 'failure)
           (list (issue "$.failure"
                        'forbidden
                        "failure is admitted only for failed, timed-out, or crashed outcomes"))]
          [else '()])
        (cond
          [(member outcome '("timed-out" "crashed" "cancelled"))
           (if (object? (hash-value value 'termination))
               '()
               (list (issue "$.termination"
                            'required
                            "outcome requires termination detail")))]
          [else '()])
        (let ([artifacts (hash-value value 'artifacts)])
          (if (array? artifacts 64)
              (append*
               (for/list ([artifact (in-list artifacts)]
                          [index (in-naturals)])
                 (validate-artifact-reference
                  artifact
                  (index-path "$.artifacts" index))))
              (list (issue "$.artifacts"
                           'limit
                           "expected at most 64 artifact references"))))
        (if (and (hash-has-key? value 'parent_step_id)
                 (equal? (hash-ref value 'parent_step_id)
                         (hash-value value 'step_id)))
            (list (issue "$.parent_step_id"
                         'cycle
                         "step cannot be its own parent"))
            '()))
       '())))

(define (validate-subject-registry value)
  (define subjects (hash-value value 'subjects))
  (append
   (required-issues value "$" '(schema subjects))
   (unknown-field-issues value "$" (seteq 'schema 'subjects))
   (if (object? value)
       (append
        (value-issue (hash-value value 'schema)
                     "$.schema"
                     (lambda (item)
                       (equal? item "odra-evidence/subject-registry/v1"))
                     'schema
                     "unsupported subject registry schema")
        (cond
          [(not (and (list? subjects)
                     (positive? (length subjects))
                     (<= (length subjects) 1024)))
           (list (issue "$.subjects"
                        'limit
                        "expected between 1 and 1024 subjects"))]
          [else
           (define identities
             (for/list ([subject (in-list subjects)])
               (hash-value subject 'subject_id)))
           (append
            (append*
             (for/list ([subject (in-list subjects)]
                        [index (in-naturals)])
               (define path (index-path "$.subjects" index))
               (define required
                 '(subject_id kind source_repository default_branch
                              evidence_policy))
               (append
                (required-issues subject path required)
                (unknown-field-issues subject path (list->seteq required))
                (if (object? subject)
                    (append
                     (value-issue (hash-value subject 'subject_id)
                                  (field-path path 'subject_id)
                                  namespaced-identity?
                                  'format
                                  "expected a namespaced subject identity")
                     (value-issue (hash-value subject 'kind)
                                  (field-path path 'kind)
                                  (enum? '(product package tooling))
                                  'enum
                                  "unsupported subject kind")
                     (value-issue (hash-value subject 'source_repository)
                                  (field-path path 'source_repository)
                                  namespaced-identity?
                                  'format
                                  "expected a logical repository identity")
                     (value-issue (hash-value subject 'default_branch)
                                  (field-path path 'default_branch)
                                  (lambda (item) (bounded-string? item 160))
                                  'format
                                  "expected a bounded branch identity")
                     (value-issue (hash-value subject 'evidence_policy)
                                  (field-path path 'evidence_policy)
                                  namespaced-identity?
                                  'format
                                  "expected an evidence policy identity"))
                    '()))))
            (if (= (length identities)
                   (set-count (list->set identities)))
                '()
                (list (issue "$.subjects"
                             'duplicate
                             "subject identities must be unique"))))]))
       '())))

(define (validate-workflow-steps value path)
  (cond
    [(not (and (list? value)
               (positive? (length value))
               (<= (length value) 4096)))
     (list (issue path 'limit "expected between 1 and 4096 steps"))]
    [else
     (append
      (append*
       (for/list ([step (in-list value)]
                  [index (in-naturals)])
         (value-issue step
                      (index-path path index)
                      namespaced-identity?
                      'format
                      "expected a namespaced step identity")))
      (if (= (length value) (set-count (list->set value)))
          '()
          (list (issue path 'duplicate "step identities must be unique"))))]))

(define (validate-workflow-limits value path)
  (define required '(timeout_ms max_steps max_artifacts))
  (append
   (required-issues value path required)
   (unknown-field-issues value path (list->seteq required))
   (if (object? value)
       (append
        (value-issue (hash-value value 'timeout_ms)
                     (field-path path 'timeout_ms)
                     positive-integer?
                     'range
                     "expected a positive timeout")
        (for/fold ([issues '()])
                  ([field (in-list '(max_steps max_artifacts))])
          (append issues
                  (value-issue
                   (hash-value value field)
                   (field-path path field)
                   (lambda (item)
                     (and (nonnegative-integer? item) (<= item 4096)))
                   'range
                   "expected a bound between 0 and 4096"))))
       '())))

(define (validate-workflow-definition workflow path subjects)
  (define required
    '(subject_id workflow_id definition_version class steps limits))
  (append
   (required-issues workflow path required)
   (unknown-field-issues workflow path (list->seteq required))
   (if (object? workflow)
       (append
        (value-issue (hash-value workflow 'subject_id)
                     (field-path path 'subject_id)
                     (lambda (item)
                       (and (namespaced-identity? item)
                            (set-member? subjects item)))
                     'reference
                     "workflow subject is not registered")
        (value-issue (hash-value workflow 'workflow_id)
                     (field-path path 'workflow_id)
                     namespaced-identity?
                     'format
                     "expected a namespaced workflow identity")
        (value-issue (hash-value workflow 'definition_version)
                     (field-path path 'definition_version)
                     positive-integer?
                     'range
                     "expected a positive definition version")
        (value-issue (hash-value workflow 'class)
                     (field-path path 'class)
                     (enum? '(focused integration nightly release))
                     'enum
                     "unsupported workflow class")
        (validate-workflow-steps (hash-value workflow 'steps)
                                 (field-path path 'steps))
        (validate-workflow-limits (hash-value workflow 'limits)
                                  (field-path path 'limits)))
       '())))

(define (validate-workflow-registry value subject-registry)
  (define workflows (hash-value value 'workflows))
  (define subjects
    (for/set ([subject
               (in-list (or (hash-value subject-registry 'subjects) '()))])
      (hash-value subject 'subject_id)))
  (append
   (required-issues value "$" '(schema workflows))
   (unknown-field-issues value "$" (seteq 'schema 'workflows))
   (if (object? value)
       (append
        (value-issue (hash-value value 'schema)
                     "$.schema"
                     (lambda (item)
                       (equal? item "odra-evidence/workflow-registry/v1"))
                     'schema
                     "unsupported workflow registry schema")
        (cond
          [(not (and (list? workflows)
                     (positive? (length workflows))
                     (<= (length workflows) 4096)))
           (list (issue "$.workflows"
                        'limit
                        "expected between 1 and 4096 workflows"))]
          [else
           (define identities
             (for/list ([workflow (in-list workflows)])
               (hash-value workflow 'workflow_id)))
           (append
            (append*
             (for/list ([workflow (in-list workflows)]
                        [index (in-naturals)])
               (validate-workflow-definition
                workflow
                (index-path "$.workflows" index)
                subjects)))
            (if (= (length identities) (set-count (list->set identities)))
                '()
                (list (issue "$.workflows"
                             'duplicate
                             "workflow identities must be unique"))))]))
       '())))

(define (bundle-relative-path? value)
  (and (bounded-string? value 240)
       (or (member value '("run.json" "steps.jsonl" "summary.md"
                                       "assessment.md"))
           (regexp-match? #px"^failures/[A-Za-z0-9._/-]+$" value))
       (not (regexp-match? #px"(^|/)\\.\\.(/|$)" value))
       (not (regexp-match? #px"//" value))))

(define (validate-bundle-file value path)
  (define required '(path size_bytes sha256 role))
  (append
   (required-issues value path required)
   (unknown-field-issues value path (list->seteq required))
   (if (object? value)
       (append
        (value-issue (hash-value value 'path)
                     (field-path path 'path)
                     bundle-relative-path?
                     'path
                     "expected an admitted safe bundle-relative path")
        (value-issue (hash-value value 'size_bytes)
                     (field-path path 'size_bytes)
                     (lambda (item)
                       (and (nonnegative-integer? item) (<= item 1048576)))
                     'limit
                     "file size must not exceed 1 MiB")
        (value-issue (hash-value value 'sha256)
                     (field-path path 'sha256)
                     sha256?
                     'format
                     "expected a SHA-256 digest")
        (value-issue (hash-value value 'role)
                     (field-path path 'role)
                     (enum? '(run steps failure summary assessment))
                     'enum
                     "unsupported bundle file role"))
       '())))

(define (validate-bundle-limits value path)
  (define expected
    (hasheq 'bundle_bytes 8388608 'file_count 256 'step_count 4096))
  (append
   (required-issues value path (hash-keys expected))
   (unknown-field-issues value path (list->seteq (hash-keys expected)))
   (if (object? value)
       (append*
        (for/list ([(field expected-value) (in-hash expected)])
          (if (equal? (hash-value value field) expected-value)
              '()
              (list (issue (field-path path field)
                           'policy
                           "bundle limit does not match schema policy")))))
       '())))

(define (validate-bundle-manifest value)
  (define required '(schema files limits))
  (define files (hash-value value 'files))
  (append
   (required-issues value "$" required)
   (unknown-field-issues value "$" (list->seteq required))
   (if (object? value)
       (append
        (value-issue (hash-value value 'schema)
                     "$.schema"
                     (lambda (item) (equal? item "odra-evidence/bundle/v1"))
                     'schema
                     "unsupported bundle schema")
        (cond
          [(not (and (list? files)
                     (<= 2 (length files) 256)))
           (list (issue "$.files"
                        'limit
                        "expected between 2 and 256 bundle files"))]
          [else
           (define paths (map (lambda (file) (hash-value file 'path)) files))
           (define roles (map (lambda (file) (hash-value file 'role)) files))
           (append
            (append*
             (for/list ([file (in-list files)]
                        [index (in-naturals)])
               (validate-bundle-file file (index-path "$.files" index))))
            (if (= (length paths) (set-count (list->set paths)))
                '()
                (list (issue "$.files"
                             'duplicate
                             "bundle file paths must be unique")))
            (if (and (= (count (lambda (role) (equal? role "run")) roles) 1)
                     (= (count (lambda (role) (equal? role "steps")) roles) 1)
                     (member "run.json" paths)
                     (member "steps.jsonl" paths))
                '()
                (list (issue "$.files"
                             'required
                             "bundle requires one run and one steps file"))))])
        (validate-bundle-limits (hash-value value 'limits) "$.limits"))
       '())))

(define (read-json-lines path)
  (call-with-input-file path
    (lambda (input)
      (for/list ([line (in-lines input)]
                 #:unless (string=? line ""))
        (call-with-input-string line read-json)))))

(define (canonical-json-lines-bytes values)
  (apply bytes-append
         (for/list ([value (in-list values)])
           (bytes-append (jsexpr->canonical-bytes value) #"\n"))))

(define (validate-bundle-directory bundle-path subjects-path workflows-path)
  (define root (simple-form-path bundle-path))
  (define run-path (build-path root "run.json"))
  (define steps-path (build-path root "steps.jsonl"))
  (define manifest-path (build-path root "bundle.json"))
  (cond
    [(not (directory-exists? root))
     (list (issue "$" 'missing "bundle directory does not exist"))]
    [(not (and (file-exists? manifest-path)
               (file-exists? run-path)
               (file-exists? steps-path)))
     (list (issue "$"
                  'missing
                  "bundle requires bundle.json, run.json, and steps.jsonl"))]
    [else
     (with-handlers ([exn:fail?
                      (lambda (error)
                        (list (issue "$"
                                     'parse
                                     (exn-message error))))])
       (define subjects (read-json-file subjects-path))
       (define workflows (read-json-file workflows-path))
       (define manifest (read-json-file manifest-path))
       (define run (read-json-file run-path))
       (define steps (read-json-lines steps-path))
       (define manifest-issues (validate-bundle-manifest manifest))
       (define run-issues (validate-run run))
       (define step-issues
         (append*
          (for/list ([step (in-list steps)]
                     [index (in-naturals)])
            (for/list ([found (in-list (validate-step step))])
              (struct-copy validation-issue found
                           [path
                            (string-append
                             (index-path "$.steps" index)
                             (substring (validation-issue-path found) 1))])))))
       (define ordinal-issues
         (for/list ([step (in-list steps)]
                    [expected (in-naturals)]
                    #:unless (equal? (hash-value step 'ordinal) expected))
           (issue (field-path (index-path "$.steps" expected) 'ordinal)
                  'sequence
                  "step ordinals must be zero-based and contiguous")))
       (define steps-digest
         (bytes-sha256 (canonical-json-lines-bytes steps)))
       (define digest-issues
         (if (equal? (hash-value run 'steps_digest) steps-digest)
             '()
             (list (issue "$.run.steps_digest"
                          'digest
                          "steps digest does not match canonical steps.jsonl"))))
       (define registry-issues
         (append (validate-subject-registry subjects)
                 (validate-workflow-registry workflows subjects)))
       (define inventory-issues
         (if (and (object? manifest) (list? (hash-value manifest 'files)))
             (let* ([file-records (hash-ref manifest 'files)]
                    [declared-paths
                     (for/list ([record (in-list file-records)])
                       (hash-value record 'path))]
                    [actual-paths
                     (sort
                      (for/list ([path (in-list (find-files file-exists? root))]
                                 #:unless (equal? path manifest-path))
                        (path->string (find-relative-path root path)))
                      string<?)])
               (append
                (if (equal? (sort declared-paths string<?) actual-paths)
                    '()
                    (list (issue "$.bundle.files"
                                 'inventory
                                 "manifest file inventory does not match bundle")))
                (append*
                 (for/list ([record (in-list file-records)]
                            [index (in-naturals)])
                   (define relative (hash-value record 'path))
                   (define path (and (bundle-relative-path? relative)
                                     (build-path root relative)))
                   (cond
                     [(not (and path (file-exists? path)))
                      (list (issue
                             (field-path (index-path "$.bundle.files" index)
                                         'path)
                             'missing
                             "declared bundle file does not exist"))]
                     [else
                      (append
                       (if (equal? (file-size path)
                                   (hash-value record 'size_bytes))
                           '()
                           (list (issue
                                  (field-path
                                   (index-path "$.bundle.files" index)
                                   'size_bytes)
                                  'integrity
                                  "declared file size does not match")))
                       (if (equal? (file-sha256 path)
                                   (hash-value record 'sha256))
                           '()
                           (list (issue
                                  (field-path
                                   (index-path "$.bundle.files" index)
                                   'sha256)
                                  'integrity
                                  "declared file digest does not match"))))])))
                (if (<= (for/sum ([record (in-list file-records)])
                          (or (hash-value record 'size_bytes) 0))
                        8388608)
                    '()
                    (list (issue "$.bundle.files"
                                 'limit
                                 "bundle content exceeds 8 MiB")))))
             '()))
       (define reference-issues
         (if (and (object? run) (list? (hash-value workflows 'workflows)))
             (let ([definition
                    (for/first ([workflow
                                 (in-list (hash-ref workflows 'workflows))]
                                #:when
                                (and
                                 (equal? (hash-value workflow 'subject_id)
                                         (hash-value run 'subject_id))
                                 (equal? (hash-value workflow 'workflow_id)
                                         (hash-value run 'workflow_id))))
                      workflow)])
               (if definition
                   (append
                    (if (equal? (hash-value run 'workflow_version)
                                (hash-ref definition 'definition_version))
                        '()
                        (list (issue "$.run.workflow_version"
                                     'reference
                                     "run workflow version does not match registry")))
                    (if (equal? (hash-value run 'workflow_digest)
                                (jsexpr-sha256 definition))
                        '()
                        (list (issue "$.run.workflow_digest"
                                     'digest
                                     "run workflow digest does not match registry")))
                    (if (equal? (map (lambda (step)
                                       (hash-value step 'step_id))
                                     steps)
                                (hash-ref definition 'steps))
                        '()
                        (list (issue "$.steps"
                                     'reference
                                     "bundle step sequence does not match registry"))))
                   (list (issue "$.run.workflow_id"
                                'reference
                                "run workflow is not registered for its subject"))))
             '()))
       (append manifest-issues registry-issues inventory-issues run-issues
               step-issues ordinal-issues digest-issues reference-issues))]))
