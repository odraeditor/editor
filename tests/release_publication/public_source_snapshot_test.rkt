#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require json
         racket/file
         racket/path
         racket/port
         racket/string
         racket/system
         rackunit
         rackunit/text-ui
         "../../scripts/release/check-public-source-snapshot.rkt"
         "../../scripts/release/public-source-export.rkt")

(define git
  (or (find-executable-path "git")
      (raise-user-error 'public-source-snapshot-test "git is unavailable")))

(define canonical-hash-header
  (string-append
   "# SPDX-FileCopyrightText: 2026 Adrian PK\n"
   "# SPDX-License-Identifier: GPL-3.0-only\n"
   "#\n"
   "# This file is part of Odra. See COPYING for license terms.\n\n"))

(define canonical-slash-header
  (string-append
   "// SPDX-FileCopyrightText: 2026 Adrian PK\n"
   "// SPDX-License-Identifier: GPL-3.0-only\n"
   "//\n"
   "// This file is part of Odra. See COPYING for license terms.\n\n"))

(define (write-file path content)
  (make-parent-directory* path)
  (call-with-output-file path
    #:exists 'truncate/replace
    (lambda (output)
      (if (bytes? content)
          (write-bytes content output)
          (display content output)))))

(define (write-json-file path value)
  (write-file path (string-append (jsexpr->string value) "\n")))

(define (run-git repository . arguments)
  (define-values (process output input errors)
    (apply subprocess #f #f #f git "-C" (path->string repository) arguments))
  (close-output-port input)
  (define standard-output (port->string output))
  (define standard-error (port->string errors))
  (subprocess-wait process)
  (unless (zero? (subprocess-status process))
    (error 'public-source-snapshot-test
           "git ~a failed: ~a"
           (string-join arguments " ")
           standard-error))
  (string-trim standard-output))

(define (fixture-policy path)
  (define source
    (hasheq
     'schema 1
     'version "snapshot-fixture-v1"
     'rules
     (list (hasheq 'match "exact" 'pattern "COPYING"
                   'classification "include" 'reason "license-text")
           (hasheq 'match "exact" 'pattern "Makefile"
                   'classification "include" 'reason "build-entrypoint")
           (hasheq 'match "exact" 'pattern "REUSE.toml"
                   'classification "include" 'reason "license-metadata")
           (hasheq 'match "prefix" 'pattern "assets/"
                   'classification "include" 'reason "product-assets")
           (hasheq 'match "prefix" 'pattern "ops/"
                   'classification "exclude" 'reason "private-operations")
           (hasheq 'match "prefix" 'pattern "src/"
                   'classification "include" 'reason "product-source")
           (hasheq 'match "prefix" 'pattern "third_party/"
                   'classification "include" 'reason "third-party-source"))))
  (write-json-file path source)
  (read-export-policy path))

(define (fixture-contract path)
  (define source
    (hasheq
     'schema 1
     'version "snapshot-closure-fixture-v1"
     'forbidden_prefixes '(".git/" "ops/")
     'content_scan_exemptions '()
     'required_files '("COPYING" "Makefile" "src/main.odin"
                       "third_party/vendor/LICENSE")
     'required_prefixes '("src/" "third_party/")
     'declared_binary_inputs '("assets/logo.png")))
  (write-json-file path source)
  (read-closure-contract path))

(define (populate-repository root)
  (write-file (build-path root "COPYING") "GNU GENERAL PUBLIC LICENSE\n")
  (write-file (build-path root "Makefile")
              (string-append canonical-hash-header "all:\n\t@true\n"))
  (write-file
   (build-path root "REUSE.toml")
   (string-append
    canonical-hash-header
    "version = 1\n\n"
    "[[annotations]]\n"
    "path = [\n  \"assets/logo.png\",\n]\n"
    "precedence = \"aggregate\"\n"
    "SPDX-FileCopyrightText = \"2026 Adrian PK\"\n"
    "SPDX-License-Identifier = \"GPL-3.0-only\"\n"))
  (write-file (build-path root "assets" "logo.png") #"\211PNG\r\n\032\n\377")
  (write-file (build-path root "src" "main.odin")
              (string-append canonical-slash-header "package main\n"))
  (write-file (build-path root "third_party" "vendor" "LICENSE")
              "Fixture vendor license\n")
  (write-file (build-path root "ops" "private.md") "private\n"))

(define (initialize-repository root)
  (make-directory root)
  (run-git root "init" "--quiet" "--initial-branch=main")
  (run-git root "config" "user.name" "Odra Fixture")
  (run-git root "config" "user.email" "fixture@example.invalid")
  (populate-repository root)
  (run-git root "add" "--all")
  (run-git root "commit" "--quiet" "-m" "fixture")
  (run-git root "rev-parse" "HEAD"))

(define (with-export procedure)
  (define root (make-temporary-file "public-source-snapshot-test-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define repository (build-path root "repository"))
     (define policy-path (build-path root "policy.json"))
     (define contract-path (build-path root "closure.json"))
     (define commit (initialize-repository repository))
     (define output (build-path root "export"))
     (export-public-source! repository commit (fixture-policy policy-path) output)
     (procedure output (fixture-contract contract-path)))
   (lambda () (delete-directory/files root))))

(define (messages-containing audit fragment)
  (filter (lambda (message) (string-contains? message fragment))
          (snapshot-audit-errors audit)))

(define snapshot-tests
  (test-suite
   "Public source snapshot audit"

   (test-case "Accepts a complete exported fixture"
     (with-export
      (lambda (output contract)
        (define audit (audit-public-source-snapshot output contract))
        (check-equal? (snapshot-audit-errors audit) '())
        (check-equal? (snapshot-audit-binary-inputs audit) 1))))

   (test-case "Rejects private content"
     (with-export
      (lambda (output contract)
        (write-file (build-path output "tree" "src" "main.odin")
                    (string-append canonical-slash-header
                                   "package main\n// /home/adrian/private\n"))
        (define audit (audit-public-source-snapshot output contract))
        (check-not-equal?
         (messages-containing audit "sensitive content maintainer-home")
         '()))))

   (test-case "Rejects missing first-party licensing"
     (with-export
      (lambda (output contract)
        (write-file (build-path output "tree" "Makefile") "all:\n\t@true\n")
        (define audit (audit-public-source-snapshot output contract))
        (check-not-equal?
         (messages-containing audit "lacks the canonical notice: Makefile")
         '()))))

   (test-case "Rejects missing metadata licensing"
     (with-export
      (lambda (output contract)
        (write-file (build-path output "tree" "REUSE.toml")
                    (string-append canonical-hash-header "version = 1\n"))
        (define audit (audit-public-source-snapshot output contract))
        (check-not-equal?
         (messages-containing audit
                              "metadata lacks REUSE coverage: assets/logo.png")
         '()))))

   (test-case "Rejects incomplete source closure"
     (with-export
      (lambda (output contract)
        (define incomplete
          (hash-set contract 'required_files
                    (cons "scripts/missing-build-input.sh"
                          (hash-ref contract 'required_files))))
        (define audit (audit-public-source-snapshot output incomplete))
        (check-not-equal?
         (messages-containing audit "required source-closure file is missing")
         '()))))

   (test-case "Rejects undeclared binary inputs"
     (with-export
      (lambda (output contract)
        (define incomplete
          (hash-set contract 'declared_binary_inputs '()))
        (define audit (audit-public-source-snapshot output incomplete))
        (check-not-equal?
         (messages-containing audit "binary input declaration differs")
         '()))))

   (test-case "Rejects tree and inventory drift"
     (with-export
      (lambda (output contract)
        (write-file (build-path output "tree" "src" "extra.odin")
                    (string-append canonical-slash-header "package extra\n"))
        (define audit (audit-public-source-snapshot output contract))
        (check-not-equal?
         (messages-containing audit "tree paths differ")
         '()))))))

(define failures (run-tests snapshot-tests))
(unless (zero? failures) (exit 1))
