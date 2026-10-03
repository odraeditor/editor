#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/list
         racket/port
         racket/runtime-path
         racket/system
         rackunit)

(define-runtime-path validator
  "../../scripts/validate-package-catalog-publication.rkt")
(define-runtime-path publisher
  "../../scripts/publish-package-catalog-snapshot.rkt")
(define-runtime-path repository
  "../package_catalog_publication_fixture/repository.rkt")
(define racket-executable
  (or (find-executable-path "racket")
      (error 'package-catalog-publisher-cli-test "racket is unavailable")))

(define (run-script script arguments)
  (define output (open-output-bytes))
  (define diagnostics (open-output-bytes))
  (define success?
    (parameterize ([current-output-port output]
                   [current-error-port diagnostics])
      (apply system* racket-executable script arguments)))
  (values success? (get-output-bytes output) (get-output-bytes diagnostics)))

(define (published-bytes root)
  (for/list ([path (in-list (sort (find-files file-exists? root)
                                  string<? #:key path->string))])
    (file->bytes path)))

(test-case "validator reports one bounded reproducible summary"
  (define-values (success? output diagnostics)
    (run-script validator (list "--repository" (path->string repository))))
  (check-true success? (bytes->string/utf-8 diagnostics))
  (check-true (< (bytes-length output) 512))
  (check-regexp-match #rx#"package-catalog-publication: valid" output)
  (check-equal? diagnostics #""))

(test-case "publisher writes only immutable local catalog output"
  (define output-root
    (make-temporary-file "odra-package-catalog-cli-~a" 'directory))
  (file-or-directory-permissions output-root #o700)
  (dynamic-wind
    void
    (lambda ()
      (define arguments
        (list "--repository" (path->string repository)
              "--output" (path->string output-root)))
      (define-values (first-success first-output first-diagnostics)
        (run-script publisher arguments))
      (check-true first-success (bytes->string/utf-8 first-diagnostics))
      (check-true (< (bytes-length first-output) 512))
      (define first-files (published-bytes output-root))
      (check-equal? (length first-files) 4)
      (define-values (second-success _second-output second-diagnostics)
        (run-script publisher arguments))
      (check-true second-success (bytes->string/utf-8 second-diagnostics))
      (check-equal? (published-bytes output-root) first-files))
    (lambda () (delete-directory/files output-root))))

(test-case "missing repository input fails explicitly"
  (define-values (success? _output diagnostics)
    (run-script validator (list "--repository" "missing-publication.rkt")))
  (check-false success?)
  (check-regexp-match #rx#"repository module is unavailable" diagnostics))

(test-case "entrypoints contain no implicit push or deployment operation"
  (for ([path (in-list (list validator publisher))])
    (define source (file->bytes path))
    (check-false (regexp-match? #rx#"git[ ]+push" source))
    (check-false (regexp-match? #rx#"deploy" source))))
