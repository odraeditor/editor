#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.

(require rackunit
         (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         json
         racket/file
         racket/list
         racket/path
         racket/port
         racket/runtime-path
         racket/string
         racket/system)

(define-runtime-path test-directory ".")
(define repository-root (simplify-path (build-path test-directory ".." "..") #t))
(define build-root (build-path repository-root ".build"))
(define core-path (build-path build-root "odra-development"))
(define module-root (build-path build-root "modules"))
(define manifest-path (build-path module-root "product-modules.manifest"))
(define runtime-closure-path
  (build-path repository-root "release" "linux-x86_64" "runtime-closure.json"))

(define expected-modules
  (list
   (list "odra.ksawery" "source-control" "libodra-ksawery.so"
         "src/ksawery_module/module.odin" "src/ksawery_module")
   (list "odra.maksym" "file-management" "libodra-maksym.so"
         "src/maksym_module/module.odin" "src/maksym_module")
   (list "odra.darek" "workspace-hierarchy" "libodra-darek.so"
         "src/darek_module/module.odin" "src/darek_module")
   (list "odra.jan" "structured-document" "libodra-jan.so"
         "src/jan_module/module.odin" "src/jan_module")))

(define official-source-directories
  '("ksawery" "ksawery_bridge" "ksawery_command" "ksawery_module"
    "maksym" "maksym_module" "darek" "darek_module"
    "jan_editing" "jan_planning" "jan_computation" "jan_output" "jan_module"))

(define (sha256-file path)
  (call-with-input-file path
    (lambda (input) (bytes->hex-string (sha256-bytes input)))
    #:mode 'binary))

(define (read-product-module-manifest path)
  (define lines (file->lines path))
  (check-equal? (car lines) "odra-product-modules 1")
  (let loop ([remaining (cdr lines)] [current #f] [records '()])
    (cond
      [(null? remaining)
       (check-false current "manifest ends inside a module declaration")
       (reverse records)]
      [(string=? (car remaining) "module")
       (check-false current "manifest nests module declarations")
       (loop (cdr remaining) (hash) records)]
      [(string=? (car remaining) "end")
       (check-true (hash? current) "manifest closes no module declaration")
       (loop (cdr remaining) #f (cons current records))]
      [else
       (check-true (hash? current) "manifest field appears outside a module declaration")
       (define parts (string-split (car remaining) "=" #:trim? #f))
       (check-equal? (length parts) 2 (format "invalid manifest field: ~a" (car remaining)))
       (loop (cdr remaining)
             (hash-set current (car parts) (cadr parts))
             records)])))

(define (run/capture executable . arguments)
  (define-values (process output input error-output)
    (parameterize ([current-directory repository-root])
      (apply subprocess #f #f #f executable arguments)))
  (close-output-port input)
  (define stdout (port->string output))
  (define stderr (port->string error-output))
  (subprocess-wait process)
  (values (subprocess-status process) stdout stderr))

(define (module-build-lines text)
  (filter (lambda (line) (regexp-match? #rx"odin build src/[^ ]+_module" line))
          (string-split text "\n")))

(test-case "default distribution contains the four verified official module artifacts"
  (check-true (file-exists? core-path) "development core artifact is missing")
  (define records (read-product-module-manifest manifest-path))
  (check-equal? (length records) (length expected-modules))
  (for ([expected (in-list expected-modules)]
        [record (in-list records)])
    (define identity (list-ref expected 0))
    (define role (list-ref expected 1))
    (define artifact-name (list-ref expected 2))
    (define artifact-path (build-path module-root artifact-name))
    (check-equal? (hash-ref record "identity") identity)
    (check-equal? (hash-ref record "version") "1.0.0")
    (check-equal? (hash-ref record "role") role)
    (check-equal? (hash-ref record "artifact") artifact-name)
    (check-equal? (hash-ref record "entrypoint") "odra_product_module_entrypoint")
    (check-equal? (hash-ref record "abi-minimum") "5")
    (check-equal? (hash-ref record "abi-maximum") "5")
    (check-true (file-exists? artifact-path) (format "missing artifact: ~a" artifact-name))
    (check-equal? (hash-ref record "digest") (sha256-file artifact-path))
    (check-equal? (hash-ref record "size") (number->string (file-size artifact-path)))
    (check-false (absolute-path? (string->path (hash-ref record "artifact"))))
    (check-false (regexp-match? #rx"://" (hash-ref record "artifact")))))

(test-case "release composition names the same official module artifacts"
  (define closure (call-with-input-file runtime-closure-path read-json))
  (define declared
    (hash-ref (hash-ref (hash-ref closure 'bundle) 'product_modules) 'artifacts))
  (check-equal? declared (map (lambda (entry) (list-ref entry 2)) expected-modules)))

(test-case "core Odin sources do not import official implementation packages"
  (define source-root (build-path repository-root "src"))
  (define import-pattern
    #px"(?m:^\\s*import(?:\\s+[A-Za-z_][A-Za-z0-9_]*)?\\s+\"([^\"]+)\")")
  (define violations
    (for*/list ([path (in-directory source-root)]
                #:when (and (file-exists? path)
                            (regexp-match? #rx"\\.odin$" (path->string path))
                            (not (regexp-match? #rx"_test\\.odin$" (path->string path))))
                [relative (in-value (find-relative-path source-root path))]
                [segments (in-value (map path->string (explode-path relative)))]
                #:unless (member (car segments) official-source-directories)
                [imported (in-list
                           (regexp-match* import-pattern
                                          (file->string path)
                                          #:match-select cadr))]
                #:when (regexp-match?
                        (pregexp
                         (string-append
                          "(^|/)("
                          (string-join (map regexp-quote official-source-directories) "|")
                          ")(/|$)"))
                        imported))
      (format "~a imports ~a" relative imported)))
  (check-equal? violations '()))

(test-case "each module-only change rebuilds only that module and the composition manifest"
  (define make-path (find-executable-path "make"))
  (check-not-false make-path "make is required for build-isolation checks")
  (define-values (query-status _query-output query-error)
    (run/capture make-path "-q" "development-build"))
  (check-equal? query-status 0
                (string-append "development artifacts must be current before isolation checks: "
                               query-error))
  (for ([expected (in-list expected-modules)])
    (define source (list-ref expected 3))
    (define build-package (list-ref expected 4))
    (define-values (status stdout stderr)
      (run/capture make-path "-n" "--no-print-directory" "-W" source "development-build"))
    (check-equal? status 0 stderr)
    (check-equal? (module-build-lines stdout)
                  (list (format "odin build ~a -build-mode:dll -out:.build/modules/~a -o:none -vet -warnings-as-errors"
                                build-package
                                (list-ref expected 2))))
    (check-false (regexp-match? #rx"odin build src/odra" stdout))
    (check-true (regexp-match? #rx"scripts/write-product-module-manifest.rkt" stdout))))

(printf "official-module-isolation: core=~a modules=~a\n"
        (sha256-file core-path)
        (string-join
         (for/list ([entry (in-list expected-modules)])
           (define name (list-ref entry 2))
           (format "~a:~a" name (sha256-file (build-path module-root name))))
         ","))
