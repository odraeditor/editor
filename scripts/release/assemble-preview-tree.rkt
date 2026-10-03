#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require json
         racket/cmdline
         racket/file
         racket/list
         racket/path
         racket/runtime-path
         racket/string
         "add-preview-metadata.rkt"
         "check-runtime-closure.rkt"
         "preview-identity.rkt")

(provide assemble-preview-tree!
         preview-tree-errors)

(define-runtime-path script-directory ".")
(define default-repository-root
  (simplify-path (build-path script-directory ".." "..")))
(define default-closure-path
  (build-path default-repository-root
              "release"
              "linux-x86_64"
              "runtime-closure.json"))
(define default-terms-path
  (build-path default-repository-root
              "release"
              "linux-x86_64"
              "PREVIEW_TERMS.md"))

(define canonical-binary-path "bin/odra")
(define canonical-resource-contracts
  (hasheq
   'racket-boot
   (hasheq 'source_root "release-input"
           'source "usr/lib/racket"
           'destination "lib/odra/racket/lib"
           'mode "selected-files"
           'files '("petite.boot" "racket.boot" "scheme.boot" "system.rktd"))
   'racket-collects
   (hasheq 'source_root "release-input"
           'source "usr/share/racket/collects"
           'destination "share/odra/racket/collects"
           'mode "tree"
           'files '())
   'racket-config
   (hasheq 'source_root "generated"
           'source "minimal-racket-config"
           'destination "share/odra/racket/etc"
           'mode "generated-file"
           'files '("config.rktd"))))
(define canonical-root-entries
  '("LICENSES"
    "PREVIEW_TERMS.md"
    "README.md"
    "THIRD_PARTY_NOTICES.md"
    "bin"
    "lib"
    "manifest.json"
    "share"))
(define canonical-required-entries
  '("README.md"
    "PREVIEW_TERMS.md"
    "THIRD_PARTY_NOTICES.md"
    "manifest.json"
    "bin/odra"
    "lib/odra/racket/lib/petite.boot"
    "lib/odra/racket/lib/racket.boot"
    "lib/odra/racket/lib/scheme.boot"
    "lib/odra/racket/lib/system.rktd"
    "share/odra/racket/collects"
    "share/odra/racket/etc/config.rktd"))
