#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.

(require rackunit
         racket/file
         racket/list
         racket/port
         racket/runtime-path
         racket/string
         racket/system
         (only-in "../../scripts/release/candidate-store.rkt"
                  open-candidate-store initialize-candidate!)
         "../../scripts/evidence/bundle.rkt"
         "../../scripts/evidence/definitions.rkt"
         "../../scripts/evidence/release.rkt"
         "../../scripts/evidence/session.rkt"
         "../../scripts/evidence/vendor/canonical-json.rkt"
         "../../scripts/evidence/vendor/validation.rkt")

(define source (hasheq 'repository "odra/odra" 'commit (make-string 40 #\a)
                       'tree (make-string 40 #\b) 'ref "main" 'dirty #f))
(define environment (hasheq 'platform "linux"))
(define inputs (hasheq 'source source 'mode "candidate" 'attempt "native:420"))
(define candidate
  (hasheq 'candidate_id (make-string 64 #\c) 'phases '() 'artifacts '()))
(define-runtime-path producer "../../scripts/evidence/release-producer.rkt")

(define (needs-for mode)
  (for/hasheq ([job release-job-names])
    (values (string->symbol job)
            (hasheq 'result
                    (if (or (and (equal? mode "candidate")
                                 (member job '("package-authority-probe" "guide-authority-probe"
                                               "publish-source" "publish-bundle"
                                               "publish-user-guide" "public-verification")))
                            (and (equal? mode "publish") (equal? job "candidate-complete")))
                        "skipped" "success")))))

;; Candidate and publish modes use one workflow contract and distinct execution inputs.
(test-case "finalizes bounded candidate and publication evidence"
  (for ([mode '("candidate" "publish")])
    (define root (make-temporary-file "native-release-~a" 'directory))
    (dynamic-wind
      void
      (lambda ()
        (define output (build-path root "bundle"))
        (finalize-release! output source environment (hash-set inputs 'mode mode)
                           (needs-for mode) candidate (utc-now))
        (check-equal? (validate-bundle-directory output subjects-path workflows-path) '())
        (define run (read-json-file (build-path output "run.json")))
        (check-equal? (hash-ref run 'outcome) "passed")
        (check-not-false (member "native/release-job-timing-unavailable"
                                (hash-ref (hash-ref run 'producer) 'limitations))))
      (lambda () (delete-directory/files root)))))

;; Job results come from this run; old candidate records cannot replace a failed job.
(test-case "preserves current failures and cancelled publication"
  (for ([status '("failure" "cancelled")])
    (define needs (hash-set (needs-for "publish") 'publish-source (hasheq 'result status)))
    (define steps (release-records needs candidate inputs (utc-now)))
    (check-equal? (aggregate-outcome steps)
                  (if (equal? status "failure") "failed" "cancelled"))
    (for ([step steps]) (check-equal? (validate-step step) '()))))

;; Retained semantic inputs establish reuse without inventing fresh timing or CPU values.
(test-case "records reused phase fingerprints and omits unavailable measurements"
  (define retained
    (hash-set candidate 'phases
              (list (hasheq 'phase "bundle-validation"
                            'attempts
                            (list (hasheq 'phase "bundle-validation" 'state "passed"
                                          'started_at "2026-09-01T00:00:00Z"
                                          'input_sha256 (make-string 64 #\d)))))))
  (define steps (release-records (needs-for "publish") retained inputs (utc-now)))
  (define build (list-ref steps 5))
  (check-equal? (hash-ref (hash-ref build 'reuse) 'classification) "reused")
  (check-false (hash-has-key? build 'duration_ms))
  (check-false (hash-has-key? build 'resource_observation))
  (define changed
    (hash-set retained 'phases
              (list (hasheq 'phase "bundle-validation"
                            'attempts
                            (list (hasheq 'phase "bundle-validation" 'state "passed"
                                          'started_at "2026-09-01T00:00:00Z"
                                          'input_sha256 (make-string 64 #\e)))))))
  (check-not-equal?
   (hash-ref build 'input_digest)
   (hash-ref (list-ref (release-records (needs-for "publish") changed inputs (utc-now)) 5)
             'input_digest)))

;; Semantic execution identity must not change solely because another attempt is observed.
(test-case "keeps attempt identity out of equivalent execution fingerprints"
  (define root (make-temporary-file "native-attempts-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (for ([attempt '("native:420" "native:421")] [name '("first" "second")])
        (finalize-release! (build-path root name) source environment
                           (hash-set inputs 'attempt attempt) (needs-for "candidate")
                           candidate (utc-now)))
      (define first (read-json-file (build-path root "first/run.json")))
      (define second (read-json-file (build-path root "second/run.json")))
      (check-not-equal? (hash-ref first 'run_id) (hash-ref second 'run_id))
      (check-equal? (hash-ref first 'execution_input_digest)
                    (hash-ref second 'execution_input_digest)))
    (lambda () (delete-directory/files root))))

;; Exercise the actual entrypoint against clean Git and the production candidate reader.
(test-case "reads exact source and candidate state without mutating either"
  (define root (make-temporary-file "native-entrypoint-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define checkout (build-path root "source"))
      (make-directory checkout)
      (define (git . args)
        (parameterize ([current-output-port (open-output-nowhere)]
                       [current-error-port (open-output-nowhere)])
          (check-true (apply system* (find-executable-path "git") "-C" checkout args))))
      (git "init" "-b" "main")
      (write-json! (build-path checkout "fixture.json") (hasheq 'fixture #t))
      (git "add" ".")
      (git "-c" "user.name=Evidence Fixture" "-c" "user.email=fixture@example.invalid"
           "-c" "commit.gpgsign=false" "commit" "-m" "Initial commit")
      (define-values (process output input errors)
        (subprocess #f #f #f (find-executable-path "git") "-C" checkout "rev-parse" "HEAD"))
      (close-output-port input)
      (define commit (string-trim (port->string output)))
      (port->string errors)
      (subprocess-wait process)
      (check-equal? (subprocess-status process) 0)
      (define store-root (build-path root "store"))
      (define store (open-candidate-store store-root))
      (define id (hash-ref candidate 'candidate_id))
      (initialize-candidate! store id "0.2.0" (make-string 64 #\d) (utc-now))
      (define candidate-path (build-path store-root id "state.json"))
      (define before (file->bytes candidate-path))
      (define env (environment-variables-copy (current-environment-variables)))
      (for ([pair (list (cons "ODRA_EVIDENCE_SOURCE_COMMIT" commit)
                        (cons "ODRA_EVIDENCE_ADAPTER_COMMIT" commit)
                        (cons "ODRA_EVIDENCE_VERSION" "0.2.0")
                        (cons "ODRA_EVIDENCE_RELEASE_MODE" "candidate")
                        (cons "ODRA_EVIDENCE_RUN_ID" "420")
                        (cons "ODRA_EVIDENCE_STARTED_AT" (utc-now))
                        (cons "ODRA_EVIDENCE_CANDIDATE_ID" id)
                        (cons "ODRA_EVIDENCE_NEEDS"
                              (bytes->string/utf-8 (jsexpr->canonical-bytes (needs-for "candidate"))))
                        (cons "ODRA_RELEASE_CANDIDATE_STORE" (path->string store-root)))])
        (environment-variables-set! env (string->bytes/utf-8 (car pair))
                                     (string->bytes/utf-8 (cdr pair))))
      (for ([version '("0.2.0" "0.2.1")] [destination '("bundle" "mismatch")])
        (environment-variables-set! env #"ODRA_EVIDENCE_VERSION" (string->bytes/utf-8 version))
        (define-values (command stdout stdin stderr)
          (parameterize ([current-environment-variables env])
            (subprocess #f #f #f (find-executable-path "timeout") "--foreground"
                        "--kill-after=1s" "40s" (find-executable-path "racket") producer
                        "--source-root" checkout "--output" (build-path root destination))))
        (close-output-port stdin)
        (port->string stdout)
        (define diagnostic (port->string stderr))
        (subprocess-wait command)
        (if (equal? version "0.2.0")
            (begin
              (check-equal? (subprocess-status command) 0 diagnostic)
              (check-equal? (validate-bundle-directory (build-path root destination)
                                                       subjects-path workflows-path) '()))
            (begin
              (check-not-equal? (subprocess-status command) 0)
              (check-false (directory-exists? (build-path root destination))))))
      (check-equal? (file->bytes candidate-path) before)
      (git "diff" "--exit-code"))
    (lambda () (delete-directory/files root))))

;; Unknown job graphs and states are rejected instead of silently yielding green evidence.
(test-case "rejects incomplete job results"
  (check-exn exn:fail?
             (lambda () (release-records (hasheq) candidate inputs (utc-now))))
  (check-exn exn:fail?
             (lambda () (release-records
                         (hash-set (needs-for "candidate") 'preflight (hasheq 'result "unknown"))
                         candidate inputs (utc-now)))))

;; Retained artifacts export content identities and logical references, not private paths.
(test-case "omits private candidate paths from finalized artifacts"
  (define root (make-temporary-file "native-artifacts-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define retained
        (hash-set candidate 'artifacts
                  (list (hasheq 'name "linux-bundle" 'media_type "application/zstd"
                                'byte_size 1024 'sha256 (make-string 64 #\d)
                                'path "/home/private-fixture/secret-path"))))
      (define output (build-path root "bundle"))
      (finalize-release! output source environment inputs (needs-for "candidate") retained (utc-now))
      (check-equal? (validate-bundle-directory output subjects-path workflows-path) '())
      (for ([path (directory-list output #:build? #t)])
        (check-false (string-contains? (file->string path) "private-fixture"))))
    (lambda () (delete-directory/files root))))
