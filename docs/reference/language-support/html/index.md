<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# HTML Language Support Reference

## Identity and Selectors

Language identity `html`, numeric ID `8`; selectors `.html` and `.htm`.

## Bundle and Origin

`org.odra.html` version `1.0.0`, publisher `odra`, source `odra.factory`,
maintained and enabled in the basic pack.

## Syntax

Provider `html.syntax`; Tree-sitter HTML `0.23.2`, grammar symbol
`tree_sitter_html`, ABI `14`, ordinary resource profile, maintained highlight
query, and explicit injection query.

## Embedded Languages

Admitted script regions select JavaScript or TypeScript syntax; admitted style
regions select CSS. Parent and child providers retain separate ownership,
accounting, failures, and deterministic non-overlapping spans.

## Service

`vscode-html-language-server`, launched directly with `--stdio`. The nearest
`package.json` is the root, falling back to the trusted Project root.

## Formatter

`html.language-server-format`; service-backed buffer and range formatting with
text-edit output.

## Capabilities

Diagnostics, completion, hover, symbols, and formatting. Navigation,
references, rename, semantic tokens, and code actions are not declared by this
Factory service profile.

## Prerequisites

Node.js, `vscode-langservers-extracted` `4.10.0`, and a trusted Project for the
external service. Local HTML and embedded syntax do not require the server.

## Setup

```sh
npm install --global vscode-langservers-extracted@4.10.0
vscode-html-language-server --version
```

## Commands and Bindings

Use `C-M-i` and the shared Direct or Modal commands whose capabilities are
available. Exact bindings are in the
[Language Bundle Reference](../../language-bundles/index.md).

## Health Inspection

Run `M-x describe-language-support` and `M-x describe-language-service`.
Confirm HTML identity, `html.syntax`, injection declarations, package root,
executable, synchronized revision, and negotiated features.

## Recovery

If the server is unavailable, HTML, JavaScript/TypeScript script regions, and
CSS style regions retain local syntax. If a child provider fails, the parent
and other regions remain editable. Repair Node.js, trust, or the failed
provider and reopen or restart as reported.

## Version Evidence

Bundle/API `1.0.0`; Tree-sitter runtime `0.26.12`; HTML grammar `0.23.2`, ABI
`14`; accepted service package `4.10.0`. Grammar, scanner, highlight and
injection queries, license, and setup metadata are exact Factory artifacts.
