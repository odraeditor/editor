<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Odin Language Support Reference

## Identity and Selectors

Language identity `odin`, numeric ID `1`; selector `.odin`.

## Bundle and Origin

`org.odra.odin` version `1.0.0`, publisher `odra`, source `odra.factory`,
maintained and enabled in the basic pack.

## Syntax

Provider `odin.syntax`; Tree-sitter Odin `1.3.0`, grammar symbol
`tree_sitter_odin`, ABI `14`, ordinary resource profile, and vendored highlight
query.

## Embedded Languages

None declared.

## Service

`ols`, launched directly as `ols`. The nearest `ols.json` is the root, falling
back to the trusted Project root.

## Formatter

No formatter is declared by the Factory Odin bundle.

## Capabilities

The Factory service declares diagnostics and completion. Syntax and structural
operations remain local. Other generic service commands report unavailable
unless a complete higher-precedence service definition negotiates them.

## Prerequisites

OLS must be visible to Odra for diagnostics and completion. A trusted Project
is required for OLS, not for local syntax.

## Setup

Install OLS by its upstream instructions, confirm `command -v ols`, and place
`ols.json` at the intended Project root when project-specific configuration is
needed.

## Commands and Bindings

Use `C-M-i` for completion and the common Direct and Modal language maps for
capabilities that are available. Exact bindings are in the
[Language Bundle Reference](../../language-bundles/index.md).

## Health Inspection

Run `M-x describe-language-support`, then `M-x describe-language-service`.
Confirm `org.odra.odin`, `odin.syntax`, OLS executable, selected root, document
revision, diagnostics, and completion.

## Recovery

If OLS is absent or fails, local syntax and ordinary editing remain active.
Repair `PATH`, `ols.json`, or Project trust, then restart Odra or the reaped
service session.

## Version Evidence

Bundle/API `1.0.0`; Tree-sitter runtime `0.26.12`; grammar `1.3.0`, ABI `14`.
Factory grammar, scanner, query, and license artifacts carry exact sizes and
SHA-256 digests.
