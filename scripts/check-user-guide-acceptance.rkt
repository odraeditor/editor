#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/list
         racket/path
         racket/string)

(provide check-user-guide-acceptance)

(define chapter-pattern
  #px"`(docs/tutorials/user-guide/[^`]+\\.md)`")

(define (chapter-files root)
  (sort
   (for/list ([path (in-directory root)]
              #:when (and (file-exists? path)
                          (equal? (path-get-extension path) #".md")
                          (not (equal? (path->string (file-name-from-path path))
                                       "index.md"))))
     (path->string
      (build-path "docs/tutorials/user-guide"
                  (find-relative-path root path))))
   string<?))

(define (reported-chapters report)
  (for/list ([match (in-list (regexp-match* chapter-pattern
                                             (file->string report)
                                             #:match-select values))])
    (cadr match)))

(define (duplicates values)
  (for/list ([value (in-list (remove-duplicates values))]
             #:when (> (count (lambda (candidate) (string=? value candidate)) values) 1))
    value))

(define (check-user-guide-acceptance root report)
  (define expected (chapter-files root))
  (define actual (reported-chapters report))
  (append
   (for/list ([path (in-list expected)]
              #:unless (member path actual))
     (format "~a: chapter is missing from the acceptance ledger" path))
   (for/list ([path (in-list actual)]
              #:unless (member path expected))
     (format "~a: acceptance ledger names an unknown chapter" path))
   (for/list ([path (in-list (duplicates actual))])
     (format "~a: chapter appears more than once in the acceptance ledger" path))))

(module+ main
  (define failures
    (check-user-guide-acceptance
     "docs/tutorials/user-guide"
     "ops/default/report/studies/user-guide-acceptance.md"))
  (unless (null? failures)
    (for-each displayln failures)
    (exit 1))
  (printf "Checked chapter-by-chapter User Guide acceptance.\n"))

(module+ test
  (require rackunit)

  (define (write-text path content)
    (make-parent-directory* path)
    (call-with-output-file path
      #:exists 'truncate
      (lambda (output) (display content output))))

  (define (with-fixture procedure)
    (define root (make-temporary-file "odra-user-guide-acceptance~a" 'directory))
    (dynamic-wind
      void
      (lambda ()
        (define guide (build-path root "docs" "tutorials" "user-guide"))
        (define report (build-path root "acceptance.md"))
        (write-text (build-path guide "index.md") "# User Guide\n")
        (write-text (build-path guide "part" "index.md") "# Part\n")
        (write-text (build-path guide "part" "one.md") "# One\n")
        (write-text (build-path guide "part" "two.md") "# Two\n")
        (procedure guide report))
      (lambda () (delete-directory/files root))))

  (test-case "accepts exactly one row per chapter"
    (with-fixture
     (lambda (guide report)
       (write-text report
                   (string-append
                    "`docs/tutorials/user-guide/part/one.md`\n"
                    "`docs/tutorials/user-guide/part/two.md`\n"))
       (check-equal? (check-user-guide-acceptance guide report) '()))))

  (test-case "rejects missing unknown and duplicate rows"
    (with-fixture
     (lambda (guide report)
       (write-text report
                   (string-append
                    "`docs/tutorials/user-guide/part/one.md`\n"
                    "`docs/tutorials/user-guide/part/one.md`\n"
                    "`docs/tutorials/user-guide/part/unknown.md`\n"))
       (define failures (check-user-guide-acceptance guide report))
       (check-equal? (length failures) 3)
       (check-true (for/or ([failure (in-list failures)])
                     (string-contains? failure "missing")))
       (check-true (for/or ([failure (in-list failures)])
                     (string-contains? failure "unknown")))
       (check-true (for/or ([failure (in-list failures)])
                     (string-contains? failure "more than once")))))))
