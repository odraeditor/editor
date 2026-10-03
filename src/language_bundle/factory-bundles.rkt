#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/contract/base
         racket/list
         (prefix-in bundle: "../command/language-bundles.rkt")
         (prefix-in language: "../command/languages.rkt"))

(provide
 (contract-out
  [factory-odin-language-bundle bundle:odra-language-support-bundle?]
  [factory-jan-language-bundle bundle:odra-language-support-bundle?]
  [factory-racket-language-bundle bundle:odra-language-support-bundle?]
  [factory-go-language-bundle bundle:odra-language-support-bundle?]
  [factory-rust-language-bundle bundle:odra-language-support-bundle?]
  [factory-javascript-language-bundle bundle:odra-language-support-bundle?]
  [factory-typescript-language-bundle bundle:odra-language-support-bundle?]
  [factory-html-language-bundle bundle:odra-language-support-bundle?]
  [factory-css-language-bundle bundle:odra-language-support-bundle?]
  [factory-language-bundles
   (-> (listof bundle:odra-language-support-bundle?))]
  [factory-language-bundle-find
   (-> symbol? (or/c #f bundle:odra-language-support-bundle?))]))

(define factory-targets
  '((darwin aarch64)
    (darwin x86-64)
    (linux aarch64)
    (linux x86-64)
    (windows aarch64)
    (windows x86-64)))

(define (artifact id kind path digest size [authority #f])
  (bundle:language-bundle-artifact
   #:id id
   #:kind kind
   #:path path
   #:sha256 digest
   #:size size
   #:targets factory-targets
   #:authority authority))

(define odin-artifacts
  (list
   (artifact
    'odin.grammar 'tree-sitter-grammar
    "third_party/tree-sitter-odin/1.3.0/src/parser.c"
    "8f672d8d022d70eeae822796924f2e45e692d6b2acd2ddc79bfeb5f696fa24f0"
    14767097
    'native-grammar)
   (artifact
    'odin.scanner 'data
    "third_party/tree-sitter-odin/1.3.0/src/scanner.c"
    "e342d07d3e35c3865a6bda0587f3a3b46a7b2411fd93cbee01dc40ab7631c93b"
    9521)
   (artifact
    'odin.highlights 'query
    "third_party/tree-sitter-odin/1.3.0/queries/highlights.scm"
    "d32354fc8cef7da7f2b235ed17d2d48c074150d5dc69bfedf18d1370b03f8cc7"
    4389)
   (artifact
    'odin.license 'license
    "third_party/tree-sitter-odin/1.3.0/LICENSE"
    "099c44248f8cf353123211318680e93465587c005a4b3730ce8cb5334de043d6"
    1101)))

(define odin-captures
  (hasheq
   'attribute 'attribute
   'boolean 'constant
   'character 'string
   'comment 'comment
   'conditional 'keyword
   'conditional.ternary 'operator
   'constant 'constant
   'constant.builtin 'constant
   'error 'error
   'field 'field
   'float 'number
   'function 'function
   'function.call 'function
   'function.macro 'function
   'include 'keyword
   'keyword 'keyword
   'keyword.function 'keyword
   'keyword.operator 'operator
   'keyword.return 'keyword
   'label 'label
   'namespace 'namespace
   'number 'number
   'operator 'operator
   'parameter 'parameter
   'preproc 'keyword
   'punctuation.bracket 'punctuation
   'punctuation.delimiter 'punctuation
   'punctuation.special 'punctuation
   'repeat 'keyword
   'storageclass 'keyword
   'string 'string
   'string.escape 'escape
   'type 'type
   'type.builtin 'type
   'variable 'variable
   'variable.builtin 'variable))

(define odin-syntax
  (bundle:tree-sitter-syntax-provider
   #:id 'odin.syntax
   #:languages '(odin)
   #:grammar-artifact 'odin.grammar
   #:grammar-symbol "tree_sitter_odin"
   #:abi-min 14
   #:abi-max 14
   #:query-artifacts '(odin.highlights)
   #:captures odin-captures
   #:resource-profile 'ordinary
   #:authority 'native-grammar))

(define odin-service
  (language:language-service
   #:id 'ols
   #:display-name "OLS"
   #:languages '(odin)
   #:command '("ols")
   #:root-markers '("ols.json")
   #:features '(diagnostics completion)
   #:enabled? #t
   #:default? #t))

(define (native-command id description effects
                        [requirements '(active-buffer active-document)]
                        [availability 'language-capability])
  (bundle:language-command
   #:id id
   #:description description
   #:implementation (string->symbol (format "native.~a" id))
   #:requirements requirements
   #:effects effects
   #:availability availability
   #:provenance "Odra Factory language command"))

(define odin-commands
  (list
   (native-command 'language-show-hover "Show language hover content." '(view lifecycle))
   (native-command 'language-go-to-definition "Visit a selected definition." '(view lifecycle))
   (native-command 'language-find-references "Present language references." '(view lifecycle))
   (native-command 'language-document-symbols "Present document symbols." '(view lifecycle))
   (native-command 'language-workspace-symbols "Present workspace symbols." '(view lifecycle))
   (native-command 'language-signature-help "Show callable signatures." '(view lifecycle))
   (native-command 'language-rename "Apply a checked language rename."
                   '(buffer view lifecycle text-mutation))
   (native-command 'language-format-buffer "Format the active document."
                   '(buffer view lifecycle text-mutation))
   (native-command 'language-format-region "Format the active region."
                   '(buffer view lifecycle text-mutation)
                   '(active-buffer active-document active-region))
   (native-command 'language-code-actions "Select and apply a checked code action."
                   '(buffer view lifecycle text-mutation))
   (native-command 'describe-language-support "Inspect effective language support."
                   '(lifecycle))
   (native-command 'describe-language-service "Inspect the selected language service."
                   '(lifecycle))
   (native-command 'restart-language-service "Restart the selected language service."
                   '(lifecycle))))

(define odin-direct-bindings
  (hash
   "C-c C-l h" 'language-show-hover
   "C-c C-l d" 'language-go-to-definition
   "C-c C-l r" 'language-find-references
   "C-c C-l s" 'language-document-symbols
   "C-c C-l S" 'language-workspace-symbols
   "C-c C-l n" 'language-rename
   "C-c C-l f" 'language-format-buffer
   "C-c C-l a" 'language-code-actions
   "C-c C-l i" 'describe-language-support
   "C-c C-l R" 'restart-language-service))

(define odin-modal-bindings
  (hash
   "normal:g d" 'language-go-to-definition
   "normal:g r" 'language-find-references
   "normal:K" 'language-show-hover
   "normal:g l s" 'language-document-symbols
   "normal:g l S" 'language-workspace-symbols
   "normal:g l n" 'language-rename
   "normal:g l f" 'language-format-buffer
   "normal:g l a" 'language-code-actions
   "normal:g l i" 'describe-language-support
   "normal:g l R" 'restart-language-service
   "visual-character:g l f" 'language-format-region
   "visual-character:g l a" 'language-code-actions
   "visual-line:g l f" 'language-format-region
   "visual-line:g l a" 'language-code-actions))

(define odin-keymaps
  (list
   (bundle:language-keymap
    #:id 'odin.direct
    #:languages '(odin)
    #:states '(direct)
    #:context 'language-context
    #:bindings odin-direct-bindings
    #:provenance "Odra Factory Direct language map")
   (bundle:language-keymap
    #:id 'odin.modal
    #:languages '(odin)
    #:states '(normal visual-character visual-line)
    #:context 'language-context
    #:bindings odin-modal-bindings
    #:provenance "Odra Factory Modal language map")))

(define factory-odin-language-bundle
  (bundle:language-support-bundle
   #:id 'org.odra.odin
   #:display-name "Odin Language Support"
   #:version "1.0.0"
   #:api-min "1.0.0"
   #:api-max "1.0.0"
   #:description
   "Factory Odin recognition, syntax, structure, OLS, commands, and interaction maps."
   #:publisher 'odra
   #:source 'odra.factory
   #:targets factory-targets
   #:license "MIT"
   #:authorities
   (list (bundle:language-bundle-authority 'native-grammar)
         (bundle:language-bundle-authority 'external-process))
   #:languages
   (list (language:language
          #:id 'odin
          #:display-name "Odin"
          #:suffixes '(".odin")))
   #:syntax-providers (list odin-syntax)
   #:services (list odin-service)
   #:commands odin-commands
   #:keymaps odin-keymaps
   #:artifacts odin-artifacts
   #:provenance
   "Odra Factory; tree-sitter 0.26.12; tree-sitter-odin 1.3.0"))

(define jan-artifacts
  (list
   (artifact
    'jan.grammar 'tree-sitter-grammar
    "third_party/tree-sitter-jan/jan-org-9.8.10-v1/src/parser.c"
    "0d05add3963b04d6f8a4be24ecc3e4b381d5aadaf72cb5aaff9ff84ac236296a"
    2662089
    'native-grammar)
   (artifact
    'jan.scanner 'data
    "third_party/tree-sitter-jan/jan-org-9.8.10-v1/src/scanner.c"
    "c9d3bbfa93dea84312055a85a07072622c8c61b069bb735bd1ba958c21e7cab6"
    1640)
   (artifact
    'jan.highlights 'query
    "assets/language-bundles/factory/jan/highlights.scm"
    "05bfd3bbeab52c61cad9b459a1407368991e681c6bd0c044fc4516bb2fb91b31"
    1239)
   (artifact
    'jan.capabilities 'data
    "src/language/jan_availability.odin"
    "0868f609b8d1250c70702c8c154b387d3e44312c1a9764717a61b8839f43a839"
    3373)
   (artifact
    'jan.license 'license
    "third_party/tree-sitter-jan/jan-org-9.8.10-v1/TREE_SITTER_LICENSE"
    "c5cfb43042b6b72045f4ba997834d0a7786d2793d91680868b5815b39f14fc78"
    1080)
   (artifact
    'jan.documentation 'documentation
    "third_party/tree-sitter-jan/jan-org-9.8.10-v1/README.md"
    "4ccb5f0dd8b83b0123af865e9c9817b19df99af785fe0f6f2ca4a505e73a6f1a"
    2237)))

(define jan-captures
  (hasheq
   'label 'label
   'keyword 'keyword
   'attribute 'attribute
   'comment 'comment
   'comment.error 'comment
   'string 'string
   'constant 'constant
   'number 'number
   'punctuation 'punctuation))

(define jan-syntax
  (bundle:tree-sitter-syntax-provider
   #:id 'jan.syntax
   #:languages '(jan)
   #:grammar-artifact 'jan.grammar
   #:grammar-symbol "tree_sitter_jan"
   #:abi-min 15
   #:abi-max 15
   #:query-artifacts '(jan.highlights)
   #:captures jan-captures
   #:resource-profile 'ordinary
   #:authority 'native-grammar))

(define jan-command-kinds
  '((view . jan-cycle)
    (view . jan-global-cycle)
    (view . jan-show-overview)
    (view . jan-show-contents)
    (view . jan-show-all)
    (view . jan-sparse-view)
    (view . jan-next-heading)
    (view . jan-previous-heading)
    (view . jan-next-same-level-heading)
    (view . jan-previous-same-level-heading)
    (view . jan-parent-heading)
    (view . jan-first-child-heading)
    (view . jan-subtree-start)
    (view . jan-subtree-end)
    (view . jan-next-structural-element)
    (view . jan-previous-structural-element)
    (view . jan-next-list-item)
    (view . jan-previous-list-item)
    (view . jan-next-table-row)
    (view . jan-previous-table-row)
    (view . jan-next-table-cell)
    (view . jan-previous-table-cell)
    (view . jan-next-drawer)
    (view . jan-previous-drawer)
    (view . jan-next-block)
    (view . jan-previous-block)
    (view . jan-next-footnote)
    (view . jan-previous-footnote)
    (edit . jan-insert-heading-before)
    (edit . jan-insert-heading-after)
    (edit . jan-insert-heading-below)
    (edit . jan-split-heading)
    (edit . jan-promote-heading)
    (edit . jan-demote-heading)
    (edit . jan-move-subtree-up)
    (edit . jan-move-subtree-down)
    (edit . jan-clone-subtree)
    (edit . jan-kill-subtree)
    (edit . jan-sort-child-headings)
    (edit . jan-heading-to-list-item)
    (edit . jan-list-item-to-heading)
    (edit . jan-insert-list-item-before)
    (edit . jan-insert-list-item-after)
    (edit . jan-delete-list-item)
    (edit . jan-promote-list-item)
    (edit . jan-demote-list-item)
    (edit . jan-move-list-item-up)
    (edit . jan-move-list-item-down)
    (edit . jan-duplicate-list-item)
    (edit . jan-sort-list-items)
    (edit . jan-cycle-list-bullet)
    (edit . jan-repair-list-indentation)
    (edit . jan-insert-drawer)
    (edit . jan-insert-block)
    (view . jan-select-structure)
    (edit . jan-move-structure-up)
    (edit . jan-move-structure-down)
    (edit . jan-delete-structure)
    (edit . jan-create-table)
    (edit . jan-align-table)
    (edit . jan-insert-table-row)
    (edit . jan-delete-table-row)
    (edit . jan-move-table-row-up)
    (edit . jan-move-table-row-down)
    (edit . jan-duplicate-table-row)
    (edit . jan-insert-table-column)
    (edit . jan-delete-table-column)
    (edit . jan-move-table-column-left)
    (edit . jan-move-table-column-right)
    (edit . jan-duplicate-table-column)
    (edit . jan-insert-table-separator)
    (edit . jan-delete-table-separator)
    (edit . jan-edit-table-cell)
    (view . jan-visit-footnote)
    (edit . jan-create-footnote)
    (edit . jan-normalize-footnote)
    (edit . jan-renumber-footnotes)
    (edit . jan-move-footnote-up)
    (edit . jan-move-footnote-down)
    (view . jan-complete)
    (edit . jan-expand-template)
    (edit . jan-indent)
    (edit . jan-context-action)
    (view . jan-repeat)
    (view . jan-present)
    (view . jan-request-preview)
    (view . jan-inspect-availability)
    (inspect . jan-inspect-syntax)
    (inspect . jan-lint)
    (inspect . jan-lint-refresh)
    (inspect . jan-language-status)))

(define jan-commands
  (for/list ([entry (in-list jan-command-kinds)])
    (define kind (car entry))
    (define id (cdr entry))
    (native-command
     id
     (format "Factory Jan command ~a." id)
     (case kind
       [(view) '(view lifecycle)]
       [(edit) '(buffer view lifecycle text-mutation)]
       [else '(lifecycle)])
     '(active-buffer)
     'jan-capability)))

(define jan-keymaps
  (list
   (bundle:language-keymap
    #:id 'jan.direct
    #:languages '(jan)
    #:states '(direct)
    #:context 'language-context
    #:bindings
    (hash
     "TAB" 'jan-cycle
     "S-TAB" 'jan-global-cycle
     "M-RET" 'jan-insert-heading-after
     "M-LEFT" 'jan-promote-heading
     "M-RIGHT" 'jan-demote-heading
     "M-UP" 'jan-context-meta-up
     "M-DOWN" 'jan-context-meta-down
     "C-c C-n" 'jan-next-heading
     "C-c C-p" 'jan-previous-heading
     "C-c C-f" 'jan-next-same-level-heading
     "C-c C-b" 'jan-previous-same-level-heading
     "C-c C-u" 'jan-parent-heading
     "C-c C-c" 'jan-context-action
     "C-c C-o" 'jan-open-result
     "C-c C-v p" 'jan-previous-block
     "C-c C-v n" 'jan-next-block
     "C-c C-v e" 'jan-execute
     "C-c C-v o" 'jan-open-result
     "C-c C-v v" 'jan-expand-source
     "C-c C-v u" 'jan-goto-source-head
     "C-c C-v g" 'jan-goto-named-source
     "C-c C-v r" 'jan-goto-named-result
     "C-c C-v b" 'jan-execute-buffer
     "C-c C-v s" 'jan-execute-subtree
     "C-c C-v d" 'jan-demarcate-source
     "C-c C-v t" 'jan-tangle
     "C-c C-v f" 'jan-tangle-file
     "C-c C-v c" 'jan-check-source
     "C-c C-v j" 'jan-insert-header-argument
     "C-c C-v l" 'jan-load-in-session
     "C-c C-v i" 'jan-library-load
     "C-c C-v I" 'jan-view-source-info
     "C-c C-v z" 'jan-switch-to-session-with-code
     "C-c C-v a" 'jan-source-hash
     "C-c C-v h" 'jan-babel-help
     "C-c C-v x" 'jan-edit-source
     "C-c C-t" 'jan-todo
     "C-c C-s" 'jan-schedule
     "C-c C-d" 'jan-deadline
     "C-c C-q" 'jan-set-tags
     "C-c C-w" 'jan-refile
     "C-c C-a" 'jan-attach
     "C-c C-e" 'jan-export
     "C-c |" 'jan-create-table
     "C-c C-x p" 'jan-set-property
     "C-c C-x e" 'jan-set-effort
     "C-c C-x C-i" 'jan-clock-in
     "C-c C-x C-o" 'jan-clock-out
     "C-c C-x C-q" 'jan-clock-cancel
     "C-c C-x C-r" 'jan-clock-report
     "C-c C-x C-a" 'jan-archive-subtree
     "C-c C-x a" 'jan-toggle-archive
     "C-c c" 'jan-capture
     "C-c a" 'jan-agenda
     "C-c l" 'jan-store-link
     "C-c j c" 'jan-cycle
     "C-c j g" 'jan-global-cycle
     "C-c j n" 'jan-next-heading
     "C-c j p" 'jan-previous-heading
     "C-c j a" 'jan-context-action
     "C-c j t" 'jan-todo
     "C-c j A" 'jan-agenda
     "C-c j r" 'jan-table-recalculate
     "C-c j e" 'jan-export
     "C-c j h" 'jan-help-at-point)
    #:provenance "Odra Factory Direct Jan map")
   (bundle:language-keymap
    #:id 'jan.modal
    #:languages '(jan)
    #:states '(normal)
    #:context 'language-context
    #:bindings
    (hash
     "normal:z a" 'jan-cycle
     "normal:z A" 'jan-global-cycle
     "normal:] h" 'jan-next-heading
     "normal:[ h" 'jan-previous-heading
     "normal:g a" 'jan-context-action
     "normal:g T" 'jan-todo
     "normal:g A" 'jan-agenda
     "normal:g R" 'jan-table-recalculate
     "normal:g E" 'jan-export
     "normal:g H" 'jan-help-at-point)
    #:provenance "Odra Factory Modal Jan map")))

(define factory-jan-language-bundle
  (bundle:language-support-bundle
   #:id 'org.odra.jan
   #:display-name "Jan Language Support"
   #:version "1.0.0"
   #:api-min "1.0.0"
   #:api-max "1.0.0"
   #:description
   "Factory Jan recognition, syntax, lossless analysis, structured editing, commands, and interaction maps."
   #:publisher 'odra
   #:source 'odra.factory
   #:targets factory-targets
   #:license "MIT"
   #:authorities
   (list (bundle:language-bundle-authority 'native-grammar))
   #:languages
   (list (language:language
          #:id 'jan
          #:display-name "Jan"
          #:suffixes '(".org" ".jan")))
   #:syntax-providers (list jan-syntax)
   #:commands jan-commands
   #:keymaps jan-keymaps
   #:artifacts jan-artifacts
   #:provenance
   "Odra Factory; tree-sitter 0.26.12; jan-org-9.8.10-v1; native Jan analysis"))

(define racket-artifacts
  (list
   (artifact
    'racket.grammar 'tree-sitter-grammar
    "third_party/tree-sitter-racket/0.25.0/src/parser.c"
    "3cbab79ab9bd99684a7de4cb93a0aafd6773bb3ecf6720c59f1b7cdb0ceddd9c"
    404149
    'native-grammar)
   (artifact
    'racket.scanner 'data
    "third_party/tree-sitter-racket/0.25.0/src/scanner.c"
    "7285b6a4175ff0a58db1c97ed4f3756fcef8fc1f3d24f5c1a5a466ee27ea4a2a"
    4245)
   (artifact
    'racket.highlights 'query
    "third_party/tree-sitter-racket/0.25.0/queries/highlights.scm"
    "01792cd742c91d4f0a93ab8e16214ea47587647b6824207034f118210504c07e"
    42852)
   (artifact
    'racket.license 'license
    "third_party/tree-sitter-racket/0.25.0/LICENSE"
    "cc35bd4a973bf6067558e88b56d9a369e02c36e240b2b537aef8f751b7808fd7"
    1062)
   (artifact
    'racket.documentation 'documentation
    "third_party/tree-sitter-racket/0.25.0/README.md"
    "ecb157bff0911b1e316c1f5733f0a6fdef91464654ce31d0bd5675742b04bf59"
    1687)
   (artifact
    'racket.setup 'documentation
    "assets/language-bundles/factory/racket/setup.md"
    "539796db1ebcfee9594cef33422e61c28e7a0bc60cfb0122afacc0d585710a80"
    596)))

(define racket-captures
  (hasheq
   'comment 'comment
   'constant 'constant
   'constant.builtin 'constant
   'escape 'escape
   'function 'function
   'function.builtin 'function
   'keyword 'keyword
   'number 'number
   'operator 'operator
   'punctuation.bracket 'punctuation
   'string 'string
   'string.special 'string
   'variable 'variable
   'variable.builtin 'variable
   'variable.parameter 'parameter))

(define racket-syntax
  (bundle:tree-sitter-syntax-provider
   #:id 'racket.syntax
   #:languages '(racket)
   #:grammar-artifact 'racket.grammar
   #:grammar-symbol "tree_sitter_racket"
   #:abi-min 15
   #:abi-max 15
   #:query-artifacts '(racket.highlights)
   #:captures racket-captures
   #:resource-profile 'ordinary
   #:authority 'native-grammar))

(define racket-service
  (language:language-service
   #:id 'racket-langserver
   #:display-name "Racket Language Server"
   #:languages '(racket)
   #:command '("racket" "-l" "racket-langserver")
   #:root-markers '("info.rkt")
   #:features
   '(diagnostics completion navigation hover references symbols signature-help
                 rename formatting semantic-tokens code-actions)
   #:enabled? #t
   #:default? #t))

(define racket-formatter
  (bundle:language-formatter
   #:id 'racket.language-server-format
   #:languages '(racket)
   #:kind 'language-service
   #:service 'racket-langserver
   #:root-markers '("info.rkt")
   #:scopes '(buffer range)
   #:input 'text
   #:output 'text-edits))

(define factory-racket-language-bundle
  (bundle:language-support-bundle
   #:id 'org.odra.racket
   #:display-name "Racket Language Support"
   #:version "1.0.0"
   #:api-min "1.0.0"
   #:api-max "1.0.0"
   #:description
   "Factory Racket recognition and syntax support for the default readtable."
   #:publisher 'odra
   #:source 'odra.factory
   #:targets factory-targets
   #:license "MIT"
   #:authorities
   (list (bundle:language-bundle-authority 'native-grammar)
         (bundle:language-bundle-authority 'external-process))
   #:languages
   (list (language:language
          #:id 'racket
          #:display-name "Racket"
          #:suffixes '(".rkt")))
   #:syntax-providers (list racket-syntax)
   #:services (list racket-service)
   #:formatters (list racket-formatter)
   #:artifacts racket-artifacts
   #:provenance
   "Odra Factory; tree-sitter 0.26.12; tree-sitter-racket 0.25.0; default readtable only"))

(define go-artifacts
  (list
   (artifact
    'go.grammar 'tree-sitter-grammar
    "third_party/tree-sitter-go/0.25.0/src/parser.c"
    "3dbf6ed1238b5dfcf2be4d2f2d4cb27a14d34f34d7784eccccbfd532fd4a6d85"
    1572685
    'native-grammar)
   (artifact
    'go.highlights 'query
    "third_party/tree-sitter-go/0.25.0/queries/highlights.scm"
    "81182c986547eba7fa6316e82dfd621fb13b8fc89efac85432aee51a48ed0896"
    1421)
   (artifact
    'go.license 'license
    "third_party/tree-sitter-go/0.25.0/LICENSE"
    "2e0110e07abef7c2548b26ec9d6969775617ca539a0dc8dbeeb14d6452c711d1"
    1080)
   (artifact
    'go.documentation 'documentation
    "third_party/tree-sitter-go/0.25.0/README.md"
    "37e2434348fcf0f67520f55fe71090b72d23ebfedb453c351492ec6e11bcb4d2"
    1012)
   (artifact
    'go.setup 'documentation
    "assets/language-bundles/factory/go/setup.md"
    "ae541a8e747384cb1bbba23ab18921162461838073c262f6a40abbcd721d3ce5"
    454)))

(define go-captures
  (hasheq
   'comment 'comment
   'constant.builtin 'constant
   'escape 'escape
   'function 'function
   'function.builtin 'function
   'function.method 'function
   'keyword 'keyword
   'number 'number
   'operator 'operator
   'property 'variable
   'punctuation.bracket 'punctuation
   'string 'string
   'type 'type
   'variable 'variable))

(define go-syntax
  (bundle:tree-sitter-syntax-provider
   #:id 'go.syntax
   #:languages '(go)
   #:grammar-artifact 'go.grammar
   #:grammar-symbol "tree_sitter_go"
   #:abi-min 15
   #:abi-max 15
   #:query-artifacts '(go.highlights)
   #:captures go-captures
   #:resource-profile 'ordinary
   #:authority 'native-grammar))

(define go-service
  (language:language-service
   #:id 'gopls
   #:display-name "gopls"
   #:languages '(go)
   #:command '("gopls" "serve")
   #:root-markers '("go.work" "go.mod")
   #:features
   '(diagnostics completion navigation hover references symbols signature-help
                 rename formatting semantic-tokens code-actions)
   #:enabled? #t
   #:default? #t))

(define go-formatter
  (bundle:language-formatter
   #:id 'go.language-server-format
   #:languages '(go)
   #:kind 'language-service
   #:service 'gopls
   #:root-markers '("go.work" "go.mod")
   #:scopes '(buffer range)
   #:input 'text
   #:output 'text-edits))

(define factory-go-language-bundle
  (bundle:language-support-bundle
   #:id 'org.odra.go
   #:display-name "Go Language Support"
   #:version "1.0.0"
   #:api-min "1.0.0"
   #:api-max "1.0.0"
   #:description "Factory Go recognition and syntax support."
   #:publisher 'odra
   #:source 'odra.factory
   #:targets factory-targets
   #:license "BSD-3-Clause"
   #:authorities
   (list (bundle:language-bundle-authority 'native-grammar)
         (bundle:language-bundle-authority 'external-process))
   #:languages
   (list (language:language
          #:id 'go
          #:display-name "Go"
          #:suffixes '(".go")))
   #:syntax-providers (list go-syntax)
   #:services (list go-service)
   #:formatters (list go-formatter)
   #:artifacts go-artifacts
   #:provenance
   "Odra Factory; tree-sitter 0.26.12; tree-sitter-go 0.25.0"))

(define rust-artifacts
  (list
   (artifact
    'rust.grammar 'tree-sitter-grammar
    "third_party/tree-sitter-rust/0.24.2/src/parser.c"
    "9602518f9e57919910bf0e777e52f6bfc9325d4c182e998bdb4efd5682b76e4a"
    6505510
    'native-grammar)
   (artifact
    'rust.scanner 'data
    "third_party/tree-sitter-rust/0.24.2/src/scanner.c"
    "9609a2f92dbb7c32bc056fd8fb94e5478428f04496696aa08b048a9b66caf283"
    12588)
   (artifact
    'rust.syntax-query 'query
    "assets/language-bundles/factory/rust/highlights-and-structure.scm"
    "c74bc02e55c555366d91c1d3739cc9bf75104ae5000b7d78761852c37245111c"
    4592)
   (artifact
    'rust.upstream-highlights 'query
    "third_party/tree-sitter-rust/0.24.2/queries/highlights.scm"
    "0f0343107f14a7690157f51090a979eb8f8bfe4eada7c61763ddb4c54b1311d1"
    3527)
   (artifact
    'rust.injections 'query
    "third_party/tree-sitter-rust/0.24.2/queries/injections.scm"
    "723146f179bc0edfba2f51731c99afce8bed3b677dfb4435c303859fae299ba5"
    247)
   (artifact
    'rust.tags 'query
    "third_party/tree-sitter-rust/0.24.2/queries/tags.scm"
    "f22867fdebde5cb091861c08d34690dc2540f4318068bf81be9f6b0d348ab8c1"
    1194)
   (artifact
    'rust.license 'license
    "third_party/tree-sitter-rust/0.24.2/LICENSE"
    "31d5b6f4243d5c7c6e1c4ebbbb9f6407bd1457a08bcc4f706521710341acba36"
    1080)
   (artifact
    'rust.documentation 'documentation
    "third_party/tree-sitter-rust/0.24.2/README.md"
    "2d9ed9b99c93d7a48a3d4f0c3e957f12100eee0d8bb2c3e0a136926312d0e9f5"
    2066)
   (artifact
    'rust.setup 'documentation
    "assets/language-bundles/factory/rust/setup.md"
    "8342cd686ffd0a41a8ad48dc885e6eafc954e99fb2da11f4f0cf59b33364349c"
    596)))

(define rust-captures
  (hasheq
   'attribute 'attribute
   'comment 'comment
   'comment.documentation 'comment
   'constant 'constant
   'constant.builtin 'constant
   'constructor 'constructor
   'escape 'string
   'function 'function
   'function.macro 'function
   'function.method 'function
   'keyword 'keyword
   'label 'label
   'operator 'operator
   'property 'variable
   'punctuation.bracket 'punctuation
   'punctuation.delimiter 'punctuation
   'string 'string
   'structure.declaration 'type
   'structure.definition 'function
   'structure.name 'variable
   'structure.reference 'variable
   'type 'type
   'type.builtin 'type
   'variable.builtin 'variable
   'variable.parameter 'parameter))

(define rust-syntax
  (bundle:tree-sitter-syntax-provider
   #:id 'rust.syntax
   #:languages '(rust)
   #:grammar-artifact 'rust.grammar
   #:grammar-symbol "tree_sitter_rust"
   #:abi-min 15
   #:abi-max 15
   #:query-artifacts '(rust.syntax-query)
   #:captures rust-captures
   #:resource-profile 'ordinary
   #:authority 'native-grammar))

(define rust-service
  (language:language-service
   #:id 'rust-analyzer
   #:display-name "rust-analyzer"
   #:languages '(rust)
   #:command '("rust-analyzer")
   #:root-markers '("Cargo.toml")
   #:features
   '(diagnostics completion navigation hover references symbols signature-help
                 rename formatting semantic-tokens code-actions)
   #:enabled? #t
   #:default? #t))

(define rust-formatter
  (bundle:language-formatter
   #:id 'rust.language-server-format
   #:languages '(rust)
   #:kind 'language-service
   #:service 'rust-analyzer
   #:root-markers '("Cargo.toml")
   #:scopes '(buffer range)
   #:input 'text
   #:output 'text-edits))

(define factory-rust-language-bundle
  (bundle:language-support-bundle
   #:id 'org.odra.rust
   #:display-name "Rust Language Support"
   #:version "1.0.0"
   #:api-min "1.0.0"
   #:api-max "1.0.0"
   #:description
   "Factory Rust recognition, syntax, structure, rust-analyzer, and formatting."
   #:publisher 'odra
   #:source 'odra.factory
   #:targets factory-targets
   #:license "MIT"
   #:authorities
   (list (bundle:language-bundle-authority 'native-grammar)
         (bundle:language-bundle-authority 'external-process))
   #:languages
   (list (language:language
          #:id 'rust
          #:display-name "Rust"
          #:suffixes '(".rs")))
   #:syntax-providers (list rust-syntax)
   #:services (list rust-service)
   #:formatters (list rust-formatter)
   #:artifacts rust-artifacts
   #:provenance
   "Odra Factory; tree-sitter 0.26.12; tree-sitter-rust 0.24.2"))

(define javascript-artifacts
  (list
   (artifact 'javascript.grammar 'tree-sitter-grammar
             "third_party/tree-sitter-javascript/0.25.0/src/parser.c"
             "67209ca7ef6e1a4f74e29e48b5928455f892fe1821a3960fbcd62f4e972f7384"
             2855934 'native-grammar)
   (artifact 'javascript.scanner 'data
             "third_party/tree-sitter-javascript/0.25.0/src/scanner.c"
             "b3d3f64284d97bf80749c026862427782cf7ecc0b7dc094e6698ab311c9a42c7"
             10576)
   (artifact 'javascript.highlights 'query
             "assets/language-bundles/factory/javascript/highlights.scm"
             "e6484bd90a7c805ac971b74e17666b1011471fbb55e389ec6d0129461a7e80d0"
             2902)
   (artifact 'javascript.jsx-highlights 'query
             "assets/language-bundles/factory/javascript/highlights-jsx.scm"
             "760280d87386e98dff95a1b4379958b1ee0e0a5d3cba60ff73dd62a64788fcbc"
             3420)
   (artifact 'javascript.license 'license
             "third_party/tree-sitter-javascript/0.25.0/LICENSE"
             "2e0110e07abef7c2548b26ec9d6969775617ca539a0dc8dbeeb14d6452c711d1"
             1080)
   (artifact 'javascript.setup 'documentation
             "assets/language-bundles/factory/javascript/setup.md"
             "708321d560fcbe298cdaf5efb5967d36892d410034a0c3f76442e6eb51a7c9fa"
             587)))

(define javascript-captures
  (hasheq 'attribute 'attribute 'comment 'comment 'constant 'constant
          'constant.builtin 'constant 'constructor 'constructor
          'embedded 'string 'function 'function 'function.builtin 'function
          'function.method 'function 'keyword 'keyword 'number 'number
          'operator 'operator 'property 'variable 'punctuation.bracket 'punctuation
          'punctuation.delimiter 'punctuation 'punctuation.special 'punctuation
          'string 'string 'string.special 'string 'tag 'type
          'variable 'variable 'variable.builtin 'variable))

(define javascript-syntax
  (bundle:tree-sitter-syntax-provider
   #:id 'javascript.syntax #:languages '(javascript)
   #:grammar-artifact 'javascript.grammar #:grammar-symbol "tree_sitter_javascript"
   #:abi-min 15 #:abi-max 15 #:query-artifacts '(javascript.highlights)
   #:captures javascript-captures #:resource-profile 'ordinary
   #:authority 'native-grammar))

(define javascript-jsx-syntax
  (bundle:tree-sitter-syntax-provider
   #:id 'javascript.jsx-syntax #:languages '(javascript)
   #:grammar-artifact 'javascript.grammar #:grammar-symbol "tree_sitter_javascript"
   #:abi-min 15 #:abi-max 15 #:query-artifacts '(javascript.jsx-highlights)
   #:captures javascript-captures #:resource-profile 'ordinary
   #:authority 'native-grammar))

(define javascript-service
  (language:language-service
   #:id 'typescript-language-server #:display-name "TypeScript Language Server"
   #:languages '(javascript) #:command '("typescript-language-server" "--stdio")
   #:root-markers '("tsconfig.json" "jsconfig.json" "package.json")
   #:features
   '(diagnostics completion navigation hover references symbols signature-help
                 rename formatting semantic-tokens code-actions)
   #:enabled? #t #:default? #t))

(define javascript-formatter
  (bundle:language-formatter
   #:id 'javascript.language-server-format #:languages '(javascript)
   #:kind 'language-service #:service 'typescript-language-server
   #:root-markers '("tsconfig.json" "jsconfig.json" "package.json")
   #:scopes '(buffer range) #:input 'text #:output 'text-edits))

(define factory-javascript-language-bundle
  (bundle:language-support-bundle
   #:id 'org.odra.javascript #:display-name "JavaScript Language Support"
   #:version "1.0.0" #:api-min "1.0.0" #:api-max "1.0.0"
   #:description "Factory JavaScript and JSX recognition and syntax support."
   #:publisher 'odra #:source 'odra.factory #:targets factory-targets
   #:license "MIT"
   #:authorities
   (list (bundle:language-bundle-authority 'native-grammar)
         (bundle:language-bundle-authority 'external-process))
   #:languages
   (list (language:language #:id 'javascript #:display-name "JavaScript"
                            #:suffixes '(".js" ".jsx" ".mjs" ".cjs")))
   #:syntax-providers (list javascript-syntax javascript-jsx-syntax)
   #:services (list javascript-service)
   #:formatters (list javascript-formatter)
   #:artifacts javascript-artifacts
   #:provenance
   "Odra Factory; tree-sitter 0.26.12; tree-sitter-javascript 0.25.0"))

(define typescript-artifacts
  (list
   (artifact 'typescript.grammar 'tree-sitter-grammar
             "third_party/tree-sitter-typescript/0.23.2/typescript/src/parser.c"
             "74fe453edd70f4eae9af0a1050cbd7943d8971d59165b6aaebbaa0a0b716d1aa"
             8745894 'native-grammar)
   (artifact 'typescript.scanner 'data
             "third_party/tree-sitter-typescript/0.23.2/typescript/src/scanner.c"
             "9125013b42cb888379d9be909f1d73dfb75a37626c2cdbf4122718a2b431a6d3"
             573)
   (artifact 'typescript.tsx-grammar 'tree-sitter-grammar
             "third_party/tree-sitter-typescript/0.23.2/tsx/src/parser.c"
             "1902cb53fa7ff5179df89b2eea863165e84c8cc866226419dc26921d8c055885"
             8769870 'native-grammar)
   (artifact 'typescript.tsx-scanner 'data
             "third_party/tree-sitter-typescript/0.23.2/tsx/src/scanner.c"
             "d563cd30b2f39718c9ae4292795c5ce03a2ad01954ba3a86ef84c2781a736673"
             538)
   (artifact 'typescript.highlights 'query
             "assets/language-bundles/factory/typescript/highlights.scm"
             "574e8df3e4dec3fb9c274363eaaff775259fd7582c709dbb8abafe416cda9b9e"
             3494)
   (artifact 'typescript.tsx-highlights 'query
             "assets/language-bundles/factory/typescript/highlights-tsx.scm"
             "c2ac0b8c0f927df3e27ac197267eee86e5e0968f112d6ebafc4403e14182bfeb"
             4012)
   (artifact 'typescript.license 'license
             "third_party/tree-sitter-typescript/0.23.2/LICENSE"
             "49bf33cf78ef5897e4e161ce1517df7de1ae5042a65b6bcfd44401e0fc606559"
             1080)
   (artifact 'typescript.setup 'documentation
             "assets/language-bundles/factory/typescript/setup.md"
             "3ea1a3529b477ab880bd552021c2b2cfe5e91d6e53bed7aa08792f074b6c3d9b"
             587)))

(define typescript-captures
  (hash-set* javascript-captures
             'type 'type 'type.builtin 'type
             'variable.parameter 'parameter))

(define typescript-syntax
  (bundle:tree-sitter-syntax-provider
   #:id 'typescript.syntax #:languages '(typescript)
   #:grammar-artifact 'typescript.grammar #:grammar-symbol "tree_sitter_typescript"
   #:abi-min 14 #:abi-max 14 #:query-artifacts '(typescript.highlights)
   #:captures typescript-captures #:resource-profile 'ordinary
   #:authority 'native-grammar))

(define typescript-tsx-syntax
  (bundle:tree-sitter-syntax-provider
   #:id 'typescript.tsx-syntax #:languages '(typescript)
   #:grammar-artifact 'typescript.tsx-grammar #:grammar-symbol "tree_sitter_tsx"
   #:abi-min 14 #:abi-max 14 #:query-artifacts '(typescript.tsx-highlights)
   #:captures typescript-captures #:resource-profile 'ordinary
   #:authority 'native-grammar))

(define typescript-service
  (language:language-service
   #:id 'typescript-language-server #:display-name "TypeScript Language Server"
   #:languages '(typescript) #:command '("typescript-language-server" "--stdio")
   #:root-markers '("tsconfig.json" "jsconfig.json" "package.json")
   #:features
   '(diagnostics completion navigation hover references symbols signature-help
                 rename formatting semantic-tokens code-actions)
   #:enabled? #t #:default? #t))

(define typescript-formatter
  (bundle:language-formatter
   #:id 'typescript.language-server-format #:languages '(typescript)
   #:kind 'language-service #:service 'typescript-language-server
   #:root-markers '("tsconfig.json" "jsconfig.json" "package.json")
   #:scopes '(buffer range) #:input 'text #:output 'text-edits))

(define factory-typescript-language-bundle
  (bundle:language-support-bundle
   #:id 'org.odra.typescript #:display-name "TypeScript Language Support"
   #:version "1.0.0" #:api-min "1.0.0" #:api-max "1.0.0"
   #:description "Factory TypeScript and TSX recognition and syntax support."
   #:publisher 'odra #:source 'odra.factory #:targets factory-targets
   #:license "MIT"
   #:authorities
   (list (bundle:language-bundle-authority 'native-grammar)
         (bundle:language-bundle-authority 'external-process))
   #:languages
   (list (language:language #:id 'typescript #:display-name "TypeScript"
                            #:suffixes '(".ts" ".tsx" ".mts" ".cts")))
   #:syntax-providers (list typescript-syntax typescript-tsx-syntax)
   #:services (list typescript-service)
   #:formatters (list typescript-formatter)
   #:artifacts typescript-artifacts
   #:provenance
   "Odra Factory; tree-sitter 0.26.12; tree-sitter-typescript 0.23.2"))

(define html-artifacts
  (list
   (artifact 'html.grammar 'tree-sitter-grammar
             "third_party/tree-sitter-html/0.23.2/src/parser.c"
             "65768172733b3bbe461cbdc14ea928f00fbfcc51d8ac68f0a5c72071c6a0bbf1"
             66466 'native-grammar)
   (artifact 'html.scanner 'data "third_party/tree-sitter-html/0.23.2/src/scanner.c"
             "5c0a0567e010277b81fe63be0acd04f6b44c3ef3063ac01429b910c1d22f0dca" 10796)
   (artifact 'html.highlights 'query "assets/language-bundles/factory/html/highlights.scm"
             "545f7d948f1eb66cea8ee20c2f4199c1602c2aa16ec2bc2fb4c7cb3560313a81" 354)
   (artifact 'html.injections 'query
             "assets/language-bundles/factory/html/injections.scm"
             "df8e92ff4a4cebbe16f5a5f7c9926fbcb0c5fd894608f04e90cfea306bea753e" 97)
   (artifact 'html.license 'license "third_party/tree-sitter-html/0.23.2/LICENSE"
             "2e0110e07abef7c2548b26ec9d6969775617ca539a0dc8dbeeb14d6452c711d1" 1080)
   (artifact 'html.setup 'documentation "assets/language-bundles/factory/html/setup.md"
             "12f377eab3ca5094ece49ba84f9fa3c2d7a429755878477e98db51e15b5af503" 440)))

(define html-captures
  (hasheq 'attribute 'attribute 'comment 'comment 'constant 'constant
          'punctuation.bracket 'punctuation 'string 'string
          'tag 'type 'tag.error 'type
          'injection.javascript 'string 'injection.css 'string))

(define html-syntax
  (bundle:tree-sitter-syntax-provider
   #:id 'html.syntax #:languages '(html)
   #:grammar-artifact 'html.grammar #:grammar-symbol "tree_sitter_html"
   #:abi-min 14 #:abi-max 14 #:query-artifacts '(html.highlights html.injections)
   #:captures html-captures #:resource-profile 'ordinary
   #:authority 'native-grammar))

(define html-service
  (language:language-service
   #:id 'vscode-html-language-server #:display-name "HTML Language Server"
   #:languages '(html) #:command '("vscode-html-language-server" "--stdio")
   #:root-markers '("package.json")
   #:features '(diagnostics completion hover symbols formatting)
   #:enabled? #t #:default? #t))

(define html-formatter
  (bundle:language-formatter
   #:id 'html.language-server-format #:languages '(html)
   #:kind 'language-service #:service 'vscode-html-language-server
   #:root-markers '("package.json") #:scopes '(buffer range)
   #:input 'text #:output 'text-edits))

(define factory-html-language-bundle
  (bundle:language-support-bundle
   #:id 'org.odra.html #:display-name "HTML Language Support"
   #:version "1.0.0" #:api-min "1.0.0" #:api-max "1.0.0"
   #:description "Factory HTML recognition, syntax, and embedded-region declarations."
   #:publisher 'odra #:source 'odra.factory #:targets factory-targets #:license "MIT"
   #:authorities
   (list (bundle:language-bundle-authority 'native-grammar)
         (bundle:language-bundle-authority 'external-process))
   #:languages (list (language:language #:id 'html #:display-name "HTML"
                                        #:suffixes '(".html" ".htm")))
   #:syntax-providers (list html-syntax) #:services (list html-service)
   #:formatters (list html-formatter) #:artifacts html-artifacts
   #:provenance "Odra Factory; tree-sitter 0.26.12; tree-sitter-html 0.23.2"))

(define css-artifacts
  (list
   (artifact 'css.grammar 'tree-sitter-grammar
             "third_party/tree-sitter-css/0.25.0/src/parser.c"
             "2e5150071220012ee635ac9e2119f4f3a93e0b51a7a3b69ab0cd87c18cf5e51e"
             504262 'native-grammar)
   (artifact 'css.scanner 'data "third_party/tree-sitter-css/0.25.0/src/scanner.c"
             "18dae8c8c4f515f28a3dc7ffb5bda259b06013a752921dc411a2fad8ecf78988" 3469)
   (artifact 'css.highlights 'query "assets/language-bundles/factory/css/highlights.scm"
             "723a269eb5ef54d0342e256697de9f6130c17a2435f10af4a273968bbae0ee6f" 1333)
   (artifact 'css.license 'license "third_party/tree-sitter-css/0.25.0/LICENSE"
             "c5cfb43042b6b72045f4ba997834d0a7786d2793d91680868b5815b39f14fc78" 1080)
   (artifact 'css.setup 'documentation "assets/language-bundles/factory/css/setup.md"
             "6422238ff6769b64da21299ea4a2888341730c93aade4e5c8591dc558d3b4b24" 401)))

(define css-captures
  (hasheq 'attribute 'attribute 'charset 'keyword 'comment 'comment
          'function 'function 'import 'keyword 'keyframes 'keyword
          'keyword 'keyword 'media 'keyword 'namespace 'type 'number 'number
          'operator 'operator 'property 'variable 'punctuation.bracket 'punctuation
          'punctuation.delimiter 'punctuation 'string 'string
          'string.special 'string 'supports 'keyword 'tag 'type
          'type 'type 'variable 'variable))

(define css-syntax
  (bundle:tree-sitter-syntax-provider
   #:id 'css.syntax #:languages '(css)
   #:grammar-artifact 'css.grammar #:grammar-symbol "tree_sitter_css"
   #:abi-min 15 #:abi-max 15 #:query-artifacts '(css.highlights)
   #:captures css-captures #:resource-profile 'ordinary
   #:authority 'native-grammar))

(define css-service
  (language:language-service
   #:id 'vscode-css-language-server #:display-name "CSS Language Server"
   #:languages '(css) #:command '("vscode-css-language-server" "--stdio")
   #:root-markers '("package.json")
   #:features '(diagnostics completion hover symbols formatting)
   #:enabled? #t #:default? #t))

(define css-formatter
  (bundle:language-formatter
   #:id 'css.language-server-format #:languages '(css)
   #:kind 'language-service #:service 'vscode-css-language-server
   #:root-markers '("package.json") #:scopes '(buffer range)
   #:input 'text #:output 'text-edits))

(define factory-css-language-bundle
  (bundle:language-support-bundle
   #:id 'org.odra.css #:display-name "CSS Language Support"
   #:version "1.0.0" #:api-min "1.0.0" #:api-max "1.0.0"
   #:description "Factory CSS recognition and syntax support."
   #:publisher 'odra #:source 'odra.factory #:targets factory-targets #:license "MIT"
   #:authorities
   (list (bundle:language-bundle-authority 'native-grammar)
         (bundle:language-bundle-authority 'external-process))
   #:languages (list (language:language #:id 'css #:display-name "CSS"
                                        #:suffixes '(".css")))
   #:syntax-providers (list css-syntax) #:services (list css-service)
   #:formatters (list css-formatter) #:artifacts css-artifacts
   #:provenance "Odra Factory; tree-sitter 0.26.12; tree-sitter-css 0.25.0"))

(define (factory-language-bundles)
  (list factory-jan-language-bundle
        factory-odin-language-bundle
        factory-racket-language-bundle
        factory-go-language-bundle
        factory-rust-language-bundle
        factory-javascript-language-bundle
        factory-typescript-language-bundle
        factory-html-language-bundle
        factory-css-language-bundle))

(define (factory-language-bundle-find id)
  (findf
   (lambda (value)
     (eq? id (bundle:odra-language-support-bundle-id value)))
   (factory-language-bundles)))

(module+ test
  (require rackunit
           (prefix-in bridge: "../hosting/language-bundle-bridge.rkt"))

  (test-case "Odin Factory support is one validated bundle"
    (check-eq? (bundle:odra-language-support-bundle-id
                factory-odin-language-bundle)
               'org.odra.odin)
    (check-equal?
     (map language:odra-language-id
          (bundle:odra-language-support-bundle-languages
           factory-odin-language-bundle))
     '(odin))
    (check-equal?
     (map bundle:odra-tree-sitter-syntax-provider-id
          (bundle:odra-language-support-bundle-syntax-providers
           factory-odin-language-bundle))
     '(odin.syntax))
    (check-equal?
     (map language:odra-language-service-id
          (bundle:odra-language-support-bundle-services
           factory-odin-language-bundle))
     '(ols))
    (check-equal? (length odin-commands) 13)
    (check-equal? (length odin-keymaps) 2))

  (test-case "Odin Factory manifest crosses the generic native bridge"
    (define encoded
      (bridge:language-bundle-encode factory-odin-language-bundle))
    (check-true (immutable? encoded))
    (check-equal?
     (bridge:language-bundle-digest factory-odin-language-bundle)
     (bridge:language-bundle-digest factory-odin-language-bundle))
    (check-true (positive? (bytes-length encoded))))

  (test-case "Odin Factory metadata preserves selectors and exact artifacts"
    (define language
      (car (bundle:odra-language-support-bundle-languages
            factory-odin-language-bundle)))
    (check-equal? (language:odra-language-suffixes language) '(".odin"))
    (check-equal?
     (bundle:odra-tree-sitter-syntax-provider-grammar-symbol odin-syntax)
     "tree_sitter_odin")
    (check-equal?
     (hash-ref odin-captures 'keyword)
     'keyword)
    (check-equal?
     (map bundle:odra-language-bundle-artifact-id odin-artifacts)
     '(odin.grammar odin.scanner odin.highlights odin.license)))

  (test-case "Jan Factory support retains uniform discovery and native capabilities"
    (check-eq? (bundle:odra-language-support-bundle-id
                factory-jan-language-bundle)
               'org.odra.jan)
    (define language
      (car (bundle:odra-language-support-bundle-languages
            factory-jan-language-bundle)))
    (check-equal? (language:odra-language-suffixes language)
                  '(".org" ".jan"))
    (check-equal? (length jan-commands) 91)
    (check-equal? (length jan-keymaps) 2)
    (check-equal?
     (bundle:odra-tree-sitter-syntax-provider-grammar-symbol jan-syntax)
     "tree_sitter_jan")
    (check-not-false
     (member 'jan-insert-drawer
             (map bundle:odra-language-command-id jan-commands)))
    (check-not-false
     (member 'jan-align-table
             (map bundle:odra-language-command-id jan-commands))))

  (test-case "Racket Factory support declares one complete service profile"
    (check-equal? (language:odra-language-service-command racket-service)
                  '("racket" "-l" "racket-langserver"))
    (check-equal? (language:odra-language-service-root-markers racket-service)
                  '("info.rkt"))
    (check-not-false
     (member 'semantic-tokens
             (language:odra-language-service-features racket-service)))
    (check-eq? (bundle:odra-language-formatter-service racket-formatter)
               'racket-langserver)
    (check-equal? (bundle:odra-language-formatter-scopes racket-formatter)
                  '(buffer range)))

  (test-case "Go Factory support declares one complete service profile"
    (check-equal? (language:odra-language-service-command go-service)
                  '("gopls" "serve"))
    (check-equal? (language:odra-language-service-root-markers go-service)
                  '("go.work" "go.mod"))
    (check-not-false
     (member 'formatting
             (language:odra-language-service-features go-service)))
    (check-eq? (bundle:odra-language-formatter-service go-formatter) 'gopls)
    (check-equal? (bundle:odra-language-formatter-scopes go-formatter)
                  '(buffer range)))

  (test-case "Rust Factory support declares pinned syntax and structure"
    (check-eq? (bundle:odra-language-support-bundle-id
                factory-rust-language-bundle)
               'org.odra.rust)
    (check-equal?
     (map language:odra-language-suffixes
          (bundle:odra-language-support-bundle-languages
           factory-rust-language-bundle))
     '((".rs")))
    (check-equal?
     (bundle:odra-tree-sitter-syntax-provider-grammar-symbol rust-syntax)
     "tree_sitter_rust")
    (check-equal?
     (bundle:odra-tree-sitter-syntax-provider-query-artifacts rust-syntax)
     '(rust.syntax-query))
    (check-equal?
     (map bundle:odra-language-bundle-artifact-id rust-artifacts)
     '(rust.grammar rust.scanner rust.syntax-query rust.upstream-highlights
                    rust.injections rust.tags rust.license rust.documentation
                    rust.setup))
    (check-equal? (language:odra-language-service-command rust-service)
                  '("rust-analyzer"))
    (check-equal? (language:odra-language-service-root-markers rust-service)
                  '("Cargo.toml"))
    (check-not-false
     (member 'formatting
             (language:odra-language-service-features rust-service)))
    (check-eq? (bundle:odra-language-formatter-service rust-formatter)
               'rust-analyzer)
    (check-equal? (bundle:odra-language-formatter-scopes rust-formatter)
                  '(buffer range)))

  (test-case "Factory bundle discovery is stable and shared"
    (check-equal?
     (map bundle:odra-language-support-bundle-id (factory-language-bundles))
     '(org.odra.jan org.odra.odin org.odra.racket org.odra.go org.odra.rust
                    org.odra.javascript org.odra.typescript org.odra.html
                    org.odra.css))
    (check-eq? (factory-language-bundle-find 'org.odra.jan)
               factory-jan-language-bundle)
    (check-false (factory-language-bundle-find 'org.odra.unknown))
    (check-true
     (positive?
      (bytes-length
       (bridge:language-bundle-encode factory-jan-language-bundle))))))
