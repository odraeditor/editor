<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Language Support Reference

## Identity and Selectors

Language identity `jan`, numeric ID `2`; selectors `.org` and `.jan`.

## Bundle and Origin

`org.odra.jan` version `1.0.0`, publisher `odra`, source `odra.factory`,
included and enabled in the basic pack. Jan uses the same bundle inspection and
lifecycle vocabulary as every other language.

## Syntax

Provider `jan.syntax`; `jan-org-9.8.10-v1` grammar, symbol `tree_sitter_jan`,
ABI `15`, ordinary resource profile, maintained highlight query, and native
lossless Jan analysis.

## Embedded Languages

No generic injection is declared. Jan blocks remain source-faithful document
structures; later language-specific injection requires an explicit provider.

## Service

No external language service is declared. Jan inspection, lint, outline,
lists, drawers, blocks, tables, rich presentation, and contextual authoring
are native specialized capabilities.

## Formatter

No generic formatter is declared. Jan commands perform checked structural and
table edits through native transactions.

## Capabilities

Local syntax, lossless analysis, inspection and lint, visibility cycling,
outline navigation and editing, list and structure editing, drawers, blocks,
tables, rich presentation, contextual authoring, and source-preserving saves.

## Prerequisites

None beyond Odra. Factory setup is already included and enabled.

## Setup

Open a `.org` or `.jan` file. No package, external executable, or Personal
language definition is required.

## Commands and Bindings

Direct: `C-c j c` cycle, `C-c j g` global cycle, `C-c j n`/`C-c j p` heading
navigation, and `C-c j a` contextual action. Modal Normal: `z a`, `z A`, `] h`,
`[ h`, and `g a`. All specialized `M-x jan-*` commands remain discoverable.

## Health Inspection

Run `M-x describe-language-support`, `M-x jan-language-status`,
`M-x jan-inspect-syntax`, and `M-x jan-lint-refresh`. The support inspector
reports the same bundle, origin, provider, generation, and failure fields used
by external languages.

## Recovery

Reopen the document after a selector or provider change. A syntax-analysis
failure preserves ordinary editing and exact source text. Use Jan inspection
and lint diagnostics before applying structural recovery commands.

## Version Evidence

Bundle/API `1.0.0`; Tree-sitter runtime `0.26.12`;
`jan-org-9.8.10-v1`, ABI `15`. Grammar, scanner, query, capability manifest,
license, and documentation are exact Factory artifacts.

See the [Jan Factory Language Integration Reference](../../jan-factory-language-integration/index.md)
and [Jan Structured Editing Commands](../../jan-structured-editing-commands/index.md)
for the specialized contract.
