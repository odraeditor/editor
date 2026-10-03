#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require json
         (except-in openssl/sha1 sha1)
         (only-in file/sha1 bytes->hex-string)
         racket/cmdline
         racket/file
         racket/list
         racket/path
         racket/port
         racket/string)

(provide record-preview-provenance
         tree-inventory)

(define provenance-model "pinned-input-provenance")
(define digest-pattern #px"^[0-9a-f]{64}$")
(define environment-pattern #px"^sha256:[0-9a-f]{64}$")
(define commit-pattern #px"^[0-9a-f]{40}$")

(define (sha256-file path)
  (call-with-input-file path
    (lambda (input) (bytes->hex-string (sha256-bytes input)))))

(define (relative-name root path)
  (path->string (find-relative-path root path)))

(define (path-kind path)
  (case (file-or-directory-type path #f)
    [(link) "link"]
    [(directory) "directory"]
    [(file) "file"]
    [else "unknown"]))

(define (mode-string path)
  (number->string (file-or-directory-permissions path 'bits) 8))

(define (tree-inventory root)
  (define complete-root (path->complete-path root))
  (define paths
    (sort (filter (lambda (path)
                    (not (equal? (simplify-path path)
                                 (simplify-path complete-root))))
                  (find-files (lambda (_) #t) complete-root #:follow-links? #f))
          string<?
          #:key (lambda (path) (relative-name complete-root path))))
  (for/list ([path (in-list paths)])
    (define kind (path-kind path))
    (define name (relative-name complete-root path))
    (define detail
      (cond
        [(equal? kind "file") (sha256-file path)]
        [(equal? kind "link") (path->string (resolve-path path))]
        [else "-"]))
    (format "~a\t~a\t~a\t~a" name kind (mode-string path) detail)))

(define (hash-value table key [fallback #f])
  (if (hash? table) (hash-ref table key fallback) fallback))

(define (path-name path)
  (path->string (file-name-from-path path)))

(define (regular-file? path)
  (eq? (file-or-directory-type path #f) 'file))

(define (read-checksum path)
  (define fields (string-split (string-trim (file->string path))))
  (if (pair? fields) (car fields) ""))

(define (write-lines path lines)
  (call-with-output-file path
    (lambda (output)
      (for ([line (in-list lines)])
        (displayln line output)))
    #:exists 'truncate/replace))

(define (manifest-errors manifest archive checksum tag commit source-date-epoch
                         build-environment)
  (define artifact (hash-value manifest 'artifact (hasheq)))
  (append
   (if (equal? (hash-value manifest 'tag) tag)
       '()
       '("manifest tag differs from requested release"))
   (if (equal? (hash-value manifest 'commit) commit)
       '()
       '("manifest commit differs from requested source"))
   (if (equal? (hash-value manifest 'source_date_epoch) source-date-epoch)
       '()
       '("manifest source date differs from requested source"))
   (if (equal? (hash-value manifest 'build_environment_digest)
               build-environment)
       '()
       '("manifest build environment differs from requested environment"))
   (if (equal? (hash-value artifact 'archive) (path-name archive))
       '()
       '("manifest archive name differs from produced archive"))
   (if (equal? (hash-value artifact 'checksum) (path-name checksum))
       '()
       '("manifest checksum name differs from produced checksum"))))

(define (record-preview-provenance tree archive checksum tag commit adapter-commit
                                   source-date-epoch build-environment
                                   evidence-directory)
  (define manifest-path (build-path tree "manifest.json"))
  (define executable-path (build-path tree "bin" "odra"))
  (define inventory (tree-inventory tree))
  (define archive-digest (sha256-file archive))
  (define checksum-value (read-checksum checksum))
  (define manifest
    (with-handlers ([exn:fail? (lambda (_) #f)])
      (call-with-input-file manifest-path read-json)))
  (define errors
    (append
     (if (and (string? checksum-value)
              (regexp-match? digest-pattern checksum-value)
              (equal? checksum-value archive-digest))
         '()
         '("checksum does not identify the produced archive"))
     (if (hash? manifest)
         (manifest-errors manifest archive checksum tag commit
                          source-date-epoch build-environment)
         '("preview manifest is unavailable or invalid"))
     (if (eq? (file-or-directory-type executable-path #f) 'file)
         '()
         '("preview executable is unavailable"))))
  (make-directory* evidence-directory)
  (write-lines (build-path evidence-directory "tree.inventory") inventory)
  (call-with-output-file (build-path evidence-directory "summary.json")
    (lambda (output)
      (write-json
       (hasheq 'schema 1
               'model provenance-model
               'provenance_valid (null? errors)
               'tag tag
               'commit commit
               'adapter_commit adapter-commit
               'source_date_epoch source-date-epoch
               'build_environment_digest build-environment
               'archive (path-name archive)
               'checksum (path-name checksum)
               'archive_sha256 archive-digest
               'manifest_sha256
               (and (regular-file? manifest-path) (sha256-file manifest-path))
               'executable_sha256
               (and (regular-file? executable-path) (sha256-file executable-path))
               'file_count (length inventory)
               'byte_identical_rebuilds_required #f
               'known_variable_paths '("bin/odra")
               'errors errors)
       output)
      (newline output))
    #:exists 'truncate/replace)
  errors)

(module+ main
  (define tree #f)
  (define archive #f)
  (define checksum #f)
  (define tag #f)
  (define commit #f)
  (define adapter-commit #f)
  (define source-date-epoch #f)
  (define build-environment #f)
  (define evidence-directory #f)
  (command-line
   #:program "record-preview-provenance.rkt"
   #:once-each
   [("--tree") path "Assembled preview tree" (set! tree path)]
   [("--archive") path "Preview archive" (set! archive path)]
   [("--checksum") path "Archive checksum" (set! checksum path)]
   [("--tag") value "Requested release tag" (set! tag value)]
   [("--commit") value "Requested source commit" (set! commit value)]
   [("--adapter-commit") value "Publication adapter commit"
    (set! adapter-commit value)]
   [("--source-date-epoch") value "Requested source date"
    (set! source-date-epoch (string->number value))]
   [("--build-environment") value "Pinned build environment digest"
    (set! build-environment value)]
   [("--evidence") path "Provenance evidence directory"
    (set! evidence-directory path)])
  (for ([required (in-list
                   (list tree archive checksum tag commit adapter-commit source-date-epoch
                         build-environment evidence-directory))])
    (unless required
      (raise-user-error 'preview-provenance "all values are required")))
  (unless (regexp-match? environment-pattern build-environment)
    (raise-user-error 'preview-provenance
                      "build environment digest is invalid"))
  (unless (regexp-match? commit-pattern adapter-commit)
    (raise-user-error 'preview-provenance
                      "publication adapter commit is invalid"))
  (define errors
    (record-preview-provenance tree archive checksum tag commit adapter-commit
                               source-date-epoch build-environment
                               evidence-directory))
  (unless (null? errors)
    (for-each (lambda (error) (eprintf "preview provenance: ~a\n" error)) errors)
    (exit 1))
  (printf "preview_provenance=valid sha256=~a evidence=~a\n"
          (sha256-file archive)
          evidence-directory))

(module+ test
  (require rackunit)

  (define fixture-tag "v1.2.3")
  (define fixture-commit "0123456789abcdef0123456789abcdef01234567")
  (define fixture-adapter-commit "89abcdef0123456789abcdef0123456789abcdef")
  (define fixture-source-date 1798761600)
  (define fixture-environment
    "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")

  (define (write-file path content [permissions #o644])
    (make-parent-directory* path)
    (call-with-output-file path
      (lambda (output) (display content output))
      #:exists 'truncate/replace)
    (file-or-directory-permissions path permissions))

  (define (fixture root)
    (define tree (build-path root "tree"))
    (define archive
      (build-path root "odra-1.2.3-linux-x86_64.tar.zst"))
    (define checksum
      (build-path root "odra-1.2.3-linux-x86_64.tar.zst.sha256"))
    (make-directory* tree)
    (write-file
     (build-path tree "manifest.json")
     (jsexpr->string
      (hasheq 'schema 1
              'tag fixture-tag
              'commit fixture-commit
              'source_date_epoch fixture-source-date
              'build_environment_digest fixture-environment
              'artifact
              (hasheq 'archive (path-name archive)
                      'checksum (path-name checksum)))))
    (write-file (build-path tree "bin" "odra") "binary" #o755)
    (write-file archive "canonical archive")
    (write-file checksum
                (format "~a  ~a\n" (sha256-file archive) (path-name archive)))
    (values tree archive checksum))

  (test-case "records one clean artifact and its exact provenance"
    (define root (make-temporary-file "preview-provenance-~a" 'directory))
    (dynamic-wind
      void
      (lambda ()
        (define-values (tree archive checksum) (fixture root))
        (define evidence (build-path root "evidence"))
        (check-equal?
         (record-preview-provenance
          tree archive checksum fixture-tag fixture-commit
          fixture-adapter-commit fixture-source-date
          fixture-environment evidence)
         '())
        (define summary
          (call-with-input-file (build-path evidence "summary.json") read-json))
        (check-true (hash-ref summary 'provenance_valid))
        (check-equal? (hash-ref summary 'adapter_commit)
                      fixture-adapter-commit)
        (check-false (hash-ref summary 'byte_identical_rebuilds_required))
        (check-equal? (hash-ref summary 'known_variable_paths) '("bin/odra"))
        (check-equal? (hash-ref summary 'file_count) 3))
      (lambda () (delete-directory/files root))))

  (test-case "rejects a checksum that does not identify the archive"
    (define root (make-temporary-file "preview-provenance-~a" 'directory))
    (dynamic-wind
      void
      (lambda ()
        (define-values (tree archive checksum) (fixture root))
        (write-file checksum
                    (format "~a  ~a\n" (make-string 64 #\a) (path-name archive)))
        (check-not-false
         (member
          "checksum does not identify the produced archive"
          (record-preview-provenance
           tree archive checksum fixture-tag fixture-commit
           fixture-adapter-commit fixture-source-date
           fixture-environment (build-path root "evidence")))))
      (lambda () (delete-directory/files root))))

  (test-case "rejects provenance that differs from the requested source"
    (define root (make-temporary-file "preview-provenance-~a" 'directory))
    (dynamic-wind
      void
      (lambda ()
        (define-values (tree archive checksum) (fixture root))
        (check-not-false
         (member
          "manifest commit differs from requested source"
          (record-preview-provenance
           tree archive checksum fixture-tag
           "1123456789abcdef0123456789abcdef01234567"
           fixture-adapter-commit fixture-source-date fixture-environment
           (build-path root "evidence")))))
      (lambda () (delete-directory/files root)))))
