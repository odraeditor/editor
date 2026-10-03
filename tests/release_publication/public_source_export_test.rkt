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
         "../../scripts/release/public-source-export.rkt")

(define-runtime-path policy-path "../../release/public-source-policy.json")

(define git
  (or (find-executable-path "git")
      (raise-user-error 'public-source-export-test "git is unavailable")))

(define (run-git repository . arguments)
  (define environment
    (environment-variables-copy (current-environment-variables)))
  (environment-variables-set! environment
                              #"GIT_AUTHOR_DATE"
                              #"2026-09-26T12:00:00Z")
  (environment-variables-set! environment
                              #"GIT_COMMITTER_DATE"
                              #"2026-09-26T12:00:00Z")
  (define-values (process output input errors)
    (parameterize ([current-environment-variables environment])
      (apply subprocess
             #f #f #f git
             "-C" (path->string repository)
             arguments)))
  (close-output-port input)
  (define standard-output (port->string output))
  (define standard-error (port->string errors))
  (subprocess-wait process)
  (unless (zero? (subprocess-status process))
    (error 'public-source-export-test
           "git ~a failed: ~a"
           (string-join arguments " ")
           standard-error))
  (string-trim standard-output))

(define (write-file path content [mode #o644])
  (make-parent-directory* path)
  (call-with-output-file path
    #:exists 'truncate/replace
    (lambda (output) (display content output)))
  (file-or-directory-permissions path mode))

(define (initialize-repository root populate)
  (make-directory root)
  (run-git root "init" "--quiet" "--initial-branch=main")
  (run-git root "config" "user.name" "Odra Fixture")
  (run-git root "config" "user.email" "fixture@example.invalid")
  (populate root)
  (run-git root "add" "--all")
  (run-git root "commit" "--quiet" "-m" "fixture")
  (run-git root "rev-parse" "HEAD"))

(define (populate-standard root)
  (write-file (build-path root "README.md") "# Fixture\n")
  (write-file (build-path root "src" "main.odin") "package main\n")
  (write-file (build-path root "scripts" "build.sh") "#!/bin/sh\nexit 0\n" #o755)
  (write-file (build-path root "docs" "source.md") "# Source\n")
  (make-file-or-directory-link "source.md" (build-path root "docs" "link.md"))
  (write-file (build-path root "ops" "private.md") "private\n"))

(define (with-temporary-root procedure)
  (define root (make-temporary-file "public-source-export-test-~a" 'directory))
  (dynamic-wind void
                (lambda () (procedure root))
                (lambda () (delete-directory/files root))))

(define export-tests
  (test-suite
   "Deterministic public source export"

   (test-case "Loads the versioned fail-closed policy"
     (define policy (read-export-policy policy-path))
     (check-true (export-policy-valid? policy))
     (check-equal? (string-length (export-policy-sha256 policy)) 64)
     (check-equal?
      (path-classification-classification
       (classify-export-path policy "src/main.odin"))
      'include)
     (check-equal?
      (path-classification-classification
       (classify-export-path policy "ops/default/spec/private.md"))
      'exclude)
     (check-exn exn:fail:contract?
                (lambda () (classify-export-path policy "unknown.file"))))

   (test-case "Rejects ambiguous and unsafe classifications"
     (define ambiguous
       (export-policy
        1
        "fixture-v1"
        (list (export-rule 'prefix "src/" 'include "source")
              (export-rule 'exact "src/main.odin" 'exclude "conflict"))
        (hasheq 'schema 1 'version "fixture-v1" 'rules '())))
     (check-true (export-policy-valid? ambiguous))
     (check-exn exn:fail:contract?
                (lambda ()
                  (classify-export-path ambiguous "src/main.odin")))
     (check-exn exn:fail:contract?
                (lambda ()
                  (classify-export-path ambiguous "../src/main.odin"))))

   (test-case "Inventories and exports one exact commit deterministically"
     (with-temporary-root
      (lambda (root)
        (define repository (build-path root "repository"))
        (define commit (initialize-repository repository populate-standard))
        (define policy (read-export-policy policy-path))
        (define inventory (build-source-inventory repository commit policy))
        (check-equal? (source-inventory-source-commit inventory) commit)
        (check-equal? (source-inventory-source-date-epoch inventory) 1790424000)
        (check-equal? (length (source-inventory-entries inventory)) 6)
        (check-equal?
         (count (lambda (entry)
                  (eq? (source-entry-classification entry) 'include))
                (source-inventory-entries inventory))
         5)
        (define first-output (build-path root "first"))
        (define second-output (build-path root "second"))
        (define first
          (export-public-source! repository commit policy first-output))
        (define second
          (export-public-source! repository commit policy second-output))
        (check-equal? (source-export-result-inventory-sha256 first)
                      (source-export-result-inventory-sha256 second))
        (check-equal? (source-export-result-tree-sha256 first)
                      (source-export-result-tree-sha256 second))
        (check-equal? (file->bytes (build-path first-output "inventory.json"))
                      (file->bytes (build-path second-output "inventory.json")))
        (check-equal? (file->bytes (build-path first-output "summary.json"))
                      (file->bytes (build-path second-output "summary.json")))
        (define tree (build-path first-output "tree"))
        (check-true (file-exists? (build-path tree "src" "main.odin")))
        (check-false (file-or-directory-type (build-path tree "ops") #f))
        (check-equal? (file-or-directory-permissions
                       (build-path tree "scripts" "build.sh")
                       'bits)
                      #o755)
        (check-equal? (file-or-directory-type
                       (build-path tree "docs" "link.md")
                       #f)
                      'link)
        (check-equal? (path->string
                       (resolve-path (build-path tree "docs" "link.md")))
                      "source.md")
        (define manifest
          (call-with-input-file
           (build-path tree "release" "public-source-manifest.json")
           read-json))
        (check-equal? (hash-ref manifest 'source_commit) commit)
        (check-equal? (hash-ref manifest 'included_files) 5)
        (check-equal? (hash-ref manifest 'excluded_files) 1))))

   (test-case "Rejects unclassified paths"
     (with-temporary-root
      (lambda (root)
        (define repository (build-path root "repository"))
        (define commit
          (initialize-repository
           repository
           (lambda (path)
             (write-file (build-path path "unclassified.txt") "no rule\n"))))
        (check-exn exn:fail:contract?
                   (lambda ()
                     (build-source-inventory
                      repository commit (read-export-policy policy-path)))))))

   (test-case "Rejects case-colliding paths"
     (with-temporary-root
      (lambda (root)
        (define repository (build-path root "repository"))
        (define commit
          (initialize-repository
           repository
           (lambda (path)
             (write-file (build-path path "src" "Case.odin") "package a\n")
             (write-file (build-path path "src" "case.odin") "package b\n"))))
        (check-exn exn:fail:contract?
                   (lambda ()
                     (build-source-inventory
                      repository commit (read-export-policy policy-path)))))))

   (test-case "Rejects escaping symlink targets"
     (with-temporary-root
      (lambda (root)
        (define repository (build-path root "repository"))
        (define commit
          (initialize-repository
           repository
           (lambda (path)
             (make-directory* (build-path path "docs"))
             (make-file-or-directory-link
              "/etc/passwd"
              (build-path path "docs" "escape.md")))))
        (check-exn exn:fail?
                   (lambda ()
                     (export-public-source!
                      repository
                      commit
                      (read-export-policy policy-path)
                      (build-path root "output")))))))

   (test-case "Preserves a non-empty destination"
     (with-temporary-root
      (lambda (root)
        (define repository (build-path root "repository"))
        (define commit (initialize-repository repository populate-standard))
        (define output (build-path root "output"))
        (make-directory output)
        (write-file (build-path output "keep.txt") "keep\n")
        (check-exn exn:fail:contract?
                   (lambda ()
                     (export-public-source!
                      repository commit (read-export-policy policy-path) output)))
        (check-equal? (file->string (build-path output "keep.txt"))
                      "keep\n"))))))

(define failures (run-tests export-tests))
(unless (zero? failures)
  (exit 1))
