#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (only-in file/sha1 bytes->hex-string)
         (except-in openssl/sha1 sha1)
         json
         racket/file
         racket/path
         racket/runtime-path
         rackunit
         "../../scripts/language-bundle-author.rkt")

(define-runtime-path repository-root "../..")
(define grammar-source
  (string->path
   (or (getenv "ODRA_EXTERNAL_BUNDLE_GRAMMAR")
       (path->string
        (build-path repository-root
                    ".build/syntax-provider-fixture/libtree-sitter-odin.so")))))
(define schema-path
  (build-path repository-root
              "assets/language-bundles/author-kit/language-bundle.schema.json"))
(define template-path
  (build-path repository-root
              "assets/language-bundles/author-kit/template/bundle.rkt"))

(define (sha256-file path)
  (call-with-input-file path
    (lambda (input) (bytes->hex-string (sha256-bytes input)))))

(define (write-bundle root grammar-digest grammar-size query-digest query-size)
  (define path (build-path root "bundle.rkt"))
  (call-with-output-file path
    (lambda (output)
      (display
       (format
        #<<BUNDLE
#lang racket/base
(require odra/language-bundles)
(provide odra-language-bundle)
(define target '((linux x86-64)))
(define grammar
  (language-bundle-artifact
   #:id 'quill.grammar #:kind 'tree-sitter-grammar
   #:path "grammar/parser.so" #:sha256 ~s #:size ~a
   #:targets target #:authority 'native-grammar))
(define highlights
  (language-bundle-artifact
   #:id 'quill.highlights #:kind 'query
   #:path "queries/highlights.scm" #:sha256 ~s #:size ~a #:targets target))
(define service
  (language-service
   #:id 'quill.lsp #:languages '(quill) #:command '("quill-lsp" "--stdio")
   #:root-markers '("quill.project") #:features '(diagnostics completion)
   #:default? #t))
(define odra-language-bundle
  (language-support-bundle
   #:id 'org.example.quill #:display-name "Quill" #:version "1.0.0"
   #:api-min "1.0.0" #:api-max "2.0.0"
   #:description "Author kit fixture." #:publisher 'org.example
   #:source 'catalog.example #:targets target
   #:authorities
   (list (language-bundle-authority 'external-process)
         (language-bundle-authority 'native-grammar)
         (language-bundle-authority 'project-read))
   #:languages (list (language #:id 'quill #:suffixes '(".quill")))
   #:syntax-providers
   (list (tree-sitter-syntax-provider
          #:id 'quill.syntax #:languages '(quill)
          #:grammar-artifact 'quill.grammar #:grammar-symbol "tree_sitter_odin"
          #:query-artifacts '(quill.highlights)
          #:captures (hasheq 'variable 'variable)))
   #:services (list service)
   #:commands
   (list (language-command #:id 'quill.describe
                           #:description "Describe Quill support."
                           #:implementation 'describe-language-support))
   #:keymaps
   (list (language-keymap #:id 'quill.direct #:languages '(quill)
                          #:states '(direct) #:context 'language-context
                          #:bindings (hash "C-c C-l q" 'quill.describe))
         (language-keymap #:id 'quill.modal #:languages '(quill)
                          #:states '(modal-normal) #:context 'language-context
                          #:bindings (hash "g l q" 'quill.describe)))
   #:artifacts (list grammar highlights)))
BUNDLE
        grammar-digest grammar-size query-digest query-size)
       output))
    #:exists 'truncate/replace)
  path)

(define (diagnostic-codes result)
  (map bundle-author-diagnostic-code
       (language-bundle-validation-diagnostics result)))

(test-case "manifest schema and template expose the complete author surface"
  (define schema (call-with-input-file schema-path read-json))
  (check-equal? (hash-ref schema '$schema)
                "https://json-schema.org/draft/2020-12/schema")
  (check-equal? (hash-ref (hash-ref schema 'properties) 'schema)
                (hasheq 'const 1))
  (for ([required
         (in-list '(schema format-version id version api-range targets authorities
                           contributions artifacts entrypoint))])
    (check-not-false (member (symbol->string required) (hash-ref schema 'required))))
  (define template-result (validate-language-bundle template-path))
  (check-eq? (language-bundle-validation-state template-result) 'invalid)
  (check-not-false (member 'artifact-missing (diagnostic-codes template-result))))

(test-case "validator conformance and archive builder are deterministic"
  (define root (make-temporary-file "odra-author-kit-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define grammar (build-path root "grammar/parser.so"))
     (define query (build-path root "queries/highlights.scm"))
     (make-parent-directory* grammar)
     (make-parent-directory* query)
     (copy-file grammar-source grammar)
     (call-with-output-file query
       (lambda (output) (display "(identifier) @variable\n" output))
       #:exists 'truncate/replace)
     (define module-path
       (write-bundle root
                     (sha256-file grammar) (file-size grammar)
                     (sha256-file query) (file-size query)))
     (define validated (validate-language-bundle module-path))
     (check-eq? (language-bundle-validation-state validated) 'valid
                (format "~s" (language-bundle-validation-diagnostics validated)))
     (define conformant (conform-language-bundle module-path))
     (check-eq? (language-bundle-validation-state conformant) 'conformant
                (format "~s" (language-bundle-validation-diagnostics conformant)))
     (define incompatible
       (validate-language-bundle module-path #:api-version "3.0.0"))
     (check-not-false (member 'incompatible-api (diagnostic-codes incompatible)))
     (define first-path (build-path root "dist/first.tar"))
     (define second-path (build-path root "dist/second.tar"))
     (define first (build-language-bundle-archive module-path first-path))
     (define second (build-language-bundle-archive module-path second-path))
     (check-equal? (file->bytes first-path) (file->bytes second-path))
     (check-equal? (language-bundle-archive-digest first)
                   (language-bundle-archive-digest second))
     (check-equal? (language-bundle-archive-members first) 2)
     (call-with-output-file query
       (lambda (output) (display "(identifier) @tampered\n" output))
       #:exists 'truncate/replace)
     (define tampered (validate-language-bundle module-path))
     (check-not-false (member 'artifact-digest (diagnostic-codes tampered))))
   (lambda () (delete-directory/files root))))
