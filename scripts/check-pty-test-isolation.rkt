#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.

(require racket/file
         racket/list
         racket/path
         racket/runtime-path
         racket/string)

(define-runtime-path script-directory ".")
(define repository-root (simplify-path (build-path script-directory "..") #t))
(define makefile-paths
  (list (build-path repository-root "Makefile")
        (build-path repository-root "makefiles" "internal.mk")))

(define (logical-recipes lines)
  (let loop ([remaining lines] [line-number 1] [recipes '()])
    (cond
      [(null? remaining) (reverse recipes)]
      [(regexp-match? #rx"ODRA_PTY_EXECUTABLE=" (car remaining))
       (define-values (recipe rest consumed)
         (let collect ([pending remaining] [parts '()] [count 0])
           (define line (car pending))
           (define next-parts (cons line parts))
           (define next-count (add1 count))
           (if (and (string-suffix? (string-trim line) "\\")
                    (pair? (cdr pending)))
               (collect (cdr pending) next-parts next-count)
               (values (string-join (reverse next-parts) "\n")
                       (cdr pending)
                       next-count))))
       (loop rest
             (+ line-number consumed)
             (cons (cons line-number recipe) recipes))]
      [else (loop (cdr remaining) (add1 line-number) recipes)])))

(define violations
  (for*/list ([path (in-list makefile-paths)]
              [recipe (in-list (logical-recipes (file->lines path)))]
              #:when (regexp-match? #rx"\\$\\(RACKET_TEST\\)" (cdr recipe)))
    (format "~a:~a: PTY acceptance must use $(PTY_RACKET_TEST)"
            (find-relative-path repository-root path)
            (car recipe))))

(unless (null? violations)
  (for ([violation (in-list violations)])
    (displayln violation (current-error-port)))
  (exit 1))

(printf "pty-test-isolation: checked ~a Makefile recipes\n"
        (for/sum ([path (in-list makefile-paths)])
          (length (logical-recipes (file->lines path)))))

(module+ test
  (require rackunit)
  (check-equal?
   (logical-recipes
    '("target:"
      "\tODRA_PTY_EXECUTABLE=.build/odra \\"
      "\t\t$(PTY_RACKET_TEST) tests/example.rkt"))
   (list
    (cons 2
          (string-append
           "\tODRA_PTY_EXECUTABLE=.build/odra \\\n"
           "\t\t$(PTY_RACKET_TEST) tests/example.rkt")))))
