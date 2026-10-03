#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.

(require racket/cmdline
         racket/file
         "bundle.rkt"
         "definitions.rkt"
         "observations.rkt"
         "session.rkt"
         "vendor/canonical-json.rkt")

(module+ main
  (define directory #f)
  (define workflow #f)
  (define stage #f)
  (define commit #f)
  (define ref "detached")
  (define attempt #f)
  (define source-root ".")
  (define code #f)
  (define finished #f)
  (define metrics #f)
  (define action
    (command-line
     #:once-each
     [("--directory") value "New evidence session directory" (set! directory value)]
     [("--workflow") value "Stable workflow identity" (set! workflow value)]
     [("--stage") value "Stable phase identity" (set! stage value)]
     [("--commit") value "Exact clean source commit" (set! commit value)]
     [("--ref") value "Logical source ref" (set! ref value)]
     [("--attempt") value "Unique producer attempt" (set! attempt value)]
     [("--source-root") value "Exact source checkout" (set! source-root value)]
     [("--exit-code") value "Original command exit code" (set! code (string->number value))]
     [("--finished-ms") value "Observed completion epoch" (set! finished (string->number value))]
     [("--metrics") value "Optional GNU time observation" (set! metrics value)]
     #:args (action) action))
  (unless directory (raise-user-error 'native-evidence "directory is required"))
  (case (string->symbol action)
    [(start)
     (unless (and workflow commit attempt) (raise-user-error 'native-evidence "start inputs missing"))
     (define environment (environment-observation))
     (define source (source-observation source-root commit ref))
     (start-session! directory workflow source environment
                      (hasheq 'source (hash-remove source 'ref) 'environment environment
                              'producer (jsexpr-sha256 producer-definition)
                              'configuration (input-observation source-root))
                      attempt)]
    [(prepare)
     (unless stage (raise-user-error 'native-evidence "stage missing"))
     (prepare-stage! directory stage (input-observation source-root))
     (write-json! (build-path directory (string-append stage ".pressure.json"))
                  (pressure-observation))]
    [(observe)
     (unless (and stage (exact-nonnegative-integer? code)
                  (exact-nonnegative-integer? finished) metrics)
       (raise-user-error 'native-evidence "observation inputs missing"))
     (observe-stage! directory stage code finished
                     (resource-observation
                      metrics (read-bounded-json
                               (build-path directory (string-append stage ".pressure.json")))))]
    [(skip)
     (unless stage (raise-user-error 'native-evidence "stage missing"))
     (skip-stage! directory stage)]
    [(finish) (void (finish-session! directory))]
    [else (raise-user-error 'native-evidence "unknown producer action")]))