(define minimal-racket-config #"#hash()\n")

(define (hash-value table key [fallback #f])
  (hash-ref table key fallback))

(define (path-present? path)
  (or (file-exists? path)
      (directory-exists? path)
      (link-exists? path)))

(define (regular-file? path)
  (eq? (file-or-directory-type path #f) 'file))

(define (plain-directory? path)
  (eq? (file-or-directory-type path #f) 'directory))

(define (resource-by-name closure name)
  (define resources
    (hash-value (hash-value closure 'bundle (hasheq))
                'runtime_resources
                '()))
  (for/first ([resource (in-list resources)]
              #:when (equal? (hash-value resource 'name) name))
    resource))

(define (canonical-resource-errors closure)
  (append-map
   (lambda (name)
     (define resource (resource-by-name closure (symbol->string name)))
     (define expected (hash-ref canonical-resource-contracts name))
     (cond
       [(not resource)
        (list (format "canonical runtime resource is missing: ~a" name))]
       [else
        (for/fold ([errors '()])
                  ([key (in-list '(source_root source destination mode files))])
          (if (equal? (hash-value resource key) (hash-ref expected key))
              errors
              (cons (format "runtime resource ~a has noncanonical ~a" name key)
                    errors)))]))
   (hash-keys canonical-resource-contracts)))

(define (canonical-closure-errors closure)
  (append
   (if (equal? (hash-value (hash-value closure 'bundle (hasheq)) 'binary)
               canonical-binary-path)
       '()
       '("bundle binary path is not canonical"))
   (canonical-resource-errors closure)))

(define (product-module-required-entries closure)
  (define declaration
    (hash-value (hash-value closure 'bundle (hasheq)) 'product_modules))
  (if declaration
      (let ([destination (hash-value declaration 'destination "")])
        (map (lambda (name) (path->string (build-path destination name)))
             (cons (hash-value declaration 'manifest "")
                   (hash-value declaration 'artifacts '()))))
      '()))

(define (relative-segments root path)
  (explode-path (find-relative-path root path)))

(define (forbidden-path? root path forbidden-segments)
  (and (not (equal? (simple-form-path root) (simple-form-path path)))
       (for/or ([segment (in-list (relative-segments root path))])
         (and (path? segment)
              (member (path->string segment) forbidden-segments)))))

(define (private-source-path? path)
  (equal? (path-get-extension path) #".odin"))

(define (copy-runtime-entry! source destination source-root forbidden-segments)
  (when (forbidden-path? source-root source forbidden-segments)
    (raise-user-error 'preview-tree
                      "runtime input enters a forbidden segment: ~a"
                      (find-relative-path source-root source)))
  (case (file-or-directory-type source #f)
    [(file)
     (make-directory* (path-only destination))
     (copy-file source destination)
     (file-or-directory-permissions destination #o644)]
    [(directory)
     (make-directory* destination)
     (file-or-directory-permissions destination #o755)
     (for ([child (in-list (sort (directory-list source #:build? #t)
                                 path<?))])
       (copy-runtime-entry!
        child
        (build-path destination (file-name-from-path child))
        source-root
        forbidden-segments))]
    [(link)
     (raise-user-error 'preview-tree
                       "runtime input symlinks are not admitted: ~a"
                       (find-relative-path source-root source))]
    [else
     (raise-user-error 'preview-tree
                       "runtime input type is not admitted: ~a"
                       (find-relative-path source-root source))]))

(define (copy-selected-files! source destination files forbidden-segments)
  (unless (plain-directory? source)
    (raise-user-error 'preview-tree "runtime source directory is missing: ~a" source))
  (make-directory* destination)
  (file-or-directory-permissions destination #o755)
  (for ([name (in-list files)])
    (define input (build-path source name))
    (unless (regular-file? input)
      (raise-user-error 'preview-tree "runtime source file is missing: ~a" input))
    (copy-runtime-entry!
     input
     (build-path destination name)
     source
     forbidden-segments)))

(define (copy-runtime-tree! source destination forbidden-segments)
  (unless (plain-directory? source)
    (raise-user-error 'preview-tree "runtime source directory is missing: ~a" source))
  (copy-runtime-entry! source destination source forbidden-segments))

(define (write-minimal-racket-config! destination)
  (make-directory* destination)
  (file-or-directory-permissions destination #o755)
  (define config-path (build-path destination "config.rktd"))
  (call-with-output-file
   config-path
   #:exists 'error
   (lambda (output) (write-bytes minimal-racket-config output)))
  (file-or-directory-permissions config-path #o644))

(define (stage-resource! root release-input-root closure resource)
  (define destination (build-path root (hash-value resource 'destination)))
  (define mode (hash-value resource 'mode))
  (define forbidden-segments (hash-value closure 'forbidden_bundle_segments '()))
  (cond
    [(equal? mode "selected-files")
     (copy-selected-files!
      (build-path release-input-root (hash-value resource 'source))
      destination
      (hash-value resource 'files)
      forbidden-segments)]
    [(equal? mode "tree")
     (copy-runtime-tree!
      (build-path release-input-root (hash-value resource 'source))
      destination
      forbidden-segments)]
    [(equal? mode "generated-file")
     (write-minimal-racket-config! destination)]
    [else
     (raise-user-error 'preview-tree "unsupported runtime resource mode: ~a" mode)]))

(define (stage-product-modules! root module-root closure)
  (define declaration
    (hash-value (hash-value closure 'bundle (hasheq)) 'product_modules))
  (when declaration
    (unless module-root
      (raise-user-error 'preview-tree "product module input root is required"))
    (copy-selected-files!
     module-root
     (build-path root (hash-value declaration 'destination))
     (cons (hash-value declaration 'manifest)
           (hash-value declaration 'artifacts))
     (hash-value closure 'forbidden_bundle_segments '()))))

(define (all-tree-paths root)
  (let loop ([directory root])
    (append
     (list directory)
     (append-map
      (lambda (child)
        (if (plain-directory? child)
            (loop child)
            (list child)))
      (directory-list directory #:build? #t)))))

(define (tree-permission-errors root)
  (define executable (simple-form-path (build-path root "bin" "odra")))
  (for/fold ([errors '()])
            ([path (in-list (all-tree-paths root))])
    (define kind (file-or-directory-type path #f))
    (define expected
      (cond
        [(eq? kind 'directory) #o755]
        [(equal? (simple-form-path path) executable) #o755]
        [(eq? kind 'file) #o644]
        [else #f]))
    (if (and expected
             (= (file-or-directory-permissions path 'bits) expected))
        errors
        (cons (format "preview tree path has invalid permissions: ~a"
                      (find-relative-path root path))
              errors))))

(define (preview-tree-errors root closure)
  (define forbidden-segments (hash-value closure 'forbidden_bundle_segments '()))
  (define root-entries
    (if (plain-directory? root)
        (sort (map (lambda (path) (path->string (file-name-from-path path)))
                   (directory-list root #:build? #t))
              string<?)
        '()))
  (append
   (if (plain-directory? root) '() '("preview tree root is unavailable"))
   (if (equal? root-entries canonical-root-entries)
       '()
       (list (format "preview tree root entries differ: ~a" root-entries)))
   (for/list ([relative (in-list (append canonical-required-entries
                                          (product-module-required-entries closure)))]
              #:unless (path-present? (build-path root relative)))
     (format "preview tree required entry is missing: ~a" relative))
   (if (and (regular-file? (build-path root "bin" "odra"))
            (= (file-or-directory-permissions (build-path root "bin" "odra") 'bits)
               #o755))
       '()
       '("preview executable is missing or has invalid permissions"))
   (if (and (plain-directory? (build-path root "LICENSES"))
            (= (file-or-directory-permissions (build-path root "LICENSES") 'bits)
               #o755))
       '()
       '("preview license directory is missing or has invalid permissions"))
   (if (and (plain-directory? root)
            (for/and ([path (in-list (all-tree-paths root))])
              (not (link-exists? path))))
       '()
       '("preview tree contains a symbolic link"))
   (if (and (plain-directory? root)
            (for/and ([path (in-list (all-tree-paths root))])
              (not (forbidden-path? root path forbidden-segments))))
       '()
       '("preview tree contains a forbidden path segment"))
   (if (and (plain-directory? root)
            (for/and ([path (in-list (all-tree-paths root))])
              (not (private-source-path? path))))
       '()
       '("preview tree contains an Odra source file"))
   (if (plain-directory? root)
       (tree-permission-errors root)
       '())))

(define (assemble-preview-tree! identity
                                closure-path
                                binary-path
                                repository-root
                                release-input-root
                                output-parent
                                terms-path
                                build-environment
                                #:module-root [module-root #f])
  (define identity-errors (preview-identity-errors identity))
  (unless (null? identity-errors)
    (raise-arguments-error 'assemble-preview-tree!
                           "invalid preview identity"
                           "errors" identity-errors))
  (define closure (read-runtime-closure closure-path))
  (unless (regular-file? binary-path)
    (raise-user-error 'preview-tree "preview executable is unavailable: ~a" binary-path))
  (define-values (needed interpreter) (read-elf-closure binary-path))
  (define closure-errors
    (append
     (runtime-closure-errors closure
                             repository-root
                             release-input-root
                             #:needed needed
                             #:interpreter interpreter)
     (canonical-closure-errors closure)))
  (unless (null? closure-errors)
    (raise-arguments-error 'assemble-preview-tree!
                           "invalid runtime closure"
                           "errors" closure-errors))

  (make-directory* output-parent)
  (define destination
    (build-path output-parent (preview-artifact-stem identity)))
  (when (path-present? destination)
    (raise-user-error 'preview-tree "destination already exists: ~a" destination))
  (define staging (make-temporary-file "preview-tree-~a" 'directory output-parent))
  (dynamic-wind
   void
   (lambda ()
     (file-or-directory-permissions staging #o755)
     (make-directory (build-path staging "bin"))
     (file-or-directory-permissions (build-path staging "bin") #o755)
     (make-directory (build-path staging "LICENSES"))
     (file-or-directory-permissions (build-path staging "LICENSES") #o755)
     (copy-file binary-path (build-path staging "bin" "odra"))
     (file-or-directory-permissions (build-path staging "bin" "odra") #o755)
     (for ([resource (in-list
                      (hash-value (hash-value closure 'bundle)
                                  'runtime_resources))])
       (stage-resource! staging release-input-root closure resource))
     (stage-product-modules! staging module-root closure)
     (add-preview-metadata! identity
                            staging
                            closure
                            repository-root
                            release-input-root
                            terms-path
                            build-environment)
     (define errors (preview-tree-errors staging closure))
     (unless (null? errors)
       (raise-arguments-error 'assemble-preview-tree!
                              "assembled preview tree is invalid"
                              "errors" errors))
     (rename-file-or-directory staging destination)
     destination)
   (lambda ()
     (when (path-present? staging)
       (delete-directory/files staging)))))

(module+ main
  (define manifest-path default-closure-path)
  (define binary-path #f)
  (define repository-root default-repository-root)
  (define release-input-root (string->path "/"))
  (define output-parent #f)
  (define tag #f)
  (define tag-commit #f)
  (define main-commit #f)
  (define source-date-epoch #f)
  (define platform preview-platform)
  (define terms-path default-terms-path)
  (define build-environment #f)
  (define module-root #f)
  (command-line
   #:program "assemble-preview-tree.rkt"
   #:once-each
   [("--manifest") path "Runtime closure manifest" (set! manifest-path path)]
   [("--binary") path "Preview executable" (set! binary-path path)]
   [("--repository-root") path "Repository input root"
    (set! repository-root (path->complete-path path))]
   [("--release-input-root") path "Pinned distribution input root"
    (set! release-input-root (path->complete-path path))]
   [("--output-parent") path "Generated tree parent"
    (set! output-parent (path->complete-path path))]
   [("--tag") value "Canonical SemVer tag" (set! tag value)]
   [("--tag-commit") value "Exact tag commit" (set! tag-commit value)]
   [("--main-commit") value "Exact main commit" (set! main-commit value)]
   [("--source-date-epoch") value "Source commit timestamp"
    (set! source-date-epoch (string->number value))]
   [("--platform") value "Preview platform" (set! platform value)]
   [("--terms") path "Approved preview terms"
    (set! terms-path (path->complete-path path))]
   [("--build-environment") value "Pinned build environment digest"
    (set! build-environment value)]
   [("--module-root") path "Built product module input root"
    (set! module-root (path->complete-path path))])
  (for ([required (in-list
                   (list (cons "--binary" binary-path)
                         (cons "--output-parent" output-parent)
                         (cons "--tag" tag)
                         (cons "--tag-commit" tag-commit)
                         (cons "--main-commit" main-commit)
                         (cons "--source-date-epoch" source-date-epoch)
                         (cons "--build-environment" build-environment)))])
    (unless (cdr required)
      (raise-user-error 'preview-tree "~a is required" (car required))))
  (define identity
    (preview-identity tag
                      tag-commit
                      main-commit
                      source-date-epoch
                      platform))
  (define destination
    (assemble-preview-tree! identity
                            manifest-path
                            (path->complete-path binary-path)
                            repository-root
                            release-input-root
                            output-parent
                            terms-path
                            build-environment
                            #:module-root module-root))
  (printf "preview_tree=~a\n" destination))

(module+ test
  (require (except-in openssl/sha1 sha1)
           (only-in file/sha1 bytes->hex-string)
           rackunit)

  (test-case "identifies private source files"
    (check-true (private-source-path? (string->path "main.odin")))
    (check-false (private-source-path? (string->path "config.rktd"))))

  (define source-binary (path->complete-path "/bin/true"))
  (define fixture-commit "0123456789abcdef0123456789abcdef01234567")
  (define fixture-identity
    (preview-identity "v1.2.3"
                      fixture-commit
                      fixture-commit
                      1798761600
                      preview-platform))
  (define fixture-build-environment
    "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")

  (define (sha256-file path)
    (call-with-input-file path
      (lambda (input) (bytes->hex-string (sha256-bytes input)))))

  (define (write-file path content)
    (make-directory* (path-only path))
    (call-with-output-file path
      #:exists 'truncate/replace
      (lambda (output) (display content output))))

  (define (write-closure path closure)
    (call-with-output-file path
      #:exists 'truncate/replace
      (lambda (output) (write-json closure output))))

  (define (fixture-closure license-digest terms-digest)
    (define-values (needed interpreter) (read-elf-closure source-binary))
    (hasheq
     'schema 1
     'platform preview-platform
     'bundle
     (hasheq
      'binary canonical-binary-path
      'license_directory "LICENSES"
      'runtime_resources
      (for/list ([name (in-list '(racket-boot racket-collects racket-config))])
        (hash-set (hash-ref canonical-resource-contracts name)
                  'name
                  (symbol->string name))))
     'product_terms
     (hasheq 'path "release/PREVIEW_TERMS.md"
             'sha256 terms-digest)
     'baseline
     (hasheq 'interpreter interpreter
             'needed needed
             'system_components '())
     'components
     (list
      (hasheq
       'name "fixture-component"
       'version "1.0.0"
       'revision "fixture"
       'source_url "https://example.invalid/fixture"
       'incorporation "static"
       'redistributed #t
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
              'version "1.0.0"
              'revision "fixture"
              'source_url "https://example.invalid/tool"
              'incorporation "build-only"
              'redistributed #f
              'license_expression "MIT"))
     'forbidden_bundle_segments '(".build" ".git" "ops" "src" "tests")))

  (define temporary-directory
    (make-temporary-file "preview-tree-test-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define repository-root (build-path temporary-directory "repository"))
     (define release-input-root (build-path temporary-directory "release-input"))
     (define output-parent (build-path temporary-directory "output"))
     (define license-path
       (build-path release-input-root "licenses" "fixture" "LICENSE"))
     (define terms-path
       (build-path repository-root "release" "PREVIEW_TERMS.md"))
     (write-file license-path "fixture license\n")
     (write-file terms-path "# Preview Terms\n\nFixture terms.\n")
     (for ([name (in-list '("petite.boot" "racket.boot" "scheme.boot" "system.rktd"))])
       (write-file (build-path release-input-root "usr" "lib" "racket" name)
                   (string-append name "\n")))
     (write-file
      (build-path release-input-root
                  "usr" "share" "racket" "collects" "fixture" "main.rkt")
      "#lang racket/base\n")
     (make-directory* repository-root)
     (define closure
       (fixture-closure (sha256-file license-path)
                        (sha256-file terms-path)))
     (define closure-path (build-path temporary-directory "runtime-closure.json"))
     (write-closure closure-path closure)

     (test-case "assembles the canonical preview tree"
       (define destination
         (assemble-preview-tree! fixture-identity
                                 closure-path
                                 source-binary
                                 repository-root
                                 release-input-root
                                 output-parent
                                 terms-path
                                 fixture-build-environment))
       (check-equal? (path->string (file-name-from-path destination))
                     "odra-1.2.3-linux-x86_64")
       (check-equal? (preview-tree-errors destination closure) '())
       (check-equal? (file-or-directory-permissions
                      (build-path destination "bin" "odra")
                      'bits)
                     #o755)
       (check-equal? (file-or-directory-permissions
                      (build-path destination
                                  "lib" "odra" "racket" "lib" "racket.boot")
                      'bits)
                     #o644)
       (check-equal? (file->bytes
                      (build-path destination
                                  "share" "odra" "racket" "etc" "config.rktd"))
                     minimal-racket-config)
       (define config-path
         (build-path destination
                     "share" "odra" "racket" "etc" "config.rktd"))
       (file-or-directory-permissions config-path #o600)
       (check-not-false
        (member "preview tree path has invalid permissions: share/odra/racket/etc/config.rktd"
                (preview-tree-errors destination closure)))
       (file-or-directory-permissions config-path #o644)
       (check-exn
        #rx"destination already exists"
        (lambda ()
          (assemble-preview-tree! fixture-identity
                                  closure-path
                                  source-binary
                                  repository-root
                                  release-input-root
                                  output-parent
                                  terms-path
                                  fixture-build-environment))))

     (test-case "rejects a missing runtime input without partial output"
       (define missing-identity
         (struct-copy preview-identity fixture-identity [tag "v1.2.4"]))
       (delete-file
        (build-path release-input-root "usr" "lib" "racket" "scheme.boot"))
       (check-exn
        #rx"runtime source file is missing"
        (lambda ()
          (assemble-preview-tree! missing-identity
                                  closure-path
                                  source-binary
                                  repository-root
                                  release-input-root
                                  output-parent
                                  terms-path
                                  fixture-build-environment)))
       (check-false
        (path-present? (build-path output-parent "odra-1.2.4-linux-x86_64")))
       (write-file
        (build-path release-input-root "usr" "lib" "racket" "scheme.boot")
        "scheme.boot\n"))

     (test-case "rejects noncanonical closure destinations"
       (define resources
         (hash-value (hash-value closure 'bundle) 'runtime_resources))
       (define unsafe-resource
         (hash-set (car resources) 'destination "share/odra/other"))
       (define unsafe-closure
         (hash-set closure
                   'bundle
                   (hash-set (hash-value closure 'bundle)
                             'runtime_resources
                             (cons unsafe-resource (cdr resources)))))
       (define unsafe-path (build-path temporary-directory "unsafe-closure.json"))
       (write-closure unsafe-path unsafe-closure)
       (check-exn
        #rx"invalid runtime closure"
        (lambda ()
          (assemble-preview-tree!
           (struct-copy preview-identity fixture-identity [tag "v1.2.5"])
           unsafe-path
           source-binary
           repository-root
           release-input-root
           output-parent
           terms-path
           fixture-build-environment))))

     (test-case "rejects symlinked and forbidden runtime content"
       (define collects-root
         (build-path release-input-root "usr" "share" "racket" "collects"))
       (make-file-or-directory-link license-path
                                    (build-path collects-root "linked-license"))
       (check-exn
        #rx"runtime input symlinks are not admitted"
        (lambda ()
          (assemble-preview-tree!
           (struct-copy preview-identity fixture-identity [tag "v1.2.6"])
           closure-path
           source-binary
           repository-root
           release-input-root
           output-parent
           terms-path
           fixture-build-environment)))
       (delete-file (build-path collects-root "linked-license"))
       (write-file (build-path collects-root "src" "private.rkt") "source\n")
       (check-exn
        #rx"runtime input enters a forbidden segment"
        (lambda ()
          (assemble-preview-tree!
           (struct-copy preview-identity fixture-identity [tag "v1.2.7"])
           closure-path
           source-binary
           repository-root
           release-input-root
           output-parent
           terms-path
           fixture-build-environment)))))
   (lambda () (delete-directory/files temporary-directory))))
