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
         "../../scripts/evidence/bundle.rkt"
         "../../scripts/evidence/definitions.rkt"
         "../../scripts/evidence/observations.rkt"
         "../../scripts/evidence/session.rkt"
         "../../scripts/evidence/vendor/canonical-json.rkt"
         "../../scripts/evidence/vendor/validation.rkt")

(define-runtime-path wrapper "../../scripts/evidence/run-stage.sh")
(define source
  (hasheq 'repository "odra/odra" 'commit (make-string 40 #\a)
          'tree (make-string 40 #\b) 'ref "main" 'dirty #f))
(define environment (hasheq 'platform "linux" 'toolchains (hasheq 'racket "9.2")))
(define inputs (hasheq 'source source 'environment environment))

(define (with-session workflow thunk)
  (define root (make-temporary-file "native-producer-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define directory (build-path root "session"))
      (start-session! directory workflow source environment inputs "native:odra:420")
      (thunk root directory))
    (lambda () (delete-directory/files root))))

;; Each registered phase becomes a validated ordered record before atomic publication.
(test-case "finalizes complete Main Check and nightly bundles"
  (for ([workflow '("odra/main-check" "odra/nightly")])
    (with-session
     workflow
     (lambda (_root directory)
       (for ([step (hash-ref (workflow-definition workflow) 'steps)])
         (define stage (substring step (add1 (string-length workflow))))
         (prepare-stage! directory stage inputs)
         (observe-stage! directory stage 0
                         (inexact->exact (floor (current-inexact-milliseconds)))
                         (hasheq 'cpu_user_ms 10 'peak_rss_bytes 4096)))
       (finish-session! directory)
       (define bundle (build-path directory "bundle"))
       (check-equal? (validate-bundle-directory bundle subjects-path workflows-path) '())
       (define run (read-json-file (build-path bundle "run.json")))
       (check-equal? (hash-ref run 'outcome) "passed")
       (check-equal? (hash-ref (hash-ref run 'producer) 'kind) "native")
       (check-equal? (hash-ref run 'evidence_state) "complete")
       (check-exn exn:fail? (lambda () (finish-session! directory)))))))

;; Missing phase observations remain unavailable and cannot silently count as success.
(test-case "marks incomplete observation instead of inventing passed phases"
  (with-session
   "odra/main-check"
   (lambda (_root directory)
     (prepare-stage! directory "source-hygiene" inputs)
     (observe-stage! directory "source-hygiene" 7
                     (inexact->exact (floor (current-inexact-milliseconds))) (hasheq))
     (finish-session! directory)
     (define run (read-json-file (build-path directory "bundle/run.json")))
     (check-equal? (hash-ref run 'outcome) "failed")
     (check-equal? (hash-ref run 'evidence_state) "partial"))))

;; Cleanup removes only our staging tree and never exposes an invalid final bundle.
(test-case "rejects invalid final records atomically"
  (define root (make-temporary-file "native-atomic-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (check-exn exn:fail?
                 (lambda () (finalize-bundle! (build-path root "bundle") (hasheq) '())))
      (check-false (directory-exists? (build-path root "bundle")))
      (check-equal? (directory-list root) '()))
    (lambda () (delete-directory/files root))))

;; Real shell commands execute once, and recording failures cannot alter their exits.
(test-case "preserves command exits through successful and failed instrumentation"
  (for* ([recording? '(#t #f)] [code '(0 7 124 139)])
    (with-session
     "odra/main-check"
     (lambda (root directory)
       (when (not recording?)
         (write-json! (build-path directory "session.json") (hasheq)))
       (define marker (build-path root "calls"))
       (define env (environment-variables-copy (current-environment-variables)))
       (environment-variables-set! env #"ODRA_EVIDENCE_DIRECTORY" (path->bytes directory))
       (define-values (process output input errors)
         (parameterize ([current-environment-variables env])
           (subprocess #f #f #f (find-executable-path "bash") wrapper
                       "source-hygiene" "--" (find-executable-path "bash") "-c"
                       "printf 'called\\n' >> \"$1\"; exit \"$2\"" "fixture"
                       (path->string marker) (number->string code))))
       (close-output-port input)
       (port->string output)
       (port->string errors)
       (subprocess-wait process)
       (check-equal? (subprocess-status process) code)
       (check-equal? (file->lines marker) '("called"))
       (when recording?
         (define step (read-json-file (build-path directory "source-hygiene.json")))
         (check-equal? (hash-ref step 'exit_code) code)
         (check-equal? (validate-step step) '()))))))

;; Only measured metrics are retained; GNU time reports RSS in KiB, not bytes.
(test-case "normalizes resource units and preserves absent telemetry"
  (define root (make-temporary-file "native-metrics-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define path (build-path root "time"))
      (check-equal? (resource-observation path (hasheq) (hasheq)) (hasheq))
      (call-with-output-file path (lambda (output) (display "0.12 0.03 1024\n" output)))
      (define observed
        (resource-observation path (hasheq 'cpu_some_us 10) (hasheq 'cpu_some_us 17)))
      (check-equal? (hash-ref observed 'cpu_user_ms) 120)
      (check-equal? (hash-ref observed 'cpu_system_ms) 30)
      (check-equal? (hash-ref observed 'peak_rss_bytes) 1048576)
      (check-equal? (hash-ref observed 'pressure) (hasheq 'cpu_some_us 7))
      (check-false (hash-has-key? observed 'io_read_bytes)))
    (lambda () (delete-directory/files root))))

;; Identity comparisons must include actual inputs while excluding incidental paths.
(test-case "changes fingerprints for input changes and redacts build overrides"
  (with-session
   "odra/main-check"
   (lambda (root directory)
     (define env (environment-variables-copy (current-environment-variables)))
     (parameterize ([current-environment-variables env])
       (putenv "CFLAGS" "fixture-secret /home/fixture-person/private")
       (define observed (input-observation root))
       (check-false (string-contains? (bytes->string/utf-8 (jsexpr->canonical-bytes observed))
                                      "fixture-secret"))
       (prepare-stage! directory "source-hygiene" observed)
       (define first (read-json-file (build-path directory "source-hygiene.prepared.json")))
       (putenv "CFLAGS" "replacement")
       (define second-directory (build-path root "second"))
       (start-session! second-directory "odra/main-check" source environment inputs "native:odra:421")
       (prepare-stage! second-directory "source-hygiene" (input-observation root))
       (define second (read-json-file (build-path second-directory "source-hygiene.prepared.json")))
       (check-not-equal? (hash-ref first 'input_digest) (hash-ref second 'input_digest))))))

;; Known deadline skips differ from lost observations and must preserve timeout status.
(test-case "records unexecuted phases after the nightly deadline"
  (with-session
   "odra/nightly"
   (lambda (_root directory)
     (prepare-stage! directory "source-hygiene" inputs)
     (observe-stage! directory "source-hygiene" 124
                     (inexact->exact (floor (current-inexact-milliseconds))) (hasheq))
     (for ([stage '("compile-checks" "ui-migration" "test-suite" "hosting" "documentation")])
       (skip-stage! directory stage))
     (finish-session! directory)
     (define bundle (build-path directory "bundle"))
     (check-equal? (validate-bundle-directory bundle subjects-path workflows-path) '())
     (define run (read-json-file (build-path bundle "run.json")))
     (check-equal? (hash-ref run 'outcome) "timed-out")
     (check-equal? (hash-ref run 'evidence_state) "complete")
     (check-not-false (member "native/cpu-rss-unavailable"
                             (hash-ref (hash-ref run 'producer) 'limitations)))
     (check-equal? (hash-ref (read-json-file (build-path directory "documentation.json")) 'outcome)
                   "skipped"))))

;; Failures after command execution must not turn a product success into failure.
(test-case "preserves exits when metrics or final observation fail"
  (for* ([failure '("metrics" "observation")] [code '(0 7)])
    (with-session
     "odra/main-check"
     (lambda (root directory)
       (when (equal? failure "metrics")
         (make-directory (build-path directory "source-hygiene.time")))
       (define marker (build-path root "calls"))
       (define env (environment-variables-copy (current-environment-variables)))
       (environment-variables-set! env #"ODRA_EVIDENCE_DIRECTORY" (path->bytes directory))
       (define-values (process output input errors)
         (parameterize ([current-environment-variables env])
           (subprocess #f #f #f (find-executable-path "bash") wrapper "source-hygiene" "--"
                       (find-executable-path "bash") "-c"
                       (if (equal? failure "observation")
                           "printf 'called\\n' >> \"$1\"; printf '{}' > \"$3/session.json\"; exit \"$2\""
                           "printf 'called\\n' >> \"$1\"; exit \"$2\"")
                       "fixture" (path->string marker) (number->string code)
                       (path->string directory))))
       (close-output-port input)
       (port->string output)
       (port->string errors)
       (subprocess-wait process)
       (check-equal? (subprocess-status process) code)
       (check-equal? (file->lines marker) '("called"))))))
