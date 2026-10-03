#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require json
         racket/cmdline
         racket/list
         racket/runtime-path
         racket/string)

(provide read-build-environment
         build-environment-errors)

(define expected-schema 1)
(define expected-platform "linux-x86_64")
(define expected-image-kinds '(build validation))
(define expected-network-phases
  '(input_preparation native_build bundle_assembly smoke_validation))
(define expected-offline-phases
  '(native_build bundle_assembly smoke_validation))
(define expected-tool-names
  '("odin-compiler" "racket-build-tools" "zig-compiler"))
(define digest-pattern #px"^sha256:[0-9a-f]{64}$")
(define bare-digest-pattern #px"^[0-9a-f]{64}$")
(define image-reference-pattern #px"^[^[:space:]@]+@sha256:[0-9a-f]{64}$")
(define snapshot-pattern
  #px"^https://archive\\.archlinux\\.org/repos/[0-9]{4}/[0-9]{2}/[0-9]{2}/\\$repo/os/\\$arch$")
(define-runtime-path script-directory ".")
(define default-repository-root
  (simplify-path (build-path script-directory ".." "..")))
(define default-environment-path
  (build-path default-repository-root
              "release"
              "linux-x86_64"
              "build-environment.json"))
(define default-closure-path
  (build-path default-repository-root
              "release"
              "linux-x86_64"
              "runtime-closure.json"))

(define (read-build-environment path)
  (call-with-input-file path read-json))

(define (hash-value table key [fallback #f])
  (if (hash? table) (hash-ref table key fallback) fallback))

(define (sorted-unique-by-name? values)
  (and (list? values)
       (andmap hash? values)
       (let ([names (map (lambda (value) (hash-value value 'name)) values)])
         (and (andmap string? names)
              (equal? names (sort (remove-duplicates names) string<?))))))

(define (image-errors kind image)
  (define reference (hash-value image 'reference))
  (define digest (hash-value image 'digest))
  (append
   (if (and (string? reference)
            (regexp-match? image-reference-pattern reference))
       '()
       (list (format "~a image reference is not pinned by digest" kind)))
   (if (and (string? digest) (regexp-match? digest-pattern digest))
       '()
       (list (format "~a image digest is invalid" kind)))
   (if (and (string? reference)
            (string? digest)
            (string-suffix? reference (string-append "@" digest)))
       '()
       (list (format "~a image reference and digest disagree" kind)))
   (if (equal? (hash-value image 'os) "linux")
       '()
       (list (format "~a image operating system is unsupported" kind)))
   (if (equal? (hash-value image 'architecture) "amd64")
       '()
       (list (format "~a image architecture is unsupported" kind)))
   (if (and (string? (hash-value image 'created))
            (regexp-match? #px"^[0-9]{4}-[0-9]{2}-[0-9]{2}T" (hash-value image 'created)))
       '()
       (list (format "~a image creation time is invalid" kind)))))

(define (package-errors packages)
  (define pinned-downloads
    (if (list? packages)
        (filter (lambda (package)
                  (member (hash-value package 'name) '("odin" "racket")))
                packages)
        '()))
  (append
   (if (sorted-unique-by-name? packages)
       '()
       '("package inputs must be sorted and unique by name"))
   (if (and (list? packages)
            (for/and ([package (in-list packages)])
              (and (string? (hash-value package 'name))
                   (non-empty-string? (hash-value package 'name))
                   (string? (hash-value package 'version))
                   (non-empty-string? (hash-value package 'version)))))
       '()
       '("package inputs require exact names and versions"))
   (if (and (= (length pinned-downloads) 2)
            (for/and ([package (in-list pinned-downloads)])
              (and (string? (hash-value package 'source_url))
                   (string-prefix? (hash-value package 'source_url)
                                   "https://archive.archlinux.org/packages/")
                   (string? (hash-value package 'sha256))
                   (regexp-match? bare-digest-pattern
                                  (hash-value package 'sha256)))))
       '()
       '("Odin and Racket packages require immutable downloads"))))

(define (toolchain-errors toolchains closure)
  (define closure-tools (hash-value closure 'build_tools '()))
  (append
   (if (and (sorted-unique-by-name? toolchains)
            (equal? (map (lambda (tool) (hash-value tool 'name)) toolchains)
                    expected-tool-names))
       '()
       '("toolchain inventory is incomplete or unsorted"))
   (if (and (list? toolchains)
            (for/and ([tool (in-list toolchains)])
              (define name (hash-value tool 'name))
              (define closure-tool
                (findf (lambda (candidate)
                         (equal? (hash-value candidate 'name) name))
                       closure-tools))
              (and closure-tool
                   (equal? (hash-value tool 'version)
                           (hash-value closure-tool 'version))
                   (equal? (hash-value tool 'revision)
                           (hash-value closure-tool 'revision))
                   (let ([probe (hash-value tool 'probe)])
                     (and (list? probe)
                          (pair? probe)
                          (andmap non-empty-string? probe)))
                   (non-empty-string? (hash-value tool 'expected_output)))))
       '()
       '("toolchain versions disagree with the runtime closure"))))

(define (network-errors network)
  (append
   (if (and (hash? network)
            (for/and ([phase (in-list expected-network-phases)])
              (string? (hash-value network phase))))
       '()
       '("network policy is incomplete"))
   (if (equal? (hash-value network 'input_preparation) "required")
       '()
       '("input preparation network policy must be required"))
   (if (for/and ([phase (in-list expected-offline-phases)])
         (equal? (hash-value network phase) "none"))
       '()
       '("native build, assembly, and smoke phases must be offline"))))

(define (reproducibility-errors reproducibility)
  (append
   (if (equal? (hash-value reproducibility 'model)
               "pinned-input-provenance")
       '()
       '("reproducibility model must use pinned input provenance"))
   (if (equal? (hash-value reproducibility 'byte_identical_rebuilds)
               "not-required")
       '()
       '("byte-identical rebuilds must not be an initial preview gate"))
   (if (equal? (hash-value reproducibility 'published_checksum)
               "authoritative-for-published-artifact")
       '()
       '("published checksum authority is invalid"))
   (if (equal? (hash-value reproducibility 'known_variable_paths)
               '("bin/odra"))
       '()
       '("known build variability must be limited to bin/odra"))))

(define (resource-errors resources)
  (define (bounded? key minimum maximum)
    (define value (hash-value resources key))
    (and (exact-integer? value) (<= minimum value maximum)))
  (append
   (if (bounded? 'cpus 1 4) '() '("CPU limit must be between 1 and 4"))
   (if (bounded? 'memory_bytes (* 4 1024 1024 1024) (* 6 1024 1024 1024))
       '()
       '("memory limit must be between 4 GiB and 6 GiB"))
   (if (bounded? 'pids 64 512) '() '("process limit must be between 64 and 512"))
   (if (bounded? 'timeout_seconds 1 7200) '() '("timeout must not exceed two hours"))
   (if (equal? (hash-value resources 'odin_threads) 1)
       '()
       '("Odin release builds require one bounded checker thread"))
   (if (bounded? 'terminal_vendor_jobs 1 2)
       '()
       '("terminal vendor job limit must not exceed 2"))
   (if (bounded? 'terminal_vendor_max_rss_bytes
                 (* 1024 1024 1024)
                 (* 4 1024 1024 1024))
       '()
       '("terminal vendor RSS limit must not exceed 4 GiB"))))

(define (requirement-errors requirements)
  (append
   (if (equal? (hash-value requirements 'container_engine) "docker")
       '()
       '("container engine is unsupported"))
   (if (equal? (hash-value requirements 'cgroup_version) 2)
       '()
       '("cgroup version is unsupported"))
   (if (equal? (hash-value requirements 'host_os) "linux")
       '()
       '("host operating system is unsupported"))
   (if (equal? (hash-value requirements 'host_architecture) "x86_64")
       '()
       '("host architecture is unsupported"))))

(define (build-environment-errors environment closure)
  (define images (hash-value environment 'images (hasheq)))
  (define repository (hash-value environment 'package_repository (hasheq)))
  (append
   (if (equal? (hash-value environment 'schema) expected-schema)
       '()
       '("build environment schema is unsupported"))
   (if (equal? (hash-value environment 'platform) expected-platform)
       '()
       '("build environment platform is unsupported"))
   (append-map
    (lambda (kind)
      (image-errors kind (hash-value images kind (hasheq))))
    expected-image-kinds)
   (if (and (string? (hash-value repository 'server))
            (regexp-match? snapshot-pattern (hash-value repository 'server)))
       '()
       '("package repository is not an immutable Arch snapshot"))
   (if (equal? (hash-value repository 'signature_policy)
               "Required DatabaseOptional")
       '()
       '("package signature policy is unsupported"))
   (package-errors (hash-value environment 'packages '()))
   (toolchain-errors (hash-value environment 'toolchains '()) closure)
   (network-errors (hash-value environment 'network (hasheq)))
   (reproducibility-errors
    (hash-value environment 'reproducibility (hasheq)))
   (resource-errors (hash-value environment 'resources (hasheq)))
   (requirement-errors (hash-value environment 'requirements (hasheq)))))

(module+ main
  (define environment-path default-environment-path)
  (define closure-path default-closure-path)
  (command-line
   #:program "check-build-environment.rkt"
   #:once-each
   [("--environment") path "Build environment manifest"
    (set! environment-path path)]
   [("--runtime-closure") path "Runtime closure manifest"
    (set! closure-path path)])
  (define environment (read-build-environment environment-path))
  (define closure (call-with-input-file closure-path read-json))
  (define errors (build-environment-errors environment closure))
  (unless (null? errors)
    (for-each (lambda (error) (eprintf "build environment: ~a\n" error)) errors)
    (exit 1))
  (printf "build_environment=valid platform=~a packages=~a toolchains=~a\n"
          (hash-value environment 'platform)
          (length (hash-value environment 'packages))
          (length (hash-value environment 'toolchains))))

(module+ test
  (require rackunit)

  (define environment (read-build-environment default-environment-path))
  (define closure (call-with-input-file default-closure-path read-json))

  (define (replace-section key update)
    (hash-set environment key (update (hash-value environment key))))

  (test-case "accepts the pinned Linux build environment"
    (check-equal? (build-environment-errors environment closure) '()))

  (test-case "rejects a movable image reference"
    (define images (hash-value environment 'images))
    (define build-image (hash-value images 'build))
    (define changed
      (hash-set environment
                'images
                (hash-set images
                          'build
                          (hash-set build-image
                                    'reference
                                    "docker.io/library/archlinux:base-devel"))))
    (check-not-false
     (member "build image reference is not pinned by digest"
             (build-environment-errors changed closure))))

  (test-case "rejects toolchain drift"
    (define tools (hash-value environment 'toolchains))
    (define changed-tool (hash-set (car tools) 'revision "unexpected"))
    (define changed (hash-set environment 'toolchains (cons changed-tool (cdr tools))))
    (check-not-false
     (member "toolchain versions disagree with the runtime closure"
             (build-environment-errors changed closure))))

  (test-case "rejects an unverified toolchain package"
    (define packages (hash-value environment 'packages))
    (define odin (findf (lambda (package)
                          (equal? (hash-value package 'name) "odin"))
                        packages))
    (define changed-odin (hash-remove odin 'sha256))
    (define changed
      (hash-set environment
                'packages
                (map (lambda (package)
                       (if (equal? (hash-value package 'name) "odin")
                           changed-odin
                           package))
                     packages)))
    (check-not-false
     (member "Odin and Racket packages require immutable downloads"
             (build-environment-errors changed closure))))

  (test-case "rejects networked native builds"
    (define changed
      (replace-section 'network
                       (lambda (network)
                         (hash-set network 'native_build "required"))))
    (check-not-false
     (member "native build, assembly, and smoke phases must be offline"
             (build-environment-errors changed closure))))

  (test-case "rejects byte-identical rebuilds as an initial preview gate"
    (define changed
      (replace-section 'reproducibility
                       (lambda (reproducibility)
                         (hash-set reproducibility
                                   'byte_identical_rebuilds
                                   "required"))))
    (check-not-false
     (member "byte-identical rebuilds must not be an initial preview gate"
             (build-environment-errors changed closure))))

  (test-case "rejects unbounded native resources"
    (define changed
      (replace-section 'resources
                       (lambda (resources)
                         (hash-set resources 'memory_bytes (* 8 1024 1024 1024)))))
    (check-not-false
     (member "memory limit must be between 4 GiB and 6 GiB"
             (build-environment-errors changed closure))))

  (test-case "rejects an unbounded Odin checker"
    (define changed
      (replace-section 'resources
                       (lambda (resources)
                         (hash-set resources 'odin_threads 4))))
    (check-not-false
     (member "Odin release builds require one bounded checker thread"
             (build-environment-errors changed closure))))

  (test-case "rejects an unsupported host"
    (define changed
      (replace-section 'requirements
                       (lambda (requirements)
                         (hash-set requirements 'host_architecture "aarch64"))))
    (check-not-false
     (member "host architecture is unsupported"
             (build-environment-errors changed closure)))))
