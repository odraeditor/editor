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
         racket/runtime-path
         racket/string
         "add-preview-metadata.rkt"
         "assemble-preview-tree.rkt"
         "check-runtime-closure.rkt"
         "preview-identity.rkt")

(provide archive-preview-tree!
         read-ustar-entries
         ustar-errors
         (struct-out ustar-entry)
         (struct-out archive-result))

(define-runtime-path script-directory ".")
(define default-repository-root
  (simplify-path (build-path script-directory ".." "..")))
(define default-closure-path
  (build-path default-repository-root
              "release"
              "linux-x86_64"
              "runtime-closure.json"))
(define zstd-level "-19")
(define tar-block-size 512)

(struct ustar-entry (name mode uid gid size mtime type) #:transparent)
(struct archive-result (archive checksum notices digest) #:transparent)

(define (path-present? path)
  (or (file-exists? path)
      (directory-exists? path)
      (link-exists? path)))

(define (hash-value table key [fallback #f])
  (if (hash? table) (hash-ref table key fallback) fallback))

(define (plain-directory? path)
  (eq? (file-or-directory-type path #f) 'directory))

(define (deterministic-environment)
  (define environment
    (environment-variables-copy (current-environment-variables)))
  (environment-variables-set! environment #"LC_ALL" #"C")
  (environment-variables-set! environment #"LANG" #"C")
  (environment-variables-set! environment #"TZ" #"UTC")
  environment)

(define (run-command! owner executable arguments)
  (define-values (process output input error-output)
    (parameterize ([current-environment-variables (deterministic-environment)])
      (apply subprocess #f #f #f executable arguments)))
  (close-output-port input)
  (define output-bytes (port->bytes output))
  (define error-bytes (port->bytes error-output))
  (close-input-port output)
  (close-input-port error-output)
  (subprocess-wait process)
  (unless (zero? (subprocess-status process))
    (raise-user-error owner
                      "command failed: ~a ~a; stdout=~s; stderr=~s"
                      executable
                      (string-join arguments " ")
                      output-bytes
                      error-bytes))
  output-bytes)

(define (required-executable owner name)
  (or (find-executable-path name)
      (raise-user-error owner "required executable is unavailable: ~a" name)))

(define (sha256-file path)
  (call-with-input-file path
    (lambda (input) (bytes->hex-string (sha256-bytes input)))))

(define (field-string block start end)
  (define field (subbytes block start end))
  (define nul
    (for/first ([byte (in-bytes field)]
                [index (in-naturals)]
                #:when (zero? byte))
      index))
  (bytes->string/utf-8 (if nul (subbytes field 0 nul) field)))

(define (octal-field block start end)
  (define value (string-trim (field-string block start end)))
  (or (and (not (string=? value "")) (string->number value 8)) 0))

(define (zero-block? block)
  (for/and ([byte (in-bytes block)]) (zero? byte)))

(define (ustar-name block)
  (define name (field-string block 0 100))
  (define prefix (field-string block 345 500))
  (if (string=? prefix "") name (string-append prefix "/" name)))

(define (read-ustar-entries path)
  (call-with-input-file path
    (lambda (input)
      (let loop ([entries '()])
        (define block (read-bytes tar-block-size input))
        (cond
          [(eof-object? block) (reverse entries)]
          [(not (= (bytes-length block) tar-block-size))
           (raise-user-error 'ustar "truncated archive header")]
          [(zero-block? block) (reverse entries)]
          [else
           (define size (octal-field block 124 136))
           (define entry
             (ustar-entry (ustar-name block)
                          (octal-field block 100 108)
                          (octal-field block 108 116)
                          (octal-field block 116 124)
                          size
                          (octal-field block 136 148)
                          (integer->char (bytes-ref block 156))))
           (define padded-size
             (* tar-block-size (quotient (+ size (sub1 tar-block-size))
                                         tar-block-size)))
           (file-position input (+ (file-position input) padded-size))
           (loop (cons entry entries))])))))

(define (all-tree-paths root)
  (let loop ([path root])
    (if (plain-directory? path)
        (cons path
              (append-map loop
                          (sort (directory-list path #:build? #t) path<?)))
        (list path))))

(define (expected-ustar-entry tree path source-date-epoch)
  (define relative
    (path->string (find-relative-path (path-only tree) path)))
  (define directory? (plain-directory? path))
  (ustar-entry (if directory? (string-append relative "/") relative)
               (file-or-directory-permissions path 'bits)
               0
               0
               (if directory? 0 (file-size path))
               source-date-epoch
               (if directory? #\5 #\0)))

(define (ustar-errors tar-path tree source-date-epoch)
  (define actual (read-ustar-entries tar-path))
  (define expected
    (map (lambda (path)
           (expected-ustar-entry tree path source-date-epoch))
         (all-tree-paths tree)))
  (append
   (if (equal? (map ustar-entry-name actual)
               (map ustar-entry-name expected))
       '()
       '("archive entries are not complete and lexically sorted"))
   (if (= (length actual) (length expected))
       (append-map
        (lambda (actual-entry expected-entry)
          (append
           (if (= (ustar-entry-mode actual-entry)
                  (ustar-entry-mode expected-entry))
               '()
               (list (format "archive mode differs: ~a"
                             (ustar-entry-name actual-entry))))
           (if (and (zero? (ustar-entry-uid actual-entry))
                    (zero? (ustar-entry-gid actual-entry)))
               '()
               (list (format "archive ownership differs: ~a"
                             (ustar-entry-name actual-entry))))
           (if (= (ustar-entry-size actual-entry)
                  (ustar-entry-size expected-entry))
               '()
               (list (format "archive size differs: ~a"
                             (ustar-entry-name actual-entry))))
           (if (= (ustar-entry-mtime actual-entry) source-date-epoch)
               '()
               (list (format "archive timestamp differs: ~a"
                             (ustar-entry-name actual-entry))))
           (if (char=? (ustar-entry-type actual-entry)
                       (ustar-entry-type expected-entry))
               '()
               (list (format "archive type differs: ~a"
                             (ustar-entry-name actual-entry))))))
        actual
        expected)
       '())))

(define (validate-tree! identity tree closure)
  (unless (plain-directory? tree)
    (raise-user-error 'preview-archive "preview tree is unavailable: ~a" tree))
  (define expected-name (preview-artifact-stem identity))
  (unless (equal? (path->string (file-name-from-path tree)) expected-name)
    (raise-user-error 'preview-archive
                      "preview tree name differs: expected ~a"
                      expected-name))
  (define manifest
    (with-handlers ([exn:fail? (lambda (_) #f)])
      (call-with-input-file (build-path tree "manifest.json") read-json)))
  (define build-environment
    (hash-value manifest 'build_environment_digest))
  (define errors
    (append (preview-tree-errors tree closure)
            (preview-metadata-errors identity
                                     tree
                                     closure
                                     build-environment)))
  (unless (null? errors)
    (raise-arguments-error 'archive-preview-tree!
                           "invalid preview tree"
                           "errors" errors)))

(define (archive-preview-tree! identity tree closure-path output-parent)
  (define identity-errors (preview-identity-errors identity))
  (unless (null? identity-errors)
    (raise-arguments-error 'archive-preview-tree!
                           "invalid preview identity"
                           "errors" identity-errors))
  (define closure (read-runtime-closure closure-path))
  (validate-tree! identity tree closure)
  (make-directory* output-parent)
  (define archive-path (build-path output-parent (preview-archive-name identity)))
  (define checksum-path (build-path output-parent (preview-checksum-name identity)))
  (define notices-path (build-path output-parent (preview-notices-name identity)))
  (when (or (path-present? archive-path)
            (path-present? checksum-path)
            (path-present? notices-path))
    (raise-user-error 'preview-archive
                      "archive, checksum, or notices destination already exists"))

  (define tar (required-executable 'preview-archive "tar"))
  (define zstd (required-executable 'preview-archive "zstd"))
  (define temporary-tar
    (make-temporary-file "preview-archive-~a.tar" #f output-parent))
  (define temporary-archive
    (make-temporary-file "preview-archive-~a.tar.zst" #f output-parent))
  (define temporary-checksum
    (make-temporary-file "preview-archive-~a.sha256" #f output-parent))
  (define temporary-notices
    (make-temporary-file "preview-archive-~a-notices.md" #f output-parent))
  (define archive-published? #f)
  (define checksum-published? #f)
  (define notices-published? #f)
  (dynamic-wind
   void
   (lambda ()
     (run-command!
      'preview-archive
      tar
      (list "--create"
            "--file" (path->string temporary-tar)
            "--format=ustar"
            "--sort=name"
            (format "--mtime=@~a" (preview-identity-source-date-epoch identity))
            "--owner=0"
            "--group=0"
            "--numeric-owner"
            "--mode=u+rwX,go+rX,go-w"
            "--directory" (path->string (path-only tree))
            (path->string (file-name-from-path tree))))
     (define metadata-errors
       (ustar-errors temporary-tar
                     tree
                     (preview-identity-source-date-epoch identity)))
     (unless (null? metadata-errors)
       (raise-arguments-error 'archive-preview-tree!
                              "normalized archive metadata is invalid"
                              "errors" metadata-errors))
     (run-command!
      'preview-archive
      zstd
      (list zstd-level
            "--single-thread"
            "--no-progress"
            "--quiet"
            "--force"
            (path->string temporary-tar)
            "-o"
            (path->string temporary-archive)))
     (run-command!
      'preview-archive
      zstd
      (list "--test" "--quiet" (path->string temporary-archive)))
     (file-or-directory-permissions temporary-archive #o644)
     (define digest (sha256-file temporary-archive))
     (call-with-output-file temporary-checksum
       #:exists 'truncate/replace
       (lambda (output)
         (fprintf output "~a  ~a\n" digest (preview-archive-name identity))))
     (file-or-directory-permissions temporary-checksum #o644)
     (copy-file (build-path tree "THIRD_PARTY_NOTICES.md")
                temporary-notices
                #t)
     (file-or-directory-permissions temporary-notices #o644)
     (rename-file-or-directory temporary-archive archive-path)
     (set! archive-published? #t)
     (rename-file-or-directory temporary-checksum checksum-path)
     (set! checksum-published? #t)
     (rename-file-or-directory temporary-notices notices-path)
     (set! notices-published? #t)
     (archive-result archive-path checksum-path notices-path digest))
   (lambda ()
     (for ([temporary (in-list
                       (list temporary-tar
                             temporary-archive
                             temporary-checksum
                             temporary-notices))])
       (when (path-present? temporary) (delete-file temporary)))
     (unless notices-published?
       (when (path-present? notices-path) (delete-file notices-path)))
     (unless checksum-published?
       (when (path-present? checksum-path) (delete-file checksum-path)))
     (unless (and archive-published? checksum-published? notices-published?)
       (when (path-present? archive-path) (delete-file archive-path))))))

(module+ main
  (define closure-path default-closure-path)
  (define tree #f)
  (define output-parent #f)
  (define tag #f)
  (define tag-commit #f)
  (define main-commit #f)
  (define source-date-epoch #f)
  (define platform preview-platform)
  (command-line
   #:program "archive-preview-tree.rkt"
   #:once-each
   [("--manifest") path "Runtime closure manifest" (set! closure-path path)]
   [("--tree") path "Canonical preview tree"
    (set! tree (path->complete-path path))]
   [("--output-parent") path "Archive output directory"
    (set! output-parent (path->complete-path path))]
   [("--tag") value "Canonical SemVer tag" (set! tag value)]
   [("--tag-commit") value "Exact tag commit" (set! tag-commit value)]
   [("--main-commit") value "Exact main commit" (set! main-commit value)]
   [("--source-date-epoch") value "Source commit timestamp"
    (set! source-date-epoch (string->number value))]
   [("--platform") value "Preview platform" (set! platform value)])
  (for ([required (in-list
                   (list (cons "--tree" tree)
                         (cons "--output-parent" output-parent)
                         (cons "--tag" tag)
                         (cons "--tag-commit" tag-commit)
                         (cons "--main-commit" main-commit)
                         (cons "--source-date-epoch" source-date-epoch)))])
    (unless (cdr required)
      (raise-user-error 'preview-archive "~a is required" (car required))))
  (define identity
    (preview-identity tag
                      tag-commit
                      main-commit
                      source-date-epoch
                      platform))
  (define result
    (archive-preview-tree! identity tree closure-path output-parent))
  (printf "preview_archive=~a\npreview_checksum=~a\npreview_notices=~a\nsha256=~a\n"
          (archive-result-archive result)
          (archive-result-checksum result)
          (archive-result-notices result)
          (archive-result-digest result)))

(module+ test
  (require rackunit)

  (define fixture-commit "0123456789abcdef0123456789abcdef01234567")
  (define fixture-epoch 1798761600)
  (define fixture-identity
    (preview-identity "v1.2.3"
                      fixture-commit
                      fixture-commit
                      fixture-epoch
                      preview-platform))
  (define fixture-build-environment
    "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")

  (define (write-file path content mode)
    (make-directory* (path-only path))
    (call-with-output-file path
      #:exists 'truncate/replace
      (lambda (output) (display content output)))
    (file-or-directory-permissions path mode))

  (define (fixture-closure license-digest terms-digest)
    (hasheq
     'bundle
     (hasheq 'binary "bin/odra"
             'runtime_resources
             (list (hasheq 'name "fixture-runtime"
                           'destination "share/odra/fixture")))
     'product_terms
     (hasheq 'path "terms.md" 'sha256 terms-digest)
     'baseline
     (hasheq 'interpreter "/lib64/ld-linux-x86-64.so.2"
             'needed '("libc.so.6")
             'system_components
             (list (hasheq 'name "glibc" 'needed '("libc.so.6"))))
     'components
     (list
      (hasheq 'name "fixture-component"
              'version "1.0.0"
              'revision "fixture-revision"
              'source_url "https://example.invalid/fixture"
              'incorporation "static"
              'license_expression "MIT"
              'selected_license "MIT"
              'source_obligation "none"
              'license_inputs
              (list
               (hasheq 'kind "file"
                       'root "release-input"
                       'path "licenses/fixture/LICENSE"
                       'sha256 license-digest
                       'bundle_path "LICENSES/Fixture/LICENSE"))))
     'build_tools
     (list
      (hasheq 'name "fixture-tool"
              'version "2.0.0"
              'revision "fixture-tool-revision"
              'source_url "https://example.invalid/tool"
              'incorporation "build-only"
              'license_expression "MIT"))
     'forbidden_bundle_segments '(".build" ".git" "ops" "src" "tests")))

  (define (make-fixture-tree parent
                             closure
                             repository-root
                             release-input-root
                             terms-path)
    (define root (build-path parent "odra-1.2.3-linux-x86_64"))
    (for ([relative (in-list '("LICENSES"
                               "bin"
                               "lib/odra/racket/lib"
                               "share/odra/racket/collects"
                               "share/odra/racket/etc"))])
      (define directory (build-path root relative))
      (make-directory* directory)
      (file-or-directory-permissions directory #o755))
    (write-file (build-path root "bin" "odra") "binary\n" #o755)
    (for ([name (in-list '("petite.boot" "racket.boot" "scheme.boot" "system.rktd"))])
      (write-file (build-path root "lib" "odra" "racket" "lib" name)
                  (string-append name "\n")
                  #o644))
    (write-file (build-path root "share" "odra" "racket" "etc" "config.rktd")
                "#hash()\n"
                #o644)
    (write-file
     (build-path root "share" "odra" "racket" "collects" "main.rkt")
     "#lang racket/base\n"
     #o644)
    (add-preview-metadata! fixture-identity
                           root
                           closure
                           repository-root
                           release-input-root
                           terms-path
                           fixture-build-environment)
    (for ([path (in-list (all-tree-paths root))]
          [offset (in-naturals)])
      (file-or-directory-modify-seconds path (+ 1000 offset)))
    root)

  (define temporary-directory
    (make-temporary-file "preview-archive-test-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define input-parent (build-path temporary-directory "input"))
     (define first-output (build-path temporary-directory "first"))
     (define second-output (build-path temporary-directory "second"))
     (define repository-root (build-path temporary-directory "repository"))
     (define release-input-root (build-path temporary-directory "release-input"))
     (define license-path
       (build-path release-input-root "licenses" "fixture" "LICENSE"))
     (define terms-path (build-path repository-root "terms.md"))
     (write-file license-path "fixture license\n" #o644)
     (write-file terms-path "# Preview Terms\n\nFixture terms.\n" #o644)
     (define closure
       (fixture-closure (sha256-file license-path) (sha256-file terms-path)))
     (make-directory* input-parent)
     (define tree
       (make-fixture-tree input-parent
                          closure
                          repository-root
                          release-input-root
                          terms-path))
     (define closure-path (build-path temporary-directory "closure.json"))
     (call-with-output-file closure-path
       (lambda (output) (write-json closure output)))

     (test-case "normalizes identical archives and checksums"
       (define first
         (archive-preview-tree! fixture-identity tree closure-path first-output))
       (define second
         (archive-preview-tree! fixture-identity tree closure-path second-output))
       (check-equal? (archive-result-digest first) (archive-result-digest second))
       (check-equal? (file->bytes (archive-result-archive first))
                     (file->bytes (archive-result-archive second)))
       (check-equal?
        (file->string (archive-result-checksum first))
        (format "~a  odra-1.2.3-linux-x86_64.tar.zst\n"
                (archive-result-digest first)))
       (check-equal? (file->bytes (archive-result-notices first))
                     (file->bytes (build-path tree "THIRD_PARTY_NOTICES.md")))
       (define extracted-parent (build-path temporary-directory "extracted"))
       (define extracted-tar (build-path temporary-directory "extracted.tar"))
       (make-directory extracted-parent)
       (run-command! 'preview-archive-test
                     (required-executable 'preview-archive-test "zstd")
                     (list "--decompress"
                           "--quiet"
                           "--force"
                           (path->string (archive-result-archive first))
                           "-o"
                           (path->string extracted-tar)))
       (run-command! 'preview-archive-test
                     (required-executable 'preview-archive-test "tar")
                     (list "--extract"
                           "--file" (path->string extracted-tar)
                           "--directory" (path->string extracted-parent)))
       (define extracted-tree
         (build-path extracted-parent "odra-1.2.3-linux-x86_64"))
       (check-equal? (preview-tree-errors extracted-tree closure) '())
       (check-equal?
        (preview-metadata-errors fixture-identity
                                 extracted-tree
                                 closure
                                 fixture-build-environment)
        '())
       (check-equal? (file->bytes (build-path extracted-tree "manifest.json"))
                     (file->bytes (build-path tree "manifest.json")))
       (check-exn
        #rx"destination already exists"
        (lambda ()
          (archive-preview-tree! fixture-identity
                                 tree
                                 closure-path
                                 first-output))))

     (test-case "rejects metadata drift without partial output"
       (define license (build-path tree "LICENSES" "Fixture" "LICENSE"))
       (define original (file->bytes license))
       (call-with-output-file license
         #:exists 'truncate/replace
         (lambda (output) (display "changed license\n" output)))
       (define rejected-output (build-path temporary-directory "metadata-drift"))
       (check-exn
        #rx"invalid preview tree"
        (lambda ()
          (archive-preview-tree! fixture-identity
                                 tree
                                 closure-path
                                 rejected-output)))
       (check-false (directory-exists? rejected-output))
       (call-with-output-file license
         #:exists 'truncate/replace
         (lambda (output) (write-bytes original output))))

     (test-case "rejects tree identity mismatch"
       (define mismatched
         (struct-copy preview-identity fixture-identity [tag "v1.2.4"]))
       (check-exn
        #rx"preview tree name differs"
        (lambda ()
          (archive-preview-tree! mismatched
                                 tree
                                 closure-path
                                 (build-path temporary-directory "mismatch")))))

     (test-case "rejects permission drift before archiving"
       (define config
         (build-path tree "share" "odra" "racket" "etc" "config.rktd"))
       (file-or-directory-permissions config #o600)
       (check-exn
        #rx"invalid preview tree"
        (lambda ()
          (archive-preview-tree!
           fixture-identity
           tree
           closure-path
           (build-path temporary-directory "invalid-permissions"))))
       (file-or-directory-permissions config #o644)))
   (lambda () (delete-directory/files temporary-directory))))
