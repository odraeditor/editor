<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Use Contextual Operations

This chapter uses the selected Darek node as context for language symbols,
shell commands, checked bulk file work, and command discovery.

## Before You Begin

Complete [Manage Resources](manage-resources.md). Open the maintained `User
Guide` Workspace, show Darek with `C-x t t`, and keep an ordinary editing pane
available beside it.

## Browse Document Symbols

Select `Forecast Engine/src/forecast/model.odin` and press `TAB` or `Right`.
Darek requests the current document-symbol generation from the configured
language provider and inserts symbol children beneath the file.

Move through the symbol rows with the ordinary `n`, `p`, and arrow bindings.
Press `RET` on a symbol to open its file at the exact source revision and byte
position reported by the provider. Refresh or reopen the file when Darek
rejects a symbol from an older provider or document generation.

A file remains an ordinary leaf when no document-symbol provider is available.
Darek does not parse language syntax itself.

## Run a Shell Command from the Tree

Select a file and press `!`. Enter `pwd` and press `RET`. The process owner runs
the command from the file's containing directory. On a directory or Project
row, the selected path is the working directory.

Press `M-!` to run from the selected node's Project root regardless of its
depth. Process output, cancellation, and completion use the editor's normal
process feedback instead of a Darek-specific terminal implementation.

## Open the Context in Maksym

Select a directory and press `M-m`. Odra opens that directory in Maksym. On a
file or symbol, it opens the containing directory.

Use Maksym's target-set commands for multi-resource copy, move, rename, or
delete work. Darek supplies the context; Maksym remains responsible for target
selection, validation, mutation, and recovery.

## Discover Contextual Commands

Press `M-RET` on the selected node. The command surface lists commands admitted
by the current editor and Darek context. Filter by name, move through the
results, and accept one with `RET`. Cancel with `C-g` to return without running
an action.

A secondary-button press on a current Darek row first selects that exact row
and then opens the same command surface. A stale row or projection is rejected
before focus, selection, or command activation changes.

The terminal frontend does not currently report double-click identity or drag
payloads to Darek. Use `RET` for activation and Maksym for multi-resource work.

## Verify the Result

You have completed this chapter when a source file exposes provider-owned
symbol children, `!` and `M-!` use the expected working directories, `M-m`
opens the selected context in Maksym, and both `M-RET` and a secondary-button
press expose the same registered command surface.

For exact commands, providers, bounds, and ownership, see the
[Darek Reference](../../../../reference/darek/index.md).

---

[Previous: Manage Resources](manage-resources.md) ·
[Files, Projects, and Workspaces](../index.md) ·
[Next: Maksym](../maksym/index.md)
