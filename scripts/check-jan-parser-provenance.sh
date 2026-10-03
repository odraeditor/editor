#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Adrian PK
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Odra. See COPYING for license terms.

set -euo pipefail

runtime_dir=third_party/tree-sitter/0.26.12
grammar_dir=third_party/tree-sitter-jan/jan-org-9.8.10-v1
factory_language_source=src/language/factory_languages.odin
factory_bundle_source=src/language_bundle/factory-bundles.rkt
application_workflow_source=src/syntax_workflow/syntax_workflow.odin
jan_workflow_source=src/syntax_workflow/jan_syntax_workflow.odin
foreign_source=src/language/tree_sitter_foreign.odin

sha256sum --check "$grammar_dir/SHA256SUMS"

grep -Fq '#define TREE_SITTER_LANGUAGE_VERSION 15' \
  "$runtime_dir/lib/include/tree_sitter/api.h"
grep -Fq '#define TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION 13' \
  "$runtime_dir/lib/include/tree_sitter/api.h"
grep -Fq '#define LANGUAGE_VERSION 15' "$grammar_dir/src/parser.c"
grep -Fq '"tree-sitter-cli": "0.26.9"' "$grammar_dir/package.json"
grep -Fq 'jan-org-9.8.10-v1' "$grammar_dir/README.md"
grep -Fq '"org"' "$grammar_dir/tree-sitter.json"
grep -Fq '"jan"' "$grammar_dir/tree-sitter.json"

test -s "$grammar_dir/grammar.js"
test -s "$grammar_dir/src/grammar.json"
test -s "$grammar_dir/src/node-types.json"
test -s "$grammar_dir/src/parser.c"
test -s "$grammar_dir/src/scanner.c"
test -s "$grammar_dir/bindings/c/tree-sitter-jan.h"

grep -Fq 'name = "factory-jan-tree-sitter"' "$factory_language_source"
grep -Fq 'parser_name = "tree-sitter-jan"' "$factory_language_source"
grep -Fq 'grammar_abi = TREE_SITTER_JAN_ABI' "$factory_language_source"
grep -Fq "#:id 'org.odra.jan" "$factory_bundle_source"
grep -Fq "#:suffixes '(\".org\" \".jan\")" "$factory_bundle_source"
grep -Fq 'factory_syntax_bundle_registrations' "$application_workflow_source"
grep -Fq 'candidate.bundle_identity = registration.bundle_identity' "$application_workflow_source"
grep -Fq 'odra_tree_sitter_factory_language' "$foreign_source"
if grep -Eq 'tree_sitter_(odin|jan) ::' "$foreign_source"; then
  printf '%s\n' 'grammar-specific Tree-sitter foreign declaration remains' >&2
  exit 1
fi
grep -Fq 'syntax_workflow_parse_jan_current' "$application_workflow_source"
grep -Fq 'jan_structural_owner_publish_initial' "$jan_workflow_source"

for node_type in \
  document zeroth_section heading section center_block quote_block \
  special_block drawer property_drawer dynamic_block footnote_definition \
  inline_task list_item plain_list pipe_table table_provider_form \
  source_block example_block export_block comment_block lesser_block clock \
  diary_expression planning_line line_comment fixed_width_area \
  horizontal_rule keyword affiliated_keyword latex_environment node_property \
  paragraph table_row table_separator_row table_cell recovery \
  entity special_symbol latex_fragment export_snippet \
  named_footnote_reference inline_footnote_reference \
  anonymous_footnote_reference citation citation_reference inline_call \
  inline_source explicit_line_break plain_link angle_link regular_link macro \
  target radio_target percentage_cookie fraction_cookie subscript superscript \
  point_timestamp active_timestamp inactive_timestamp diary_timestamp \
  timestamp_range repeating_timestamp delayed_timestamp bold_markup \
  italic_markup underline_markup verbatim_markup code_markup \
  strike_through_markup plain_text; do
  grep -Fq "\"type\": \"$node_type\"" "$grammar_dir/src/node-types.json"
done

printf '%s\n' \
  'parser=jan valid=true structural=true inline=true offline=true bundle_registered=true' \
  'baseline=jan-org-9.8.10-v1 syntax=org-syntax-v2 specification_commit=a0d1feaa414a0236f4fafc035cb890109d76c00a' \
  'runtime_revision=v0.26.12 runtime_abi=15 minimum_abi=13 generator=tree-sitter-cli-0.26.9 grammar_abi=15'
