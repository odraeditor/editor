<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Racket Language Support Reference

## Identity and Selectors

Language identity `racket`, numeric ID `3`; selector `.rkt`.

## Bundle and Origin

`org.odra.racket` version `1.0.0`, publisher `odra`, source `odra.factory`,
maintained and enabled in the basic pack.

## Syntax

Provider `racket.syntax`; Tree-sitter Racket `0.25.0` at commit
`b3cbbde75ce2de3079e33c7fe90bd41b1d45be48`, grammar symbol
`tree_sitter_racket`, ABI `15`, ordinary resource profile, and vendored
`queries/highlights.scm`. It targets the default Racket readtable.

## Embedded Languages

None declared. Arbitrary custom `#lang` readers and Scribble are not inferred;
unsupported lexical forms remain editable with ordinary text fallback.

## Service

`racket-langserver`, launched directly as `racket -l racket-langserver`.
The nearest `info.rkt` is the root, falling back to the trusted Project root.

## Formatter

`racket.language-server-format`; service-backed buffer and range formatting
with text-edit output.

## Capabilities

Diagnostics, completion, navigation, hover, references, symbols, signature
help, rename, formatting, semantic tokens, and code actions, subject to server
negotiation and native policy.

## Prerequisites

Racket and the `racket-langserver` package must be visible to Odra. A trusted
Project is required for the external process, not for local syntax.

## Setup

```sh
raco pkg install --auto racket-langserver
raco pkg show --all --long racket-langserver
```

## Commands and Bindings

Use `C-M-i`, the Direct `C-c C-l` map, the Modal `g d`, `g r`, `K`, and `g l`
map, or the shared semantic `M-x language-*` commands. Exact bindings are in
the [Language Bundle Reference](../../language-bundles/index.md).

## Health Inspection

Run `M-x describe-language-support`, then `M-x describe-language-service`.
Confirm bundle, syntax provider, `info.rkt` root, executable and module
resolution, synchronized revision, and negotiated features.

## Recovery

If Racket or the module is unavailable, retain local syntax, repair the visible
Racket installation, and restart Odra or the reaped service session. Do not add
a Personal definition merely to repair a missing executable.

## Version Evidence

Bundle/API `1.0.0`; Tree-sitter runtime `0.26.12`; grammar `0.25.0`; accepted
package checksum `93efe35dcc07a7cc86c958f00497280744f0e75c`. Factory artifacts carry exact
paths, byte sizes, SHA-256 digests, license, and provenance.
