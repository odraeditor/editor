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
         racket/runtime-path
         racket/string)

(provide read-runtime-closure
         runtime-closure-errors
         read-elf-closure)

(define expected-schema 1)
(define expected-platform "linux-x86_64")
(define expected-resource-names
  '("racket-boot" "racket-collects" "racket-config"))
(define admitted-incorporations
  '("generated-data" "static" "static-and-runtime-resource"))
(define admitted-license-kinds '("archive-member" "file"))
(define admitted-license-roots '("release-input" "repository"))
(define sha256-pattern #px"^[0-9a-f]{64}$")
(define-runtime-path script-directory ".")
(define default-repository-root
  (simplify-path (build-path script-directory ".." "..")))
(define default-manifest-path
  (build-path default-repository-root
              "release"
              "linux-x86_64"
              "runtime-closure.json"))

(define (read-runtime-closure path)
  (call-with-input-file path read-json))

(define (hash-value table key [fallback #f])
  (hash-ref table key fallback))

(define (safe-relative-path? value)
  (and (string? value)
       (positive? (string-length value))
       (not (string-prefix? value "/"))
       (not (string-contains? value "\\"))
       (not (string-contains? value (string #\nul)))
       (for/and ([segment (in-list (string-split value "/" #:trim? #f))])
         (and (positive? (string-length segment))
              (not (member segment '("." "..")))))))

(define (sorted-unique-strings? values)
  (and (list? values)
       (andmap string? values)
       (equal? values (sort (remove-duplicates values) string<?))))

(define (sha256-port input)
  (bytes->hex-string (sha256-bytes input)))

(define (sha256-file path)
  (call-with-input-file path sha256-port))

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

(define (archive-member-bytes archive member)
  (define tar (find-executable-path "tar"))
  (unless tar
    (raise-user-error 'runtime-closure "tar is unavailable"))
  (define-values (content status error-text)
    (run/capture tar (list "xOf" (path->string archive) member)))
  (unless (zero? status)
    (raise-user-error 'runtime-closure
                      "cannot read archive member ~a: ~a"
                      member
                      (string-trim error-text)))
  content)

(define (root-path root-name repository-root release-input-root)
  (case (string->symbol root-name)
    [(repository) repository-root]
    [(release-input) release-input-root]
    [else #f]))

(define (license-input-errors input repository-root release-input-root)
  (define kind (hash-value input 'kind))
  (define root-name (hash-value input 'root))
  (define digest (hash-value input 'sha256))
  (define bundle-path (hash-value input 'bundle_path))
  (define errors
    (append
     (if (member kind admitted-license-kinds)
         '()
         '("license input kind is not admitted"))
     (if (member root-name admitted-license-roots)
         '()
         '("license input root is not admitted"))
     (if (and (string? digest) (regexp-match? sha256-pattern digest))
         '()
         '("license input SHA-256 is invalid"))
     (if (safe-relative-path? bundle-path)
         '()
         '("license bundle path is unsafe"))))
  (if (pair? errors)
      errors
      (with-handlers ([exn:fail?
                       (lambda (failure)
                         (list (format "license input is unavailable: ~a"
                                       (exn-message failure))))])
        (define root (root-path root-name repository-root release-input-root))
        (define actual
          (cond
            [(equal? kind "file")
             (define relative (hash-value input 'path))
             (unless (safe-relative-path? relative)
               (raise-user-error 'runtime-closure "license file path is unsafe"))
             (define path (build-path root relative))
             (unless (file-exists? path)
               (raise-user-error 'runtime-closure "license file is missing: ~a" relative))
             (sha256-file path)]
            [else
             (define archive-relative (hash-value input 'archive))
             (define member (hash-value input 'member))
             (unless (and (safe-relative-path? archive-relative)
                          (safe-relative-path? member))
               (raise-user-error 'runtime-closure "archive license path is unsafe"))
             (define archive (build-path root archive-relative))
             (unless (file-exists? archive)
               (raise-user-error 'runtime-closure
                                 "license archive is missing: ~a"
                                 archive-relative))
             (sha256-port
              (open-input-bytes (archive-member-bytes archive member)))]))
        (if (equal? actual digest)
            '()
            (list (format "license input checksum mismatch: ~a" bundle-path))))))

(define (resource-errors resource forbidden-segments)
  (define name (hash-value resource 'name))
  (define source-root (hash-value resource 'source_root))
  (define source (hash-value resource 'source))
  (define destination (hash-value resource 'destination))
  (define mode (hash-value resource 'mode))
  (define files (hash-value resource 'files))
  (append
   (if (and (string? name) (member name expected-resource-names))
       '()
       '("runtime resource name is not admitted"))
   (if (member source-root '("generated" "release-input"))
       '()
       (list (format "runtime resource has invalid source root: ~a" name)))
   (if (safe-relative-path? source)
       '()
       (list (format "runtime resource has unsafe source: ~a" name)))
   (if (safe-relative-path? destination)
       '()
       (list (format "runtime resource has unsafe destination: ~a" name)))
   (if (member mode '("generated-file" "selected-files" "tree"))
       '()
       (list (format "runtime resource has invalid mode: ~a" name)))
   (if (and (list? files) (andmap safe-relative-path? files))
       '()
       (list (format "runtime resource has unsafe file selection: ~a" name)))
   (if (and (safe-relative-path? destination)
            (for/or ([segment (in-list (string-split destination "/"))])
              (member segment forbidden-segments)))
       (list (format "runtime resource enters a forbidden bundle segment: ~a" name))
       '())))

(define (product-module-errors declaration forbidden-segments)
  (if (not declaration)
      '()
      (let ([destination (hash-value declaration 'destination)]
            [manifest (hash-value declaration 'manifest)]
            [artifacts (hash-value declaration 'artifacts)])
        (append
         (if (safe-relative-path? destination)
             '()
             '("product module destination is unsafe"))
         (if (safe-relative-path? manifest)
             '()
             '("product module manifest path is unsafe"))
         (if (and (list? artifacts)
                  (pair? artifacts)
                  (andmap safe-relative-path? artifacts)
                  (sorted-unique-strings? artifacts))
             '()
             '("product module artifact inventory is invalid"))
         (if (and (safe-relative-path? destination)
                  (for/or ([segment (in-list (string-split destination "/"))])
                    (member segment forbidden-segments)))
             '("product module destination enters a forbidden bundle segment")
             '())))))

(define (component-errors component repository-root release-input-root)
  (define name (hash-value component 'name))
  (define license-inputs (hash-value component 'license_inputs))
  (append
   (if (and (string? name) (positive? (string-length name)))
       '()
       '("redistributed component name is invalid"))
   (for/fold ([errors '()])
             ([key (in-list '(version revision source_url license_expression
                                      selected_license source_obligation))])
     (define value (hash-value component key))
     (if (and (string? value) (positive? (string-length value)))
         errors
         (cons (format "component ~a is missing ~a" name key) errors)))
   (if (member (hash-value component 'incorporation) admitted-incorporations)
       '()
       (list (format "component ~a has invalid incorporation" name)))
   (if (eq? (hash-value component 'redistributed) #t)
       '()
       (list (format "component ~a must be classified as redistributed" name)))
   (if (and (list? license-inputs) (pair? license-inputs))
       (append-map
        (lambda (input)
          (map (lambda (error) (format "component ~a: ~a" name error))
               (license-input-errors input repository-root release-input-root)))
        license-inputs)
       (list (format "component ~a has no license inputs" name)))))

(define (build-tool-errors tool)
  (define name (hash-value tool 'name))
  (append
   (for/fold ([errors '()])
             ([key (in-list '(name version revision source_url license_expression))])
     (define value (hash-value tool key))
     (if (and (string? value) (positive? (string-length value)))
         errors
         (cons (format "build tool ~a is missing ~a" name key) errors)))
   (if (equal? (hash-value tool 'incorporation) "build-only")
       '()
       (list (format "build tool ~a is not build-only" name)))
   (if (eq? (hash-value tool 'redistributed) #f)
       '()
       (list (format "build tool ~a must not be redistributed" name)))))

(define (runtime-closure-errors closure
                                repository-root
                                release-input-root
                                #:needed [actual-needed #f]
                                #:interpreter [actual-interpreter #f])
  (define bundle (hash-value closure 'bundle (hasheq)))
  (define product-terms (hash-value closure 'product_terms (hasheq)))
  (define baseline (hash-value closure 'baseline (hasheq)))
  (define resources (hash-value bundle 'runtime_resources '()))
  (define product-modules (hash-value bundle 'product_modules))
  (define components (hash-value closure 'components '()))
  (define build-tools (hash-value closure 'build_tools '()))
  (define forbidden-segments
    (hash-value closure 'forbidden_bundle_segments '()))
  (define expected-needed (hash-value baseline 'needed '()))
  (define component-names (map (lambda (component) (hash-value component 'name)) components))
  (define license-bundle-paths
    (for*/list ([component (in-list components)]
                [input (in-list (hash-value component 'license_inputs '()))])
      (hash-value input 'bundle_path)))
  (append
   (if (equal? (hash-value closure 'schema) expected-schema)
       '()
       '("runtime closure schema is invalid"))
   (if (equal? (hash-value closure 'platform) expected-platform)
       '()
       '("runtime closure platform is invalid"))
   (if (safe-relative-path? (hash-value bundle 'binary))
       '()
       '("bundle binary path is unsafe"))
   (if (equal? (hash-value bundle 'license_directory) "LICENSES")
       '()
       '("bundle license directory is invalid"))
   (if (safe-relative-path? (hash-value product-terms 'path))
       '()
       '("product terms path is unsafe"))
   (if (and (string? (hash-value product-terms 'sha256))
            (regexp-match? sha256-pattern (hash-value product-terms 'sha256)))
       '()
       '("product terms SHA-256 is invalid"))
   (if (and (safe-relative-path? (hash-value product-terms 'path))
            (file-exists? (build-path repository-root
                                      (hash-value product-terms 'path)))
            (equal? (sha256-file
                     (build-path repository-root
                                 (hash-value product-terms 'path)))
                    (hash-value product-terms 'sha256)))
       '()
       '("approved product terms are unavailable or changed"))
   (if (and (list? forbidden-segments)
            (andmap (lambda (value)
                      (and (string? value)
                           (not (string-contains? value "/"))))
                    forbidden-segments))
       '()
       '("forbidden bundle segments are invalid"))
   (if (and (list? resources)
            (equal? (sort (map (lambda (resource) (hash-value resource 'name)) resources)
                          string<?)
                    expected-resource-names))
       '()
       '("runtime resource inventory is incomplete"))
   (append-map (lambda (resource) (resource-errors resource forbidden-segments))
               resources)
   (product-module-errors product-modules forbidden-segments)
   (if (sorted-unique-strings? expected-needed)
       '()
       '("baseline dependency allowlist must be sorted and unique"))
   (if (and (string? (hash-value baseline 'interpreter))
            (string-prefix? (hash-value baseline 'interpreter) "/"))
       '()
       '("baseline ELF interpreter is invalid"))
   (if (and (list? components)
            (pair? components)
            (= (length component-names)
               (length (remove-duplicates component-names))))
       '()
       '("redistributed component names must be unique"))
   (append-map
    (lambda (component)
      (component-errors component repository-root release-input-root))
    components)
   (if (and (list? license-bundle-paths)
            (andmap safe-relative-path? license-bundle-paths)
            (= (length license-bundle-paths)
               (length (remove-duplicates license-bundle-paths))))
       '()
       '("bundled license paths must be safe and unique"))
   (if (and (list? build-tools) (pair? build-tools))
       (append-map build-tool-errors build-tools)
       '("build-only tool inventory is missing"))
   (if (and actual-needed (not (equal? actual-needed expected-needed)))
       (list (format "ELF dependency closure mismatch: expected ~a, found ~a"
                     expected-needed
                     actual-needed))
       '())
   (if (and actual-interpreter
            (not (equal? actual-interpreter (hash-value baseline 'interpreter))))
       (list (format "ELF interpreter mismatch: expected ~a, found ~a"
                     (hash-value baseline 'interpreter)
                     actual-interpreter))
       '())))

(define (read-elf-closure binary)
  (define readelf (find-executable-path "readelf"))
  (unless readelf
    (raise-user-error 'runtime-closure "readelf is unavailable"))
  (define-values (dynamic-bytes dynamic-status dynamic-error)
    (run/capture readelf
                 (list "-d" (if (path? binary) (path->string binary) binary))))
  (unless (zero? dynamic-status)
    (raise-user-error 'runtime-closure
                      "cannot inspect ELF dependencies: ~a"
                      (string-trim dynamic-error)))
  (define needed
    (sort
     (for/list ([line (in-list (string-split (bytes->string/utf-8 dynamic-bytes) "\n"))]
                #:when (regexp-match #px"Shared library: \\[([^]]+)\\]" line))
       (cadr (regexp-match #px"Shared library: \\[([^]]+)\\]" line)))
     string<?))
  (define-values (program-bytes program-status program-error)
    (run/capture readelf
                 (list "-l" (if (path? binary) (path->string binary) binary))))
  (unless (zero? program-status)
    (raise-user-error 'runtime-closure
                      "cannot inspect ELF interpreter: ~a"
                      (string-trim program-error)))
  (define interpreter-match
    (regexp-match #px"Requesting program interpreter: ([^]]+)"
                  (bytes->string/utf-8 program-bytes)))
  (unless interpreter-match
    (raise-user-error 'runtime-closure "ELF interpreter is unavailable"))
  (values needed (cadr interpreter-match)))

(module+ main
  (define manifest-path default-manifest-path)
  (define binary-path #f)
  (define repository-root default-repository-root)
  (define release-input-root (string->path "/"))
  (command-line
   #:program "check-runtime-closure.rkt"
   #:once-each
   [("--manifest") path "Runtime closure manifest" (set! manifest-path path)]
   [("--binary") path "ELF executable to inspect" (set! binary-path path)]
   [("--repository-root") path "Repository input root"
    (set! repository-root (path->complete-path path))]
   [("--release-input-root") path "Pinned distribution input root"
    (set! release-input-root (path->complete-path path))])
  (unless binary-path
    (raise-user-error 'runtime-closure "--binary is required"))
  (define closure (read-runtime-closure manifest-path))
  (define-values (needed interpreter) (read-elf-closure binary-path))
  (define errors
    (runtime-closure-errors closure
                            repository-root
                            release-input-root
                            #:needed needed
                            #:interpreter interpreter))
  (unless (null? errors)
    (for-each (lambda (error) (eprintf "runtime closure: ~a\n" error)) errors)
    (exit 1))
  (printf "runtime_closure=valid platform=~a components=~a needed=~a\n"
          (hash-value closure 'platform)
          (length (hash-value closure 'components))
          (length needed)))

(module+ test
  (require rackunit)

  (define manifest-path default-manifest-path)
  (define closure (read-runtime-closure manifest-path))
  (define repository-root default-repository-root)
  (define release-input-root (string->path "/"))
  (define baseline (hash-value closure 'baseline))

  (test-case "accepts the declared runtime and license closure"
    (check-equal?
     (runtime-closure-errors closure repository-root release-input-root)
     '()))

  (test-case "rejects an undeclared ELF dependency"
    (define needed
      (append (hash-value baseline 'needed) '("libunexpected.so.1")))
    (check-not-false
     (member
      (format "ELF dependency closure mismatch: expected ~a, found ~a"
              (hash-value baseline 'needed)
              needed)
      (runtime-closure-errors closure
                              repository-root
                              release-input-root
                              #:needed needed))))

  (test-case "rejects unsafe runtime destinations"
    (define bundle (hash-value closure 'bundle))
    (define resources (hash-value bundle 'runtime_resources))
    (define unsafe-resource
      (hash-set (car resources) 'destination "../outside"))
    (define unsafe-bundle
      (hash-set bundle 'runtime_resources (cons unsafe-resource (cdr resources))))
    (define unsafe-closure (hash-set closure 'bundle unsafe-bundle))
    (check-not-false
     (member "runtime resource has unsafe destination: racket-boot"
             (runtime-closure-errors unsafe-closure
                                     repository-root
                                     release-input-root))))

  (test-case "rejects changed product terms"
    (define changed-terms
      (hash-set (hash-value closure 'product_terms)
                'sha256
                "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
    (define changed-closure
      (hash-set closure 'product_terms changed-terms))
    (check-not-false
     (member "approved product terms are unavailable or changed"
             (runtime-closure-errors changed-closure
                                     repository-root
                                     release-input-root))))

  (test-case "rejects missing license inputs"
    (define components (hash-value closure 'components))
    (define first-component (car components))
    (define first-input (car (hash-value first-component 'license_inputs)))
    (define missing-input
      (hash-set first-input 'path "missing/LICENSE"))
    (define missing-component
      (hash-set first-component 'license_inputs (list missing-input)))
    (define missing-closure
      (hash-set closure 'components (cons missing-component (cdr components))))
    (check-true
     (for/or ([error (in-list
                      (runtime-closure-errors missing-closure
                                              repository-root
                                              release-input-root))])
       (string-contains? error "license file is missing")))))
