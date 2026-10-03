#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require json
         racket/cmdline
         racket/date
         racket/list
         racket/match
         racket/port
         racket/string
         racket/system)

(define workflow-name "nightly.yml")

(define (run/capture executable arguments)
  (define program (find-executable-path executable))
  (unless program
    (raise-user-error 'nightly-status "command is unavailable: ~a" executable))
  (define-values (process output input errors)
    (apply subprocess #f #f #f program arguments))
  (close-output-port input)
  (define standard-output (port->string output))
  (define standard-error (port->string errors))
  (subprocess-wait process)
  (values (subprocess-status process) standard-output standard-error))

(define (repository-slug origin)
  (match (regexp-match #px"([^/:]+/[^/]+?)(?:\\.git)?$" (string-trim origin))
    [(list _ slug) slug]
    [_ #f]))

(define (local-date)
  (parameterize ([current-environment-variables
                  (environment-variables-copy
                   (current-environment-variables))]
                 [date-display-format 'iso-8601])
    (putenv "TZ" "Europe/Warsaw")
    (date->string (seconds->date (current-seconds)))))

(define (run-started-on? run date)
  (define started (hash-ref run 'started ""))
  (and (string? started) (string-prefix? started date)))

(define (nightly-run? run date)
  (and (equal? (hash-ref run 'workflow_id #f) workflow-name)
       (run-started-on? run date)))

(define (daily-runs runs date)
  (sort (filter (lambda (run) (nightly-run? run date)) runs)
        <
        #:key (lambda (run) (hash-ref run 'id 0))))

(define retryable-statuses '("failure" "cancelled" "canceled" "skipped"))

(define (run-status run)
  (define status (hash-ref run 'status "unknown"))
  (if (string? status) (string-downcase status) "unknown"))

(define (retryable-run? run)
  (member (run-status run) retryable-statuses))

(define (canonical-run runs date)
  (for/first ([run (in-list (daily-runs runs date))]
              #:unless (retryable-run? run))
    run))

(define (different-source? first-run second-run)
  (define first-source (hash-ref first-run 'commit_sha #f))
  (define second-source (hash-ref second-run 'commit_sha #f))
  (and (string? first-source)
       (string? second-source)
       (regexp-match? #px"^[0-9a-f]{40}$" first-source)
       (regexp-match? #px"^[0-9a-f]{40}$" second-source)
       (not (equal? first-source second-source))))

(define (admission-owner current candidates)
  (for/first ([run (in-list candidates)]
              #:unless (or (retryable-run? run)
                           (and (equal? (run-status run) "success")
                                (different-source? run current))))
    run))

(define (admission-decision run-id runs date)
  (define candidates (daily-runs runs date))
  (define current
    (findf (lambda (run) (= run-id (hash-ref run 'id 0))) candidates))
  (define canonical (and current (admission-owner current candidates)))
  (cond
    [(not current) 'absent]
    [(and canonical (= run-id (hash-ref canonical 'id 0))) 'accepted]
    [else 'duplicate]))

(define (query-runs repository login)
  (define arguments
    (append
     (list "api"
           "/repos/{owner}/{repo}/actions/runs?limit=50"
           "--repo"
           repository)
     (if login (list "--login" login) '())))
  (define-values (status output errors) (run/capture "tea" arguments))
  (unless (zero? status)
    (raise-user-error 'nightly-status
                      "Forgejo query failed: ~a"
                      (string-trim errors)))
  (hash-ref (read-json (open-input-string output)) 'workflow_runs '()))

(define (read-runs-file path)
  (call-with-input-file path
    (lambda (input)
      (hash-ref (read-json input) 'workflow_runs '()))))

(define (print-run run date count admission)
  (cond
    [run
     (printf "nightly: status=~a admission=~a date=~a run=~a runs=~a sha=~a started=~a url=~a\n"
             (hash-ref run 'status "unknown")
             admission
             date
             (hash-ref run 'id "unknown")
             count
             (hash-ref run 'commit_sha "unknown")
             (hash-ref run 'started "unknown")
             (hash-ref run 'html_url "unavailable"))]
    [else
     (printf "nightly: status=missing date=~a\n" date)]))

(module+ main
  (define requested-date #f)
  (define runs-file #f)
  (define admitted-run #f)
  (define requested-source #f)
  (command-line
   #:program "nightly-status"
   #:once-each
   [("--date") date "Local date in YYYY-MM-DD form"
                  (set! requested-date date)]
   [("--runs-file") path "Read the Forgejo actions response from this JSON file"
                       (set! runs-file path)]
   [("--source-commit") source "Query admission for an exact source commit"
                               (set! requested-source source)]
   [("--admit-run") run-id "Admit one nightly owner for the exact source commit"
                            (set! admitted-run (string->number run-id))])
  (with-handlers ([exn:fail?
                   (lambda (failure)
                     (printf "nightly: status=unavailable reason=~s\n"
                             (exn-message failure))
                     (exit 2))])
    (define date (or requested-date (local-date)))
    (when (and requested-source
               (not (regexp-match? #px"^[0-9a-f]{40}$" requested-source)))
      (raise-user-error 'nightly-status "source commit must be a full Git commit"))
    (define runs
      (cond
        [runs-file (read-runs-file runs-file)]
        [else
         (define-values (git-status origin errors)
           (run/capture "git" '("remote" "get-url" "origin")))
         (unless (zero? git-status)
           (raise-user-error 'nightly-status
                             "origin lookup failed: ~a"
                             (string-trim errors)))
         (define repository (repository-slug origin))
         (unless repository
           (raise-user-error 'nightly-status
                             "unable to derive the repository slug"))
         (query-runs repository (getenv "ODRA_TEA_LOGIN"))]))
    (define candidates (daily-runs runs date))
    (cond
      [admitted-run
       (define decision (admission-decision admitted-run candidates date))
       (case decision
         [(accepted)
          (define retry-count
            (count (lambda (run)
                     (and (< (hash-ref run 'id 0) admitted-run)
                          (retryable-run? run)))
                   candidates))
          (printf "nightly: admission=accepted date=~a run=~a runs=~a retries=~a\n"
                  date admitted-run (length candidates) retry-count)]
         [(duplicate)
          (define current
            (findf (lambda (run) (= admitted-run (hash-ref run 'id 0)))
                   candidates))
          (define owner (admission-owner current candidates))
          (printf "nightly: admission=duplicate date=~a run=~a canonical=~a canonical-status=~a runs=~a\n"
                  date admitted-run
                  (hash-ref owner 'id 0)
                  (run-status owner)
                  (length candidates))
          (exit 20)]
         [else
          (raise-user-error 'nightly-status
                            "current run is absent from the Forgejo actions response")])]
      [else
       (define source-run (and requested-source (hasheq 'commit_sha requested-source)))
       (define relevant
         (if source-run
             (filter (lambda (run) (not (different-source? run source-run)))
                     candidates)
             candidates))
       (define admitted
         (if source-run
             (admission-owner source-run candidates)
             (canonical-run candidates date)))
       (if admitted
           (print-run admitted date (length candidates) "blocked")
           (print-run (and (pair? relevant) (last relevant))
                      date
                      (length candidates)
                      "retryable"))])))

(module+ test
  (require rackunit)

  (define sample-runs
    (list
     (hasheq 'id 8
             'workflow_id workflow-name
             'event "push"
             'status "failure"
             'started "2026-08-31T04:17:00+02:00")
     (hasheq 'id 9
             'workflow_id workflow-name
             'event ""
             'status "success"
             'started "2026-08-31T11:02:00+02:00")
     (hasheq 'id 10
             'workflow_id "another.yml"
             'event "schedule"
             'status "success"
             'started "2026-08-31T12:00:00+02:00")))

  (test-case "derives common repository slugs"
    (check-equal?
     (repository-slug "ssh://git@example.test:2222/owner/repository.git")
     "owner/repository")
    (check-equal?
     (repository-slug "git@example.test:owner/repository.git")
     "owner/repository")
    (check-equal?
     (repository-slug "https://example.test/owner/repository.git")
     "owner/repository"))

  (test-case "selects the first verifying run after retryable failures"
    (check-equal?
     (hash-ref (canonical-run sample-runs "2026-08-31") 'id)
     9)
    (check-equal? (length (daily-runs sample-runs "2026-08-31")) 2)
    (check-eq? (admission-decision 8 sample-runs "2026-08-31") 'duplicate)
    (check-eq? (admission-decision 9 sample-runs "2026-08-31") 'accepted)
    (check-false (canonical-run sample-runs "2026-09-01")))

  (test-case "running and successful runs retain same-date admission"
    (define running
      (list
       (hasheq 'id 20 'workflow_id workflow-name 'status "running"
               'started "2026-09-01T04:17:00+02:00")
       (hasheq 'id 21 'workflow_id workflow-name 'status "running"
               'started "2026-09-01T05:00:00+02:00")))
    (check-eq? (admission-decision 20 running "2026-09-01") 'accepted)
    (check-eq? (admission-decision 21 running "2026-09-01") 'duplicate)
    (define successful
      (cons (hash-set (first running) 'status "success") (rest running)))
    (check-eq? (admission-decision 21 successful "2026-09-01") 'duplicate))

  (test-case "failed canceled and skipped runs admit a deterministic retry"
    (define retries
      (list
       (hasheq 'id 30 'workflow_id workflow-name 'status "failure"
               'started "2026-09-02T04:17:00+02:00")
       (hasheq 'id 31 'workflow_id workflow-name 'status "cancelled"
               'started "2026-09-02T05:00:00+02:00")
       (hasheq 'id 32 'workflow_id workflow-name 'status "skipped"
               'started "2026-09-02T06:00:00+02:00")
       (hasheq 'id 33 'workflow_id workflow-name 'status "running"
               'started "2026-09-02T07:00:00+02:00")))
    (check-eq? (admission-decision 33 retries "2026-09-02") 'accepted)
    (check-equal? (hash-ref (canonical-run retries "2026-09-02") 'id) 33)
    (check-eq? (admission-decision 99 retries "2026-09-02") 'absent))

  ;; A completed older source must not prevent validating a release correction.
  ;; Active runs and unverifiable identities must still block another owner.
  (test-case "admission follows source identity"
    (define original (make-string 40 #\a))
    (define changed (make-string 40 #\b))
    (define date "2026-10-03")
    (define cases
      (list
       (list "changed source after success" "success" original changed 'accepted)
       (list "same source after success" "success" original original 'duplicate)
       (list "changed source while running" "running" original changed 'duplicate)
       (list "changed source while waiting" "waiting" original changed 'duplicate)
       (list "missing earlier source" "success" #f changed 'duplicate)
       (list "missing current source" "success" original #f 'duplicate)
       (list "malformed earlier source" "success" "unknown" changed 'duplicate)
       (list "same source after failure" "failure" original original 'accepted)
       (list "same source after cancellation" "cancelled" original original 'accepted)
       (list "same source after skipped run" "skipped" original original 'accepted)))
    (for ([scenario (in-list cases)])
      (match-define (list name status earlier-source current-source expected)
        scenario)
      (define earlier
        (hasheq 'id 50 'workflow_id workflow-name 'status status
                'commit_sha earlier-source 'started "2026-10-03T04:17:00+02:00"))
      (define current
        (hasheq 'id 51 'workflow_id workflow-name 'status "running"
                'commit_sha current-source 'started "2026-10-03T14:00:00+02:00"))
      (check-eq? (admission-decision 51 (list earlier current) date)
                 expected name)))

  (test-case "uses an ISO local date"
    (check-regexp-match #px"^[0-9]{4}-[0-9]{2}-[0-9]{2}$" (local-date))))
