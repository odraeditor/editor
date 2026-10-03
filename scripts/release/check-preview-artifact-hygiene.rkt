#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (except-in openssl/sha1 sha1)
         (only-in file/sha1 bytes->hex-string)
         json
         racket/cmdline
         racket/file
         racket/list
         racket/path
         racket/port
         racket/string
         "add-preview-metadata.rkt"
         "archive-preview-tree.rkt"
         "assemble-preview-tree.rkt"
         "check-runtime-closure.rkt"
         "preview-identity.rkt")

(provide checksum-errors
         elf-private-metadata-findings
         sensitive-string-findings)

(define credential-patterns
  (list #px"-----BEGIN (?:RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----"
        #px"(?:^|[^[:alnum:]_])ghp_[[:alnum:]]{20,}"
        #px"github_pat_[[:alnum:]_]{20,}"
        #px"(?:FORGEJO|GITHUB|CODEBERG)_TOKEN="
        #px"password=[^[:space:]]+"))
(define host-path-patterns
  (list #px"/(?:home|Users)/[^/[:space:]]+/"
        #px"/root/"))
(define private-source-patterns
  (list #px"/workspace/(?:src|tests|ops)/[^[:space:]]+"))
(define private-elf-section-pattern
  #px"\\.(?:debug[^[:space:]]*|symtab)[[:space:]]")

(define (hash-value table key [fallback #f])
  (if (hash? table) (hash-ref table key fallback) fallback))

(define (regular-file? path)
  (eq? (file-or-directory-type path #f) 'file))

(define (sha256-file path)
  (call-with-input-file path
    (lambda (input) (bytes->hex-string (sha256-bytes input)))))

(define (run/capture executable arguments)
  (define-values (process output input error-output)
    (apply subprocess #f #f #f executable arguments))
  (close-output-port input)
  (define output-bytes (port->bytes output))
  (define error-text (port->string error-output))
  (close-input-port output)
  (close-input-port error-output)
  (subprocess-wait process)
  (values output-bytes (subprocess-status process) error-text))

(define (required-executable owner name)
  (or (find-executable-path name)
      (raise-user-error owner "required executable is unavailable: ~a" name)))

(define (checksum-errors archive checksum)
  (cond
    [(not (regular-file? archive)) '("preview archive is unavailable")]
    [(not (regular-file? checksum)) '("preview checksum is unavailable")]
    [else
     (define fields (string-split (string-trim (file->string checksum))))
     (define expected-name (path->string (file-name-from-path archive)))
     (define expected-digest (sha256-file archive))
     (append
      (if (= (length fields) 2)
          '()
          '("preview checksum record is malformed"))
      (if (and (= (length fields) 2)
               (equal? (car fields) expected-digest))
          '()
          '("preview archive checksum differs"))
      (if (and (= (length fields) 2)
               (equal? (cadr fields) expected-name))
          '()
          '("preview checksum filename differs")))]))

(define (sensitive-string-findings content)
  (append
   (for/list ([pattern (in-list host-path-patterns)]
              #:when (regexp-match? pattern content))
     "executable contains a host-specific absolute path")
   (for/list ([pattern (in-list credential-patterns)]
              #:when (regexp-match? pattern content))
     "executable contains a credential-like string")
   (for/list ([pattern (in-list private-source-patterns)]
              #:when (regexp-match? pattern content))
     "executable contains a private source path")))

(define (elf-private-metadata-findings content)
  (if (regexp-match? private-elf-section-pattern content)
      '("executable contains private debug or symbol metadata")
      '()))

(define (binary-string-errors binary)
  (define strings (required-executable 'preview-hygiene "strings"))
  (define-values (content status error-text)
    (run/capture strings (list "-a" (path->string binary))))
  (if (zero? status)
      (remove-duplicates
       (sensitive-string-findings (bytes->string/utf-8 content #\?)))
      (list (format "cannot inspect executable strings: ~a"
                    (string-trim error-text)))))

(define (elf-errors binary closure)
  (define readelf (required-executable 'preview-hygiene "readelf"))
  (define-values (needed interpreter) (read-elf-closure binary))
  (define-values (section-bytes section-status section-error)
    (run/capture readelf (list "--sections" "--wide" (path->string binary))))
  (define baseline (hash-value closure 'baseline (hasheq)))
  (append
   (if (equal? needed (hash-value baseline 'needed '()))
       '()
       (list (format "ELF dependency closure differs: ~a" needed)))
   (if (equal? interpreter (hash-value baseline 'interpreter))
       '()
       (list (format "ELF interpreter differs: ~a" interpreter)))
   (if (zero? section-status)
       (elf-private-metadata-findings
        (bytes->string/utf-8 section-bytes #\?))
       (list (format "cannot inspect ELF sections: ~a"
                     (string-trim section-error))))))

(define (identity-from-manifest manifest)
  (preview-identity (hash-value manifest 'tag)
                    (hash-value manifest 'commit)
                    (hash-value manifest 'commit)
                    (hash-value manifest 'source_date_epoch)
                    (hash-value manifest 'platform)))

(define (archive-errors archive tree source-date-epoch)
  (define zstd (required-executable 'preview-hygiene "zstd"))
  (define temporary-tar (make-temporary-file "preview-hygiene-~a.tar"))
  (dynamic-wind
    void
    (lambda ()
      (define-values (process output input error-output)
        (subprocess #f #f #f zstd
                    "--decompress"
                    "--stdout"
                    (path->string archive)))
      (close-output-port input)
      (call-with-output-file temporary-tar
        (lambda (destination) (copy-port output destination))
        #:exists 'truncate/replace)
      (define error-text (port->string error-output))
      (close-input-port output)
      (close-input-port error-output)
      (subprocess-wait process)
      (define status (subprocess-status process))
      (if (zero? status)
          (ustar-errors temporary-tar tree source-date-epoch)
          (list (format "cannot validate archive: ~a" (string-trim error-text)))))
    (lambda ()
      (when (file-exists? temporary-tar) (delete-file temporary-tar)))))

(define (notice-errors tree notice manifest)
  (define expected-name
    (hash-value (hash-value manifest 'artifact (hasheq))
                'third_party_notices))
  (append
   (if (and (regular-file? notice)
            (equal? (path->string (file-name-from-path notice)) expected-name))
       '()
       '("public third-party notice identity differs"))
   (if (and (regular-file? notice)
            (bytes=? (file->bytes notice)
                     (file->bytes (build-path tree "THIRD_PARTY_NOTICES.md"))))
       '()
       '("public third-party notice content differs"))))

(define (source-obligation-errors closure)
  (for/list ([component (in-list (hash-value closure 'components '()))]
             #:unless (equal? (hash-value component 'source_obligation) "none"))
    (format "redistributed component has an unmet source obligation: ~a"
            (hash-value component 'name))))

(define (generated-path-errors repository-root paths)
  (define git (required-executable 'preview-hygiene "git"))
  (define root (simple-form-path repository-root))
  (append-map
   (lambda (path)
     (define relative (find-relative-path root (simple-form-path path)))
     (if (member 'up (explode-path relative))
         '()
         (let-values ([(output status errors)
                       (run/capture git
                                    (list "-C"
                                          (path->string root)
                                          "check-ignore"
                                          "--quiet"
                                          (path->string relative)))])
           (if (zero? status)
               '()
               (list (format "generated artifact is not ignored by Git: ~a"
                             relative))))))
   paths))

(define (preview-artifact-hygiene-errors tree archive checksum notice closure repository-root)
  (define manifest-path (build-path tree "manifest.json"))
  (define manifest
    (and (regular-file? manifest-path)
         (with-handlers ([exn:fail? (lambda (_) #f)])
           (call-with-input-file manifest-path read-json))))
  (cond
    [(not manifest) '("preview manifest is unavailable or invalid")]
    [else
     (define identity (identity-from-manifest manifest))
     (define binary (build-path tree "bin" "odra"))
     (append
      (preview-identity-errors identity)
      (preview-tree-errors tree closure)
      (preview-metadata-errors identity
                               tree
                               closure
                               (hash-value manifest 'build_environment_digest))
      (elf-errors binary closure)
      (binary-string-errors binary)
      (checksum-errors archive checksum)
      (archive-errors archive tree (preview-identity-source-date-epoch identity))
      (notice-errors tree notice manifest)
      (source-obligation-errors closure)
      (generated-path-errors repository-root
                             (list tree archive checksum notice)))]))

(module+ main
  (define tree #f)
  (define archive #f)
  (define checksum #f)
  (define notice #f)
  (define closure-path #f)
  (define repository-root #f)
  (command-line
   #:program "check-preview-artifact-hygiene.rkt"
   #:once-each
   [("--tree") path "Extracted preview tree" (set! tree (path->complete-path path))]
   [("--archive") path "Preview archive" (set! archive (path->complete-path path))]
   [("--checksum") path "Preview checksum" (set! checksum (path->complete-path path))]
   [("--notice") path "Public third-party notice" (set! notice (path->complete-path path))]
   [("--closure") path "Runtime closure manifest" (set! closure-path path)]
   [("--repository-root") path "Repository root"
    (set! repository-root (path->complete-path path))])
  (for ([required (in-list (list tree archive checksum notice closure-path repository-root))])
    (unless required
      (raise-user-error 'preview-hygiene "all values are required")))
  (define closure (read-runtime-closure closure-path))
  (define errors
    (preview-artifact-hygiene-errors tree
                                     archive
                                     checksum
                                     notice
                                     closure
                                     repository-root))
  (unless (null? errors)
    (for-each (lambda (error) (eprintf "preview hygiene: ~a\n" error)) errors)
    (exit 1))
  (printf "preview_hygiene=valid files=~a components=~a\n"
          (length (find-files file-exists? tree))
          (length (hash-value closure 'components '()))))

(module+ test
  (require rackunit)

  (test-case "rejects private source paths and ELF metadata"
    (check-equal?
     (sensitive-string-findings "/workspace/src/odra/main.odin")
     '("executable contains a private source path"))
    (check-equal?
     (elf-private-metadata-findings
      "[32] .debug_info PROGBITS\n[40] .symtab SYMTAB\n")
     '("executable contains private debug or symbol metadata"))
    (check-equal?
     (elf-private-metadata-findings
      "[5] .dynsym DYNSYM\n[7] .dynstr STRTAB\n")
     '()))

  (test-case "rejects host paths and credential material"
    (check-equal?
     (sensitive-string-findings
      "/home/operator/project/src/main.odin\n-----BEGIN PRIVATE KEY-----")
     '("executable contains a host-specific absolute path"
       "executable contains a credential-like string")))

  (test-case "validates exact checksum identity"
    (define directory (make-temporary-file "preview-checksum-~a" 'directory))
    (dynamic-wind
      void
      (lambda ()
        (define archive (build-path directory "preview.tar.zst"))
        (define checksum (build-path directory "preview.tar.zst.sha256"))
        (call-with-output-file archive (lambda (output) (display "archive" output)))
        (call-with-output-file checksum
          (lambda (output)
            (fprintf output "~a  preview.tar.zst\n" (sha256-file archive))))
        (check-equal? (checksum-errors archive checksum) '())
        (call-with-output-file checksum
          (lambda (output) (display "invalid  other.tar.zst\n" output))
          #:exists 'truncate/replace)
        (check-not-equal? (checksum-errors archive checksum) '()))
      (lambda () (delete-directory/files directory))))

  (test-case "accepts artifacts outside the source checkout"
    (define directory (make-temporary-file "preview-paths-~a" 'directory))
    (dynamic-wind
      void
      (lambda ()
        (define repository (build-path directory "repository"))
        (define output (build-path directory "output" "artifact"))
        (make-directory* repository)
        (make-directory* output)
        (define-values (_ status __)
          (run/capture (required-executable 'preview-hygiene "git")
                       (list "-C" (path->string repository)
                             "init" "--quiet")))
        (check-equal? status 0)
        (check-equal? (generated-path-errors repository (list output)) '()))
      (lambda () (delete-directory/files directory)))))
