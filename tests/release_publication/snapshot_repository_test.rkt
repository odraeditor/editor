#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/path
         racket/port
         racket/string
         racket/system
         rackunit
         rackunit/text-ui
         "../../scripts/release/snapshot-repository.rkt")

(define git
  (or (find-executable-path "git")
      (raise-user-error 'snapshot-repository-test "git is unavailable")))

(define (run-git repository . arguments)
  (define prefix
    (if repository (list "-C" (path->string repository)) '()))
  (define-values (process output input errors)
    (apply subprocess #f #f #f git (append prefix arguments)))
  (close-output-port input)
  (define standard-output (port->string output))
  (define standard-error (port->string errors))
  (subprocess-wait process)
  (unless (zero? (subprocess-status process))
    (error 'snapshot-repository-test
           "git ~a failed: ~a"
           (string-join arguments " ")
           standard-error))
  (string-trim standard-output))

(define (write-file path content)
  (make-parent-directory* path)
  (call-with-output-file path
    #:exists 'truncate/replace
    (lambda (output) (display content output))))

(define (make-snapshot root marker)
  (make-directory root)
  (write-file (build-path root "README.md") (format "# Snapshot ~a\n" marker))
  (write-file (build-path root "src" "main.odin")
              (format "package main\n// ~a\n" marker)))

(define (with-fixture procedure)
  (define root (make-temporary-file "snapshot-repository-test-~a" 'directory))
  (define original-authorization (getenv "ODRA_TEST_AUTHORIZATION"))
  (dynamic-wind
   (lambda () (putenv "ODRA_TEST_AUTHORIZATION" "fixture-secret"))
   (lambda () (procedure root))
   (lambda ()
     (putenv "ODRA_TEST_AUTHORIZATION" (or original-authorization ""))
     (delete-directory/files root))))

(define (initialize-bare path)
  (run-git #f "init" "--bare" "--quiet" "--initial-branch=main"
           (path->string path)))

(define (bare-ref bare reference)
  (define-values (process output input errors)
    (subprocess #f #f #f git "--git-dir" (path->string bare)
                "rev-parse" reference))
  (close-output-port input)
  (define value (string-trim (port->string output)))
  (port->string errors)
  (subprocess-wait process)
  (and (zero? (subprocess-status process)) value))

(define lifecycle-tests
  (test-suite
   "Snapshot repository lifecycle"

   (test-case "Prepares one clean deterministic snapshot commit"
     (with-fixture
      (lambda (root)
        (define source (build-path root "source"))
        (define target (build-path root "target.git"))
        (make-snapshot source "one")
        (initialize-bare target)
        (define first
          (prepare-snapshot-commit! source (build-path root "first")
                                    "0.2.0" 1790430000
                                    #:target (path->string target)))
        (define second
          (prepare-snapshot-commit! source (build-path root "second")
                                    "0.2.0" 1790430000
                                    #:target (path->string target)))
        (check-equal? (prepared-snapshot-commit first)
                      (prepared-snapshot-commit second))
        (check-false (prepared-snapshot-parent first))
        (check-equal?
         (run-git (prepared-snapshot-workspace first) "rev-list" "--count"
                  (prepared-snapshot-commit first))
         "1")
        (check-equal? (prepared-snapshot-candidate-ref first)
                      "refs/heads/candidates/v0.2.0"))))

   (test-case "Transfers idempotently and verifies through a fresh checkout"
     (with-fixture
      (lambda (root)
        (define source (build-path root "source"))
        (define target (build-path root "target.git"))
        (make-snapshot source "one")
        (initialize-bare target)
        (define prepared
          (prepare-snapshot-commit! source (build-path root "workspace")
                                    "0.2.0" 1790430000
                                    #:target (path->string target)
                                    #:authorization-env "ODRA_TEST_AUTHORIZATION"))
        (check-equal?
         (transfer-result-state
          (transfer-snapshot-candidate!
           prepared (path->string target)
           #:authorization-env "ODRA_TEST_AUTHORIZATION"))
         'created)
        (check-equal?
         (transfer-result-state
          (transfer-snapshot-candidate!
           prepared (path->string target)
           #:authorization-env "ODRA_TEST_AUTHORIZATION"))
         'identical)
        (define checkout (build-path root "checkout"))
        (define verified
          (verify-snapshot-candidate!
           (path->string target)
           (prepared-snapshot-candidate-ref prepared)
           (prepared-snapshot-commit prepared)
           (prepared-snapshot-tree prepared)
           checkout
           #:authorization-env "ODRA_TEST_AUTHORIZATION"))
        (check-equal? (transfer-result-state verified) 'verified)
        (check-equal? (file->string (build-path checkout "README.md"))
                      "# Snapshot one\n")
        (check-false
         (regexp-match? #rx"fixture-secret"
                        (file->string (build-path checkout ".git" "config")))))))

   (test-case "Rejects a conflicting candidate identity"
     (with-fixture
      (lambda (root)
        (define target (build-path root "target.git"))
        (define first-source (build-path root "first-source"))
        (define second-source (build-path root "second-source"))
        (initialize-bare target)
        (make-snapshot first-source "one")
        (make-snapshot second-source "different")
        (define first
          (prepare-snapshot-commit! first-source (build-path root "first")
                                    "0.2.0" 1790430000))
        (define second
          (prepare-snapshot-commit! second-source (build-path root "second")
                                    "0.2.0" 1790430000))
        (transfer-snapshot-candidate! first (path->string target))
        (check-exn exn:fail?
                   (lambda ()
                     (transfer-snapshot-candidate! second
                                                   (path->string target)))))))

   (test-case "Recovers candidate transfer after an unreferenced object upload"
     (with-fixture
      (lambda (root)
        (define source (build-path root "source"))
        (define target (build-path root "target.git"))
        (make-snapshot source "one")
        (initialize-bare target)
        (define prepared
          (prepare-snapshot-commit! source (build-path root "workspace")
                                    "0.2.0" 1790430000))
        (run-git (prepared-snapshot-workspace prepared)
                 "push" (path->string target)
                 (string-append (prepared-snapshot-commit prepared)
                                ":refs/heads/interrupted"))
        (run-git #f "--git-dir" (path->string target)
                 "update-ref" "-d" "refs/heads/interrupted")
        (check-equal?
         (transfer-result-state
          (transfer-snapshot-candidate! prepared (path->string target)))
         'created))))

   (test-case "Publishes initial and later releases as linear immutable state"
     (with-fixture
      (lambda (root)
        (define target (build-path root "target.git"))
        (initialize-bare target)
        (define first-source (build-path root "source-one"))
        (make-snapshot first-source "one")
        (define first
          (prepare-snapshot-commit! first-source (build-path root "first")
                                    "0.2.0" 1790430000
                                    #:target (path->string target)))
        (transfer-snapshot-candidate! first (path->string target))
        (check-equal? (transfer-result-state
                       (publish-snapshot-release! first (path->string target)))
                      'created)
        (check-equal? (transfer-result-state
                       (publish-snapshot-release! first (path->string target)))
                      'identical)
        (define first-state
          (inspect-snapshot-target (path->string target) "0.2.0"))
        (check-equal? (snapshot-target-state-candidate first-state)
                      (prepared-snapshot-commit first))
        (check-equal? (snapshot-target-state-main first-state)
                      (prepared-snapshot-commit first))
        (check-true (regexp-match? #px"^[0-9a-f]{40}$"
                                   (snapshot-target-state-tag first-state)))
        (define second-source (build-path root "source-two"))
        (make-snapshot second-source "two")
        (define second
          (prepare-snapshot-commit! second-source (build-path root "second")
                                    "0.3.0" 1790433600
                                    #:target (path->string target)))
        (check-equal? (prepared-snapshot-parent second)
                      (prepared-snapshot-commit first))
        (transfer-snapshot-candidate! second (path->string target))
        (publish-snapshot-release! second (path->string target))
        (check-equal? (bare-ref target "refs/heads/main")
                      (prepared-snapshot-commit second))
        (check-equal?
         (run-git (prepared-snapshot-workspace second) "rev-list" "--count"
                  (prepared-snapshot-commit second))
         "2"))))

   (test-case "Protects release tags and rejects credential-bearing targets"
     (with-fixture
      (lambda (root)
        (define target (build-path root "target.git"))
        (initialize-bare target)
        (define source (build-path root "source"))
        (make-snapshot source "one")
        (define first
          (prepare-snapshot-commit! source (build-path root "first")
                                    "0.2.0" 1790430000
                                    #:target (path->string target)))
        (publish-snapshot-release! first (path->string target))
        (define changed-source (build-path root "changed-source"))
        (make-snapshot changed-source "changed")
        (define conflicting
          (prepare-snapshot-commit! changed-source (build-path root "conflicting")
                                    "0.2.0" 1790433600
                                    #:target (path->string target)))
        (check-exn exn:fail?
                   (lambda ()
                     (publish-snapshot-release! conflicting
                                                (path->string target))))
        (check-exn exn:fail:contract?
                   (lambda ()
                     (transfer-snapshot-candidate!
                      first "https://secret@example.invalid/odra/editor.git")))
        (check-exn exn:fail:contract?
                   (lambda ()
                     (transfer-snapshot-candidate!
                      first "secret@example.invalid:odra/editor.git"))))))))

(define failures (run-tests lifecycle-tests))
(unless (zero? failures) (exit 1))
