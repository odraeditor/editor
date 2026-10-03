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
         rackunit
         rackunit/text-ui
         "../../scripts/release/snapshot-build.rkt")

(define-runtime-path snapshot-build-script
  "../../scripts/release/snapshot-build.rkt")

(define git
  (or (find-executable-path "git")
      (raise-user-error 'snapshot-build-test "git is unavailable")))

(define racket-executable
  (or (find-executable-path "racket")
      (raise-user-error 'snapshot-build-test "racket is unavailable")))

(define fixture-commit "1111111111111111111111111111111111111111")
(define fixture-adapter-commit "2222222222222222222222222222222222222222")
(define fixture-digest
  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
(define fixture-image-digest
  "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
(define fixture-epoch 1790430000)

(define (write-file path content)
  (make-parent-directory* path)
  (call-with-output-file path
    #:exists 'truncate/replace
    (lambda (output) (display content output))))

(define (write-json-file path value)
  (write-file path (string-append (jsexpr->string value) "\n")))

(define (run-git repository . arguments)
  (define environment
    (environment-variables-copy (current-environment-variables)))
  (environment-variables-set! environment #"GIT_AUTHOR_NAME" #"Odra Fixture")
  (environment-variables-set! environment #"GIT_AUTHOR_EMAIL"
                              #"fixture@example.invalid")
  (environment-variables-set! environment #"GIT_COMMITTER_NAME"
                              #"Odra Fixture")
  (environment-variables-set! environment #"GIT_COMMITTER_EMAIL"
                              #"fixture@example.invalid")
  (environment-variables-set! environment #"GIT_AUTHOR_DATE"
                              (string->bytes/utf-8
                               (format "@~a +0000" fixture-epoch)))
  (environment-variables-set! environment #"GIT_COMMITTER_DATE"
                              (string->bytes/utf-8
                               (format "@~a +0000" fixture-epoch)))
  (define-values (process output input errors)
    (parameterize ([current-environment-variables environment])
      (apply subprocess #f #f #f git "-C" (path->string repository) arguments)))
  (close-output-port input)
  (define standard-output (port->string output))
  (define standard-error (port->string errors))
  (subprocess-wait process)
  (unless (zero? (subprocess-status process))
    (error 'snapshot-build-test
           "git ~a failed: ~a"
           (string-join arguments " ")
           standard-error))
  (string-trim standard-output))

(define (populate-checkout root)
  (for ([relative (in-list
                   '("Makefile"
                     "makefiles/internal.mk"
                     "release/linux-x86_64/Containerfile.build"
                     "release/linux-x86_64/runtime-closure.json"
                     "scripts/release/assemble-preview-tree.rkt"
                     "scripts/release/archive-preview-tree.rkt"
                     "scripts/release/build-racket-runtime-module.rkt"
                     "scripts/release/check-build-environment.rkt"
                     "scripts/release/record-preview-provenance.rkt"
                     "src/odra/main.odin"))])
    (write-file (build-path root relative) (format "fixture ~a\n" relative)))
  (write-json-file
   (build-path root "release" "public-source-manifest.json")
   (hasheq 'schema 1
           'model "odra-public-source-snapshot"
           'source_commit fixture-commit
           'inventory_sha256 fixture-digest))
  (write-json-file
   (build-path root "release" "linux-x86_64" "build-environment.json")
   (hasheq 'schema 1
           'images (hasheq 'build (hasheq 'digest fixture-image-digest)))))

(define (initialize-checkout root)
  (make-directory root)
  (run-git root "init" "--quiet" "--initial-branch=main")
  (populate-checkout root)
  (run-git root "add" "--all")
  (run-git root "commit" "--quiet" "-m" "snapshot fixture")
  (values (run-git root "rev-parse" "HEAD^{commit}")
          (run-git root "rev-parse" "HEAD^{tree}")))

(define (with-checkout procedure)
  (define root (make-temporary-file "snapshot-build-test-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define checkout (build-path root "checkout"))
     (define-values (commit tree) (initialize-checkout checkout))
     (procedure root checkout commit tree))
   (lambda () (delete-directory/files root))))

(define (fixture-request root checkout commit tree)
  (snapshot-build-request checkout commit tree fixture-adapter-commit
                          "0.2.0" fixture-epoch
                          (build-path root "output")))

(define (step-by-name plan name)
  (findf (lambda (step) (eq? (build-step-name step) name))
         (snapshot-build-plan-steps plan)))

(define build-tests
  (test-suite
   "Snapshot build adapter"

   (test-case "Plans a build from one exact clean snapshot checkout"
     (with-checkout
      (lambda (root checkout commit tree)
        (define plan
          (prepare-snapshot-build-plan
           (fixture-request root checkout commit tree)))
        (define identity (snapshot-build-plan-identity plan))
        (check-equal? (snapshot-build-identity-snapshot-commit identity) commit)
        (check-equal? (snapshot-build-identity-snapshot-tree identity) tree)
        (check-equal? (snapshot-build-identity-canonical-source-commit identity)
                      fixture-commit)
        (check-equal? (snapshot-build-identity-inventory-sha256 identity)
                      fixture-digest)
        (check-equal? (snapshot-build-identity-adapter-commit identity)
                      fixture-adapter-commit)
        (check-equal?
         (hash-ref (snapshot-build-identity->jsexpr identity)
                   'build_environment_digest)
         fixture-image-digest)
        (check-equal? (map build-step-name (snapshot-build-plan-steps plan))
                      '(environment-check image-build toolchain-probe
                        validation-image-build validation-image-probe
                        bundle-build provenance)))))

   (test-case "Keeps validation image failures observable"
     (with-checkout
      (lambda (root checkout commit tree)
        (define plan
          (prepare-snapshot-build-plan
           (fixture-request root checkout commit tree)))
        (define validation (step-by-name plan 'validation-image-build))
        (define arguments (build-step-arguments validation))
        (check-not-false (member "--progress=plain" arguments))
        (check-false (member "--quiet" arguments)))))

   (test-case "Probes the runtime image before native compilation"
     (with-checkout
      (lambda (root checkout commit tree)
        (define plan
          (prepare-snapshot-build-plan
           (fixture-request root checkout commit tree)))
        (define probe (step-by-name plan 'validation-image-probe))
        (define arguments (build-step-arguments probe))
        (check-equal? (build-step-program probe) "docker")
        (check-not-false (member "--network" arguments))
        (check-not-false (member "none" arguments))
        (check-true
         (for/or ([argument (in-list arguments)])
           (and (string-contains? argument "test ! -e /workspace")
                (string-contains? argument "libsodium.so")
                (string-contains? argument "command -v script")
                (string-contains? argument "command -v stty")))))))

   (test-case "Mounts only the read-only snapshot and isolated output"
     (with-checkout
      (lambda (root checkout commit tree)
        (define plan
          (prepare-snapshot-build-plan
           (fixture-request root checkout commit tree)))
        (define bundle (step-by-name plan 'bundle-build))
        (define arguments (build-step-arguments bundle))
        (check-equal? (build-step-program bundle) "docker")
        (check-equal? (build-step-timeout-seconds bundle) 7200)
        (check-equal? (car arguments) "run")
        (check-not-false
         (member (format "type=bind,src=~a,dst=/workspace,readonly"
                         (path->string checkout))
                 arguments))
        (check-not-false
         (member (format "type=bind,src=~a,dst=/workspace/.build"
                         (path->string (build-path root "output")))
                 arguments))
        (check-true
         (for/or ([argument (in-list arguments)])
           (string-suffix?
            argument
            "scripts/release/build-racket-runtime-module.rkt,dst=/release-adapter/build-racket-runtime-module.rkt,readonly")))
        (check-equal? (count (lambda (argument)
                               (string-prefix? argument "type=bind,"))
                             arguments)
                      3)
        (define user-position (index-of arguments "--user"))
        (check-not-false user-position)
        (check-regexp-match #px"^[0-9]+:[0-9]+$"
                            (list-ref arguments (add1 user-position)))
        (check-false (member "timeout" arguments)))))

   (test-case "Reuses the existing bundle and provenance machinery"
     (with-checkout
      (lambda (root checkout commit tree)
        (define plan
          (prepare-snapshot-build-plan
           (fixture-request root checkout commit tree)))
        (define command
          (last (build-step-arguments (step-by-name plan 'bundle-build))))
        (check-true (string-contains? command "mkdir -p \"$HOME\""))
        (check-true
         (string-contains?
          command
          "racket /release-adapter/build-racket-runtime-module.rkt"))
        (check-true (string-contains? command "make preview-tree"))
        (check-true (string-contains? command "make preview-archive"))
        (check-true (string-contains? command "BUILD_DIR=.build"))
        (check-true
         (string-suffix? (path->string (snapshot-build-plan-archive plan))
                         "odra-0.2.0-linux-x86_64.tar.zst"))
        (check-true
         (string-suffix? (car (build-step-arguments
                               (step-by-name plan 'provenance)))
                         "scripts/release/record-preview-provenance.rkt")))))

   (test-case "Rejects dirty, missing, mismatched, and overlapping inputs"
     (with-checkout
      (lambda (root checkout commit tree)
        (write-file (build-path checkout "untracked.txt") "dirty\n")
        (check-exn exn:fail?
                   (lambda ()
                     (prepare-snapshot-build-plan
                      (fixture-request root checkout commit tree))))
        (delete-file (build-path checkout "untracked.txt"))
        (check-exn exn:fail?
                   (lambda ()
                     (prepare-snapshot-build-plan
                      (snapshot-build-request
                       checkout fixture-commit tree fixture-adapter-commit
                       "0.2.0" fixture-epoch
                       (build-path root "output")))))
        (check-not-equal?
         (snapshot-build-request-errors
          (snapshot-build-request checkout commit tree fixture-adapter-commit
                                  "0.2.0" fixture-epoch
                                  (build-path checkout "output")))
         '())
        (define missing (build-path checkout "scripts" "release"
                                    "archive-preview-tree.rkt"))
        (delete-file missing)
        (check-not-equal?
         (snapshot-build-request-errors
          (fixture-request root checkout commit tree))
         '()))))

   (test-case "Prints a validated plan without executing the native build"
     (with-checkout
      (lambda (root checkout commit tree)
        (define output (build-path root "output"))
        (define-values (process standard-output standard-input standard-error)
          (subprocess
           #f #f #f racket-executable snapshot-build-script
           "--checkout" (path->string checkout)
           "--snapshot-commit" commit
           "--snapshot-tree" tree
           "--adapter-commit" fixture-adapter-commit
           "--version" "0.2.0"
           "--source-date-epoch" (number->string fixture-epoch)
           "--output" (path->string output)
           "--plan-only"))
        (close-output-port standard-input)
        (define result (port->string standard-output))
        (define diagnostic (port->string standard-error))
        (subprocess-wait process)
        (check-equal? (subprocess-status process) 0 diagnostic)
        (define summary (string->jsexpr (string-trim result)))
        (check-false (hash-ref summary 'executed))
        (check-equal? (hash-ref summary 'snapshot_commit) commit)
        (check-false (file-or-directory-type output #f)))))))

(define failures (run-tests build-tests))
(unless (zero? failures) (exit 1))
