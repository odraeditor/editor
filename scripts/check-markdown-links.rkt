#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/cmdline
         racket/file
         racket/list
         racket/path
         racket/string)

(define roots
  (command-line
   #:program "check-markdown-links.rkt"
   #:args roots
   roots))

(define link-pattern #px"\\]\\(([^)#]+)(?:#[^)]+)?\\)")

(define (markdown-files root)
  (for/list ([path (in-directory root)]
             #:when (and (file-exists? path)
                         (equal? (path-get-extension path) #".md")))
    path))

(define (local-link-target source link)
  (and (not (regexp-match? #px"^[A-Za-z][A-Za-z0-9+.-]*:" link))
       (not (string-prefix? link "/"))
       (simplify-path (build-path (path-only source) link) #f)))

(define failures
  (for*/list ([root (in-list roots)]
              [source (in-list (markdown-files root))]
              [match (in-list (regexp-match* link-pattern
                                             (file->string source)
                                             #:match-select values))]
              [link (in-value (cadr match))]
              [target (in-value (local-link-target source link))]
              #:when (and target
                          (not (file-exists? target))
                          (not (directory-exists? target))))
    (format "~a: missing local link target ~a" source link)))

(unless (null? failures)
  (for-each displayln failures)
  (exit 1))

(printf "Checked ~a Markdown files; all local link targets exist.\n"
        (for/sum ([root (in-list roots)]) (length (markdown-files root))))
