#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require json
         racket/cmdline
         racket/file
         racket/list
         racket/string)

(define stages-path #f)
(define json-path #f)
(define markdown-path #f)
(define status #f)
(define exit-code #f)
(define timed-out 'unset)
(define timeout-stage #f)
(define commit #f)
(define started-at #f)
(define finished-at #f)
(define duration-seconds #f)

(command-line
 #:program "write-nightly-summary"
 #:once-each
 [("--stages") value "Tab-separated stage records" (set! stages-path value)]
 [("--json") value "JSON summary path" (set! json-path value)]
 [("--markdown") value "Markdown summary path" (set! markdown-path value)]
 [("--status") value "Aggregate status" (set! status value)]
 [("--exit-code") value "Aggregate exit code" (set! exit-code (string->number value))]
 [("--timed-out") value "Aggregate timeout flag" (set! timed-out (string=? value "true"))]
 [("--timeout-stage") value "Timed-out stage identity" (set! timeout-stage value)]
 [("--commit") value "Verified commit" (set! commit value)]
 [("--started-at") value "UTC start time" (set! started-at value)]
 [("--finished-at") value "UTC finish time" (set! finished-at value)]
 [("--duration-seconds") value "Aggregate duration"
                            (set! duration-seconds (string->number value))])

(unless (and stages-path json-path markdown-path status exit-code
             (boolean? timed-out) timeout-stage commit started-at finished-at
             duration-seconds)
  (raise-user-error 'write-nightly-summary "all summary arguments are required"))

(define (parse-stage line)
  (define fields (string-split line "\t" #:trim? #f))
  (unless (= (length fields) 5)
    (raise-user-error 'write-nightly-summary "invalid stage record: ~s" line))
  (define exit-value (list-ref fields 3))
  (hasheq
   'name (list-ref fields 0)
   'target (list-ref fields 1)
   'status (list-ref fields 2)
   'exit_code (if (string=? exit-value "-") (json-null) (string->number exit-value))
   'duration_seconds (string->number (list-ref fields 4))))

(define stages (map parse-stage (file->lines stages-path)))
(define summary
  (hasheq
   'schema "odra-nightly/v2"
   'status status
   'exit_code exit-code
   'timed_out timed-out
   'timeout_stage (if (string=? timeout-stage "none") (json-null) timeout-stage)
   'commit commit
   'started_at started-at
   'finished_at finished-at
   'duration_seconds duration-seconds
   'stages stages))

(make-parent-directory* json-path)
(call-with-output-file json-path
  (lambda (output)
    (write-json summary output)
    (newline output))
  #:exists 'truncate/replace)

(call-with-output-file markdown-path
  (lambda (output)
    (displayln "# Nightly Verification" output)
    (newline output)
    (fprintf output "- Status: `~a`\n" status)
    (fprintf output "- Exit code: `~a`\n" exit-code)
    (fprintf output "- Timed out: `~a`\n" timed-out)
    (fprintf output "- Timeout stage: `~a`\n" timeout-stage)
    (fprintf output "- Commit: `~a`\n" commit)
    (fprintf output "- Started: `~a`\n" started-at)
    (fprintf output "- Finished: `~a`\n" finished-at)
    (fprintf output "- Duration: `~a seconds`\n" duration-seconds)
    (newline output)
    (displayln "## Stages" output)
    (newline output)
    (displayln "| Stage | Target | Status | Exit code | Duration |" output)
    (displayln "| --- | --- | --- | ---: | ---: |" output)
    (for ([stage (in-list stages)])
      (define stage-exit (hash-ref stage 'exit_code))
      (fprintf output "| `~a` | `~a` | `~a` | ~a | ~a s |\n"
               (hash-ref stage 'name)
               (hash-ref stage 'target)
               (hash-ref stage 'status)
               (if (eq? stage-exit (json-null)) "-" stage-exit)
               (hash-ref stage 'duration_seconds))))
  #:exists 'truncate/replace)
