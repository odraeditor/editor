#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require json
         racket/file
         racket/list
         racket/path
         racket/port
         racket/runtime-path
         racket/string
         racket/system
         rackunit)

(define-runtime-path test-directory ".")
(define repository-root (simplify-path (build-path test-directory ".." "..") #t))
(define runner (build-path repository-root "scripts" "run-nightly-verification.sh"))
(define workflow
  (file->string (build-path repository-root ".forgejo" "workflows" "nightly.yml")))
(define internal-makefile-lines
  (file->lines (build-path repository-root "makefiles" "internal.mk")))
(define bash-path (find-executable-path "bash"))
(check-not-false bash-path "bash is required for nightly runner tests")
(define git-path (find-executable-path "git"))
(check-not-false git-path "git is required for nightly runner tests")
(define make-path (find-executable-path "make"))
(check-not-false make-path "make is required for nightly runner tests")
(define expected-commit
  (string-trim
   (with-output-to-string
     (lambda ()
       (check-true (system* git-path "-C" repository-root "rev-parse" "HEAD"))))))

(struct fixture-result (exit-code output errors summary markdown log) #:transparent)

(define fake-make-content
  (string-append
   "#!/usr/bin/env bash\n"
   "set -eu\n"
   "target=$1\n"
   "printf 'fixture-stage=%s scenario=%s\\n' \"$target\" \"$ODRA_NIGHTLY_FIXTURE\"\n"
   "printf 'fixture-temporary-directory=%s\\n' \"$TMPDIR\"\n"
   "printf '%s\\n' \"$target\" > \"$TMPDIR/$target\"\n"
   "case \"$ODRA_NIGHTLY_FIXTURE:$target\" in\n"
   "  one-failure:check) exit 7 ;;\n"
   "  multiple-failures:source-hygiene-check) exit 3 ;;\n"
   "  multiple-failures:hosting-test) exit 9 ;;\n"
   "  timeout:check) sleep 5 ;;\n"
   "esac\n"))

(define (run-fixture scenario timeout)
  (define root (make-temporary-file "odra-nightly-runner-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define fake-make (build-path root "fake-make"))
     (define result-directory (build-path root "results"))
     (call-with-output-file fake-make
       (lambda (output) (display fake-make-content output)))
     (file-or-directory-permissions fake-make #o700)
     (define environment
       (environment-variables-copy (current-environment-variables)))
     (environment-variables-set!
      environment #"ODRA_NIGHTLY_FIXTURE" (string->bytes/utf-8 scenario))
     (environment-variables-set!
      environment #"ODRA_NIGHTLY_TIMEOUT" (string->bytes/utf-8 timeout))
     (environment-variables-set!
      environment #"ODRA_NIGHTLY_MAKE" (path->bytes fake-make))
     (environment-variables-set!
      environment #"ODRA_NIGHTLY_RESULT_DIRECTORY" (path->bytes result-directory))
     (define-values (process output input errors)
       (parameterize ([current-environment-variables environment]
                      [current-directory repository-root])
         (subprocess #f #f #f bash-path runner)))
     (close-output-port input)
     (define standard-output (port->string output))
     (define standard-error (port->string errors))
     (subprocess-wait process)
     (close-input-port output)
     (close-input-port errors)
     ;; Every phase must share run-owned scratch space and leave no temporary tree.
     (define temporary-paths
       (regexp-match* #px"fixture-temporary-directory=([^\n]+)"
                      standard-output #:match-select cadr))
     (check-false (null? temporary-paths))
     (check-equal? (length (remove-duplicates temporary-paths)) 1)
     (for ([temporary-path (in-list temporary-paths)])
       (check-equal? (simplify-path (build-path temporary-path 'up))
                     (path->directory-path result-directory))
       (check-false (directory-exists? temporary-path)))
     (fixture-result
      (subprocess-status process)
      standard-output
      standard-error
      (call-with-input-file (build-path result-directory "summary.json") read-json)
      (file->string (build-path result-directory "summary.md"))
      (file->string (build-path result-directory "verify.log"))))
   (lambda () (delete-directory/files root))))

(define (stage-statuses result)
  (map (lambda (stage) (hash-ref stage 'status))
       (hash-ref (fixture-result-summary result) 'stages)))

(define (target-recipe name)
  (define start
    (index-where
     internal-makefile-lines
     (lambda (line) (string-prefix? line (string-append name ":")))))
  (check-not-false start (format "missing Make target: ~a" name))
  (for/list ([line (in-list (drop internal-makefile-lines (add1 start)))]
             #:break (not (string-prefix? line "\t")))
    (string-trim line)))

(define (expanded-target target)
  (parameterize ([current-directory repository-root])
    (with-output-to-string
      (lambda ()
        (check-true (system* make-path "--dry-run" target))))))

(test-case "nightly reuses the complete Odra package test"
  (define focused-recipe
    (string-join (target-recipe "candidate-navigation-focused-acceptance") "\n"))
  (define complete-recipe
    (string-join (target-recipe "candidate-navigation-acceptance") "\n"))
  (define presentation-focused-recipe
    (string-join (target-recipe "terminal-presentation-focused-test") "\n"))
  (define presentation-complete-recipe
    (string-join (target-recipe "terminal-presentation-test") "\n"))
  (define internal-recipe (target-recipe "internal-test"))
  (check-false (string-contains? focused-recipe "test src/odra"))
  (check-true (string-contains? complete-recipe "test src/odra"))
  (check-false (string-contains? presentation-focused-recipe "test src/odra"))
  (check-true (string-contains? presentation-complete-recipe "test src/odra"))
  (check-not-false
   (member
    "$(call run_verification_step,candidate-navigation-focused-acceptance,$(MAKE) candidate-navigation-focused-acceptance)"
    internal-recipe))
  (check-false
   (member
    "$(call run_verification_step,candidate-navigation-acceptance,$(MAKE) candidate-navigation-acceptance)"
    internal-recipe))
  (check-not-false
   (member
    "$(call run_verification_step,terminal-presentation-focused-test,$(MAKE) terminal-presentation-focused-test)"
    internal-recipe))
  (check-false
   (member
    "$(call run_verification_step,terminal-presentation-test,$(MAKE) terminal-presentation-test)"
    internal-recipe))
  (check-equal?
   (length (regexp-match* #px"(?m:^odin test src/odra )"
                          (expanded-target "internal-test")))
   1))

(test-case "nightly deadlines are emergency limits"
  (check-true
   (string-contains? (file->string runner)
                     "timeout_limit=${ODRA_NIGHTLY_TIMEOUT:-6h}"))
  (check-true (string-contains? workflow "timeout-minutes: 390")))

(test-case "language acceptance prepares absolute dynamic syntax fixtures"
  (define makefile (string-join internal-makefile-lines "\n"))
  (define language-recipe
    (string-join (target-recipe "language-service-extensibility-acceptance") "\n"))
  (check-true
   (string-contains?
    makefile
    "language-service-extensibility-acceptance: $(SYNTAX_PROVIDER_FIXTURE_LIBRARY) $(SYNTAX_PROVIDER_FIXTURE_LINK)"))
  (for ([definition (in-list
                     '("ODRA_SYNTAX_PROVIDER_FIXTURE"
                       "ODRA_SYNTAX_PROVIDER_FIXTURE_LINK"
                       "ODRA_SYNTAX_PROVIDER_QUERY"
                       "ODRA_SYNTAX_PROVIDER_MALFORMED_QUERY"
                       "ODRA_EXTERNAL_BUNDLE_GRAMMAR"
                       "ODRA_EXTERNAL_BUNDLE_QUERY"))])
    (check-true (string-contains? language-recipe definition) definition)))

(test-case "all successful stages produce complete evidence"
  (define result (run-fixture "success" "30s"))
  (check-equal? (fixture-result-exit-code result) 0)
  (check-equal? (hash-ref (fixture-result-summary result) 'schema)
                "odra-nightly/v2")
  (check-equal? (hash-ref (fixture-result-summary result) 'commit)
                expected-commit)
  (check-true
   (exact-nonnegative-integer?
    (hash-ref (fixture-result-summary result) 'duration_seconds)))
  (check-equal? (stage-statuses result) (make-list 6 "passed"))
  (check-true (string-contains? (fixture-result-markdown result) "## Stages"))
  (check-true (string-contains? (fixture-result-output result)
                                "ODRA_NIGHTLY_SUMMARY_BEGIN")))

(test-case "one failure does not hide later stage results"
  (define result (run-fixture "one-failure" "30s"))
  (check-equal? (fixture-result-exit-code result) 1)
  (check-equal? (stage-statuses result)
                '("passed" "failed" "passed" "passed" "passed" "passed"))
  (check-true (string-contains? (fixture-result-log result)
                                "target=docs-check status=passed")))

(test-case "multiple failures retain every independent result"
  (define result (run-fixture "multiple-failures" "30s"))
  (check-equal? (fixture-result-exit-code result) 1)
  (check-equal? (stage-statuses result)
                '("failed" "passed" "passed" "passed" "failed" "passed"))
  (check-equal? (hash-ref (fixture-result-summary result) 'status) "failure"))

(test-case "timeout identifies its stage and skips remaining work"
  (define result (run-fixture "timeout" "3s"))
  (check-equal? (fixture-result-exit-code result) 124)
  (check-equal? (stage-statuses result)
                '("passed" "timed-out" "skipped" "skipped" "skipped" "skipped"))
  (check-true (hash-ref (fixture-result-summary result) 'timed_out))
  (check-equal? (hash-ref (fixture-result-summary result) 'timeout_stage)
                "compile-checks")
  (check-equal? (fixture-result-errors result) ""))

;; Isolation must include compiler scratch space and clean Go-style read-only caches.
(test-case "isolated commands clean read-only state on every exit"
  (define isolated-runner
    (build-path repository-root "scripts" "run-isolated-racket-tests.sh"))
  (define root (make-temporary-file "odra-isolation-check-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (for ([scenario (in-list '((default 0) (default 17) (explicit 0) (explicit 17)))])
       (define explicit? (eq? (car scenario) 'explicit))
       (define exit-code (cadr scenario))
       (define environment
         (environment-variables-copy (current-environment-variables)))
       (environment-variables-set! environment #"TMPDIR"
                                   (and explicit? (path->bytes root)))
       (define-values (process output input errors)
         (parameterize ([current-environment-variables environment])
           (subprocess
            #f #f #f bash-path isolated-runner bash-path "-c"
            (string-append
             "printf '%s\\n' \"$HOME\" \"$XDG_CONFIG_HOME\" \"$XDG_STATE_HOME\" "
             "\"$XDG_CACHE_HOME\" \"$XDG_DATA_HOME\" \"$TMPDIR\"; "
             "mkdir -p \"$HOME/go/pkg/mod/fixture\"; "
             "printf fixture > \"$HOME/go/pkg/mod/fixture/module.go\"; "
             "chmod 444 \"$HOME/go/pkg/mod/fixture/module.go\"; "
             "chmod 555 \"$HOME/go/pkg/mod/fixture\"; "
             "exit \"$1\"")
            "isolation-fixture" (number->string exit-code))))
       (close-output-port input)
       (define paths (string-split (port->string output) "\n"))
       (define standard-error (port->string errors))
       (subprocess-wait process)
       (close-input-port output)
       (close-input-port errors)
       (check-equal? (subprocess-status process) exit-code (format "~a" scenario))
       (check-equal? standard-error "")
       (check-equal? (length paths) 6)
       (define owned-root (simplify-path (build-path (car paths) 'up)))
       (check-equal? (simplify-path (build-path owned-root 'up))
                     (path->directory-path
                      (if explicit? root
                          (build-path repository-root ".build" "test-isolation"))))
       (for ([path (in-list paths)])
         (check-equal? (simplify-path (build-path path 'up)) owned-root))
       (check-false (directory-exists? owned-root))))
   (lambda () (delete-directory/files root))))
