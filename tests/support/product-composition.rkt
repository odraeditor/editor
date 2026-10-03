#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.

(provide stage-product-composition!)

(require racket/file
         racket/list
         racket/path
         racket/string)

(define manifest-header "odra-product-modules 1")

(define (manifest-artifact-names manifest-path)
  (define lines (file->lines manifest-path))
  (unless (and (pair? lines) (string=? (car lines) manifest-header))
    (raise-arguments-error
     'stage-product-composition!
     "manifest does not declare the supported product composition"
     "manifest" manifest-path))
  (define names
    (for/list ([line (in-list (cdr lines))]
               #:when (string-prefix? line "artifact="))
      (substring line (string-length "artifact="))))
  (when (null? names)
    (raise-arguments-error
     'stage-product-composition!
     "manifest declares no product-module artifacts"
     "manifest" manifest-path))
  names)

(define (safe-artifact-name? name)
  (define leaf
    (and (not (string=? name ""))
         (file-name-from-path (string->path name))))
  (and leaf (equal? (path->string leaf) name)))

(define (stage-product-composition! executable manifest-path destination)
  (unless (file-exists? executable)
    (raise-arguments-error
     'stage-product-composition! "executable does not exist" "executable" executable))
  (unless (file-exists? manifest-path)
    (raise-arguments-error
     'stage-product-composition! "manifest does not exist" "manifest" manifest-path))
  (when (or (file-exists? destination) (directory-exists? destination))
    (raise-arguments-error
     'stage-product-composition! "destination already exists" "destination" destination))

  (define module-source (path-only manifest-path))
  (define artifacts (manifest-artifact-names manifest-path))
  (for ([artifact (in-list artifacts)])
    (unless (safe-artifact-name? artifact)
      (raise-arguments-error
       'stage-product-composition!
       "manifest artifact must be a file name"
       "artifact" artifact))
    (define artifact-path (build-path module-source artifact))
    (unless (file-exists? artifact-path)
      (raise-arguments-error
       'stage-product-composition!
       "manifest artifact does not exist"
       "artifact" artifact-path)))

  (make-directory destination)
  (define staged-executable
    (build-path destination (file-name-from-path executable)))
  (copy-file executable staged-executable)
  (copy-directory/files module-source (build-path destination "modules"))
  staged-executable)

(module+ test
  (require rackunit)

  (define root (make-temporary-file "odra-product-composition-~a" 'directory))
  (check-false (safe-artifact-name? ""))
  (check-false (safe-artifact-name? "../libodra-example.so"))
  (check-true (safe-artifact-name? "libodra-example.so"))
  (dynamic-wind
   void
   (lambda ()
     (define executable (build-path root "odra"))
     (define module-root (build-path root "source-modules"))
     (define artifact (build-path module-root "libodra-example.so"))
     (define manifest (build-path module-root "product-modules.manifest"))
     (define destination (build-path root "staged"))
     (call-with-output-file executable #:exists 'truncate (lambda (output) (display "core" output)))
     (make-directory module-root)
     (call-with-output-file artifact #:exists 'truncate (lambda (output) (display "module" output)))
     (call-with-output-file
      manifest
      #:exists 'truncate
      (lambda (output)
        (display
         (string-append manifest-header "\nmodule\nartifact=libodra-example.so\nend\n")
         output)))
     (define staged (stage-product-composition! executable manifest destination))
     (check-equal? (file->string staged) "core")
     (check-equal?
      (file->string (build-path destination "modules" "libodra-example.so"))
      "module")
     (check-true
      (file-exists? (build-path destination "modules" "product-modules.manifest"))))
   (lambda () (delete-directory/files root))))
