<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Local Syntax and Language Services Are Separate

Syntax coloring and structural awareness must remain available when an
external language server is missing, starting, slow, failed, or unsupported.
Odra therefore treats them as independent providers joined by one language
bundle rather than as one process-backed feature.

Local syntax uses a bounded Tree-sitter grammar and queries owned by the
editor. It identifies semantic presentation roles and structural regions from
the current document revision. It does not launch a compiler, download a
server, or require Project trust. A syntax failure falls back to ordinary text
without transferring canonical buffer ownership.

A language service is an advisory external process. It runs only for an
admitted trusted Project, uses a direct command vector, resolves a language
root, synchronizes document revisions, and negotiates capabilities such as
diagnostics, completion, hover, navigation, symbols, rename, formatting, and
code actions. Odra copies and bounds its results before native code can present
or publish them.

The separation explains common behavior: a file can be correctly recognized
and colored while completion is unavailable; two languages can use distinct
sessions even when they share a server executable; and restarting a failed
service does not rebuild a syntax tree. Mutating responses still pass the
editor's revision, Project-membership, preview, and atomic transaction checks.

The bundle connects these providers through stable language identities and
declared capabilities. It does not collapse their lifetimes or trust levels.
That design keeps ordinary editing responsive and makes missing prerequisites
recoverable instead of fatal.
