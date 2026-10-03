#lang racket/base
; SPDX-FileCopyrightText: 2026 Adrian PK
; SPDX-License-Identifier: GPL-3.0-only
;
; This file is part of Odra. See COPYING for license terms.


(require racket/file
         racket/list
         racket/string
         "../tests/jan_document_language/reference-model.rkt")

(define contracts-path "src/language/jan_contracts.odin")
(define workflow-path "src/syntax_workflow/syntax_workflow.odin")
(define factory-language-path "src/language/factory_languages.odin")
(define factory-bundle-path "src/language_bundle/factory-bundles.rkt")
(define jan-workflow-path "src/syntax_workflow/jan_syntax_workflow.odin")
(define contracts-source (file->string contracts-path))
(define workflow-source (file->string workflow-path))
(define factory-language-source (file->string factory-language-path))
(define factory-bundle-source (file->string factory-bundle-path))
(define jan-workflow-source (file->string jan-workflow-path))
(define failures '())
(define JAN-BASELINE-FRAGMENT
  "JAN_BASELINE_NAME :: \"jan-org-9.8.10-v1\"")

(define (record-failure! message)
  (set! failures (cons message failures)))

(define (family->odin-name family)
  (string-join
   (map string-titlecase (string-split (symbol->string family) "-"))
   "_"))

(define (enum-line->name line)
  (string-trim (string-trim line) ","))

(define node-kind-parts
  (regexp-split #rx"Jan_Node_Kind :: enum u8" contracts-source))
(define node-kind-body
  (and (= (length node-kind-parts) 2)
       (first (regexp-split #rx"\n}" (second node-kind-parts)))))

(unless node-kind-body
  (record-failure! "Jan_Node_Kind declaration is missing"))

(when node-kind-body
  (define declared
    (for/list ([line (in-list (string-split node-kind-body "\n"))]
               #:when
               (let ([name (enum-line->name line)])
                 (and (not (string=? name ""))
                      (not (member name '("{"
                                          "Invalid"
                                          "Preserved_Whitespace"
                                          "Recovery"))))))
      (enum-line->name line)))
  (define expected
    (sort (map family->odin-name (append structural-families inline-families))
          string<?))
  (unless (equal? (sort declared string<?) expected)
    (record-failure! "Jan_Node_Kind does not match the fixture manifest")))

(define required-contract-fragments
  (list JAN-BASELINE-FRAGMENT
        "JAN_ORG_SYNTAX_VERSION :: \"Org Syntax v2\""
        "JAN_SPECIFICATION_COMMIT :: \"a0d1feaa414a0236f4fafc035cb890109d76c00a\""
        "MAX_JAN_NODES :: u32(1_048_576)"
        "MAX_JAN_STRUCTURAL_DEPTH :: u16(1_024)"
        "MAX_JAN_INLINE_DEPTH :: u16(256)"
        "MAX_JAN_ATTRIBUTES_PER_NODE :: u16(128)"
        "MAX_JAN_INDEX_FACTS :: u32(1_048_576)"
        "MAX_JAN_DIAGNOSTICS :: u32(4_096)"
        "MAX_JAN_INCREMENTAL_EDITS :: u32(16_384)"
        "MAX_JAN_REWRITE_SPLICES :: u32(16_384)"
        "MAX_JAN_MAINTENANCE_STEP_NS :: u64(50_000_000)"
        "MAX_JAN_CANDIDATE_NS :: u64(5_000_000_000)"))

(for ([fragment (in-list required-contract-fragments)])
  (unless (string-contains? contracts-source fragment)
    (record-failure! (format "Jan contract is missing: ~a" fragment))))

(unless (validate-fixture-manifest (load-fixture-manifest))
  (record-failure! "fixture manifest is incomplete or inconsistent"))

(unless (validate-resource-profiles resource-profiles)
  (record-failure! "resource profiles exceed the selected Jan policy"))

(for ([fragment
       (in-list
        '("factory-jan-tree-sitter"
          "tree-sitter-jan"
          "grammar_abi = TREE_SITTER_JAN_ABI"
          "FACTORY_JAN_BUNDLE_IDENTITY :: \"org.odra.jan\""))])
  (unless (string-contains? factory-language-source fragment)
    (record-failure! (format "factory Jan registration is missing: ~a" fragment))))

(for ([fragment
       (in-list
        '("#:id 'org.odra.jan"
          "#:suffixes '(\".org\" \".jan\")"
          "#:grammar-symbol \"tree_sitter_jan\""))])
  (unless (string-contains? factory-bundle-source fragment)
    (record-failure! (format "factory Jan bundle is missing: ~a" fragment))))

(for ([fragment
       (in-list
        '("factory_syntax_bundle_registrations"
          "candidate.bundle_identity = registration.bundle_identity"
          "syntax_workflow_parse_jan_current"
          "jan_structural_analysis_query_spans"))])
  (unless (string-contains? workflow-source fragment)
    (record-failure! (format "Jan application workflow is missing: ~a" fragment))))

(for ([fragment
       (in-list
        '("jan_structural_owner_publish_initial"
          "jan_structural_owner_analyze_incremental_configured"
          "syntax_workflow_set_jan_configuration"))])
  (unless (string-contains? jan-workflow-source fragment)
    (record-failure! (format "Jan analysis coordination is missing: ~a" fragment))))

(unless (null? failures)
  (for-each displayln (reverse failures))
  (exit 1))

(printf
 "Checked Jan baseline, 72 syntax families, selected resource limits, and Factory bundle registration.\n")
