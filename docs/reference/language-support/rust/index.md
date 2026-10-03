<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Rust Language Support Reference

## Identity and Selectors

Language identity `rust`, numeric ID `5`; selector `.rs`.

## Bundle and Origin

`org.odra.rust` version `1.0.0`, publisher `odra`, source `odra.factory`,
maintained and enabled in the basic pack.

## Syntax

Provider `rust.syntax`; Tree-sitter Rust `0.24.2` at commit
`77a3747266f4d621d0757825e6b11edcbf991ca5`, grammar symbol
`tree_sitter_rust`, ABI `15`, ordinary resource profile, and maintained
`highlights-and-structure.scm` query.

## Embedded Languages

None declared.

## Service

`rust-analyzer`, launched directly. The nearest `Cargo.toml` is the root,
falling back to the trusted Project root.

## Formatter

`rust.language-server-format`; service-backed buffer and range formatting with
text-edit output.

## Capabilities

Diagnostics, completion, navigation, hover, references, symbols, signature
help, rename, formatting, semantic tokens, and code actions, subject to server
negotiation and native policy.

## Prerequisites

`rust-analyzer` and matching Rust standard-library sources must be visible to
Odra. A trusted Project is required for the external process.

## Setup

```sh
rustup component add rust-analyzer rust-src
command -v rust-analyzer
rust-analyzer --version
```

## Commands and Bindings

Use `C-M-i`, the Direct `C-c C-l` map, the Modal `g d`, `g r`, `K`, and `g l`
map, or the shared semantic `M-x language-*` commands. Exact bindings are in
the [Language Bundle Reference](../../language-bundles/index.md).

## Health Inspection

Run `M-x describe-language-support`, then `M-x describe-language-service`.
Confirm bundle, `rust.syntax`, nearest Cargo root, executable, synchronized
revision, and negotiated features.

## Recovery

If `rust-analyzer` is absent or fails, retain local syntax, repair the selected
toolchain or trust, and restart Odra or the reaped service session. Nested
Cargo roots remain independently selected.

## Version Evidence

Bundle/API `1.0.0`; Tree-sitter runtime `0.26.12`; grammar `0.24.2`; accepted
rust-analyzer release `2026-09-14`, standalone version `0.3.3049`, asset
SHA-256 `7609ba53f85cd80a3bde77a4b2e94e304d0f94650e4f4cffc061b9bca454ba75`.
