<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Structured Documents

This part turns a Jan document into a complete working system. You will plan
work, calculate and execute source blocks, export and publish output, inspect
providers, and recover from unavailable or rejected operations.

Complete [Work with Jan Documents](../language-intelligence/work-with-jan-documents.md)
first. It establishes `.org` and `.jan` parity, source-preserving editing, and
the command interaction used here.

Follow these chapters in order:

1. [Plan Work](plan-work.md) manages tasks, metadata, time, capture, agendas,
   and provider permissions.
2. [Compute in Documents](compute-in-documents.md) recalculates tables and runs
   one source block within configured result limits.
3. [Export and Publish](export-and-publish.md) exports through native backends,
   inspects optional tools, and validates one publication.
4. [Connect and Extend Jan](connect-and-extend.md) works with links, protected
   content, synchronization, and provider results tied to source generations.
5. [Recover Jan Workflows](recover-jan-workflows.md) diagnoses unavailable,
   stale, limited, cancelled, and partial outcomes while preserving source.

These chapters describe the accepted Odra v0.2.0 Jan surface. A development
build can contain the domain contracts before the editor has linked every
command. Run the status command named by each chapter first. Continue only
when it reports the required capability as operational.

The supplied User Guide exercise kit contains safe examples under
`~/odra-guide/work/projects/forecast-engine/notes/jan-workflows/`. If the kit
is not prepared, complete
[Prepare the User Guide Exercises](../getting-started/prepare-exercises.md).

---

[Previous: Understand Provider Fallback](../language-intelligence/provider-fallback.md) ·
[User Guide](../index.md) ·
[Next: Plan Work](plan-work.md)
