#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require json
         racket/file
         racket/match
         racket/port
         racket/runtime-path
         racket/string
         racket/system
         rackunit)

(define-runtime-path test-directory ".")
(define repository-root (simplify-path (build-path test-directory ".." "..") #t))
(define status-script (build-path repository-root "scripts" "nightly-status.rkt"))
(define workflow-path (build-path repository-root ".forgejo" "workflows" "nightly.yml"))
(define dispatch-path
  (build-path repository-root "scripts" "dispatch-nightly-verification.sh"))
(define racket-path (find-executable-path "racket"))
(check-not-false racket-path "racket is required for nightly admission tests")

(define (run id status started)
  (hasheq 'id id
          'workflow_id "nightly.yml"
          'status status
          'started started
          'commit_sha (format "sha-~a" id)
          'html_url (format "https://forge.example/runs/~a" id)))

(define (invoke runs . arguments)
  (define fixture (make-temporary-file "odra-nightly-runs-~a.json"))
  (dynamic-wind
   (lambda ()
     (call-with-output-file fixture
       (lambda (output) (write-json (hasheq 'workflow_runs runs) output))
       #:exists 'truncate/replace))
   (lambda ()
     (define-values (process output input errors)
       (apply subprocess
              #f #f #f racket-path status-script
              "--runs-file" fixture
              "--date" "2026-09-28"
              arguments))
     (close-output-port input)
     (define standard-output (port->string output))
     (define standard-error (port->string errors))
     (subprocess-wait process)
     (values (subprocess-status process) standard-output standard-error))
   (lambda () (delete-file fixture))))

(test-case "a failed run admits the next same-date verification"
  (define-values (status output errors)
    (invoke
     (list
      (run 399 "failure" "2026-09-28T02:26:56+02:00")
      (run 400 "running" "2026-09-28T04:17:28+02:00"))
     "--admit-run" "400"))
  (check-equal? status 0 errors)
  (check-true (string-contains? output "admission=accepted"))
  (check-true (string-contains? output "retries=1")))

(test-case "an active owner rejects a duplicate as non-verifying"
  (define-values (status output errors)
    (invoke
     (list
      (run 410 "running" "2026-09-28T04:17:00+02:00")
      (run 411 "running" "2026-09-28T04:18:00+02:00"))
     "--admit-run" "411"))
  (check-equal? status 20 errors)
  (check-true (string-contains? output "admission=duplicate"))
  (check-true (string-contains? output "canonical-status=running")))

(test-case "status output distinguishes retryable and blocked dates"
  (define-values (failed-status failed-output failed-errors)
    (invoke (list (run 420 "cancelled" "2026-09-28T04:17:00+02:00"))))
  (check-equal? failed-status 0 failed-errors)
  (check-true (string-contains? failed-output "admission=retryable"))
  (define-values (passed-status passed-output passed-errors)
    (invoke (list (run 421 "success" "2026-09-28T05:17:00+02:00"))))
  (check-equal? passed-status 0 passed-errors)
  (check-true (string-contains? passed-output "admission=blocked")))

(test-case "workflow cannot convert duplicate admission into green verification"
  (define workflow (file->string workflow-path))
  (check-true (string-contains? workflow "echo 'admitted=no'"))
  (check-true (string-contains? workflow "exit \"$result\""))
  (check-false
   (regexp-match? #px"result.*-ne 20.*exit" workflow)))

;; Dispatch must distinguish the current main source from an earlier green run.
(test-case "source queries preserve admission boundaries"
  (define original (make-string 40 #\a))
  (define changed (make-string 40 #\b))
  (define scenarios
    (list
     (list "new source" "success" changed "status=missing")
     (list "validated source" "success" original "admission=blocked")
     (list "active different source" "running" changed "admission=blocked")))
  (for ([scenario (in-list scenarios)])
    (match-define (list name prior-status source expected) scenario)
    (define previous
      (hash-set (run 430 prior-status "2026-09-28T04:17:00+02:00")
                'commit_sha original))
    (define-values (status output errors)
      (invoke (list previous) "--source-commit" source))
    (check-equal? status 0 (string-append name ": " errors))
    (check-true (string-contains? output expected) name)))

(test-case "manual dispatch recognizes retryable status explicitly"
  (define dispatch (file->string dispatch-path))
  (check-true (string-contains? dispatch "admission=retryable"))
  (check-true
   (string-contains?
    dispatch
    "active run or a successful run for the same source owns the local date"))
  (check-true (string-contains? dispatch "ls-remote origin refs/heads/main"))
  (check-true (string-contains? dispatch "--source-commit")))
