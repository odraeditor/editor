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
         racket/port
         racket/runtime-path
         racket/string
         racket/system)

(provide (struct-out snapshot-build-request)
         (struct-out snapshot-build-identity)
         (struct-out build-step)
         (struct-out snapshot-build-plan)
         snapshot-build-request-errors
         snapshot-build-identity->jsexpr
         prepare-snapshot-build-plan
         execute-snapshot-build-plan!)

(struct snapshot-build-request
  (checkout snapshot-commit snapshot-tree adapter-commit version
            source-date-epoch output)
  #:transparent)

(struct snapshot-build-identity
  (snapshot-commit snapshot-tree canonical-source-commit inventory-sha256
                   adapter-commit build-environment-digest)
  #:transparent)

(struct build-step
  (name program arguments directory environment timeout-seconds)
  #:transparent)

(struct snapshot-build-plan
  (identity steps output artifact-tree archive checksum evidence)
  #:transparent)

(define commit-pattern #px"^[0-9a-f]{40}$")
(define digest-pattern #px"^[0-9a-f]{64}$")
(define semver-pattern
  #px"^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$")

(define-runtime-path runtime-module-builder
  "build-racket-runtime-module.rkt")
(define-runtime-path validation-containerfile
  "../../release/linux-x86_64/Containerfile.validation")

(define (hash-value table key [fallback #f])
  (if (hash? table) (hash-ref table key fallback) fallback))

(define (required-git)
  (or (find-executable-path "git")
      (raise-user-error 'snapshot-build "git is unavailable")))

(define (run/capture program arguments #:directory [directory #f])
  (define-values (process output input errors)
    (parameterize ([current-directory (or directory (current-directory))])
      (apply subprocess #f #f #f program arguments)))
  (close-output-port input)
  (define standard-output (port->string output))
  (define standard-error (port->string errors))
  (subprocess-wait process)
  (unless (zero? (subprocess-status process))
    (raise-user-error 'snapshot-build
                      "command failed: ~a"
                      (string-trim standard-error)))
  (string-trim standard-output))

(define (git-output checkout . arguments)
  (run/capture (required-git)
               (append (list "-C" (path->string checkout)) arguments)))

(define (path-components path)
  (map path->string
       (filter path? (explode-path (simplify-path (path->complete-path path))))))

(define (components-prefix? prefix value)
  (and (<= (length prefix) (length value))
       (equal? prefix (take value (length prefix)))))

(define (paths-overlap? left right)
  (define left-components (path-components left))
  (define right-components (path-components right))
  (or (components-prefix? left-components right-components)
      (components-prefix? right-components left-components)))

(define (directory-empty-or-absent? path)
  (or (not (file-or-directory-type path #f))
      (and (directory-exists? path) (null? (directory-list path)))))

(define required-snapshot-paths
  '("Makefile"
    "makefiles/internal.mk"
    "release/linux-x86_64/Containerfile.build"
    "release/linux-x86_64/build-environment.json"
    "release/linux-x86_64/runtime-closure.json"
    "release/public-source-manifest.json"
    "scripts/release/assemble-preview-tree.rkt"
    "scripts/release/archive-preview-tree.rkt"
    "scripts/release/build-racket-runtime-module.rkt"
    "scripts/release/check-build-environment.rkt"
    "scripts/release/record-preview-provenance.rkt"
    "src/odra/main.odin"))

(define (snapshot-build-request-errors request)
  (define checkout
    (and (path-string? (snapshot-build-request-checkout request))
         (path->complete-path (snapshot-build-request-checkout request))))
  (define output
    (and (path-string? (snapshot-build-request-output request))
         (path->complete-path (snapshot-build-request-output request))))
  (append
   (if (and checkout (directory-exists? checkout))
       '()
       '("snapshot checkout is unavailable"))
   (if (and (string? (snapshot-build-request-snapshot-commit request))
            (regexp-match? commit-pattern
                           (snapshot-build-request-snapshot-commit request)))
       '()
       '("snapshot commit must be a full lowercase Git identity"))
   (if (and (string? (snapshot-build-request-snapshot-tree request))
            (regexp-match? commit-pattern
                           (snapshot-build-request-snapshot-tree request)))
       '()
       '("snapshot tree must be a full lowercase Git identity"))
   (if (and (string? (snapshot-build-request-adapter-commit request))
            (regexp-match? commit-pattern
                           (snapshot-build-request-adapter-commit request)))
       '()
       '("adapter commit must be a full lowercase Git identity"))
   (if (and (string? (snapshot-build-request-version request))
            (regexp-match? semver-pattern
                           (snapshot-build-request-version request)))
       '()
       '("version must use canonical MAJOR.MINOR.PATCH form"))
   (if (and (exact-nonnegative-integer?
             (snapshot-build-request-source-date-epoch request))
            (< (snapshot-build-request-source-date-epoch request) (expt 2 63)))
       '()
       '("source date epoch must be an unsigned 63-bit integer"))
   (if output '() '("output path is invalid"))
   (if (and output (directory-empty-or-absent? output))
       '()
       '("output directory must be absent or empty"))
   (if (and checkout output (not (paths-overlap? checkout output)))
       '()
       '("snapshot checkout and output directory must not overlap"))
   (if checkout
       (for/list ([relative (in-list required-snapshot-paths)]
                  #:unless (file-exists? (build-path checkout relative)))
         (format "snapshot build input is missing: ~a" relative))
       '())))

(define (require-valid-request request)
  (define errors (snapshot-build-request-errors request))
  (unless (null? errors)
    (raise-arguments-error 'prepare-snapshot-build-plan
                           "invalid snapshot build request"
                           "errors" errors)))

(define (read-json-file path who)
  (with-handlers ([exn:fail?
                   (lambda (_)
                     (raise-user-error who "JSON input is invalid: ~a" path))])
    (call-with-input-file path read-json)))

(define (exact-checkout-identity checkout request)
  (define top-level
    (path->complete-path (git-output checkout "rev-parse" "--show-toplevel")))
  (unless (equal? (simplify-path checkout) (simplify-path top-level))
    (raise-user-error 'snapshot-build
                      "snapshot checkout must be the Git worktree root"))
  (define commit (git-output checkout "rev-parse" "HEAD^{commit}"))
  (define tree (git-output checkout "rev-parse" "HEAD^{tree}"))
  (define timestamp (string->number (git-output checkout "show" "-s" "--format=%ct")))
  (define status
    (git-output checkout "status" "--porcelain=v1" "--untracked-files=all"))
  (unless (and (string=? commit (snapshot-build-request-snapshot-commit request))
               (string=? tree (snapshot-build-request-snapshot-tree request))
               (equal? timestamp
                       (snapshot-build-request-source-date-epoch request))
               (string=? status ""))
    (raise-user-error 'snapshot-build
                      "snapshot checkout identity or cleanliness differs"))
  (values commit tree))

(define (snapshot-manifest-identity checkout)
  (define manifest
    (read-json-file (build-path checkout "release" "public-source-manifest.json")
                    'snapshot-build))
  (define canonical-commit (hash-value manifest 'source_commit))
  (define inventory-sha256 (hash-value manifest 'inventory_sha256))
  (unless (and (equal? (hash-value manifest 'model)
                       "odra-public-source-snapshot")
               (string? canonical-commit)
               (regexp-match? commit-pattern canonical-commit)
               (string? inventory-sha256)
               (regexp-match? digest-pattern inventory-sha256))
    (raise-user-error 'snapshot-build
                      "public source manifest identity is invalid"))
  (values canonical-commit inventory-sha256))

(define (build-environment-digest checkout)
  (define environment
    (read-json-file
     (build-path checkout "release" "linux-x86_64" "build-environment.json")
     'snapshot-build))
  (define digest
    (hash-value (hash-value (hash-value environment 'images (hasheq))
                            'build
                            (hasheq))
                'digest))
  (unless (and (string? digest)
               (regexp-match? #px"^sha256:[0-9a-f]{64}$" digest))
    (raise-user-error 'snapshot-build
                      "build environment image digest is invalid"))
  digest)

(define (snapshot-build-identity->jsexpr identity)
  (hasheq
   'schema 1
   'model "odra-snapshot-build"
   'snapshot_commit (snapshot-build-identity-snapshot-commit identity)
   'snapshot_tree (snapshot-build-identity-snapshot-tree identity)
   'canonical_source_commit
   (snapshot-build-identity-canonical-source-commit identity)
   'source_inventory_sha256
   (snapshot-build-identity-inventory-sha256 identity)
   'adapter_commit (snapshot-build-identity-adapter-commit identity)
   'build_environment_digest
   (snapshot-build-identity-build-environment-digest identity)))

(define (quoted-build-command request environment-digest artifact-stem)
  (define commit (snapshot-build-request-snapshot-commit request))
  (define tag (string-append "v" (snapshot-build-request-version request)))
  (define epoch (number->string (snapshot-build-request-source-date-epoch request)))
  (string-append
   "mkdir -p \"$HOME\""
   " && racket /release-adapter/build-racket-runtime-module.rkt"
   " --source-root src"
   " --entry hosting/runtime-boundary.rkt"
   " --output .build/preview-runtime/runtime_module.c"
   " && make preview-tree "
   "BUILD_DIR=.build "
   "PREVIEW_TREE_OUTPUT_PARENT=.build/artifacts "
   "PREVIEW_TAG=" tag " "
   "PREVIEW_COMMIT=" commit " "
   "PREVIEW_BUILD_ENVIRONMENT=" environment-digest " "
   "SOURCE_DATE_EPOCH=" epoch " "
   "ODRA_PREVIEW_THREAD_COUNT=1"
   " && make preview-archive "
   "BUILD_DIR=.build "
   "PREVIEW_ARCHIVE_OUTPUT_PARENT=.build/artifacts "
   "PREVIEW_TREE=.build/artifacts/" artifact-stem " "
   "PREVIEW_TAG=" tag " "
   "PREVIEW_COMMIT=" commit " "
   "SOURCE_DATE_EPOCH=" epoch))

(define (host-user-group)
  (define id
    (or (find-executable-path "id")
        (raise-user-error 'snapshot-build "id is unavailable")))
  (define user (run/capture id '("-u")))
  (define group (run/capture id '("-g")))
  (unless (and (regexp-match? #px"^[0-9]+$" user)
               (regexp-match? #px"^[0-9]+$" group))
    (raise-user-error 'snapshot-build "runner user identity is invalid"))
  (string-append user ":" group))

(define (prepare-snapshot-build-plan request)
  (require-valid-request request)
  (define checkout (path->complete-path (snapshot-build-request-checkout request)))
  (define output (path->complete-path (snapshot-build-request-output request)))
  (define-values (commit tree) (exact-checkout-identity checkout request))
  (define-values (canonical-commit inventory-sha256)
    (snapshot-manifest-identity checkout))
  (define environment-digest (build-environment-digest checkout))
  (define identity
    (snapshot-build-identity commit tree canonical-commit inventory-sha256
                             (snapshot-build-request-adapter-commit request)
                             environment-digest))
  (define artifact-stem
    (format "odra-~a-linux-x86_64" (snapshot-build-request-version request)))
  (define artifact-root (build-path output "artifacts"))
  (define artifact-tree (build-path artifact-root artifact-stem))
  (define archive (build-path artifact-root (string-append artifact-stem ".tar.zst")))
  (define checksum (build-path artifact-root
                               (string-append artifact-stem ".tar.zst.sha256")))
  (define evidence (build-path output "evidence"))
  (define image
    (string-append "odra-snapshot-build:"
                   (substring environment-digest (string-length "sha256:") 19)))
  (define validation-image
    (string-append "odra-snapshot-validation:"
                   (substring environment-digest (string-length "sha256:") 19)))
  (define checkout-string (path->string checkout))
  (define output-string (path->string output))
  (define steps
    (list
     (build-step
      'environment-check
      "racket"
      (list (path->string
             (build-path checkout "scripts" "release"
                         "check-build-environment.rkt")))
      checkout
      (hasheq)
      #f)
     (build-step
      'image-build
      "docker"
      (list "build" "--quiet" "--tag" image
            "--file"
            (path->string
             (build-path checkout "release" "linux-x86_64"
                         "Containerfile.build"))
            (path->string
             (build-path checkout "release" "linux-x86_64")))
      checkout
      (hasheq)
      #f)
     (build-step
      'toolchain-probe
      "docker"
      (list "run" "--rm" "--network" "none" "--cpus" "4"
            "--memory" "6g" "--pids-limit" "512" image "bash" "-lc"
            "test \"$(odin version)\" = \"odin version dev-2026-07:301c287de\" && test \"$(racket --version)\" = \"Welcome to Racket v9.2 [cs].\"")
      checkout
      (hasheq)
      #f)
     (build-step
      'validation-image-build
      "docker"
      (list "build" "--progress=plain" "--tag" validation-image
            "--build-arg" (string-append "ODRA_BUILD_IMAGE=" image)
            "--file" (path->string validation-containerfile)
            (path->string (path-only validation-containerfile)))
      checkout
      (hasheq)
      #f)
     (build-step
      'validation-image-probe
      "docker"
      (list "run" "--rm" "--network" "none" "--cpus" "1"
            "--memory" "268435456" "--pids-limit" "64"
            "--read-only" "--security-opt" "no-new-privileges"
            "--cap-drop" "ALL" validation-image "/bin/bash" "-lc"
            (string-append
             "test ! -e /workspace"
             " && ! command -v odin >/dev/null 2>&1"
             " && ! command -v racket >/dev/null 2>&1"
             " && command -v script >/dev/null"
             " && command -v stty >/dev/null"
             " && ldconfig -p | grep -F libsodium.so >/dev/null"))
      checkout
      (hasheq)
      #f)
     (build-step
      'bundle-build
      "docker"
      (list "run" "--rm" "--network" "none"
            "--cpus" "4" "--memory" "6g" "--pids-limit" "512"
            "--security-opt" "no-new-privileges" "--cap-drop" "ALL"
            "--user" (host-user-group)
            "--env" "HOME=/tmp/odra-home"
            "--env" (format "SOURCE_DATE_EPOCH=~a"
                            (snapshot-build-request-source-date-epoch request))
            "--tmpfs" "/tmp:rw,nosuid,nodev,size=1073741824,mode=1777"
            "--mount" (format "type=bind,src=~a,dst=/workspace,readonly"
                              checkout-string)
            "--mount"
            (format
             "type=bind,src=~a,dst=/release-adapter/build-racket-runtime-module.rkt,readonly"
             (path->string runtime-module-builder))
            "--mount" (format "type=bind,src=~a,dst=/workspace/.build" output-string)
            "--workdir" "/workspace" image "bash" "-lc"
            (quoted-build-command request environment-digest artifact-stem))
      checkout
      (hasheq)
      7200)
     (build-step
      'provenance
      "racket"
      (list (path->string
             (build-path checkout "scripts" "release"
                         "record-preview-provenance.rkt"))
            "--tree" (path->string artifact-tree)
            "--archive" (path->string archive)
            "--checksum" (path->string checksum)
            "--tag" (string-append "v" (snapshot-build-request-version request))
            "--commit" commit
            "--adapter-commit" (snapshot-build-request-adapter-commit request)
            "--source-date-epoch"
            (number->string (snapshot-build-request-source-date-epoch request))
            "--build-environment" environment-digest
            "--evidence" (path->string evidence))
      checkout
      (hasheq)
      #f)))
  (snapshot-build-plan identity steps output artifact-tree archive checksum evidence))

(define (step-environment additions)
  (define environment
    (environment-variables-copy (current-environment-variables)))
  (for ([(key value) (in-hash additions)])
    (environment-variables-set! environment
                                (string->bytes/utf-8 (symbol->string key))
                                (string->bytes/utf-8 value)))
  environment)

(define (execute-step! step log-path)
  (define executable
    (or (find-executable-path (build-step-program step))
        (raise-user-error 'snapshot-build
                          "required executable is unavailable: ~a"
                          (build-step-program step))))
  (call-with-output-file log-path
    #:exists 'truncate/replace
    (lambda (log)
      (define-values (process output input errors)
        (parameterize ([current-directory (build-step-directory step)]
                       [current-environment-variables
                        (step-environment (build-step-environment step))])
          (apply subprocess log #f log executable (build-step-arguments step))))
      (close-output-port input)
      (when output (close-input-port output))
      (when errors (close-input-port errors))
      (define timeout-seconds (build-step-timeout-seconds step))
      (when (and timeout-seconds
                 (not (sync/timeout timeout-seconds process)))
        (subprocess-kill process #f)
        (unless (sync/timeout 10 process)
          (subprocess-kill process #t))
        (subprocess-wait process)
        (raise-user-error 'snapshot-build
                          "build step timed out: ~a"
                          (build-step-name step)))
      (subprocess-wait process)
      (unless (zero? (subprocess-status process))
        (raise-user-error 'snapshot-build
                          "build step failed: ~a\n~a"
                          (build-step-name step)
                          (build-log-tail log-path))))))

(define build-log-tail-line-limit 500)

(define (build-log-tail path)
  (define lines
    (call-with-input-file path
      (lambda (input) (port->lines input))))
  (define retained
    (if (> (length lines) build-log-tail-line-limit)
        (drop lines (- (length lines) build-log-tail-line-limit))
        lines))
  (string-append
   (if (> (length lines) build-log-tail-line-limit)
       (format "last ~a of ~a log lines:\n"
               build-log-tail-line-limit
               (length lines))
       "build log:\n")
   (string-join retained "\n")))

(define (execute-snapshot-build-plan! plan)
  (define output (snapshot-build-plan-output plan))
  (unless (directory-empty-or-absent? output)
    (raise-arguments-error 'execute-snapshot-build-plan!
                           "output directory must remain absent or empty"
                           "output" output))
  (make-directory* (snapshot-build-plan-evidence plan))
  (make-directory* (build-path output "artifacts"))
  (define bundle-step
    (findf (lambda (step) (eq? (build-step-name step) 'bundle-build))
           (snapshot-build-plan-steps plan)))
  (unless bundle-step
    (raise-arguments-error 'execute-snapshot-build-plan!
                           "bundle build step is required"
                           "plan" plan))
  (make-directory* (build-path (build-step-directory bundle-step) ".build"))
  (for ([step (in-list (snapshot-build-plan-steps plan))]
        [index (in-naturals 1)])
    (execute-step!
     step
     (build-path (snapshot-build-plan-evidence plan)
                 (format "~a-~a.log" index (build-step-name step)))))
  (call-with-output-file
      (build-path (snapshot-build-plan-evidence plan) "snapshot-build.json")
    #:exists 'truncate/replace
    (lambda (output)
      (write-json
       (hash-set
        (snapshot-build-identity->jsexpr (snapshot-build-plan-identity plan))
        'archive
        (path->string (file-name-from-path
                       (snapshot-build-plan-archive plan))))
       output)
      (newline output)))
  plan)

(module+ main
  (define checkout #f)
  (define commit #f)
  (define tree #f)
  (define adapter-commit #f)
  (define version #f)
  (define epoch #f)
  (define output #f)
  (define plan-only? #f)
  (command-line
   #:program "snapshot-build.rkt"
   #:once-each
   [("--checkout") path "Clean snapshot checkout" (set! checkout path)]
   [("--snapshot-commit") value "Exact snapshot commit" (set! commit value)]
   [("--snapshot-tree") value "Exact snapshot tree" (set! tree value)]
   [("--adapter-commit") value "Validated publication adapter commit"
                                 (set! adapter-commit value)]
   [("--version") value "Canonical release version" (set! version value)]
   [("--source-date-epoch") value "Snapshot commit timestamp"
                                   (set! epoch (string->number value))]
   [("--output") path "Absent or empty build output" (set! output path)]
   [("--plan-only") "Validate and print the plan without executing"
                      (set! plan-only? #t)])
  (unless (and checkout commit tree adapter-commit version epoch output)
    (raise-user-error 'snapshot-build
                      "checkout, snapshot-commit, snapshot-tree, adapter-commit, version, source-date-epoch, and output are required"))
  (define plan
    (prepare-snapshot-build-plan
     (snapshot-build-request checkout commit tree adapter-commit version epoch output)))
  (unless plan-only? (execute-snapshot-build-plan! plan))
  (write-json
   (hash-set*
    (snapshot-build-identity->jsexpr (snapshot-build-plan-identity plan))
    'steps (map (lambda (step) (symbol->string (build-step-name step)))
                (snapshot-build-plan-steps plan))
    'executed (not plan-only?)
    'archive (path->string (snapshot-build-plan-archive plan))))
  (newline))
