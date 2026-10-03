#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.

(require racket/date
         racket/file
         racket/format
         racket/list
         racket/string
         "bundle.rkt"
         "definitions.rkt"
         "vendor/canonical-json.rkt")

(provide utc-now start-session! prepare-stage! observe-stage! skip-stage! finish-session!
         stage-record envelope)

(define (utc-now)
  (define value (seconds->date (current-seconds) #f))
  (string-append
   (string-join
    (for/list ([n (list (date-year value) (date-month value) (date-day value))]
               [width '(4 2 2)]) (~r n #:min-width width #:pad-string "0")) "-")
   "T"
   (string-join
    (for/list ([n (list (date-hour value) (date-minute value) (date-second value))])
      (~r n #:min-width 2 #:pad-string "0")) ":") "Z"))

(define (state-path directory) (build-path directory "session.json"))
(define (stage-path directory stage suffix)
  (unless (regexp-match? #px"^[a-z][a-z0-9-]{0,79}$" stage)
    (raise-user-error 'native-evidence "stage name is invalid"))
  (build-path directory (string-append stage suffix)))

(define (start-session! directory workflow source environment inputs attempt)
  (workflow-definition workflow)
  (when (or (directory-exists? directory) (file-exists? directory) (link-exists? directory))
    (raise-user-error 'native-evidence "session destination must be new"))
  (unless (regexp-match? #px"^[A-Za-z0-9][A-Za-z0-9._:/@+-]{0,159}$" attempt)
    (raise-user-error 'native-evidence "attempt identity is invalid"))
  (unless (and (equal? (hash-ref source 'repository) "odra/odra")
               (regexp-match? #px"^[0-9a-f]{40,64}$" (hash-ref source 'commit))
               (not (hash-ref source 'dirty)))
    (raise-user-error 'native-evidence "source must be an exact clean Odra commit"))
  (make-directory* directory)
  (file-or-directory-permissions directory #o700)
  (write-json! (state-path directory)
               (hasheq 'workflow workflow 'source source 'environment environment
                       'inputs inputs 'attempt attempt 'started_at (utc-now)
                       'started_ms (inexact->exact (floor (current-inexact-milliseconds))))))

(define (prepare-stage! directory stage inputs)
  (define state (read-bounded-json (state-path directory)))
  (define definition (operation-definition (hash-ref state 'workflow) stage))
  (define path (stage-path directory stage ".prepared.json"))
  (when (or (file-exists? path) (file-exists? (stage-path directory stage ".json")))
    (raise-user-error 'native-evidence "stage already prepared or completed"))
  (write-json! path
               (hasheq 'input_digest
                       (jsexpr-sha256 (hasheq 'session (hash-ref state 'inputs)
                                             'operation definition 'inputs inputs))
                       'started_ms (inexact->exact (floor (current-inexact-milliseconds))))))

(define (stage-record workflow stage ordinal input-digest outcome
                       #:exit-code [exit-code #f] #:resource [resource #f]
                       #:offset [offset #f] #:duration [duration #f]
                       #:reuse [reuse (hasheq 'classification "unknown"
                                             'reason "native/reuse-decision-unavailable")])
  (define definition (operation-definition workflow stage))
  (define base
    (hasheq 'ordinal ordinal 'step_id (hash-ref definition 'step_id)
            'definition_version 1 'operation_class (hash-ref definition 'operation_class)
            'input_digest input-digest 'operation_digest (jsexpr-sha256 definition)
            'outcome outcome 'reuse reuse 'artifacts '()))
  (define timed
    (for/fold ([value base]) ([pair (list (cons 'exit_code exit-code)
                                        (cons 'resource_observation resource)
                                        (cons 'started_offset_ms offset)
                                        (cons 'duration_ms duration))]
                             #:when (cdr pair))
      (hash-set value (car pair) (cdr pair))))
  (define with-reason
    (if (member outcome '("skipped" "unavailable"))
        (hash-set timed 'outcome_reason
                  (if (equal? outcome "skipped") "native/not-executed" "native/observation-missing"))
        timed))
  (define with-termination
    (cond [(equal? outcome "timed-out") (hash-set with-reason 'termination (hasheq 'kind "timeout"))]
          [(equal? outcome "crashed") (hash-set with-reason 'termination (hasheq 'kind "crash"))]
          [(equal? outcome "cancelled") (hash-set with-reason 'termination (hasheq 'kind "cancellation"))]
          [else with-reason]))
  (if (member outcome '("failed" "timed-out" "crashed"))
      (hash-set
       with-termination 'failure
       (hasheq 'category (string-append "native/" outcome)
               'fingerprint (jsexpr-sha256 (hasheq 'step_id (hash-ref definition 'step_id)
                                                  'outcome outcome 'exit_code (or exit-code 'null)))
               'summary (format "Workflow phase ~a ended with ~a." stage outcome)
               'diagnostics '()))
      with-termination))

(define (observe-stage! directory stage exit-code finished-ms resource)
  (define state (read-bounded-json (state-path directory)))
  (define prepared (read-bounded-json (stage-path directory stage ".prepared.json")))
  (define workflow (hash-ref state 'workflow))
  (define ordinal
    (index-of (hash-ref (workflow-definition workflow) 'steps) (string-append workflow "/" stage)))
  (define outcome (cond [(zero? exit-code) "passed"]
                        [(= exit-code 124) "timed-out"]
                        [(member exit-code '(134 139)) "crashed"]
                        [else "failed"]))
  (define duration (max 0 (- finished-ms (hash-ref prepared 'started_ms))))
  (define record
    (stage-record workflow stage ordinal (hash-ref prepared 'input_digest) outcome
                  #:exit-code exit-code #:offset (max 0 (- (hash-ref prepared 'started_ms)
                                                           (hash-ref state 'started_ms)))
                  #:duration duration #:resource (hash-set resource 'wall_ms duration)))
  (define path (stage-path directory stage ".json"))
  (when (file-exists? path) (raise-user-error 'native-evidence "stage already completed"))
  (write-json! path record))

(define (skip-stage! directory stage)
  (define state (read-bounded-json (state-path directory)))
  (define workflow (hash-ref state 'workflow))
  (define ordinal
    (index-of (hash-ref (workflow-definition workflow) 'steps) (string-append workflow "/" stage)))
  (define path (stage-path directory stage ".json"))
  (when (file-exists? path) (raise-user-error 'native-evidence "stage already completed"))
  (write-json! path
               (stage-record workflow stage ordinal
                             (jsexpr-sha256 (hasheq 'inputs (hash-ref state 'inputs)
                                                   'operation (operation-definition workflow stage)))
                             "skipped")))

(define (envelope state steps finished-at duration-ms limitations [artifacts '()])
  (define workflow (hash-ref state 'workflow))
  (define definition (workflow-definition workflow))
  (hasheq
   'schema "odra-evidence/run/v1" 'attempt_id (hash-ref state 'attempt)
   'subject_id "odra" 'workflow_id workflow 'workflow_version (hash-ref definition 'definition_version)
   'workflow_digest (jsexpr-sha256 definition) 'source (hash-ref state 'source)
   'execution_input_digest
   (jsexpr-sha256 (hasheq 'inputs (hash-ref state 'inputs)
                          'steps (map (lambda (step) (hash-ref step 'input_digest)) steps)))
   'environment (hash-ref state 'environment)
   'producer (hasheq 'kind "native" 'identity (hash-ref producer-definition 'identity)
                     'version 1 'definition_digest (jsexpr-sha256 producer-definition)
                     'limitations (sort (remove-duplicates limitations) string<?))
   'started_at (hash-ref state 'started_at) 'finished_at finished-at 'duration_ms duration-ms
   'evidence_state (if (member "native/observation-missing" limitations) "partial" "complete")
   'artifacts artifacts))

(define (finish-session! directory)
  (define state (read-bounded-json (state-path directory)))
  (define workflow (hash-ref state 'workflow))
  (define definitions (hash-ref (workflow-definition workflow) 'steps))
  (define missing? #f)
  (define steps
    (for/list ([step definitions] [ordinal (in-naturals)])
      (define stage (substring step (add1 (string-length workflow))))
      (define path (stage-path directory stage ".json"))
      (cond [(file-exists? path) (read-bounded-json path)]
            [else
             (set! missing? #t)
             (stage-record workflow stage ordinal (jsexpr-sha256 (hash-ref state 'inputs))
                           "unavailable")])))
  (define limitations
    (append '("native/io-bytes-unavailable" "native/process-count-unavailable"
              "native/output-artifact-retention-unavailable"
              "native/reuse-decision-unavailable")
            (if missing? '("native/observation-missing") '())
            (if (ormap (lambda (step)
                         (and (not (member (hash-ref step 'outcome) '("skipped" "unavailable")))
                              (not (hash-has-key? (hash-ref step 'resource_observation (hasheq))
                                                  'peak_rss_bytes)))) steps)
                '("native/cpu-rss-unavailable") '())))
  (finalize-bundle! (build-path directory "bundle")
                    (envelope state steps (utc-now)
                              (max 0 (- (inexact->exact (floor (current-inexact-milliseconds)))
                                        (hash-ref state 'started_ms)))
                              limitations)
                    steps))
