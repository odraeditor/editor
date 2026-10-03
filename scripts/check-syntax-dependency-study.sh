#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Adrian PK
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Odra. See COPYING for license terms.

set -euo pipefail

runtime_revision=v0.26.12
runtime_commit=808e4b1fc06e269a107c4bd8bd936cc6fde18b00
grammar_revision=v1.3.0
grammar_commit=e8adc739b78409a99f8c31313f0bb54cc538cf73
study_dir=$(mktemp -d /tmp/odra-syntax-dependency.XXXXXX)
trap 'rm -rf -- "$study_dir"' EXIT

git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$runtime_revision" \
  https://github.com/tree-sitter/tree-sitter.git "$study_dir/runtime"
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$grammar_revision" \
  https://github.com/tree-sitter-grammars/tree-sitter-odin.git "$study_dir/grammar"

test "$(git -C "$study_dir/runtime" rev-parse HEAD)" = "$runtime_commit"
test "$(git -C "$study_dir/grammar" rev-parse HEAD)" = "$grammar_commit"

(
  cd "$study_dir"
  sha256sum --check <<'DIGESTS'
c5cfb43042b6b72045f4ba997834d0a7786d2793d91680868b5815b39f14fc78  runtime/LICENSE
379611afd1492ece6a1c4c503ffc9c2a9827152444583205c6f35040dd418bfe  runtime/lib/include/tree_sitter/api.h
4e28f87edb86e5134d36ff7ba7e09a964ba9966a4b620c2735e3572b53c157d3  runtime/lib/src/lib.c
099c44248f8cf353123211318680e93465587c005a4b3730ce8cb5334de043d6  grammar/LICENSE
8f672d8d022d70eeae822796924f2e45e692d6b2acd2ddc79bfeb5f696fa24f0  grammar/src/parser.c
e342d07d3e35c3865a6bda0587f3a3b46a7b2411fd93cbee01dc40ab7631c93b  grammar/src/scanner.c
d32354fc8cef7da7f2b235ed17d2d48c074150d5dc69bfedf18d1370b03f8cc7  grammar/queries/highlights.scm
DIGESTS
)

grep -q '#define LANGUAGE_VERSION 14' "$study_dir/grammar/src/parser.c"
grep -q '#define TREE_SITTER_LANGUAGE_VERSION 15' "$study_dir/runtime/lib/include/tree_sitter/api.h"
grep -q '#define TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION 13' "$study_dir/runtime/lib/include/tree_sitter/api.h"

printf '%s\n' \
  "study=syntax-dependency valid=true" \
  "runtime_revision=$runtime_revision runtime_commit=$runtime_commit runtime_abi=15 minimum_abi=13" \
  "grammar_revision=$grammar_revision grammar_commit=$grammar_commit grammar_abi=14" \
  "query=grammar/queries/highlights.scm provenance=tree-sitter-odin" \
  "runtime_license=MIT grammar_license=MIT downloads=study-only production_sources=false"
