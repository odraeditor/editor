#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require odra/language-bundles)

(provide odra-language-bundle)

;; Replace the example identities and the zero digests after adding the files.
(define target '((linux x86-64)))
(define zero-digest (make-string 64 #\0))

(define grammar
  (language-bundle-artifact
   #:id 'example.grammar
   #:kind 'tree-sitter-grammar
   #:path "grammar/libtree-sitter-example.so"
   #:sha256 zero-digest
   #:size 0
   #:targets target
   #:authority 'native-grammar))

(define highlights
  (language-bundle-artifact
   #:id 'example.highlights
   #:kind 'query
   #:path "queries/highlights.scm"
   #:sha256 zero-digest
   #:size 0
   #:targets target))

(define service
  (language-service
   #:id 'example.language-server
   #:languages '(example)
   #:command '("example-language-server" "--stdio")
   #:root-markers '("example.project")
   #:features '(diagnostics completion navigation hover formatting)
   #:default? #t))

(define odra-language-bundle
  (language-support-bundle
   #:id 'org.example.language
   #:display-name "Example Language"
   #:version "1.0.0"
   #:api-min "1.0.0"
   #:api-max "1.0.0"
   #:description "Example third-party language bundle."
   #:publisher 'org.example
   #:source 'catalog.example
   #:targets target
   #:authorities
   (list (language-bundle-authority 'native-grammar)
         (language-bundle-authority 'external-process)
         (language-bundle-authority 'project-read))
   #:languages
   (list (language #:id 'example #:suffixes '(".example")))
   #:syntax-providers
   (list
    (tree-sitter-syntax-provider
     #:id 'example.syntax
     #:languages '(example)
     #:grammar-artifact 'example.grammar
     #:grammar-symbol "tree_sitter_example"
     #:query-artifacts '(example.highlights)
     #:captures (hasheq 'keyword 'keyword 'string 'string 'comment 'comment)))
   #:services (list service)
   #:formatters
   (list
    (language-formatter
     #:id 'example.format
     #:languages '(example)
     #:kind 'language-service
     #:service 'example.language-server
     #:scopes '(buffer range)
     #:input 'text
     #:output 'text-edits))
   #:commands
   (list
    (language-command
     #:id 'example.describe
     #:description "Describe effective language support."
     #:implementation 'describe-language-support))
   #:keymaps
   (list
    (language-keymap
     #:id 'example.direct
     #:languages '(example)
     #:states '(direct)
     #:context 'language-context
     #:bindings (hash "C-c C-l i" 'example.describe))
    (language-keymap
     #:id 'example.modal
     #:languages '(example)
     #:states '(modal-normal)
     #:context 'language-context
     #:bindings (hash "g l i" 'example.describe)))
   #:artifacts (list grammar highlights)
   #:provenance "Third-party language bundle template"))
