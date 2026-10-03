#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/path
         racket/port
         racket/string
         racket/system
         rackunit
         "../../src/package_catalog/manual-resolution.rkt")

(define (with-root action)
  (define root (make-temporary-file "odra-manual-failure-~a" 'directory))
  (file-or-directory-permissions root #o700)
  (dynamic-wind void (lambda () (action root))
                (lambda () (delete-directory/files root))))

(define (write-file path bytes)
  (make-directory* (path-only path))
  (void
   (call-with-output-file path
     (lambda (output) (write-bytes bytes output))
     #:exists 'truncate/replace #:mode 'binary)))

(define (directory-request source [generation 1])
  (odra-manual-package-source-request
   generation 'development-directory (path->string source) #f "bundle.rktd"))

(define (staging-empty? root)
  (define staging (build-path root "package-manual" "staging"))
  (or (not (directory-exists? staging))
      (null? (directory-list staging))))

(test-case "cancelled resolution removes its private staging directory"
  (with-root
   (lambda (root)
     (define source (build-path root "source"))
     (make-directory source)
     (write-file (build-path source "bundle.rktd") #"manifest")
     (define result
       (resolve-manual-package-source
        root (directory-request source) #:cancelled? (lambda () #t)))
     (check-eq? (odra-manual-package-resolution-failure-code result) 'cancelled)
     (check-true (staging-empty? root)))))

(test-case "directory links reject without publishing partial content"
  (with-root
   (lambda (root)
     (define source (build-path root "source"))
     (define outside (build-path root "outside"))
     (make-directory source)
     (write-file outside #"outside")
     (write-file (build-path source "bundle.rktd") #"manifest")
     (make-file-or-directory-link outside (build-path source "linked"))
     (define result
       (resolve-manual-package-source root (directory-request source)))
     (check-eq? (odra-manual-package-resolution-failure-code result)
                'unsafe-path)
     (check-true (staging-empty? root)))))

(test-case "native file and byte ceilings cannot be raised"
  (with-root
   (lambda (root)
     (define source (build-path root "source"))
     (make-directory source)
     (write-file (build-path source "bundle.rktd") #"manifest")
     (define result
       (resolve-manual-package-source
        root (directory-request source)
        #:file-limit (add1 maximum-manual-package-files)))
     (check-eq? (odra-manual-package-resolution-failure-code result) 'limit)
     (check-true (staging-empty? root)))))

(define (git! directory . arguments)
  (unless (apply system* "/usr/bin/git" "-C" (path->string directory) arguments)
    (error 'git! "fixture Git command failed")))

(define (git-output directory . arguments)
  (string-trim
   (with-output-to-string
     (lambda ()
       (unless (apply system* "/usr/bin/git" "-C" (path->string directory)
                      arguments)
         (error 'git-output "fixture Git command failed"))))))

(test-case "Git tag stays bound to its exact commit after the branch moves"
  (with-root
   (lambda (root)
     (define repository (build-path root "repository"))
     (make-directory repository)
     (git! repository "init" "-q")
     (git! repository "config" "user.name" "Fixture")
     (git! repository "config" "user.email" "fixture@example.invalid")
     (write-file (build-path repository "bundle.rktd") #"manifest-v1")
     (git! repository "add" ".")
     (git! repository "commit" "-q" "-m" "first")
     (git! repository "tag" "v1")
     (define tagged-revision (git-output repository "rev-parse" "v1^{commit}"))
     (write-file (build-path repository "bundle.rktd") #"manifest-v2")
     (git! repository "add" ".")
     (git! repository "commit" "-q" "-m" "second")
     (define result
       (resolve-manual-package-source
        root
        (odra-manual-package-source-request
         1 'git (path->string repository) "v1" "bundle.rktd")))
     (check-true (odra-manual-package-resolved-source? result) (format "~s" result))
     (check-equal?
      (odra-manual-package-resolved-source-resolved-source-revision result)
      tagged-revision)
     (check-equal?
      (file->bytes
       (build-path (odra-manual-package-resolved-source-content-path result)
                   "bundle.rktd"))
      #"manifest-v1"))))

(test-case "Git symbolic links reject before immutable publication"
  (with-root
   (lambda (root)
     (define repository (build-path root "repository"))
     (make-directory repository)
     (git! repository "init" "-q")
     (git! repository "config" "user.name" "Fixture")
     (git! repository "config" "user.email" "fixture@example.invalid")
     (write-file (build-path repository "bundle.rktd") #"manifest")
     (make-file-or-directory-link "bundle.rktd" (build-path repository "linked"))
     (git! repository "add" ".")
     (git! repository "commit" "-q" "-m" "link")
     (define result
       (resolve-manual-package-source
        root
        (odra-manual-package-source-request
         1 'git (path->string repository) "HEAD" "bundle.rktd")))
     (check-eq? (odra-manual-package-resolution-failure-code result)
                'unsafe-path)
     (check-true (staging-empty? root)))))
