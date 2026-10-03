<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Go Language Support Reference

## Identity and Selectors

Language identity `go`, numeric ID `4`; selector `.go`.

## Bundle and Origin

`org.odra.go` version `1.0.0`, publisher `odra`, source `odra.factory`,
maintained and enabled in the basic pack.

## Syntax

Provider `go.syntax`; Tree-sitter Go `0.25.0` at commit
`1547678a9da59885853f5f5cc8a99cc203fa2e2c`, grammar symbol
`tree_sitter_go`, ABI `15`, ordinary resource profile, and vendored highlight
query.

## Embedded Languages

None declared.

## Service

`gopls`, launched directly as `gopls serve`. Root selection uses the nearest
`go.work`, then `go.mod`, then the trusted Project root.

## Formatter

`go.language-server-format`; service-backed buffer and range formatting with
text-edit output.

## Capabilities

Diagnostics, completion, navigation, hover, references, symbols, signature
help, rename, formatting, semantic tokens, and code actions, subject to server
negotiation and native policy.

## Prerequisites

Go and `gopls` must be visible to Odra. A trusted Project is required for the
external process, not for local syntax.

## Setup

```sh
go install golang.org/x/tools/gopls@v0.23.0
command -v gopls
gopls version
```

## Commands and Bindings

Use `C-M-i`, the Direct `C-c C-l` map, the Modal `g d`, `g r`, `K`, and `g l`
map, or the shared semantic `M-x language-*` commands. Exact bindings are in
the [Language Bundle Reference](../../language-bundles/index.md).

## Health Inspection

Run `M-x describe-language-support`, then `M-x describe-language-service`.
Confirm bundle, `go.syntax`, nearest module/workspace root, executable,
synchronized revision, and negotiated features.

## Recovery

If `gopls` is absent or fails, retain local syntax, correct `PATH` or Project
trust, and restart Odra or the reaped service session. Distinct Projects keep
independent roots and sessions.

## Version Evidence

Bundle/API `1.0.0`; Tree-sitter runtime `0.26.12`; grammar `0.25.0`; accepted
service `gopls v0.23.0`. Factory artifacts carry exact paths, byte sizes,
SHA-256 digests, license, and provenance.
