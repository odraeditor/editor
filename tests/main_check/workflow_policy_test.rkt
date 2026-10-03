#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/list
         racket/runtime-path
         racket/string
         rackunit)

(define-runtime-path test-directory ".")
(define repository-root (simplify-path (build-path test-directory ".." "..") #t))
(define makefile-lines (file->lines (build-path repository-root "Makefile")))
(define internal-lines
  (file->lines (build-path repository-root "makefiles" "internal.mk")))
(define workflow
  (file->string (build-path repository-root ".forgejo" "workflows" "main-check.yml")))

(define (target-line lines name)
  (findf (lambda (line) (string-prefix? line (string-append name ":"))) lines))

(define (target-prerequisites lines name)
  (define line (target-line lines name))
  (check-not-false line (format "missing Make target: ~a" name))
  (string-split (string-trim (substring line (add1 (string-length name))))))

(define (target-recipe lines name)
  (define start
    (index-where lines
                 (lambda (line) (string=? line (string-append name ":")))))
  (check-not-false start (format "missing Make recipe: ~a" name))
  (for/list ([line (in-list (drop lines (add1 start)))]
             #:break (not (string-prefix? line "\t")))
    (string-trim line)))

(test-case "Main Check orders bounded integration after product build"
  (check-equal?
   (target-recipe makefile-lines "main-check")
   '("bash scripts/evidence/run-stage.sh source-hygiene -- $(MAKE) source-hygiene-check"
     "bash scripts/evidence/run-stage.sh documentation -- $(MAKE) docs-check"
     "bash scripts/evidence/run-stage.sh build -- $(MAKE) build"
     "bash scripts/evidence/run-stage.sh project-workspace-migration -- $(MAKE) project-workspace-migration-terminal-test")))

(test-case "terminal acceptance reuses official product artifacts"
  (check-equal? (target-prerequisites makefile-lines "build") '("odra"))
  (define product-prerequisites (target-prerequisites internal-lines "odra"))
  (define acceptance-prerequisites
    (target-prerequisites internal-lines
                          "project-workspace-migration-terminal-test"))
  (for ([required (in-list '("$(ODRA)"
                             "$(DAREK_MODULE_LIBRARY)"
                             "$(PRODUCT_MODULE_MANIFEST)"))])
    (check-not-false (member required product-prerequisites))
    (check-not-false (member required acceptance-prerequisites))))

(test-case "Forgejo main workflow delegates to the bounded target"
  (check-equal? (length (regexp-match* #px"run: make main-check" workflow)) 1)
  (check-false (regexp-match? #px"run: make (?:verify|nightly)" workflow)))
