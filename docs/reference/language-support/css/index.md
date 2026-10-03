<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# CSS Language Support Reference

## Identity and Selectors

Language identity `css`, numeric ID `9`; selector `.css`.

## Bundle and Origin

`org.odra.css` version `1.0.0`, publisher `odra`, source `odra.factory`,
maintained and enabled in the basic pack.

## Syntax

Provider `css.syntax`; Tree-sitter CSS `0.25.0`, grammar symbol
`tree_sitter_css`, ABI `15`, ordinary resource profile, and maintained
highlight query.

## Embedded Languages

CSS is the admitted child syntax for HTML style regions. No framework-specific
injection is inferred.

## Service

`vscode-css-language-server`, launched directly with `--stdio`. The nearest
`package.json` is the root, falling back to the trusted Project root.

## Formatter

`css.language-server-format`; service-backed buffer and range formatting with
text-edit output.

## Capabilities

Diagnostics, completion, hover, symbols, and formatting. Navigation,
references, rename, semantic tokens, and code actions are not declared by this
Factory service profile.

## Prerequisites

Node.js, `vscode-langservers-extracted` `4.10.0`, and a trusted Project for the
external service. Local syntax does not require the server.

## Setup

```sh
npm install --global vscode-langservers-extracted@4.10.0
vscode-css-language-server --version
```

## Commands and Bindings

Use `C-M-i` and the shared Direct or Modal commands whose capabilities are
available. Exact bindings are in the
[Language Bundle Reference](../../language-bundles/index.md).

## Health Inspection

Run `M-x describe-language-support` and `M-x describe-language-service`.
Confirm CSS identity, `css.syntax`, package root, executable, synchronized
revision, and negotiated features.

## Recovery

If the server is unavailable, local CSS syntax remains active in `.css` files
and admitted HTML style regions. Repair Node.js or Project trust and restart
the reaped service session.

## Version Evidence

Bundle/API `1.0.0`; Tree-sitter runtime `0.26.12`; grammar `0.25.0`, ABI `15`;
accepted service package `4.10.0`. Factory artifacts carry exact sizes,
SHA-256 digests, license, and setup metadata.
