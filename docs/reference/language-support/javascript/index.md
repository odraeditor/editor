<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# JavaScript Language Support Reference

## Identity and Selectors

Language identity `javascript`, numeric ID `6`; selectors `.js`, `.jsx`,
`.mjs`, and `.cjs`.

## Bundle and Origin

`org.odra.javascript` version `1.0.0`, publisher `odra`, source
`odra.factory`, maintained and enabled in the basic pack.

## Syntax

Providers `javascript.syntax` and `javascript.jsx-syntax`; Tree-sitter
JavaScript `0.25.0`, grammar symbol `tree_sitter_javascript`, ABI `15`,
ordinary resource profile, and maintained JavaScript and JSX highlight queries.

## Embedded Languages

JavaScript is an admitted child syntax for HTML script regions. No tagged
template or framework-specific injection is inferred.

## Service

`typescript-language-server`, launched directly with `--stdio`. Root selection
uses the nearest `tsconfig.json`, `jsconfig.json`, or `package.json`, then the
trusted Project root. JavaScript and TypeScript keep distinct language/root
sessions even though they share an executable identity.

## Formatter

`javascript.language-server-format`; service-backed buffer and range
formatting with text-edit output.

## Capabilities

Diagnostics, completion, navigation, hover, references, symbols, signature
help, rename, formatting, semantic tokens, and code actions.

## Prerequisites

Node.js, `typescript-language-server` `6.0.0`, TypeScript `6.0.3`, and a
trusted Project for the external service.

## Setup

```sh
npm install --global typescript-language-server@6.0.0 typescript@6.0.3
typescript-language-server --version
```

## Commands and Bindings

Use `C-M-i`, the Direct `C-c C-l` map, the Modal `g d`, `g r`, `K`, and `g l`
map, or shared semantic `M-x language-*` commands. Exact bindings are in the
[Language Bundle Reference](../../language-bundles/index.md).

## Health Inspection

Run `M-x describe-language-support` and `M-x describe-language-service`.
Confirm JavaScript identity, selected syntax variant, nearest configuration
root, executable, synchronized revision, and negotiated features.

## Recovery

If the server or TypeScript dependency is unavailable, local JavaScript/JSX
syntax remains active. Repair the Node.js installation or Project trust and
restart the reaped session.

## Version Evidence

Bundle/API `1.0.0`; Tree-sitter runtime `0.26.12`; grammar `0.25.0`, ABI `15`;
accepted service `6.0.0` with TypeScript `6.0.3`. Factory artifacts carry exact
sizes, SHA-256 digests, and licenses.
