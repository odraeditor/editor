#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require (prefix-in bundle: "../../src/command/language-bundles.rkt"))

(provide make-quill-bundle)

(define target '((linux x86-64)))

(define (artifact id kind path digest size #:authority [authority #f])
  (bundle:language-bundle-artifact
   #:id id
   #:kind kind
   #:path path
   #:sha256 digest
   #:size size
   #:targets target
   #:authority authority))

(define (make-quill-bundle version artifacts)
  (define (artifact-value id kind path #:authority [authority #f])
    (define metadata (hash-ref artifacts id))
    (artifact id kind path (car metadata) (cdr metadata) #:authority authority))
  (define service
    (bundle:language-service
     #:id 'quill.fixture-lsp
     #:display-name "Quill fixture language server"
     #:languages '(quill)
     #:command '("racket" "server/server.rkt")
     #:root-markers '("quill.project")
     #:features '(diagnostics completion)
     #:default? #t))
  (bundle:language-support-bundle
   #:id 'org.example.quill
   #:display-name "Quill"
   #:version version
   #:api-min "1.0.0"
   #:api-max "2.0.0"
   #:description "External conformance fixture language."
   #:publisher 'org.example
   #:source 'catalog.example
   #:targets target
   #:authorities
   (list (bundle:language-bundle-authority 'native-grammar)
         (bundle:language-bundle-authority 'external-process)
         (bundle:language-bundle-authority 'project-read))
   #:languages
   (list (bundle:language #:id 'quill #:display-name "Quill" #:suffixes '(".quill")))
   #:syntax-providers
   (list
    (bundle:tree-sitter-syntax-provider
     #:id 'quill.syntax
     #:languages '(quill)
     #:grammar-artifact 'quill.grammar
     #:grammar-symbol "tree_sitter_odin"
     #:query-artifacts '(quill.highlights)
     #:captures (hasheq 'variable 'variable)))
   #:services (list service)
   #:formatters
   (list
    (bundle:language-formatter
     #:id 'quill.format
     #:languages '(quill)
     #:kind 'language-service
     #:service 'quill.fixture-lsp
     #:scopes '(buffer range)
     #:input 'text
     #:output 'text-edits))
   #:commands
   (list
    (bundle:language-command
     #:id 'quill.describe
     #:description "Describe effective Quill language support."
     #:implementation 'describe-language-support
     #:requirements '(language)
     #:effects '(ui)
     #:availability 'language-active
     #:provenance "External conformance fixture"))
   #:keymaps
   (list
    (bundle:language-keymap
     #:id 'quill.direct
     #:languages '(quill)
     #:states '(direct)
     #:context 'language-context
     #:bindings (hash "C-c C-l q" 'quill.describe))
    (bundle:language-keymap
     #:id 'quill.modal
     #:languages '(quill)
     #:states '(modal-normal)
     #:context 'language-context
     #:bindings (hash "g l q" 'quill.describe)))
   #:artifacts
   (list
    (artifact-value 'quill.manifest 'manifest "manifest/bundle.rkt")
    (artifact-value 'quill.grammar 'tree-sitter-grammar
                    "grammar/libtree-sitter-quill.so"
                    #:authority 'native-grammar)
    (artifact-value 'quill.highlights 'query "queries/highlights.scm")
    (artifact-value 'quill.server 'racket-module "server/server.rkt"))
   #:provenance "Odra external language conformance fixture"))
