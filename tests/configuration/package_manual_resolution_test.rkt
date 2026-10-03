#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/path
         racket/system
         rackunit
         "../../src/package_catalog/manual-resolution.rkt")

(define (with-root action)
  (define root (make-temporary-file "odra-manual-resolution-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind void (lambda () (action root))
                (lambda () (delete-directory/files root))))

(define (write-file path bytes)
  (make-directory* (path-only path))
  (call-with-output-file path
    (lambda (output) (write-bytes bytes output))
    #:exists 'truncate/replace #:mode 'binary))

(define (request generation kind source label manifest)
  (odra-manual-package-source-request
   generation kind (path->string source) label manifest))

(test-case "development directory resolves to an immutable explicit snapshot"
  (with-root
   (lambda (root)
     (define source (build-path root "source"))
     (make-directory source)
     (write-file (build-path source "bundle.rktd") #"manifest-v1")
     (write-file (build-path source "src" "main.rkt") #"module-v1")
     (define first
       (resolve-manual-package-source
        root (request 1 'development-directory source #f "bundle.rktd")))
     (check-true (odra-manual-package-resolved-source? first) (format "~s" first))
     (check-equal? (odra-manual-package-resolved-source-file-count first) 2)
     (write-file (build-path source "src" "main.rkt") #"module-v2")
     (check-equal?
      (file->bytes
       (build-path (odra-manual-package-resolved-source-content-path first)
                   "src" "main.rkt"))
      #"module-v1")
     (define second
       (resolve-manual-package-source
        root (request 2 'development-directory source #f "bundle.rktd")
        #:previous first))
     (check-not-equal?
      (odra-manual-package-resolved-source-artifact-digest first)
      (odra-manual-package-resolved-source-artifact-digest second)))))

(test-case "local artifact is copied and addressed by its exact digest"
  (with-root
   (lambda (root)
     (define source (build-path root "package.tar.zst"))
     (write-file source #"immutable artifact")
     (define result
       (resolve-manual-package-source
        root (request 1 'local-artifact source #f #f)))
     (check-true (odra-manual-package-resolved-source? result))
     (check-equal?
      (file->bytes
       (build-path (odra-manual-package-resolved-source-content-path result)
                   "artifact"))
      #"immutable artifact"))))

(define (git! directory . arguments)
  (unless (apply system* "/usr/bin/git" "-C" (path->string directory) arguments)
    (error 'git! "fixture Git command failed")))

(test-case "Git branch resolves once to an exact immutable commit"
  (with-root
   (lambda (root)
     (define repository (build-path root "repository"))
     (make-directory repository)
     (git! repository "init" "-q")
     (git! repository "config" "user.name" "Fixture")
     (git! repository "config" "user.email" "fixture@example.invalid")
     (write-file (build-path repository "bundle.rktd") #"manifest-v1")
     (write-file (build-path repository "main.rkt") #"module-v1")
     (git! repository "add" ".")
     (git! repository "commit" "-q" "-m" "first")
     (define first
       (resolve-manual-package-source
        root (request 1 'git repository "HEAD" "bundle.rktd")))
     (check-true (odra-manual-package-resolved-source? first) (format "~s" first))
     (check-regexp-match
      #px"^[0-9a-f]{40}$"
      (odra-manual-package-resolved-source-resolved-source-revision first))
     (write-file (build-path repository "main.rkt") #"module-v2")
     (git! repository "add" ".")
     (git! repository "commit" "-q" "-m" "second")
     (check-equal?
      (file->bytes
       (build-path (odra-manual-package-resolved-source-content-path first)
                   "main.rkt"))
      #"module-v1")
     (define second
       (resolve-manual-package-source
        root (request 2 'git repository "HEAD" "bundle.rktd")
        #:previous first))
     (check-not-equal?
      (odra-manual-package-resolved-source-resolved-source-revision first)
      (odra-manual-package-resolved-source-resolved-source-revision second)))))

(test-case "reload generation must follow the retained source"
  (with-root
   (lambda (root)
     (define source (build-path root "source"))
     (make-directory source)
     (write-file (build-path source "bundle.rktd") #"manifest")
     (define first
       (resolve-manual-package-source
        root (request 1 'development-directory source #f "bundle.rktd")))
     (define result
       (resolve-manual-package-source
        root (request 3 'development-directory source #f "bundle.rktd")
        #:previous first))
     (check-eq? (odra-manual-package-resolution-failure-code result)
                'stale-generation))))
