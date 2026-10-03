#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         racket/contract/base
         racket/file
         racket/list
         racket/path
         racket/port
         racket/string
         "manifest-contracts.rkt")

(provide
 (struct-out odra-package-archive-production)
 (struct-out odra-package-archive-production-failure)
 (contract-out
  [produce-package-archive
   (-> odra-package-manifest? path-string? path-string? symbol? symbol?
       (or/c odra-package-archive-production?
             odra-package-archive-production-failure?))]))

(struct odra-package-archive-production
  (path digest size member-count expanded-bytes)
  #:transparent)

(struct odra-package-archive-production-failure (code path detail)
  #:transparent)

(struct exn:fail:archive-production exn:fail (code path) #:transparent)

(define (fail code path detail)
  (raise
   (exn:fail:archive-production
    detail (current-continuation-marks) code path)))

(define (file-digest path)
  (call-with-input-file path
    (lambda (input) (bytes->hex-string (sha256-bytes input)))
    #:mode 'binary))

(define (target-artifact? artifact platform architecture)
  (define target (odra-package-artifact-target artifact))
  (or (not target)
      (and (eq? platform (odra-package-target-platform target))
           (eq? architecture (odra-package-target-architecture target)))))

(define (relative-path root path)
  (string-replace (path->string (find-relative-path root path)) "\\" "/"))

(define (source-files root)
  (define result '())
  (define (walk directory)
    (for ([path (in-list (sort (directory-list directory #:build? #t)
                               string<? #:key path->string))])
      (when (link-exists? path)
        (fail 'unsafe-path (path->string path)
              "package source contains a symbolic link"))
      (cond
        [(directory-exists? path) (walk path)]
        [(file-exists? path)
         (set! result (cons (relative-path root path) result))]
        [else
         (fail 'unsafe-path (path->string path)
               "package source contains a special filesystem object")])))
  (walk root)
  (sort result string<?))

(define (run-command executable arguments code path)
  (define-values (process output input errors)
    (apply subprocess #f #f #f executable arguments))
  (close-output-port input)
  (define stdout (port->bytes output))
  (define stderr (port->bytes errors))
  (close-input-port output)
  (close-input-port errors)
  (subprocess-wait process)
  (unless (zero? (subprocess-status process))
    (fail code path
          (bytes->string/utf-8 (bytes-append stdout stderr) #\uFFFD))))

(define (copy-declared-artifact source-root stage artifact)
  (define relative (odra-package-artifact-path artifact))
  (define source (build-path source-root (string->path relative)))
  (unless (and (file-exists? source) (not (link-exists? source)))
    (fail 'missing-artifact relative "declared package artifact is absent"))
  (unless (= (file-size source) (odra-package-artifact-size artifact))
    (fail 'artifact-size relative "declared package artifact size differs"))
  (unless (string=? (file-digest source)
                    (odra-package-artifact-digest artifact))
    (fail 'artifact-digest relative "declared package artifact digest differs"))
  (define destination (build-path stage (string->path relative)))
  (make-parent-directory* destination)
  (copy-file source destination)
  (file-or-directory-permissions destination #o600))

(define (produce-package-archive manifest source-root output-path platform architecture)
  (define complete-source (path->complete-path source-root))
  (define complete-output (path->complete-path output-path))
  (define stage #f)
  (with-handlers
      ([exn:fail:archive-production?
        (lambda (observed)
          (when (and stage (directory-exists? stage))
            (delete-directory/files stage))
          (odra-package-archive-production-failure
           (exn:fail:archive-production-code observed)
           (exn:fail:archive-production-path observed)
           (exn-message observed)))]
       [exn:fail?
        (lambda (observed)
          (when (and stage (directory-exists? stage))
            (delete-directory/files stage))
          (odra-package-archive-production-failure
           'io (path->string complete-output) (exn-message observed)))])
    (unless (and (directory-exists? complete-source)
                 (not (link-exists? complete-source)))
      (fail 'source (path->string complete-source)
            "package archive source is not a regular directory"))
    (when (or (file-exists? complete-output)
              (directory-exists? complete-output)
              (link-exists? complete-output))
      (fail 'output-exists (path->string complete-output)
            "package archive output already exists"))
    (define artifacts
      (filter (lambda (artifact)
                (target-artifact? artifact platform architecture))
              (odra-package-manifest-artifacts manifest)))
    (define expected-files
      (sort (cons "odra-package.rktd"
                  (map odra-package-artifact-path artifacts))
            string<?))
    (define observed-files (source-files complete-source))
    (unless (equal? observed-files expected-files)
      (fail 'archive-shape (path->string complete-source)
            "package source files differ from the confirmed manifest"))
    (define manifest-bytes (package-manifest->canonical-bytes manifest))
    (define source-manifest (build-path complete-source "odra-package.rktd"))
    (unless (bytes=? (file->bytes source-manifest) manifest-bytes)
      (fail 'manifest-digest "odra-package.rktd"
            "package source manifest is not the canonical confirmed manifest"))
    (set! stage (make-temporary-file "odra-package-archive-~a" 'directory))
    (file-or-directory-permissions stage #o700)
    (define staged-manifest (build-path stage "odra-package.rktd"))
    (call-with-output-file staged-manifest
      (lambda (output) (write-bytes manifest-bytes output))
      #:exists 'error #:mode 'binary #:permissions #o600)
    (for ([artifact (in-list artifacts)])
      (copy-declared-artifact complete-source stage artifact))
    (define raw-archive (build-path stage "archive.tar"))
    (define member-paths
      (cons "odra-package.rktd"
            (map odra-package-artifact-path artifacts)))
    (run-command
     "/usr/bin/tar"
     (append
      (list "--format=ustar" "--owner=0" "--group=0" "--numeric-owner"
            "--mtime=@0" "--mode=u=rw,go=" "-cf" (path->string raw-archive)
            "-C" (path->string stage) "--")
      member-paths)
     'tar (path->string complete-output))
    (make-parent-directory* complete-output)
    (run-command
     "/usr/bin/zstd"
     (list "-q" "-f" "-19" "--no-progress" "-o"
           (path->string complete-output) (path->string raw-archive))
     'zstd (path->string complete-output))
    (file-or-directory-permissions complete-output #o600)
    (define result
      (odra-package-archive-production
       (path->string complete-output) (file-digest complete-output)
       (file-size complete-output) (length member-paths)
       (+ (bytes-length manifest-bytes)
          (for/sum ([artifact (in-list artifacts)])
            (odra-package-artifact-size artifact)))))
    (delete-directory/files stage)
    (set! stage #f)
    result))
