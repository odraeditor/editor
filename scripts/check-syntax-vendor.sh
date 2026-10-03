#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Adrian PK
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Odra. See COPYING for license terms.

set -euo pipefail

runtime_dir=third_party/tree-sitter/0.26.12
grammar_dir=third_party/tree-sitter-odin/1.3.0
racket_grammar_dir=third_party/tree-sitter-racket/0.25.0
go_grammar_dir=third_party/tree-sitter-go/0.25.0
rust_grammar_dir=third_party/tree-sitter-rust/0.24.2
javascript_grammar_dir=third_party/tree-sitter-javascript/0.25.0
typescript_grammar_dir=third_party/tree-sitter-typescript/0.23.2
html_grammar_dir=third_party/tree-sitter-html/0.23.2
css_grammar_dir=third_party/tree-sitter-css/0.25.0

sha256sum --check "$runtime_dir/SHA256SUMS"
sha256sum --check "$grammar_dir/SHA256SUMS"
sha256sum --check "$racket_grammar_dir/SHA256SUMS"
sha256sum --check "$go_grammar_dir/SHA256SUMS"
sha256sum --check "$rust_grammar_dir/SHA256SUMS"
sha256sum --check "$javascript_grammar_dir/SHA256SUMS"
sha256sum --check "$typescript_grammar_dir/SHA256SUMS"
sha256sum --check "$html_grammar_dir/SHA256SUMS"
sha256sum --check "$css_grammar_dir/SHA256SUMS"

grep -Fq '#define TREE_SITTER_LANGUAGE_VERSION 15' \
  "$runtime_dir/lib/include/tree_sitter/api.h"
grep -Fq '#define TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION 13' \
  "$runtime_dir/lib/include/tree_sitter/api.h"
grep -Fq '#define LANGUAGE_VERSION 14' "$grammar_dir/src/parser.c"
grep -Fq '"version": "1.3.0"' "$grammar_dir/tree-sitter.json"
grep -Fq '"tree-sitter-cli": "^0.24.5"' "$grammar_dir/package.json"
grep -A2 -F '"node_modules/tree-sitter-cli": {' \
  "$grammar_dir/package-lock.json" | grep -Fq '"version": "0.24.5"'
grep -Fq '#define LANGUAGE_VERSION 15' "$racket_grammar_dir/src/parser.c"
grep -Fq '#define LANGUAGE_VERSION 15' "$go_grammar_dir/src/parser.c"
grep -Fq '#define LANGUAGE_VERSION 15' "$rust_grammar_dir/src/parser.c"
grep -Fq '"version": "0.25.0"' "$racket_grammar_dir/tree-sitter.json"
grep -Fq '"version": "0.25.0"' "$go_grammar_dir/tree-sitter.json"
grep -Fq '"version": "0.24.2"' "$rust_grammar_dir/tree-sitter.json"
grep -Fq '#define LANGUAGE_VERSION 15' "$javascript_grammar_dir/src/parser.c"
grep -Fq '#define LANGUAGE_VERSION 14' "$typescript_grammar_dir/typescript/src/parser.c"
grep -Fq '#define LANGUAGE_VERSION 14' "$typescript_grammar_dir/tsx/src/parser.c"
grep -Fq '#define LANGUAGE_VERSION 14' "$html_grammar_dir/src/parser.c"
grep -Fq '#define LANGUAGE_VERSION 15' "$css_grammar_dir/src/parser.c"
grep -Fq '"version": "0.25.0"' "$javascript_grammar_dir/tree-sitter.json"
grep -Fq '"version": "0.23.2"' "$typescript_grammar_dir/tree-sitter.json"
grep -Fq '"version": "0.23.2"' "$html_grammar_dir/tree-sitter.json"
grep -Fq '"version": "0.25.0"' "$css_grammar_dir/tree-sitter.json"

test -s "$grammar_dir/grammar.js"
test -s "$grammar_dir/src/grammar.json"
test -s "$grammar_dir/src/node-types.json"
test -s "$grammar_dir/src/parser.c"
test -s "$grammar_dir/src/scanner.c"
test -s "$grammar_dir/queries/highlights.scm"
test -s "$racket_grammar_dir/src/scanner.c"
test -s "$racket_grammar_dir/queries/highlights.scm"
test -s "$go_grammar_dir/queries/highlights.scm"
test -s "$rust_grammar_dir/src/scanner.c"
test -s "$rust_grammar_dir/queries/highlights.scm"
test -s "$rust_grammar_dir/queries/injections.scm"
test -s "$rust_grammar_dir/queries/tags.scm"
test -s "$javascript_grammar_dir/src/scanner.c"
test -s "$javascript_grammar_dir/queries/highlights.scm"
test -s "$javascript_grammar_dir/queries/highlights-jsx.scm"
test -s "$typescript_grammar_dir/typescript/src/scanner.c"
test -s "$typescript_grammar_dir/tsx/src/scanner.c"
test -s "$typescript_grammar_dir/queries/highlights.scm"
test -s "$html_grammar_dir/src/scanner.c"
test -s "$html_grammar_dir/queries/highlights.scm"
test -s "$html_grammar_dir/queries/injections.scm"
test -s "$css_grammar_dir/src/scanner.c"
test -s "$css_grammar_dir/queries/highlights.scm"

printf '%s\n' \
  'vendor=syntax valid=true offline=true' \
  'runtime_revision=v0.26.12 runtime_commit=808e4b1fc06e269a107c4bd8bd936cc6fde18b00 runtime_abi=15 minimum_abi=13' \
  'grammar_revision=v1.3.0 grammar_commit=e8adc739b78409a99f8c31313f0bb54cc538cf73 grammar_abi=14 generator=tree-sitter-cli-0.24.5' \
  'racket_grammar_revision=v0.25.0 racket_grammar_commit=b3cbbde75ce2de3079e33c7fe90bd41b1d45be48 racket_grammar_abi=15' \
  'go_grammar_revision=v0.25.0 go_grammar_commit=1547678a9da59885853f5f5cc8a99cc203fa2e2c go_grammar_abi=15' \
  'rust_grammar_revision=v0.24.2 rust_grammar_commit=77a3747266f4d621d0757825e6b11edcbf991ca5 rust_grammar_abi=15' \
  'javascript_grammar_revision=v0.25.0 javascript_grammar_commit=44c892e0be055ac465d5eeddae6d3e194424e7de javascript_grammar_abi=15' \
  'typescript_grammar_revision=v0.23.2 typescript_grammar_commit=f975a621f4e7f532fe322e13c4f79495e0a7b2e7 typescript_grammar_abi=14' \
  'html_grammar_revision=v0.23.2 html_grammar_commit=5a5ca8551a179998360b4a4ca2c0f366a35acc03 html_grammar_abi=14' \
  'css_grammar_revision=v0.25.0 css_grammar_commit=dda5cfc5722c429eaba1c910ca32c2c0c5bb1a3f css_grammar_abi=15'
