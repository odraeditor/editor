#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.

(require racket/file
         racket/list
         racket/path
         "definitions.rkt"
         "vendor/canonical-json.rkt"
         "vendor/validation.rkt")

(provide write-json! read-bounded-json aggregate-outcome finalize-bundle!)

(define (write-json! path value)
  (call-with-atomic-output-file path
    (lambda (output _temporary)
      (write-bytes (jsexpr->canonical-bytes value) output)
      (newline output))))

(define (read-bounded-json path [maximum 1048576])
  (unless (and (file-exists? path) (not (link-exists? path))
               (<= (file-size path) maximum))
    (raise-user-error 'native-evidence "input is missing, linked, or exceeds its byte bound"))
  (read-json-file path))

(define (aggregate-outcome steps)
  (define outcomes (map (lambda (step) (hash-ref step 'outcome)) steps))
  (or (for/first ([outcome '("crashed" "timed-out" "failed" "cancelled" "unavailable")]
                  #:when (member outcome outcomes)) outcome)
      (if (andmap (lambda (outcome) (equal? outcome "skipped")) outcomes)
          "skipped" "passed")))

;; Publication becomes visible only after validation succeeds in a sibling staging tree.
(define (finalize-bundle! directory envelope steps)
  (when (or (file-exists? directory) (directory-exists? directory) (link-exists? directory))
    (raise-user-error 'native-evidence "final bundle destination must be new"))
  (define root (path->complete-path directory))
  (make-directory* (path-only root))
  (define staging (make-temporary-file ".native-evidence-~a" 'directory (path-only root)))
  (dynamic-wind
    void
    (lambda ()
      (define step-bytes
        (apply bytes-append
               (for/list ([step steps])
                 (bytes-append (jsexpr->canonical-bytes step) #"\n"))))
      (define run-base
        (hash-set (hash-set envelope 'outcome (aggregate-outcome steps))
                  'steps_digest (bytes-sha256 step-bytes)))
      (define run (hash-set run-base 'run_id (jsexpr-sha256 run-base)))
      (write-json! (build-path staging "run.json") run)
      (call-with-output-file (build-path staging "steps.jsonl")
        (lambda (output) (write-bytes step-bytes output)) #:mode 'binary)
      (call-with-output-file (build-path staging "summary.md")
        (lambda (output)
          (fprintf output "# Verification Evidence\n\nWorkflow: `~a`\n\nSource: `~a`\n\nOutcome: `~a`\n\n"
                   (hash-ref run 'workflow_id) (hash-ref (hash-ref run 'source) 'commit)
                   (hash-ref run 'outcome))
          (for ([step steps])
            (fprintf output "- `~a`: ~a\n" (hash-ref step 'step_id) (hash-ref step 'outcome)))))
      (write-json!
       (build-path staging "bundle.json")
       (hasheq 'schema "odra-evidence/bundle/v1"
               'limits (hasheq 'bundle_bytes 8388608 'file_count 256 'step_count 4096)
               'files
               (for/list ([name '("run.json" "steps.jsonl" "summary.md")]
                          [role '("run" "steps" "summary")])
                 (define path (build-path staging name))
                 (hasheq 'path name 'role role 'size_bytes (file-size path)
                         'sha256 (file-sha256 path)))))
      (unless (null? (validate-bundle-directory staging subjects-path workflows-path))
        (raise-user-error 'native-evidence "final bundle violates the pinned evidence contract"))
      (rename-file-or-directory staging root)
      (hash-ref run 'run_id))
    (lambda ()
      (when (directory-exists? staging) (delete-directory/files staging)))))
