#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (except-in openssl/sha1 sha1)
         (only-in file/sha1 bytes->hex-string)
         json
         racket/file
         racket/list
         racket/path
         racket/port
         racket/string
         "check-runtime-closure.rkt"
         "preview-identity.rkt")

(provide add-preview-metadata!
         preview-metadata-errors)

(define metadata-schema 1)
(define build-environment-pattern #px"^sha256:[0-9a-f]{64}$")
(define metadata-files
  '("README.md" "PREVIEW_TERMS.md" "THIRD_PARTY_NOTICES.md" "manifest.json"))

(define (hash-value table key [fallback #f])
  (hash-ref table key fallback))

(define (regular-file? path)
  (eq? (file-or-directory-type path #f) 'file))

(define (sha256-bytes-hex content)
  (bytes->hex-string (sha256-bytes (open-input-bytes content))))

(define (sha256-file path)
  (call-with-input-file path
    (lambda (input) (bytes->hex-string (sha256-bytes input)))))

(define (write-text! path content)
  (call-with-output-file path
    #:exists 'error
    (lambda (output) (display content output)))
  (file-or-directory-permissions path #o644))

(define (write-json-string value output)
  (write-json value output))

(define (write-canonical-json-value value output)
  (cond
    [(hash? value)
     (display "{" output)
     (for ([key (in-list (sort (hash-keys value)
                               string<?
                               #:key symbol->string))]
           [index (in-naturals)])
       (unless (zero? index) (display "," output))
       (write-json-string (symbol->string key) output)
       (display ":" output)
       (write-canonical-json-value (hash-ref value key) output))
     (display "}" output)]
    [(list? value)
     (display "[" output)
     (for ([item (in-list value)] [index (in-naturals)])
       (unless (zero? index) (display "," output))
       (write-canonical-json-value item output))
     (display "]" output)]
    [else (write-json value output)]))

(define (write-canonical-json! path value)
  (call-with-output-file path
    #:exists 'error
    (lambda (output)
      (write-canonical-json-value value output)
      (newline output)))
  (file-or-directory-permissions path #o644))

(define (run/capture executable arguments)
  (define-values (process output input error-output)
    (apply subprocess #f #f #f executable arguments))
  (close-output-port input)
  (define output-bytes (port->bytes output))
  (define error-text (port->string error-output))
  (close-input-port output)
  (close-input-port error-output)
  (subprocess-wait process)
  (unless (zero? (subprocess-status process))
    (raise-user-error 'preview-metadata
                      "cannot read license archive member: ~a"
                      (string-trim error-text)))
  output-bytes)

(define (license-input-bytes input repository-root release-input-root)
  (define root
    (if (equal? (hash-value input 'root) "repository")
        repository-root
        release-input-root))
  (cond
    [(equal? (hash-value input 'kind) "file")
     (file->bytes (build-path root (hash-value input 'path)))]
    [else
     (define tar
       (or (find-executable-path "tar")
           (raise-user-error 'preview-metadata "tar is unavailable")))
     (run/capture tar
                  (list "xOf"
                        (path->string (build-path root (hash-value input 'archive)))
                        (hash-value input 'member)))]))

(define (stage-license! root input repository-root release-input-root)
  (define content
    (license-input-bytes input repository-root release-input-root))
  (define expected (hash-value input 'sha256))
  (unless (equal? (sha256-bytes-hex content) expected)
    (raise-user-error 'preview-metadata
                      "license input checksum mismatch: ~a"
                      (hash-value input 'bundle_path)))
  (define bundle-path (hash-value input 'bundle_path))
  (define segments (string-split bundle-path "/"))
  (for/fold ([parent root]) ([segment (in-list (drop-right segments 1))])
    (define directory (build-path parent segment))
    (make-directory* directory)
    (file-or-directory-permissions directory #o755)
    directory)
  (define destination (build-path root bundle-path))
  (call-with-output-file destination
    #:exists 'error
    (lambda (output) (write-bytes content output)))
  (file-or-directory-permissions destination #o644))

(define (component-license-paths component)
  (map (lambda (input) (hash-value input 'bundle_path))
       (hash-value component 'license_inputs '())))

(define (component->manifest component)
  (hasheq
   'name (hash-value component 'name)
   'version (hash-value component 'version)
   'revision (hash-value component 'revision)
   'source_url (hash-value component 'source_url)
   'incorporation (hash-value component 'incorporation)
   'spdx_expression (hash-value component 'license_expression)
   'selected_license (hash-value component 'selected_license)
   'license_paths (component-license-paths component)
   'source_obligation (hash-value component 'source_obligation)))

(define (runtime-layout closure)
  (for/list ([resource (in-list
                        (hash-value (hash-value closure 'bundle)
                                    'runtime_resources))])
    (hasheq 'name (hash-value resource 'name)
            'destination (hash-value resource 'destination))))

(define (manifest-value identity closure build-environment terms-digest notices-digest)
  (define baseline (hash-value closure 'baseline))
  (hasheq
   'schema metadata-schema
   'product "Odra"
   'version (preview-version identity)
   'tag (preview-identity-tag identity)
   'commit (preview-identity-tag-commit identity)
   'source_date_epoch (preview-identity-source-date-epoch identity)
   'platform (preview-identity-platform identity)
   'architecture "x86_64"
   'build_environment_digest build-environment
   'artifact
   (hasheq 'archive (preview-archive-name identity)
           'checksum (preview-checksum-name identity)
           'digest
           (hasheq 'algorithm "SHA-256"
                   'value_file (preview-checksum-name identity))
           'third_party_notices (preview-notices-name identity))
   'runtime
   (hasheq 'executable (hash-value (hash-value closure 'bundle) 'binary)
           'resources (runtime-layout closure))
   'baseline
   (hasheq 'elf_interpreter (hash-value baseline 'interpreter)
           'dynamic_dependencies (hash-value baseline 'needed)
           'system_components (hash-value baseline 'system_components))
   'components
   (map component->manifest (hash-value closure 'components))
   'product_terms
   (hasheq 'path "PREVIEW_TERMS.md" 'sha256 terms-digest)
   'third_party_notice
   (hasheq 'path "THIRD_PARTY_NOTICES.md" 'sha256 notices-digest)))

(define (notices-text closure)
  (string-append
   "# Third-Party Notices\n\n"
   "This preview redistributes or statically incorporates the following "
   "third-party components. Complete license texts are included under "
   "`LICENSES/`.\n\n"
   "| Component | Version | Incorporation | License | Selected license | License files |\n"
   "| --- | --- | --- | --- | --- | --- |\n"
   (string-join
    (for/list ([component (in-list (hash-value closure 'components))])
      (format "| [~a](~a) | ~a | ~a | ~a | ~a | ~a |"
              (hash-value component 'name)
              (hash-value component 'source_url)
              (hash-value component 'version)
              (hash-value component 'incorporation)
              (hash-value component 'license_expression)
              (hash-value component 'selected_license)
              (string-join
               (map (lambda (path) (format "`~a`" path))
                    (component-license-paths component))
               "<br>")))
    "\n")
   "\n\n"
   "The following tools produced the preview but are not distributed in the "
   "bundle:\n\n"
   (string-join
    (for/list ([tool (in-list (hash-value closure 'build_tools))])
      (format "- [~a ~a](~a), revision `~a`, licensed under ~a."
              (hash-value tool 'name)
              (hash-value tool 'version)
              (hash-value tool 'source_url)
              (hash-value tool 'revision)
              (hash-value tool 'license_expression)))
    "\n")
   "\n"))

(define (readme-text identity closure)
  (define baseline (hash-value closure 'baseline))
  (string-append
   "# Odra " (preview-version identity) " Preview\n\n"
   "This is an early Linux x86-64 preview for evaluation and testing. Read "
   "[the preview terms](PREVIEW_TERMS.md) before use. Third-party attribution "
   "is available in [the notices](THIRD_PARTY_NOTICES.md).\n\n"
   "## Supported baseline\n\n"
   "The preview requires the Linux ELF interpreter `"
   (hash-value baseline 'interpreter)
   "` and these baseline dynamic libraries:\n\n"
   (string-join
    (map (lambda (name) (string-append "- `" name "`"))
         (hash-value baseline 'needed))
    "\n")
   "\n\n"
   "Racket is bundled and must not be installed separately.\n\n"
   "## Verify and extract\n\n"
   "Place `" (preview-archive-name identity) "` beside `"
   (preview-checksum-name identity) "`, then run:\n\n"
   "```sh\n"
   "sha256sum --check " (preview-checksum-name identity) "\n"
   "tar --use-compress-program=unzstd -xf " (preview-archive-name identity) "\n"
   "```\n\n"
   "## Run\n\n"
   "```sh\n"
   "./" (preview-artifact-stem identity) "/bin/odra [path]\n"
   "```\n\n"
   "The extracted directory can be moved and the command can be launched from "
   "another working directory. Keep the `bin/`, `lib/`, and `share/` layout "
   "together.\n\n"
   "## Diagnostics\n\n"
   "Startup failures are printed to standard error. Include the version `"
   (preview-version identity) "`, platform `" (preview-identity-platform identity)
   "`, exact command, and complete diagnostic when reporting a problem through "
   "the channel that supplied the download.\n"))

(define (preview-metadata-errors identity tree closure build-environment)
  (define expected-version (preview-version identity))
  (define manifest-path (build-path tree "manifest.json"))
  (define terms-path (build-path tree "PREVIEW_TERMS.md"))
  (define notices-path (build-path tree "THIRD_PARTY_NOTICES.md"))
  (define manifest
    (and (regular-file? manifest-path)
         (with-handlers ([exn:fail? (lambda (_) #f)])
           (call-with-input-file manifest-path read-json))))
  (append
   (if (and (string? build-environment)
            (regexp-match? build-environment-pattern build-environment))
       '()
       '("build environment digest is invalid"))
   (for/list ([name (in-list metadata-files)]
              #:unless (regular-file? (build-path tree name)))
     (format "preview metadata file is missing: ~a" name))
   (if (and manifest
            (equal? (hash-value manifest 'schema) metadata-schema)
            (equal? (hash-value manifest 'version) expected-version)
            (equal? (hash-value manifest 'tag) (preview-identity-tag identity))
            (equal? (hash-value manifest 'commit)
                    (preview-identity-tag-commit identity))
            (equal? (hash-value manifest 'platform)
                    (preview-identity-platform identity))
            (equal? (hash-value manifest 'build_environment_digest)
                    build-environment))
       '()
       '("preview manifest identity differs"))
   (if (and manifest
            (equal? (hash-value manifest 'components)
                    (map component->manifest (hash-value closure 'components)))
            (equal? (hash-value (hash-value manifest 'artifact) 'archive)
                    (preview-archive-name identity))
            (equal? (hash-value (hash-value manifest 'artifact) 'checksum)
                    (preview-checksum-name identity))
            (equal? (hash-value (hash-value (hash-value manifest 'artifact)
                                            'digest)
                                'algorithm)
                    "SHA-256")
            (equal? (hash-value (hash-value (hash-value manifest 'artifact)
                                            'digest)
                                'value_file)
                    (preview-checksum-name identity))
            (equal? (hash-value (hash-value manifest 'artifact)
                                'third_party_notices)
                    (preview-notices-name identity)))
       '()
       '("preview manifest inventory differs"))
   (if (and manifest
            (regular-file? terms-path)
            (regular-file? notices-path)
            (equal? (hash-value (hash-value manifest 'product_terms) 'sha256)
                    (sha256-file terms-path))
            (equal? (sha256-file terms-path)
                    (hash-value (hash-value closure 'product_terms) 'sha256))
            (equal? (hash-value (hash-value manifest 'third_party_notice) 'sha256)
                    (sha256-file notices-path)))
       '()
       '("preview metadata digest differs"))
   (append-map
    (lambda (license)
      (define relative (hash-value license 'bundle_path))
      (define path (build-path tree relative))
      (cond
        [(not (regular-file? path))
         (list (format "bundled license is missing: ~a" relative))]
        [(not (equal? (sha256-file path) (hash-value license 'sha256)))
         (list (format "bundled license checksum differs: ~a" relative))]
        [else '()]))
    (for*/list ([component (in-list (hash-value closure 'components))]
                [license (in-list (hash-value component 'license_inputs))])
      license))))

(define (add-preview-metadata! identity
                               tree
                               closure
                               repository-root
                               release-input-root
                               terms-path
                               build-environment)
  (unless (and (string? build-environment)
               (regexp-match? build-environment-pattern build-environment))
    (raise-user-error 'preview-metadata "build environment digest is invalid"))
  (unless (regular-file? terms-path)
    (raise-user-error 'preview-metadata "approved preview terms are unavailable"))
  (define terms-content (file->bytes terms-path))
  (unless (equal? (sha256-bytes-hex terms-content)
                  (hash-value (hash-value closure 'product_terms) 'sha256))
    (raise-user-error 'preview-metadata "approved preview terms have changed"))
  (for* ([component (in-list (hash-value closure 'components))]
         [input (in-list (hash-value component 'license_inputs))])
    (stage-license! tree input repository-root release-input-root))
  (define terms-destination (build-path tree "PREVIEW_TERMS.md"))
  (call-with-output-file terms-destination
    #:exists 'error
    (lambda (output) (write-bytes terms-content output)))
  (file-or-directory-permissions terms-destination #o644)
  (define notices (notices-text closure))
  (write-text! (build-path tree "THIRD_PARTY_NOTICES.md") notices)
  (write-text! (build-path tree "README.md") (readme-text identity closure))
  (write-canonical-json!
   (build-path tree "manifest.json")
   (manifest-value identity
                   closure
                   build-environment
                   (sha256-bytes-hex terms-content)
                   (sha256-bytes-hex (string->bytes/utf-8 notices))))
  (define errors (preview-metadata-errors identity tree closure build-environment))
  (unless (null? errors)
    (raise-arguments-error 'add-preview-metadata!
                           "generated preview metadata is invalid"
                           "errors" errors)))

(module+ test
  (require rackunit)

  (define fixture-commit "0123456789abcdef0123456789abcdef01234567")
  (define fixture-identity
    (preview-identity "v1.2.3"
                      fixture-commit
                      fixture-commit
                      1798761600
                      preview-platform))
  (define fixture-build-environment
    "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")

  (define (write-fixture-file path content)
    (make-directory* (path-only path))
    (call-with-output-file path
      #:exists 'truncate/replace
      (lambda (output) (display content output))))

  (define (fixture-closure license-digest terms-digest)
    (hasheq
     'bundle
     (hasheq 'binary "bin/odra"
             'runtime_resources
             (list (hasheq 'name "fixture-runtime"
                           'destination "share/odra/fixture")))
     'product_terms
     (hasheq 'path "approved-terms.md"
             'sha256 terms-digest)
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
              'license_expression "MIT"))))

  (define temporary-directory
    (make-temporary-file "preview-metadata-test-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define repository-root (build-path temporary-directory "repository"))
     (define release-input-root (build-path temporary-directory "release-input"))
     (define license-path
       (build-path release-input-root "licenses" "fixture" "LICENSE"))
     (define terms-path (build-path temporary-directory "approved-terms.md"))
     (write-fixture-file license-path "fixture license\n")
     (write-fixture-file terms-path "# Preview Terms\n\nApproved fixture terms.\n")
     (make-directory* repository-root)
     (define closure
       (fixture-closure (sha256-file license-path)
                        (sha256-file terms-path)))

     (define (generate-at name)
       (define tree (build-path temporary-directory name))
       (make-directory* (build-path tree "LICENSES"))
       (add-preview-metadata! fixture-identity
                              tree
                              closure
                              repository-root
                              release-input-root
                              terms-path
                              fixture-build-environment)
       tree)

     (test-case "generates deterministic complete preview metadata"
       (define first (generate-at "first"))
       (define second (generate-at "second"))
       (check-equal?
        (preview-metadata-errors fixture-identity
                                 first
                                 closure
                                 fixture-build-environment)
        '())
       (for ([relative (in-list
                        (append metadata-files
                                '("LICENSES/Fixture/LICENSE")))])
         (check-equal? (file->bytes (build-path first relative))
                       (file->bytes (build-path second relative))))
       (define manifest (call-with-input-file (build-path first "manifest.json")
                          read-json))
       (check-equal? (hash-value manifest 'version) "1.2.3")
       (check-equal?
        (hash-value (car (hash-value manifest 'components)) 'selected_license)
        "MIT")
       (check-false
        (string-contains? (file->string (build-path first "README.md"))
                          (path->string temporary-directory)))
       (check-true
        (string-contains? (file->string (build-path first
                                                    "THIRD_PARTY_NOTICES.md"))
                          "LICENSES/Fixture/LICENSE")))

     (test-case "detects bundled license drift"
       (define tree (generate-at "license-drift"))
       (call-with-output-file (build-path tree "LICENSES" "Fixture" "LICENSE")
         #:exists 'truncate/replace
         (lambda (output) (display "changed license\n" output)))
       (check-not-false
        (member "bundled license checksum differs: LICENSES/Fixture/LICENSE"
                (preview-metadata-errors fixture-identity
                                         tree
                                         closure
                                         fixture-build-environment))))

     (test-case "rejects an unpinned build environment"
       (define tree (build-path temporary-directory "invalid-environment"))
       (make-directory* (build-path tree "LICENSES"))
       (check-exn
        #rx"build environment digest is invalid"
        (lambda ()
          (add-preview-metadata! fixture-identity
                                 tree
                                 closure
                                 repository-root
                                 release-input-root
                                 terms-path
                                 "latest"))))

     (test-case "requires approved product terms"
       (define tree (build-path temporary-directory "missing-terms"))
       (make-directory* (build-path tree "LICENSES"))
       (check-exn
        #rx"approved preview terms are unavailable"
        (lambda ()
          (add-preview-metadata! fixture-identity
                                 tree
                                 closure
                                 repository-root
                                 release-input-root
                                 (build-path temporary-directory "missing.md")
                                 fixture-build-environment)))))
   (lambda () (delete-directory/files temporary-directory))))
