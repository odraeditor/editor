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
         racket/runtime-path
         racket/sandbox
         racket/string
         racket/system
         "../agent/definition.rkt"
         "../agent/registry.rkt"
         "../command/catalog.rkt"
         "../command/context.rkt"
         "../command/package-resources.rkt"
         (prefix-in bundle: "../command/language-bundles.rkt")
         "../command/personal-limits.rkt"
         "../command/personal.rkt"
         "acquisition.rkt"
         "authority-contract.rkt"
         "manifest-contracts.rkt"
         "state-records.rkt")

(provide
 odra-package-runtime-candidate?
 odra-package-runtime?
 (struct-out odra-package-authority-grant)
 (struct-out odra-package-runtime-limits)
 (struct-out odra-package-runtime-failure)
 default-package-runtime-limits
 (contract-out
  [prepare-package-runtime
   (->* (path-string? odra-installed-package? odra-package-manifest?
                      odra-package-authority-grant?
                      exact-positive-integer?)
        (#:limits odra-package-runtime-limits?)
        (or/c odra-package-runtime-candidate?
              odra-package-runtime-failure?))]
  [package-runtime-candidate-command-names
   (-> odra-package-runtime-candidate? (listof string?))]
  [package-runtime-candidate-catalog
   (-> odra-package-runtime-candidate? odra-command-catalog?)]
  [package-runtime-candidate-agent-catalog
   (-> odra-package-runtime-candidate? odra-agent-catalog?)]
  [package-runtime-candidate-keymaps
   (-> odra-package-runtime-candidate? (listof bundle:odra-language-keymap?))]
  [package-runtime-candidate-state
   (-> odra-package-runtime-candidate? symbol?)]
  [package-runtime-candidate-active-turns
   (-> odra-package-runtime-candidate? exact-nonnegative-integer?)]
  [discard-package-runtime-candidate!
   (-> odra-package-runtime-candidate? void?)]
  [make-package-runtime (-> odra-package-runtime?)]
  [package-runtime-catalog
   (-> odra-package-runtime? odra-command-catalog?)]
  [package-runtime-agent-catalog
   (-> odra-package-runtime? odra-agent-catalog?)]
  [package-runtime-keymaps
   (-> odra-package-runtime? (listof bundle:odra-language-keymap?))]
  [package-runtime-active-generation
   (-> odra-package-runtime? string? (or/c #f exact-positive-integer?))]
  [package-runtime-activate!
   (-> odra-package-runtime? odra-package-runtime-candidate?
       (or/c void? odra-package-runtime-failure?))]
  [package-runtime-deactivate!
   (-> odra-package-runtime? string? exact-positive-integer?
       exact-positive-integer?
       (or/c void? odra-package-runtime-failure?))]
  [package-runtime-call
   (-> odra-package-runtime? string? exact-positive-integer? string? any/c any/c)]
  [package-runtime-command-call
   (-> odra-package-runtime? string? any/c any/c)]
  [call-with-contained-package-command (-> (-> any/c) any/c)]
  [package-runtime-close! (-> odra-package-runtime? void?)]))

(define maximum-runtime-diagnostic-bytes 4096)
(define maximum-authority-provenance-bytes 4096)
(define package-compiled-file-paths (list (string->path "compiled")))
(define failure-codes
  '(authority content contribution denied evaluation limit manifest stale))
(define-runtime-module-path package-command-api-module "../command/api.rkt")
(define-runtime-module-path package-agent-api-module "../agent/api.rkt")
(define-runtime-module-path package-agent-definition-module
  "../agent/definition.rkt")
(define-runtime-module-path db-module db)
(define-runtime-module-path json-module json)
(define-runtime-module-path file-sha1-module file/sha1)
(define-runtime-module-path openssl-sha1-module openssl/sha1)
(define-runtime-module-path racket-module racket)
(define-runtime-module-path racket-base-module racket/base)
(define-runtime-module-path racket-contract-base-module racket/contract/base)
(define-runtime-module-path racket-date-module racket/date)
(define-runtime-module-path racket-file-module racket/file)
(define-runtime-module-path racket-format-module racket/format)
(define-runtime-module-path racket-list-module racket/list)
(define-runtime-module-path racket-path-module racket/path)
(define-runtime-module-path racket-port-module racket/port)
(define-runtime-module-path racket-pretty-module racket/pretty)
(define-runtime-module-path racket-provide-transform-module racket/provide-transform)
(define-runtime-module-path racket-require-transform-module racket/require-transform)
(define-runtime-module-path racket-runtime-path-module racket/runtime-path)
(define-runtime-module-path racket-string-module racket/string)
(define-runtime-module-path racket-splicing-module racket/splicing)
(define-runtime-module-path racket-struct-module racket/struct)
(define-runtime-module-path racket-match-module racket/match)
(define-runtime-module-path racket-public-undefined-module racket/undefined)
(define-runtime-module-path racket-undefined-module racket/unsafe/undefined)
(define-runtime-module-path racket-unsafe-ops-module racket/unsafe/ops)
(define-runtime-module-path ffi-unsafe-module ffi/unsafe)
(define-runtime-module-path
  syntax-function-header-module syntax/parse/lib/function-header)
(define-runtime-module-path setup-directories-module setup/dirs)
(define-runtime-module-path setup-collects-module setup/collects)
(define-runtime-module-path setup-main-collects-module setup/main-collects)
(define-runtime-module-path syntax-stx-module syntax/stx)
(define-runtime-module-path syntax-srcloc-module syntax/srcloc)
(define-runtime-module-path syntax-boundmap-module syntax/private/boundmap)
(define-runtime-module-path syntax-location-module syntax/location)
(define-runtime-module-path syntax-name-module syntax/name)
(define-runtime-module-path racket-struct-info-module racket/struct-info)
(define-runtime-module-path racket-syntax-module racket/syntax)
(define-runtime-module-path
  racket-match-expander-module racket/match/match-expander)
(define-runtime-module-path racket-private-generic-module racket/private/generic)
(define-runtime-module-path racket-mutability-module racket/mutability)
(define-runtime-module-path racket-base-reader-module (submod racket/base reader))
(define-runtime-module-path racket-runtime-config-module racket/runtime-config)
(define-runtime-module-path syntax-wrap-modbeg-module syntax/wrap-modbeg)
(define-runtime-module-path racket-stxparam-module racket/stxparam)
(define-runtime-module-path syntax-kerncase-module syntax/kerncase)
(define-runtime-module-path racket-norm-define-module racket/private/norm-define)
(define-runtime-module-path
  racket-immediate-default-module racket/private/immediate-default)
(define-runtime-module-path ffi-unsafe-os-thread-module ffi/unsafe/os-thread)
(define racket-base-language-read-syntax
  (dynamic-require racket-base-reader-module 'read-syntax))
(define-namespace-anchor package-runtime-anchor)
(define-runtime-path extension-source-root "..")
(define trusted-extension-source-root
  (simplify-path (path->complete-path extension-source-root)))
(define trusted-racket-root
  (simplify-path (path->complete-path (find-system-path 'collects-dir))))
(define trusted-racket-roots
  (let* ([installation-root
          (simplify-path (build-path trusted-racket-root 'up))]
         [packages-root
          (simplify-path (build-path installation-root "pkgs"))])
    (if (directory-exists? packages-root)
        (list trusted-racket-root packages-root)
        (list trusted-racket-root))))
(define trusted-compiled-roots
  (for/list ([root (in-list (current-compiled-file-roots))]
             #:when (path? root))
    (simplify-path (path->complete-path root))))
(define trusted-runtime-roots
  (cons (simplify-path (path->complete-path (find-system-path 'config-dir)))
        (append trusted-racket-roots
              (append trusted-compiled-roots
                      (filter values (map path-only trusted-compiled-roots))))))
(define trusted-addon-root
  (simplify-path (path->complete-path (find-system-path 'addon-dir))))
(define trusted-system-links
  (simplify-path
   (path->complete-path (build-path trusted-racket-root 'up "links.rktd"))))
(define (runtime-module-directory module)
  (define name
    (if (resolved-module-path? module)
        (resolved-module-path-name module)
        module))
  (and (path? name)
       (path-only (simplify-path (path->complete-path name)))))

(define trusted-api-directories
  (filter values
          (list (runtime-module-directory package-command-api-module)
                (runtime-module-directory package-agent-api-module))))

(define admitted-package-library-modules
  '(db json file/sha1 openssl/sha1 racket/contract/base racket/date racket/file
       racket/format racket/list racket/path racket/port racket/runtime-path
       racket/string))
(define admitted-package-library-module-paths
  (hash 'db db-module
        'json json-module
        'file/sha1 file-sha1-module
        'openssl/sha1 openssl-sha1-module
        'racket/contract/base racket-contract-base-module
        'racket/date racket-date-module
        'racket/file racket-file-module
        'racket/format racket-format-module
        'racket/list racket-list-module
        'racket/path racket-path-module
        'racket/port racket-port-module
        'racket/runtime-path racket-runtime-path-module
        'racket/string racket-string-module))
(define admitted-package-library-prefixes
  '("db/" "ffi/" "file/" "openssl/" "racket/contract/" "racket/place/"
          "racket/private/" "syntax/"))

(define (admitted-package-library-module? module-path)
  (and (symbol? module-path)
       (for/or ([prefix (in-list admitted-package-library-prefixes)])
         (string-prefix? (symbol->string module-path) prefix))))

(define (path-below-root? root candidate)
  (define root-parts (explode-path root))
  (define candidate-parts (explode-path candidate))
  (and (<= (length root-parts) (length candidate-parts))
       (equal? root-parts (take candidate-parts (length root-parts)))))

(define (trusted-runtime-path? candidate)
  (for/or ([root (in-list trusted-runtime-roots)])
    (path-below-root? root candidate)))

(define (trusted-addon-access? candidate modes)
  (and (path-below-root? trusted-addon-root candidate)
       (or (for/and ([mode (in-list modes)]) (eq? mode 'exists))
           (and (let ([name (file-name-from-path candidate)])
                  (and name
                       (member (path->string name)
                               '("config.rktd" "links.rktd"))))
                (for/and ([mode (in-list modes)])
                  (memq mode '(exists read)))))))

(define (module-name-source-path name)
  (cond
    [(path? name) name]
    [(and (pair? name) (path? (car name))) (car name)]
    [else #f]))

(define admitted-package-library-roots
  (for/list ([module (in-list '(db file/sha1 openssl/sha1 racket/contract/base))]
             #:do [(define resolved
                      ((current-module-name-resolver) module #f #f #f))
                    (define source
                      (and (resolved-module-path? resolved)
                           (module-name-source-path
                            (resolved-module-path-name resolved))))]
             #:when source)
    (path-only (simplify-path (path->complete-path source)))))

(define (admitted-package-library-path? module-path)
  (and (path? module-path)
       (let ([candidate (simplify-path (path->complete-path module-path))])
         (for/or ([root (in-list admitted-package-library-roots)])
           (path-below-root? root candidate)))))

(define (trusted-relative-source? relative-to)
  (and (resolved-module-path? relative-to)
       (let ([name (resolved-module-path-name relative-to)])
         (or (and (symbol? name)
                  (string-prefix? (symbol->string name) "#%embedded:"))
             (let ([source (module-name-source-path name)])
               (and source
                  (let ([path (simplify-path (path->complete-path source))])
                    (or (trusted-runtime-path? path)
                        (path-below-root? trusted-extension-source-root path)))))))))

(define (unlocated-runtime-module? relative-to)
  (and (resolved-module-path? relative-to)
       (let ([name (resolved-module-path-name relative-to)])
         (not (module-name-source-path name)))))

;; Expansion-time dependencies can arrive without a relative module source.
;; Package-owned modules are validated before expansion reaches this resolver.
(define (runtime-internal-import? relative-to)
  (or (not relative-to)
      (trusted-relative-source? relative-to)))

(define (bounded-text? value maximum #:empty? [empty? #f])
  (and (string? value)
       (or empty? (positive? (string-length value)))
       (not (string-contains? value (string #\nul)))
       (<= (bytes-length (string->bytes/utf-8 value)) maximum)))

(define (identity? value)
  (and (bounded-text? value 128)
       (regexp-match? #px"^[a-z0-9]+(?:[.-][a-z0-9]+)*$" value)))

(define (version? value)
  (and (bounded-text? value 128)
       (regexp-match?
        #px"^(?:0|[1-9][0-9]*)[.](?:0|[1-9][0-9]*)[.](?:0|[1-9][0-9]*)(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?$"
        value)))

(define (symbol<? left right)
  (string<? (symbol->string left) (symbol->string right)))

(struct odra-package-authority-grant
  (package-id version generation authorities provenance)
  #:transparent
  #:guard
  (lambda (package-id version generation authorities provenance _)
    (unless (and (identity? package-id) (version? version)
                 (exact-positive-integer? generation)
                 (package-authority-set? authorities)
                 (bounded-text? provenance maximum-authority-provenance-bytes))
      (raise-arguments-error 'odra-package-authority-grant
                             "invalid explicit package authority grant"))
    (values (string->immutable-string package-id)
            (string->immutable-string version) generation authorities
            (string->immutable-string provenance))))

(struct odra-package-runtime-limits
  (preparation-deadline-milliseconds preparation-memory-bytes command-limits)
  #:transparent
  #:guard
  (lambda (preparation-deadline-milliseconds preparation-memory-bytes
           command-limits _)
    (unless (and (exact-positive-integer? preparation-deadline-milliseconds)
                 (<= preparation-deadline-milliseconds 10000)
                 (exact-positive-integer? preparation-memory-bytes)
                 (<= preparation-memory-bytes (* 512 1024 1024))
                 (personal-command-limits? command-limits))
      (raise-arguments-error 'odra-package-runtime-limits
                             "invalid bounded package runtime limits"))
    (values preparation-deadline-milliseconds preparation-memory-bytes
            command-limits)))

(define default-package-runtime-limits
  (odra-package-runtime-limits
   7500 (* 128 1024 1024)
   (make-personal-command-limits #:deadline-milliseconds 10000)))

(struct odra-package-runtime-failure (code package-id version detail)
  #:transparent
  #:guard
  (lambda (code package-id version detail _)
    (unless (and (memq code failure-codes) (identity? package-id)
                 (version? version)
                 (bounded-text? detail maximum-runtime-diagnostic-bytes))
      (raise-arguments-error 'odra-package-runtime-failure
                             "invalid redacted package runtime failure"))
    (values code (string->immutable-string package-id)
            (string->immutable-string version)
            (string->immutable-string detail))))

(struct package-runtime-control
  (custodian [admitted? #:mutable] [state #:mutable] [turns #:mutable]
             [retire #:mutable] lock))

(struct odra-package-runtime-candidate
  (package-id version contribution-generation grant manifest limits control
              namespace module-root [definitions #:mutable] [command-names #:mutable]
              [catalog #:mutable] [agent-source #:mutable]
              [agent-catalog #:mutable] [keymaps #:mutable]
              [owner #:mutable] [closed? #:mutable]))

(struct odra-package-runtime
  (active latest-grants latest-contributions [catalog #:mutable]
          [agent-catalog #:mutable] [keymaps #:mutable]
          [closed? #:mutable]))

(define (failure code package-id version detail)
  (odra-package-runtime-failure code package-id version detail))

(define (manifest-entrypoint-artifact manifest)
  (define entrypoint (odra-package-manifest-entrypoint manifest))
  (and entrypoint
       (for/first
           ([artifact (in-list (odra-package-manifest-artifacts manifest))]
            #:when
            (string=? (odra-package-artifact-path artifact)
                      (odra-package-entrypoint-module-path entrypoint)))
         artifact)))

(define (file-digest path)
  (call-with-input-file path
    (lambda (input) (bytes->hex-string (sha256-bytes input)))
    #:mode 'binary))

(define (entrypoint-path root artifact)
  (package-content-path root (odra-package-artifact-digest artifact)))

(define (verified-entrypoint? path artifact installed)
  (and (member (odra-package-artifact-digest artifact)
               (odra-installed-package-artifacts installed) string=?)
       (file-exists? path)
       (not (link-exists? path))
       (= (file-size path) (odra-package-artifact-size artifact))
       (string=? (file-digest path) (odra-package-artifact-digest artifact))))

(define (package-module-artifacts manifest)
  (filter
   (lambda (artifact)
     (eq? (odra-package-artifact-kind artifact) 'racket-module))
   (odra-package-manifest-artifacts manifest)))

(define (verified-module-artifact? root artifact installed)
  (define path
    (package-content-path root (odra-package-artifact-digest artifact)))
  (and (member (odra-package-artifact-digest artifact)
               (odra-installed-package-artifacts installed) string=?)
       (file-exists? path)
       (not (link-exists? path))
       (= (file-size path) (odra-package-artifact-size artifact))
       (string=? (file-digest path) (odra-package-artifact-digest artifact))))

;; materialize-package-modules reconstructs only the verified declared module
;; tree. The content-addressed installation remains canonical.
(define (materialize-package-modules root manifest installed)
  (define artifacts (package-module-artifacts manifest))
  (unless (and (pair? artifacts)
               (andmap
                (lambda (artifact)
                  (verified-module-artifact? root artifact installed))
                artifacts))
    (raise-arguments-error
     'package-runtime "installed package module content is absent or invalid"))
  (define stage (make-temporary-file "odra-package-modules-~a" 'directory))
  (with-handlers ([exn?
                   (lambda (observed)
                     (delete-directory/files stage)
                     (raise observed))])
    (for ([artifact (in-list artifacts)])
      (define source
        (package-content-path root (odra-package-artifact-digest artifact)))
      (define destination
        (build-path stage (odra-package-artifact-path artifact)))
      (make-parent-directory* destination)
      (copy-file source destination)
      (file-or-directory-permissions destination #o400))
    stage))

(define (grant-rejection installed manifest grant)
  (cond
    [(or (not (string=? (odra-installed-package-id installed)
                        (odra-package-authority-grant-package-id grant)))
         (not (string=? (odra-installed-package-version installed)
                        (odra-package-authority-grant-version grant))))
     "authority grant names another package release"]
    [(not (member 'racket-extension
                  (odra-package-authority-grant-authorities grant)))
     "racket-extension authority was not granted"]
    [(for/or ([authority
               (in-list (odra-package-authority-grant-authorities grant))])
       (not (member authority
                    (odra-package-manifest-authorities manifest))))
     "authority grant exceeds the confirmed manifest"]
    [else #f]))

(define (manifest-rejection installed manifest)
  (cond
    [(not (and (string=? (odra-installed-package-id installed)
                         (odra-package-manifest-package-id manifest))
               (string=? (odra-installed-package-version installed)
                         (odra-package-manifest-version manifest))))
     "manifest identity differs from the installed package"]
    [(not (string=? (odra-installed-package-manifest installed)
                    (package-manifest-digest manifest)))
     "manifest digest differs from the installed package"]
    [(not (eq? (odra-installed-package-lifecycle installed)
               'installed-disabled))
     "package is not installed and disabled"]
    [(not (odra-package-manifest-entrypoint manifest))
     "package has no restricted Racket entrypoint"]
    [(for/or ([contribution
               (in-list (odra-package-manifest-contributions manifest))])
       (not (memq (odra-package-contribution-facet contribution)
                  '(agent agent-capability command keymap))))
     "package runtime does not accept one or more declared contribution facets"]
    [else #f]))

(define (make-denying-security-guard [readable #f]
                                     #:project-root [project-root #f]
                                     #:project-write? [project-write? #f]
                                     #:resources [resources '()]
                                     #:data-root [data-root #f])
  (define admitted (and readable (simplify-path (path->complete-path readable))))
  (define admitted-directory (and admitted (path-only admitted)))
  (define project
    (and project-root (simplify-path (path->complete-path project-root))))
  (define data
    (and data-root (simplify-path (path->complete-path data-root))))
  (define parent-guard (current-security-guard))
  ;; Resolve each component, including directory links, before admitting a
  ;; configured resource. Resolving only the last component misses escapes.
  (define (physical-path path)
    (parameterize ([current-security-guard parent-guard])
      (for/fold ([prefix #f]) ([part (in-list (explode-path (simplify-path path #f)))])
        (resolve-path (if prefix (build-path prefix part) part)))))
  (define admitted-resources
    (for/list ([resource (in-list resources)])
      (cons resource (physical-path (string->path (package-resource-root resource))))))
  (define (root-access? root candidate modes allowed)
    (and root candidate
         (or (path-below-root? root candidate)
             (and (path-below-root? candidate root)
                  (equal? modes '(exists))))
         (for/and ([mode (in-list modes)]) (memq mode allowed))))
  (make-security-guard
   (current-security-guard)
   (lambda (who path modes)
     (define candidate
       (and path
            (with-handlers ([exn:fail? (lambda (_) #f)])
              (simplify-path (path->complete-path path)))))
     (unless (or (and admitted candidate (equal? admitted candidate)
                      (for/and ([mode (in-list modes)])
                        (memq mode '(exists read))))
                 (and admitted-directory candidate
                      (equal? admitted-directory candidate)
                      (equal? modes '(exists)))
                 (and admitted candidate
                      (path-below-root? admitted candidate)
                      (for/and ([mode (in-list modes)])
                        (memq mode '(exists read))))
                 (and admitted candidate
                      (path-below-root? candidate admitted)
                      (equal? modes '(exists)))
                 (root-access? project candidate modes
                               (if project-write?
                                   '(exists read write delete)
                                   '(exists read)))
                 (root-access? data candidate modes
                               '(exists read write delete))
                 (for/or ([entry (in-list admitted-resources)])
                   (define resource (car entry))
                   (define allowed
                     (if (and project-write?
                              (eq? (package-resource-access resource) 'read-write))
                         '(exists read write delete)
                         '(exists read)))
                   (and (root-access? (string->path (package-resource-root resource))
                                      candidate modes allowed)
                        (root-access? (cdr entry) (physical-path candidate) modes allowed)))
                 (and candidate
                      (for/or ([directory (in-list trusted-api-directories)])
                        (equal? directory candidate))
                      (equal? modes '(exists)))
                 (and candidate
                      (path-below-root? trusted-extension-source-root candidate)
                      (equal? modes '(exists)))
                 (and candidate (trusted-runtime-path? candidate)
                      (for/and ([mode (in-list modes)])
                        (memq mode '(exists read))))
                 (and candidate (trusted-addon-access? candidate modes))
                 (and candidate (equal? candidate trusted-system-links)
                      (for/and ([mode (in-list modes)])
                        (memq mode '(exists read))))
                 (and candidate
                      (let ([name (file-name-from-path candidate)])
                        (and name
                             (equal? (path->string name) "system.rktd")))
                      (equal? modes '(exists)))
                 (and (not path) (equal? modes '(exists))))
       (error who "package runtime file access denied")))
   (lambda (who _host _port _mode)
     (error who "package runtime network access denied"))
   (lambda (who _source _target)
     (error who "package runtime link access denied"))))

(define (run-package-graphviz executable input output timeout-milliseconds)
  (define diagnostics
    (make-temporary-file "graphviz-diagnostics-~a.log" #f (path-only output)))
  (with-handlers
      ([exn:fail?
        (lambda (_)
          (when (file-exists? diagnostics) (delete-file diagnostics))
          (when (file-exists? output) (delete-file output))
          (command-tool-result 'failed #f "Graphviz execution failed."))])
    (when (file-exists? output) (delete-file output))
    (dynamic-wind
      void
      (lambda ()
        (call-with-output-file diagnostics
          (lambda (sink)
            (define-values (process _stdout stdin _stderr)
              (subprocess sink #f sink executable
                          "-Tsvg" (path->string input)
                          "-o" (path->string output)))
            (close-output-port stdin)
            (define completed
              (sync/timeout (/ timeout-milliseconds 1000.0) process))
            (cond
              [(not completed)
               (subprocess-kill process #t)
               (subprocess-wait process)
               (when (file-exists? output) (delete-file output))
               (command-tool-result
                'timeout #f "Graphviz execution timed out.")]
              [else
               (define status (subprocess-status process))
               (cond
                 [(and (zero? status)
                       (file-exists? output)
                       (positive? (file-size output))
                       (<= (file-size output) (* 64 1024 1024)))
                  (command-tool-result 'success status "")]
                 [else
                  (when (file-exists? output) (delete-file output))
                  (command-tool-result
                   'failed status
                   "Graphviz produced no admitted output.")])]))
          #:exists 'truncate))
      (lambda ()
        (when (file-exists? diagnostics) (delete-file diagnostics))))))

(define (package-tool-runner data-root external-process? graphviz-executable
                             host-security-guard)
  (lambda (tool input output timeout-milliseconds)
    (cond
      [(not external-process?)
       (command-tool-result
        'denied #f "External process authority is unavailable.")]
      [(not (eq? tool 'graphviz-dot))
       (command-tool-result 'denied #f "The requested external tool is not admitted.")]
      [(not (and data-root
                 (path-below-root? data-root input)
                 (path-below-root? data-root output)))
       (command-tool-result 'denied #f "Renderer paths are outside package storage.")]
      [else
       (parameterize ([current-security-guard host-security-guard])
         (if graphviz-executable
             (run-package-graphviz
              graphviz-executable input output timeout-milliseconds)
             (command-tool-result
              'unavailable #f "Graphviz dot is unavailable.")))])))

(define (module-import-closure roots)
  (define admitted (make-hash))
  (let loop ([pending roots])
    (cond
      [(null? pending) admitted]
      [else
       (define module (car pending))
       (cond
         [(hash-ref admitted module #f) (loop (cdr pending))]
         [else
          (hash-set! admitted module #t)
          (define imports
            (with-handlers ([exn:fail? (lambda (_) '())])
              (for*/list ([phase-imports (in-list (module->imports module))]
                          [mpi (in-list (cdr phase-imports))])
                (module-path-index-resolve mpi))))
          (loop (append imports (cdr pending)))])])))

(define (admitted-embedded-module admitted-modules module-path)
  (and (symbol? module-path)
       (let ([resolved
              (make-resolved-module-path
               (string->symbol
                (string-append
                 "#%embedded:" (symbol->string module-path) ":")))])
         (and (hash-ref admitted-modules resolved #f) resolved))))

(define (package-module-resolver
         default-resolver entrypoint module-root admitted-modules
         embedded-runtime?)
  (case-lambda
    [(resolved-module-path namespace)
     (default-resolver resolved-module-path namespace)]
    [(module-path relative-to syntax load?)
     (cond
       [(eq? module-path 'odra/commands) package-command-api-module]
       [(eq? module-path 'odra/agents) package-agent-api-module]
       [(eq? module-path 'racket/base) racket-base-module]
       [(eq? module-path 'racket/runtime-config) racket-runtime-config-module]
       [(eq? module-path 'racket/require-transform)
        (if embedded-runtime?
            racket-require-transform-module
            (default-resolver module-path relative-to syntax load?))]
       [(eq? module-path 'racket/provide-transform)
        (if embedded-runtime?
            racket-provide-transform-module
            (default-resolver module-path relative-to syntax load?))]
       [(eq? module-path 'racket/undefined)
        (if embedded-runtime?
            racket-public-undefined-module
            (default-resolver module-path relative-to syntax load?))]
       [(eq? module-path 'syntax/wrap-modbeg) syntax-wrap-modbeg-module]
       [(and (runtime-internal-import? relative-to)
             embedded-runtime?
             (admitted-embedded-module admitted-modules module-path))
        => (lambda (resolved) resolved)]
       [(memq module-path admitted-package-library-modules)
        (if embedded-runtime?
            (hash-ref admitted-package-library-module-paths module-path)
            (default-resolver module-path relative-to syntax load?))]
       [(and (runtime-internal-import? relative-to)
             (admitted-package-library-module? module-path))
        (default-resolver module-path relative-to syntax load?)]
       [(and (runtime-internal-import? relative-to)
             (admitted-package-library-path? module-path))
        (default-resolver module-path relative-to syntax load?)]
       [(equal? module-path '(submod racket/base reader))
        racket-base-reader-module]
       [(and (runtime-internal-import? relative-to)
             (with-handlers ([exn:fail? (lambda (_) #f)])
               (hash-ref admitted-modules
                         (default-resolver module-path relative-to syntax #f)
                         #f)))
        (default-resolver module-path relative-to syntax load?)]
       [(or (equal? module-path '(submod "." configure-expand))
            (equal? module-path '(submod "." configure-runtime)))
        (default-resolver module-path relative-to syntax load?)]
       [(and (list? module-path)
             (= (length module-path) 2)
             (eq? (car module-path) 'quote)
             (symbol? (cadr module-path))
             (string-prefix? (symbol->string (cadr module-path)) "#%"))
        (define resolved
          (default-resolver module-path relative-to syntax load?))
        (if (module-declared? resolved)
            resolved
            (raise-arguments-error
             'package-runtime "module is outside the package allowlist"
             "module" module-path))]
       [(or (trusted-relative-source? relative-to)
            (and (unlocated-runtime-module? relative-to)
                 (with-handlers ([exn:fail? (lambda (_) #f)])
                   (define resolved
                     (default-resolver module-path relative-to syntax #f))
                   (define name
                     (and (resolved-module-path? resolved)
                          (resolved-module-path-name resolved)))
                   (define source (and name (module-name-source-path name)))
                   (and source
                        (trusted-runtime-path?
                         (simplify-path (path->complete-path source))))))
            (and relative-to
                 (with-handlers ([exn:fail? (lambda (_) #f)])
                   (define resolved
                     (default-resolver module-path relative-to syntax #f))
                   (define name
                     (and (resolved-module-path? resolved)
                          (resolved-module-path-name resolved)))
                   (and (path? name)
                        (path-below-root?
                         module-root
                         (simplify-path (path->complete-path name)))))))
        (default-resolver module-path relative-to syntax load?)]
       [(and (path? module-path)
             (path-below-root?
              module-root
              (simplify-path (path->complete-path module-path))))
        (default-resolver module-path relative-to syntax load?)]
       [else
        (raise-arguments-error
         'package-runtime "module is outside the package allowlist"
         "module" module-path
         "relative-to" relative-to)])]))

(define (string-starts-at? text fragment index)
  (define end (+ index (string-length fragment)))
  (and (<= end (string-length text))
       (string=? fragment (substring text index end))))

(define (skip-block-comment text start)
  (let loop ([index start] [depth 1])
    (cond
      [(>= index (string-length text)) #f]
      [(string-starts-at? text "#|" index)
       (loop (+ index 2) (add1 depth))]
      [(string-starts-at? text "|#" index)
       (if (= depth 1)
           (+ index 2)
           (loop (+ index 2) (sub1 depth)))]
      [else (loop (add1 index) depth)])))

(define (skip-package-source-layout text)
  (let loop ([index 0])
    (cond
      [(>= index (string-length text)) index]
      [(char-whitespace? (string-ref text index)) (loop (add1 index))]
      [(char=? (string-ref text index) #\;)
       (define newline
         (let skip-line ([cursor index])
           (cond
             [(>= cursor (string-length text)) cursor]
             [(char=? (string-ref text cursor) #\newline) cursor]
             [else (skip-line (add1 cursor))])))
       (loop newline)]
      [(string-starts-at? text "#|" index)
       (define after-comment (skip-block-comment text (+ index 2)))
       (and after-comment (loop after-comment))]
      [else index])))

(define (package-language-body-start text)
  (define start (skip-package-source-layout text))
  (and
   start
   (string-starts-at? text "#lang racket/base" start)
   (let loop ([index (+ start (string-length "#lang racket/base"))])
     (cond
       [(>= index (string-length text)) index]
       [(memq (string-ref text index) '(#\space #\tab))
        (loop (add1 index))]
       [(char=? (string-ref text index) #\;)
        (let skip-line ([cursor (add1 index)])
          (cond
            [(>= cursor (string-length text)) cursor]
            [(char=? (string-ref text cursor) #\newline) (add1 cursor)]
            [(char=? (string-ref text cursor) #\return)
             (if (and (< (add1 cursor) (string-length text))
                      (char=? (string-ref text (add1 cursor)) #\newline))
                 (+ cursor 2)
                 (add1 cursor))]
            [else (skip-line (add1 cursor))]))]
       [(char=? (string-ref text index) #\newline) (add1 index)]
       [(char=? (string-ref text index) #\return)
        (if (and (< (add1 index) (string-length text))
                 (char=? (string-ref text (add1 index)) #\newline))
            (+ index 2)
            (add1 index))]
       [else #f]))))

(define (package-module-syntax path)
  (define text (file->string path))
  (define body-start (package-language-body-start text))
  (unless body-start
    (raise-arguments-error
     'package-runtime "package source has a denied language preamble"))
  (define input (open-input-string text path))
  (port-count-lines! input)
  (read-string body-start input)
  (define-values (line column position) (port-next-location input))
  (parameterize ([current-readtable #f]
                 [read-accept-lang #f]
                 [read-accept-reader #f])
    (racket-base-language-read-syntax
     path input (datum->syntax #f 'racket/base)
     line column position)))

(define (entrypoint-requires datum)
  (define requires '())
  (define (walk value)
    (when (pair? value)
      (cond
        [(memq (car value) '(quote quasiquote syntax quasisyntax)) (void)]
        [(eq? (car value) 'require)
         (set! requires (append (cdr value) requires))]
        [else
         (for ([part (in-list value)]) (walk part))])))
  (walk datum)
  (reverse requires))

(define (declared-relative-module-path? value)
  (and (string? value)
       (regexp-match? #px"^(?![./]*[.][./])[^/].*[.]rkt$" value)))

(define (admitted-relative-package-require? required module-path module-root)
  (and (string? required)
       (regexp-match? #px"[.]rkt$" required)
       (with-handlers ([exn:fail? (lambda (_) #f)])
         (define resolved
           (simplify-path (build-path (path-only module-path) required)))
         (and (path-below-root? module-root resolved)
              (file-exists? resolved)))))

(define (admitted-package-require? required module-path module-root)
  (cond
    [(symbol? required)
     (or (memq required '(odra/commands odra/agents))
         (memq required admitted-package-library-modules))]
    [(string? required)
     (admitted-relative-package-require? required module-path module-root)]
    [(and (list? required) (pair? required))
     (case (car required)
       [(only-in except-in rename-in)
        (and (pair? (cdr required))
             (admitted-package-require?
              (cadr required) module-path module-root))]
       [(prefix-in)
        (and (>= (length required) 3)
             (admitted-package-require?
              (caddr required) module-path module-root))]
       [(combine-in for-syntax for-template for-label)
        (andmap
         (lambda (nested)
           (admitted-package-require? nested module-path module-root))
         (cdr required))]
       [(for-meta)
        (and (>= (length required) 3)
             (andmap
              (lambda (nested)
                (admitted-package-require? nested module-path module-root))
              (cddr required)))]
       [(submod)
        (and (>= (length required) 3)
             (admitted-package-require?
              (cadr required) module-path module-root))]
       [else #f])]
    [else #f]))

(define forbidden-entrypoint-identifiers
  '(compile compile-syntax current-namespace dynamic-require eval expand
            expand-syntax load load/use-compiled make-base-empty-namespace
            make-base-namespace make-empty-namespace module->namespace
            namespace-attach-module namespace-require namespace-require/constant
            namespace-require/copy namespace-require/expansion-time
            namespace-set-variable-value! namespace-variable-value
            variable-reference->namespace))

(define (package-forbidden-identifier datum)
  (define found #f)
  (define (walk value)
    (when (and (not found) (pair? value))
      (cond
        [(memq (car value) '(quote syntax)) (void)]
        [else
         (for ([part (in-list value)])
           (cond
             [(and (symbol? part)
                   (memq part forbidden-entrypoint-identifiers))
              (set! found part)]
             [else (walk part)]))])))
  (walk datum)
  found)

(define (validate-entrypoint-syntax source)
  (define datum (syntax->datum source))
  (define requires (entrypoint-requires datum))
  (unless (and (list? datum)
               (>= (length datum) 4)
               (eq? (car datum) 'module)
               (eq? (caddr datum) 'racket/base)
               (for/or ([required (in-list requires)])
                 (memq required '(odra/commands odra/agents)))
               (andmap
                (lambda (required)
                  (or (memq required '(odra/commands odra/agents))
                      (declared-relative-module-path? required)))
                requires))
    (raise-arguments-error
     'package-runtime
     "entrypoint must use racket/base and require only public Odra APIs or declared relative modules"))
  (define forbidden (package-forbidden-identifier datum))
  (when forbidden
    (raise-arguments-error
     'package-runtime
     "entrypoint uses a forbidden reflective binding"
     "binding" forbidden)))

(define (validate-package-module-syntax source module-path module-root)
  (define datum (syntax->datum source))
  (unless (and (list? datum)
               (>= (length datum) 4)
               (eq? (car datum) 'module)
               (eq? (caddr datum) 'racket/base))
    (raise-arguments-error
     'package-runtime "package modules must use racket/base"))
  (unless
      (andmap
       (lambda (required)
         (admitted-package-require? required module-path module-root))
       (entrypoint-requires datum))
    (raise-arguments-error
     'package-runtime
     "package modules may require only public Odra APIs, safe libraries, or declared relative modules"))
  (define forbidden (package-forbidden-identifier datum))
  (when forbidden
    (raise-arguments-error
     'package-runtime
     "package module uses a forbidden reflective binding"
     "binding" forbidden)))

(define (empty-environment) (make-environment-variables))

(define (call-with-package-isolation owner guard thunk)
  (parameterize ([current-custodian owner]
                 [current-security-guard guard]
                 [current-environment-variables (empty-environment)]
                 [current-input-port (open-input-bytes #"")]
                 [current-output-port (open-output-nowhere)]
                 [current-error-port (open-output-nowhere)])
    (thunk)))

(define current-package-command-contained? (make-parameter #f))

;; call-with-contained-package-command reuses the editor command turn's limits.
(define (call-with-contained-package-command command)
  (parameterize ([current-package-command-contained? #t])
    (command)))

(define (evaluate-entrypoint owner path module-root binding limits)
  (define owner-namespace (current-namespace))
  (define default-resolver (current-module-name-resolver))
  (define embedded-runtime?
    (let ([name (resolved-module-path-name package-command-api-module)])
      (and (symbol? name)
           (string-prefix? (symbol->string name) "#%embedded:"))))
  (dynamic-require package-command-api-module #f)
  (dynamic-require package-agent-api-module #f)
  (dynamic-require package-agent-definition-module #f)
  (dynamic-require racket-module #f)
  (dynamic-require racket-base-module #f)
  (dynamic-require racket-port-module #f)
  (dynamic-require racket-pretty-module #f)
  (dynamic-require racket-match-module #f)
  (dynamic-require racket-splicing-module #f)
  (dynamic-require racket-struct-module #f)
  (dynamic-require racket-public-undefined-module #f)
  (dynamic-require racket-undefined-module #f)
  (dynamic-require racket-unsafe-ops-module #f)
  (dynamic-require ffi-unsafe-module #f)
  (dynamic-require syntax-function-header-module #f)
  (dynamic-require setup-directories-module #f)
  (dynamic-require setup-collects-module #f)
  (dynamic-require setup-main-collects-module #f)
  (dynamic-require syntax-stx-module #f)
  (dynamic-require syntax-srcloc-module #f)
  (dynamic-require syntax-boundmap-module #f)
  (dynamic-require syntax-location-module #f)
  (dynamic-require syntax-name-module #f)
  (dynamic-require racket-struct-info-module #f)
  (dynamic-require racket-syntax-module #f)
  (dynamic-require racket-match-expander-module #f)
  (dynamic-require racket-private-generic-module #f)
  (dynamic-require racket-mutability-module #f)
  (dynamic-require racket-base-reader-module #f)
  (dynamic-require racket-provide-transform-module #f)
  (dynamic-require racket-require-transform-module #f)
  (dynamic-require racket-runtime-config-module #f)
  (dynamic-require syntax-wrap-modbeg-module #f)
  (dynamic-require racket-stxparam-module #f)
  (dynamic-require syntax-kerncase-module #f)
  (dynamic-require racket-norm-define-module #f)
  (dynamic-require racket-immediate-default-module #f)
  (dynamic-require ffi-unsafe-os-thread-module #f)
  (for ([module (in-hash-values admitted-package-library-module-paths)])
    (dynamic-require module #f))
  (dynamic-require-for-syntax package-command-api-module #f)
  (dynamic-require-for-syntax package-agent-api-module #f)
  (dynamic-require-for-syntax package-agent-definition-module #f)
  (dynamic-require-for-syntax racket-base-module #f)
  (define admitted-modules
    (module-import-closure
     (append
      (list package-command-api-module package-agent-api-module
            package-agent-definition-module
            racket-module racket-base-module racket-port-module
            racket-pretty-module
            racket-match-module racket-splicing-module racket-struct-module
            racket-public-undefined-module racket-undefined-module
            racket-unsafe-ops-module ffi-unsafe-module
            syntax-function-header-module
            setup-directories-module
            setup-collects-module
            setup-main-collects-module
            syntax-stx-module syntax-srcloc-module syntax-boundmap-module
            syntax-location-module
            syntax-name-module
            racket-struct-info-module
            racket-syntax-module
            racket-match-expander-module
            racket-private-generic-module
            racket-mutability-module
            racket-base-reader-module racket-provide-transform-module
            racket-require-transform-module
            racket-runtime-config-module
            syntax-wrap-modbeg-module racket-stxparam-module
            syntax-kerncase-module racket-norm-define-module
            racket-immediate-default-module
            ffi-unsafe-os-thread-module)
      (hash-values admitted-package-library-module-paths))))
  (define namespace
    (parameterize ([current-custodian owner])
      (if embedded-runtime?
          (namespace-anchor->empty-namespace package-runtime-anchor)
          (make-base-namespace))))
  (when embedded-runtime?
    (parameterize ([current-namespace namespace])
      (namespace-require racket-base-module)))
  (unless embedded-runtime?
    (namespace-attach-module
     owner-namespace package-command-api-module namespace)
    (namespace-attach-module
     owner-namespace package-agent-api-module namespace)
    (namespace-attach-module
     owner-namespace package-agent-definition-module namespace)
    (namespace-attach-module
     owner-namespace racket-base-reader-module namespace)
    (namespace-attach-module
     owner-namespace racket-runtime-config-module namespace)
    (namespace-attach-module
     owner-namespace syntax-wrap-modbeg-module namespace))
  (define runtime-resolver
    (package-module-resolver
     default-resolver path module-root admitted-modules embedded-runtime?))
  (define result
    (parameterize ([current-load-relative-directory (path-only path)])
      (call-with-limits
       (/ (odra-package-runtime-limits-preparation-deadline-milliseconds limits)
          1000.0)
       (max 1
            (quotient
             (odra-package-runtime-limits-preparation-memory-bytes limits)
             (* 1024 1024)))
       (lambda ()
       (define guard (make-denying-security-guard module-root))
       (call-with-package-isolation
        owner guard
        (lambda ()
          (parameterize
              ([current-namespace namespace]
               [current-load-relative-directory (path-only path)]
               [current-library-collection-paths trusted-racket-roots]
               [use-compiled-file-paths '()]
               [current-module-name-resolver runtime-resolver])
            (define source (package-module-syntax path))
            (validate-entrypoint-syntax source)
            (for ([module-path (in-list (find-files file-exists? module-root))]
                  #:when
                  (and
                   (regexp-match? #px"[.]rkt$" (path->string module-path))
                   (not (equal? (simplify-path module-path)
                                (simplify-path path)))))
              (validate-package-module-syntax
               (package-module-syntax module-path) module-path module-root))
            (dynamic-require path binding))))))))
  (values namespace result runtime-resolver))

(define (semantic-set=? left right)
  (equal? (sort left symbol<?) (sort right symbol<?)))

(define (declared-contribution manifest facet identity)
  (for/first
      ([contribution (in-list (odra-package-manifest-contributions manifest))]
       #:when
       (and (eq? (odra-package-contribution-facet contribution) facet)
            (string=? identity (odra-package-contribution-id contribution))))
    contribution))

(define (identity-strings->symbols identities)
  (map string->symbol identities))

(define (definition-facet definition)
  (cond
    [(command? definition) 'command]
    [(agent? definition) 'agent]
    [(agent-capability? definition) 'agent-capability]
    [(bundle:odra-language-keymap? definition) 'keymap]
    [else #f]))

(define (definition-identity definition)
  (cond
    [(command? definition) (odra-command-definition-name definition)]
    [(agent? definition) (odra-agent-definition-identity definition)]
    [(agent-capability? definition)
     (odra-agent-capability-definition-identity definition)]
    [(bundle:odra-language-keymap? definition)
     (symbol->string (bundle:odra-language-keymap-id definition))]))

(define (definition-requirements definition)
  (cond
    [(command? definition) (odra-command-definition-requirements definition)]
    [(agent? definition)
     (identity-strings->symbols
      (odra-agent-definition-provider-requirements definition))]
    [(agent-capability? definition)
     (identity-strings->symbols
      (odra-agent-capability-definition-required-authorities definition))]
    [(bundle:odra-language-keymap? definition)
     (bundle:odra-language-keymap-languages definition)]))

(define (definition-effects definition)
  (cond
    [(command? definition) (odra-command-definition-effects definition)]
    [(agent? definition)
     (identity-strings->symbols
      (odra-agent-definition-requested-capabilities definition))]
    [(agent-capability? definition)
     (odra-agent-capability-definition-effects definition)]
    [(bundle:odra-language-keymap? definition) '()]))

(define (definitions-rejection manifest definitions)
  (cond
    [(not (and (list? definitions)
               (andmap definition-facet definitions)))
     "entrypoint export is not a list of public Odra contribution values"]
    [(not (= (length definitions)
             (length (odra-package-manifest-contributions manifest))))
     "entrypoint contribution count differs from the manifest"]
    [else
     (for/first ([definition (in-list definitions)])
       (define facet (definition-facet definition))
       (define declared
         (declared-contribution manifest facet (definition-identity definition)))
       (and
        (or (not declared)
            (not
             (semantic-set=?
              (definition-requirements definition)
              (odra-package-contribution-requirements declared)))
            (not
             (semantic-set=?
              (definition-effects definition)
              (odra-package-contribution-effects declared))))
        "entrypoint contribution differs from the manifest"))]))

(define (call-with-runtime-turn control action)
  (call-with-semaphore
   (package-runtime-control-lock control)
   (lambda ()
     (unless (package-runtime-control-admitted? control)
       (raise-arguments-error
        'package-runtime-call "package contribution generation is not active"))
     (set-package-runtime-control-turns!
      control (add1 (package-runtime-control-turns control)))))
  (dynamic-wind
    void
    action
    (lambda ()
      (define retire
        (call-with-semaphore
         (package-runtime-control-lock control)
         (lambda ()
           (set-package-runtime-control-turns!
            control (sub1 (package-runtime-control-turns control)))
           (and (zero? (package-runtime-control-turns control))
                (package-runtime-control-retire control)))))
      (when retire (retire)))))

(define (package-command-definition
         package-id version definition limits control resolver grant module-root)
  (define implementation (odra-command-definition-implementation definition))
  (define requested-limits (command-limits definition))
  (define admitted-limits (odra-package-runtime-limits-command-limits limits))
  (define effective-command-limits
    (make-personal-command-limits
     #:deadline-milliseconds
     (min (personal-command-limits-deadline-milliseconds requested-limits)
          (personal-command-limits-deadline-milliseconds admitted-limits))
     #:custodian-memory-bytes
     (min (personal-command-limits-custodian-memory-bytes requested-limits)
          (personal-command-limits-custodian-memory-bytes admitted-limits))
     #:inspection-bytes
     (min (personal-command-limits-inspection-bytes requested-limits)
          (personal-command-limits-inspection-bytes admitted-limits))
     #:replacement-bytes
     (min (personal-command-limits-replacement-bytes requested-limits)
          (personal-command-limits-replacement-bytes admitted-limits))
     #:splices
     (min (personal-command-limits-splices requested-limits)
          (personal-command-limits-splices admitted-limits))
     #:temporary-native-bytes
     (min (personal-command-limits-temporary-native-bytes requested-limits)
          (personal-command-limits-temporary-native-bytes admitted-limits))
     #:nested-operations
     (min (personal-command-limits-nested-operations requested-limits)
          (personal-command-limits-nested-operations admitted-limits))
     #:diagnostic-bytes
     (min (personal-command-limits-diagnostic-bytes requested-limits)
          (personal-command-limits-diagnostic-bytes admitted-limits))))
  (define wrapped-implementation
    (lambda (context)
      (call-with-runtime-turn
       control
       (lambda ()
         (define turn-owner
           (parameterize
               ([current-custodian
                 (package-runtime-control-custodian control)])
             (make-custodian)))
         (define authorities
           (odra-package-authority-grant-authorities grant))
         (define project-root
           (and (command-context? context)
                (member 'project-read authorities)
                (command-context-project-root context)))
         (define data-root
           (and (command-context? context)
                (command-context-package-data-root context)))
         (when data-root (make-directory* data-root))
         (define compiled-root
           (and data-root (build-path data-root "compiled")))
         (when compiled-root (make-directory* compiled-root))
         (define host-security-guard (current-security-guard))
         (define graphviz-executable
           (and (member 'external-process authorities)
                (find-executable-path "dot")))
         (define guard
           (make-denying-security-guard
            module-root
            #:project-root project-root
            #:project-write? (and (member 'project-write authorities) #t)
            #:resources
            (if (and (command-context? context)
                     (member 'project-read authorities))
                (filter
                 (lambda (resource)
                   (string=? (package-resource-package resource)
                             (odra-package-authority-grant-package-id grant)))
                 (command-context-package-resources context))
                '())
            #:data-root data-root))
         (dynamic-wind
           void
           (lambda ()
             (define (execute)
               (parameterize ([current-module-name-resolver resolver]
                              [use-compiled-file-paths
                               package-compiled-file-paths]
                              [current-compiled-file-roots
                               (append
                                '(same)
                                (if compiled-root (list compiled-root) '())
                                trusted-compiled-roots)])
                 (call-with-package-isolation
                  turn-owner guard
                  (lambda ()
                    (call-with-command-tool-runner
                     (package-tool-runner
                      data-root
                      (and (member 'external-process authorities) #t)
                      graphviz-executable
                      host-security-guard)
                     (lambda () (implementation context)))))))
             (if (current-package-command-contained?)
                 (execute)
                 (call-with-limits
                  (/ (personal-command-limits-deadline-milliseconds
                      effective-command-limits)
                     1000.0)
                  (max
                   1
                   (quotient
                    (personal-command-limits-custodian-memory-bytes
                     effective-command-limits)
                    (* 1024 1024)))
                  execute)))
           (lambda () (custodian-shutdown-all turn-owner)))))))
  (register-personal-command-implementation-limits!
   wrapped-implementation effective-command-limits)
  (make-command-definition
   (odra-command-definition-name definition)
   'personal
   (odra-command-definition-invocation definition)
   (odra-command-definition-text-requirement definition)
   (odra-command-definition-effects definition)
   (odra-command-definition-description definition)
   wrapped-implementation
   #:interactive? (odra-command-definition-interactive? definition)
   #:requirements (odra-command-definition-requirements definition)
   #:provider (string-append "package:" package-id)
   #:source (format "~a@~a" package-id version)
   #:location
   (odra-command-source-location
    (odra-command-definition-provenance definition))))

(define (prepare-package-runtime root installed manifest grant
                                 contribution-generation
                                 #:limits [limits default-package-runtime-limits])
  (define package-id (odra-installed-package-id installed))
  (define version (odra-installed-package-version installed))
  (define invalid-manifest (manifest-rejection installed manifest))
  (define invalid-grant (grant-rejection installed manifest grant))
  (cond
    [invalid-manifest (failure 'manifest package-id version invalid-manifest)]
    [invalid-grant (failure 'authority package-id version invalid-grant)]
    [else
     (define artifact (manifest-entrypoint-artifact manifest))
     (define content-path (and artifact (entrypoint-path root artifact)))
     (if (not (and artifact
                   (verified-entrypoint? content-path artifact installed)))
         (failure 'content package-id version
                  "installed entrypoint content is absent or invalid")
         (let* ([module-root
                 (with-handlers ([exn:fail? (lambda (_) #f)])
                   (materialize-package-modules root manifest installed))]
                [path
                 (and module-root
                      (build-path
                       module-root
                       (odra-package-entrypoint-module-path
                        (odra-package-manifest-entrypoint manifest))))]
                [owner (make-custodian)]
                [control
                 (package-runtime-control
                  owner #f 'prepared 0 #f (make-semaphore 1))])
           (if (not module-root)
               (begin
                 (custodian-shutdown-all owner)
                 (failure
                  'content package-id version
                  "installed package module content is absent or invalid"))
               (with-handlers
               ([exn:fail:resource?
                 (lambda (_)
                   (custodian-shutdown-all owner)
                   (when (and module-root (directory-exists? module-root))
                     (delete-directory/files module-root))
                   (failure
                    'limit package-id version
                    "package entrypoint exceeded its preparation limits"))]
                [exn:fail?
                 (lambda (observed)
                   (define denied?
                     (regexp-match?
                      #px"denied|allowlist|require only|forbidden reflective binding|#reader|#lang"
                      (exn-message observed)))
                   (custodian-shutdown-all owner)
                   (when (and module-root (directory-exists? module-root))
                     (delete-directory/files module-root))
                   (failure
                    (if denied? 'denied 'evaluation)
                    package-id version
                    (if denied?
                        "package entrypoint requested a denied capability"
                        "package entrypoint could not be evaluated")))])
             (define-values (namespace exported resolver)
               (evaluate-entrypoint
                owner path module-root
                (odra-package-entrypoint-binding
                 (odra-package-manifest-entrypoint manifest))
                limits))
             (define invalid-definitions
               (definitions-rejection manifest exported))
             (if invalid-definitions
                 (begin
                   (custodian-shutdown-all owner)
                   (delete-directory/files module-root)
                   (failure
                    'contribution package-id version invalid-definitions))
                 (let* ([exported-commands (filter command? exported)]
                        [exported-agents (filter agent? exported)]
                        [exported-capabilities
                         (filter agent-capability? exported)]
                        [exported-keymaps
                         (filter bundle:odra-language-keymap? exported)]
                        [definitions
                         (for/list ([definition (in-list exported-commands)])
                           (package-command-definition
                            package-id version definition limits control
                            resolver grant module-root))]
                        [agent-source
                         (and (or (pair? exported-agents)
                                  (pair? exported-capabilities))
                              (make-agent-contribution-source
                               package-id version contribution-generation
                               exported-agents exported-capabilities
                               #:authorities
                               (odra-package-authority-grant-authorities
                                grant)))])
                   (with-handlers
                       ([exn:fail?
                         (lambda (_)
                           (custodian-shutdown-all owner)
                           (delete-directory/files module-root)
                           (failure
                            'contribution package-id version
                            "package contribution catalog is incompatible"))])
                     (define catalog
                       (compose-command-catalog
                        contribution-generation
                        (append
                         (odra-command-catalog-definitions
                          (factory-command-catalog))
                         definitions)))
                     (define agent-catalog
                       (compose-agent-catalog
                        contribution-generation
                        (if agent-source (list agent-source) '())))
                     (odra-package-runtime-candidate
                      package-id version contribution-generation grant manifest
                      limits control namespace module-root definitions
                      (map odra-command-definition-name definitions)
                      catalog agent-source agent-catalog exported-keymaps
                      #f #f))))))))]))

(define (package-runtime-candidate-command-names candidate)
  (append (odra-package-runtime-candidate-command-names candidate) '()))

(define (package-runtime-candidate-catalog candidate)
  (define catalog (odra-package-runtime-candidate-catalog candidate))
  (unless catalog
    (raise-arguments-error
     'package-runtime-candidate-catalog "package runtime candidate is retired"))
  catalog)

(define (package-runtime-candidate-agent-catalog candidate)
  (define catalog (odra-package-runtime-candidate-agent-catalog candidate))
  (unless catalog
    (raise-arguments-error
     'package-runtime-candidate-agent-catalog
     "package runtime candidate is retired"))
  catalog)

(define (package-runtime-candidate-keymaps candidate)
  (append (odra-package-runtime-candidate-keymaps candidate) '()))

(define (package-runtime-candidate-state candidate)
  (package-runtime-control-state
   (odra-package-runtime-candidate-control candidate)))

(define (package-runtime-candidate-active-turns candidate)
  (package-runtime-control-turns
   (odra-package-runtime-candidate-control candidate)))

(define (release-package-candidate! candidate)
  (unless (odra-package-runtime-candidate-closed? candidate)
    (define module-root (odra-package-runtime-candidate-module-root candidate))
    (custodian-shutdown-all
     (package-runtime-control-custodian
      (odra-package-runtime-candidate-control candidate)))
    (when (directory-exists? module-root)
      (delete-directory/files module-root))
    (set-package-runtime-control-state!
     (odra-package-runtime-candidate-control candidate) 'retired)
    (set-odra-package-runtime-candidate-definitions! candidate '())
    (set-odra-package-runtime-candidate-command-names! candidate '())
    (set-odra-package-runtime-candidate-catalog! candidate #f)
    (set-odra-package-runtime-candidate-agent-source! candidate #f)
    (set-odra-package-runtime-candidate-agent-catalog! candidate #f)
    (set-odra-package-runtime-candidate-keymaps! candidate '())
    (set-odra-package-runtime-candidate-closed?! candidate #t))
  (void))

(define (retire-package-candidate! candidate)
  (define control (odra-package-runtime-candidate-control candidate))
  (define release-now?
    (call-with-semaphore
     (package-runtime-control-lock control)
     (lambda ()
       (set-package-runtime-control-admitted?! control #f)
       (set-package-runtime-control-state! control 'retiring)
       (set-package-runtime-control-retire!
        control (lambda () (release-package-candidate! candidate)))
       (zero? (package-runtime-control-turns control)))))
  (when release-now? (release-package-candidate! candidate))
  (void))

(define (discard-package-runtime-candidate! candidate)
  (unless (eq? (package-runtime-candidate-state candidate) 'prepared)
    (raise-arguments-error
     'discard-package-runtime-candidate!
     "only a prepared package runtime candidate can be discarded"))
  (release-package-candidate! candidate)
  (void))

(define (make-package-runtime)
  (odra-package-runtime
   (make-hash) (make-hash) (make-hash) (factory-command-catalog)
   (empty-agent-catalog) '() #f))

(define (package-runtime-catalog runtime)
  (odra-package-runtime-catalog runtime))

(define (package-runtime-agent-catalog runtime)
  (odra-package-runtime-agent-catalog runtime))

(define (package-runtime-keymaps runtime)
  (append (odra-package-runtime-keymaps runtime) '()))

(define (package-runtime-active-generation runtime package-id)
  (define active (hash-ref (odra-package-runtime-active runtime) package-id #f))
  (and active (odra-package-runtime-candidate-contribution-generation active)))

(define (candidate-failure code candidate detail)
  (failure code
           (odra-package-runtime-candidate-package-id candidate)
           (odra-package-runtime-candidate-version candidate)
           detail))

(define (runtime-definitions runtime replacing-id [replacement #f])
  (append
   (odra-command-catalog-definitions (factory-command-catalog))
   (append*
    (for/list
        ([package-id
          (in-list
           (sort (hash-keys (odra-package-runtime-active runtime)) string<?))]
         #:unless (string=? package-id replacing-id))
      (odra-package-runtime-candidate-definitions
       (hash-ref (odra-package-runtime-active runtime) package-id))))
   (if replacement
       (odra-package-runtime-candidate-definitions replacement)
       '())))

(define (runtime-agent-sources runtime replacing-id [replacement #f])
  (filter
   values
   (append
    (for/list
        ([package-id
          (in-list
           (sort (hash-keys (odra-package-runtime-active runtime)) string<?))]
         #:unless (string=? package-id replacing-id))
      (odra-package-runtime-candidate-agent-source
       (hash-ref (odra-package-runtime-active runtime) package-id)))
    (if replacement
        (list (odra-package-runtime-candidate-agent-source replacement))
        '()))))

(define (runtime-keymaps runtime replacing-id [replacement #f])
  (append*
   (append
    (for/list
        ([package-id
          (in-list
           (sort (hash-keys (odra-package-runtime-active runtime)) string<?))]
         #:unless (string=? package-id replacing-id))
      (odra-package-runtime-candidate-keymaps
       (hash-ref (odra-package-runtime-active runtime) package-id)))
    (if replacement
        (list (odra-package-runtime-candidate-keymaps replacement))
        '()))))

(define (package-runtime-activate! runtime candidate)
  (cond
    [(odra-package-runtime-closed? runtime)
     (candidate-failure 'stale candidate "package runtime is closed")]
    [(or (odra-package-runtime-candidate-closed? candidate)
         (not (eq? (package-runtime-candidate-state candidate) 'prepared)))
     (candidate-failure 'stale candidate
                        "package runtime candidate is not prepared")]
    [(and (odra-package-runtime-candidate-owner candidate)
          (not (eq? (odra-package-runtime-candidate-owner candidate) runtime)))
     (candidate-failure 'stale candidate
                        "package runtime candidate belongs to another runtime")]
    [else
     (define package-id (odra-package-runtime-candidate-package-id candidate))
     (define grant-generation
       (odra-package-authority-grant-generation
        (odra-package-runtime-candidate-grant candidate)))
     (define contribution-generation
       (odra-package-runtime-candidate-contribution-generation candidate))
     (cond
       [(<= grant-generation
            (hash-ref (odra-package-runtime-latest-grants runtime) package-id 0))
        (candidate-failure 'stale candidate
                           "authority grant generation is stale")]
       [(<= contribution-generation
            (hash-ref (odra-package-runtime-latest-contributions runtime)
                      package-id 0))
        (candidate-failure 'stale candidate
                           "contribution generation is stale")]
       [else
        (with-handlers
            ([exn:fail?
              (lambda (_)
                (candidate-failure
                 'contribution candidate
                 "package command catalog is incompatible"))])
          (define catalog
            (compose-command-catalog
             contribution-generation
             (runtime-definitions runtime package-id candidate)))
          (define agent-catalog
            (compose-agent-catalog
             contribution-generation
             (runtime-agent-sources runtime package-id candidate)))
          (define keymaps
            (runtime-keymaps runtime package-id candidate))
          (define previous
            (hash-ref (odra-package-runtime-active runtime) package-id #f))
          (set-odra-package-runtime-candidate-owner! candidate runtime)
          (set-package-runtime-control-state!
           (odra-package-runtime-candidate-control candidate) 'active)
          (set-package-runtime-control-admitted?!
           (odra-package-runtime-candidate-control candidate) #t)
          (hash-set! (odra-package-runtime-active runtime) package-id candidate)
          (hash-set! (odra-package-runtime-latest-grants runtime)
                     package-id grant-generation)
          (hash-set! (odra-package-runtime-latest-contributions runtime)
                     package-id contribution-generation)
          (set-odra-package-runtime-catalog! runtime catalog)
          (set-odra-package-runtime-agent-catalog! runtime agent-catalog)
          (set-odra-package-runtime-keymaps! runtime keymaps)
          (when previous (retire-package-candidate! previous))
          (void))])]))

(define (package-runtime-deactivate! runtime package-id expected-generation
                                     next-generation)
  (define active (hash-ref (odra-package-runtime-active runtime) package-id #f))
  (cond
    [(odra-package-runtime-closed? runtime)
     (failure 'stale package-id "0.0.0" "package runtime is closed")]
    [(not active)
     (failure 'stale package-id "0.0.0" "package is not active")]
    [(not (= expected-generation
             (odra-package-runtime-candidate-contribution-generation active)))
     (candidate-failure 'stale active
                        "active contribution generation has changed")]
    [else
     (define catalog
       (compose-command-catalog
        next-generation (runtime-definitions runtime package-id)))
     (define agent-catalog
       (compose-agent-catalog
        next-generation (runtime-agent-sources runtime package-id)))
     (define keymaps (runtime-keymaps runtime package-id))
     (hash-remove! (odra-package-runtime-active runtime) package-id)
     (set-odra-package-runtime-catalog! runtime catalog)
     (set-odra-package-runtime-agent-catalog! runtime agent-catalog)
     (set-odra-package-runtime-keymaps! runtime keymaps)
     (retire-package-candidate! active)
     (void)]))

(define (package-runtime-call runtime package-id generation command-name context)
  (define active (hash-ref (odra-package-runtime-active runtime) package-id #f))
  (unless (and active
               (= generation
                  (odra-package-runtime-candidate-contribution-generation active)))
    (raise-arguments-error
     'package-runtime-call "package contribution generation is unavailable"
     "package" package-id
     "generation" generation))
  (define definition
    (for*/first
        ([definition
          (in-list (odra-package-runtime-candidate-definitions active))]
         #:when
         (string=? command-name (odra-command-definition-name definition)))
      definition))
  (unless definition
    (raise-arguments-error
     'package-runtime-call "package command is unavailable"
     "command" command-name))
  ((odra-command-definition-implementation definition) context))

(define (package-runtime-command-call runtime command-name context)
  (define definition
    (for*/first
        ([candidate (in-hash-values (odra-package-runtime-active runtime))]
         [definition
          (in-list (odra-package-runtime-candidate-definitions candidate))]
         #:when
         (string=? command-name (odra-command-definition-name definition)))
      definition))
  (unless definition
    (raise-arguments-error
     'package-runtime-command-call "package command is unavailable"
     "command" command-name))
  ((odra-command-definition-implementation definition) context))

(define (package-runtime-close! runtime)
  (unless (odra-package-runtime-closed? runtime)
    (set-odra-package-runtime-closed?! runtime #t)
    (define active (hash-values (odra-package-runtime-active runtime)))
    (hash-clear! (odra-package-runtime-active runtime))
    (set-odra-package-runtime-catalog! runtime (factory-command-catalog))
    (set-odra-package-runtime-agent-catalog! runtime (empty-agent-catalog))
    (set-odra-package-runtime-keymaps! runtime '())
    (for ([candidate (in-list active)])
      (retire-package-candidate! candidate)))
  (void))
