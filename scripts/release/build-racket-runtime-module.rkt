#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require compiler/compile-file
         compiler/embed
         compiler/private/language
         racket/cmdline
         racket/file
         racket/list
         racket/path)

(provide build-runtime-bundle
         build-runtime-module-c)

(define (strip-source-locations value)
  (cond
    [(syntax? value)
     (datum->syntax value
                    (strip-source-locations (syntax-e value))
                    #f
                    value)]
    [(pair? value)
     (cons (strip-source-locations (car value))
           (strip-source-locations (cdr value)))]
    [(vector? value)
     (list->vector
      (map strip-source-locations (vector->list value)))]
    [(box? value)
     (box (strip-source-locations (unbox value)))]
    [else value]))

(define (prepare-source syntax)
  (namespace-syntax-introduce
   (strip-source-locations syntax)))

(define (racket-source? path)
  (and (file-exists? path)
       (regexp-match? #rx"\\.rkt$" (path->string path))))

(define (compile-source-tree source-root)
  (define complete-source-root (path->complete-path source-root))
  (define source-parent (path-only complete-source-root))
  (define relative-source-root (file-name-from-path complete-source-root))
  (parameterize ([current-directory source-parent]
                 [current-library-collection-paths
                  (cons complete-source-root
                        (current-library-collection-paths))]
                 [current-namespace (make-base-namespace)]
                 [read-accept-reader #t])
    (define sources
      (sort (find-files racket-source? relative-source-root) path<?))
    (for ([source (in-list sources)])
      (define compiled-directory
        (build-path (path-only source) "compiled"))
      (define compiled-path
        (build-path compiled-directory
                    (path-add-suffix (file-name-from-path source) #".zo")))
      (make-directory* compiled-directory)
      (compile-file source compiled-path prepare-source))))

(define (valid-entry? entry)
  (and (relative-path? entry)
       (not (for/or ([element (in-list (explode-path entry))])
              (eq? element 'up)))))

(define (contains-bytes? content value)
  (regexp-match? (byte-regexp (regexp-quote value)) content))

(define (bundle-modules entry)
  (append
   (list `(#f (file ,(path->string (build-path "src" entry)))))
   (for/list ([module-path
               (in-list
                (languages->libraries
                 (list "racket/base")
                 #:who 'build-racket-runtime-module))])
     `(#t ,module-path))))

(define (build-runtime-bundle source-root entry)
  (define complete-source-root (path->complete-path source-root))
  (define relative-entry
    (if (path? entry) entry (string->path entry)))
  (unless (and (directory-exists? complete-source-root)
               (valid-entry? relative-entry)
               (file-exists? (build-path complete-source-root relative-entry)))
    (raise-user-error 'build-racket-runtime-module
                      "entry must identify a source file below the source root"))
  (define temporary-parent (find-system-path 'temp-dir))
  (define temporary-root
    (build-path temporary-parent "odra-racket-runtime-build"))
  (define lock-path
    (build-path temporary-parent "odra-racket-runtime-build.lock"))
  (call-with-file-lock/timeout
   lock-path
   'exclusive
   (lambda ()
     (when (file-or-directory-type temporary-root #f)
       (raise-user-error 'build-racket-runtime-module
                         "canonical build root is already present"))
     (make-directory temporary-root)
     (dynamic-wind
       void
       (lambda ()
         (define copied-source-root (build-path temporary-root "src"))
         (copy-directory/files complete-source-root copied-source-root)
         (compile-source-tree copied-source-root)
         (define bundle
           (parameterize ([current-directory temporary-root]
                          [current-library-collection-paths
                           (cons copied-source-root
                                 (current-library-collection-paths))])
             (define output (open-output-bytes))
             (parameterize ([current-output-port output])
               (write-module-bundle
                #:modules (bundle-modules relative-entry)))
             (get-output-bytes output)))
         (when (contains-bytes? bundle (path->bytes complete-source-root))
           (raise-user-error 'build-racket-runtime-module
                             "compiled bundle retained a private input path"))
         bundle)
       (lambda ()
         (delete-directory/files temporary-root))))
   (lambda ()
     (raise-user-error 'build-racket-runtime-module
                       "canonical build root is locked"))))

(define (write-c-module bundle output)
  (display "#ifdef MZ_XFORM\nXFORM_START_SKIP;\n#endif\n" output)
  (fprintf output
           "static void declare_modules(~a) {\n"
           (if (eq? (system-type 'vm) 'racket) "Scheme_Env *env" "void"))
  (display "  static unsigned char data[] = {" output)
  (for ([byte (in-bytes bundle)]
        [position (in-naturals)])
    (when (zero? (modulo position 20))
      (display "\n    " output))
    (fprintf output "~a," byte))
  (display "0\n  };\n" output)
  (case (system-type 'vm)
    [(racket)
     (fprintf output
              "  scheme_register_embedded_load(~a, (const char *)data);\n"
              (bytes-length bundle))
     (fprintf output
              "  scheme_embedded_load(~a, (const char *)data, 1);\n"
              (bytes-length bundle))]
    [else
     (fprintf output
              "  racket_embedded_load_bytes((const char *)data, ~a, 1);\n"
              (bytes-length bundle))])
  (display "}\n#ifdef MZ_XFORM\nXFORM_END_SKIP;\n#endif\n" output))

(define (build-runtime-module-c source-root entry output-path)
  (define complete-output (path->complete-path output-path))
  (make-parent-directory* complete-output)
  (call-with-output-file complete-output
    #:exists 'truncate/replace
    (lambda (output)
      (write-c-module (build-runtime-bundle source-root entry) output))))

(module+ main
  (define source-root #f)
  (define entry #f)
  (define output #f)
  (command-line
   #:program "build-racket-runtime-module.rkt"
   #:once-each
   [("--source-root") path "Racket source root" (set! source-root path)]
   [("--entry") path "Runtime entry below the source root" (set! entry path)]
   [("--output") path "Generated C module" (set! output path)])
  (unless (and source-root entry output)
    (raise-user-error 'build-racket-runtime-module
                      "source root, entry, and output are required"))
  (build-runtime-module-c source-root entry output)
  (printf "racket_runtime_module=valid output=~a\n" output))

(module+ test
  (require rackunit)

  (test-case "removes build paths without embedding test source"
    (define root
      (make-temporary-file "racket-runtime-module-test-~a" 'directory))
    (dynamic-wind
      void
      (lambda ()
        (define helper (build-path root "hosting" "helper.rkt"))
        (define entry (build-path root "hosting" "runtime-boundary.rkt"))
        (make-parent-directory* entry)
        (call-with-output-file helper
          #:exists 'truncate
          (lambda (output)
            (display
             (string-append
              "#lang racket/base\n"
              "(provide answer)\n"
              "(define (answer) 42)\n")
             output)))
        (call-with-output-file entry
          #:exists 'truncate
          (lambda (output)
            (display
             (string-append
              "#lang racket/base\n"
              "(require \"helper.rkt\")\n"
              "(provide answer)\n"
              "(module+ test (displayln \"PRIVATE_TEST_SOURCE_MARKER\"))\n")
             output)))
        (define bundle
          (build-runtime-bundle root "hosting/runtime-boundary.rkt"))
        (check-false (contains-bytes? bundle (path->bytes root)))
        (check-false (contains-bytes? bundle #"PRIVATE_TEST_SOURCE_MARKER"))
        (check-true (contains-bytes? bundle #"runtime-boundary")))
      (lambda ()
        (delete-directory/files root)))))
