#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/cmdline
         racket/file
         racket/list
         racket/string)

(define files
  (command-line
   #:program "check-odin-doc-comments.rkt"
   #:args files
   files))

(define declaration-pattern #px"^\t\t[^\t ].* :: ")

(define failures
  (for*/list ([file (in-list files)]
              [lines (in-value (file->lines file))]
              [(line index) (in-indexed (in-list lines))]
              #:when (and (regexp-match? declaration-pattern line)
                          (or (= index (sub1 (length lines)))
                              (not (string-prefix? (list-ref lines (add1 index))
                                                   "\t\t\t")))))
    (format "~a:~a: public declaration has no source documentation: ~a"
            file
            (add1 index)
            (string-trim line))))

(unless (null? failures)
  (for-each displayln failures)
  (exit 1))

(printf "Checked public source documentation in ~a Odin packages.\n"
        (length files))
