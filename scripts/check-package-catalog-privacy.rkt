#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/list
         racket/path
         racket/runtime-path)

(define-runtime-path repository-root "..")

(define checked-paths
  (list
   (build-path repository-root "src" "package_catalog" "official-bootstrap.rkt")
   (build-path repository-root "assets" "package-catalog" "curator-kit")))

(define forbidden
  (list
   (cons 'private-key-pem
         #rx#"BEGIN[ ]+(?:ENCRYPTED[ ]+)?PRIVATE[ ]+KEY")
   (cons 'secret-definition
         #rx#"[(]define[ ]+[^\r\n]*(?:secret|private)[-_]key")
   (cons 'embedded-credential
         #rx#"(?:password|access[-_]token|credential)[ ]*=[ ]*[^[:space:]]+")))

(define files
  (append*
   (for/list ([path (in-list checked-paths)])
     (if (directory-exists? path)
         (find-files file-exists? path)
         (list path)))))

(define failures
  (for*/list ([path (in-list files)]
              [rule (in-list forbidden)]
              #:when (regexp-match? (cdr rule) (file->bytes path)))
    (cons path (car rule))))

(unless (null? failures)
  (for ([failure (in-list failures)])
    (eprintf "package-catalog-privacy: rejected path=~a rule=~a\n"
             (find-relative-path repository-root (car failure))
             (cdr failure)))
  (exit 1))

(printf "package-catalog-privacy: pass files=~a\n" (length files))
