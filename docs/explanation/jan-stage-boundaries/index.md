<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Jan Delivers Document Fidelity Before Document Workflows

Jan must make existing structured documents safe before it makes them more
powerful. Stage 1 therefore establishes one complete source and analysis model
without implementing every workflow that the syntax can describe.

## Recognition must precede operation

A task keyword, property, timestamp, formula, source block, export directive,
or external link has meaning even when its operational feature is unavailable.
If early implementation treated that source as disposable plain text, each
later feature could reinterpret or rewrite it differently.

Stage 1 classifies those forms now, assigns exact ranges and owning stages, and
preserves their bytes. Later stages consume the same confirmed analysis instead
of introducing feature-specific parsers.

## Fidelity is independently useful

Users can open `.org` and `.jan` documents, see semantic syntax, inspect current
structure, lint malformed input, make ordinary edits, undo and redo, and save
without normalization. These operations form a useful product boundary even
before outline manipulation, agendas, execution, or export exist.

The boundary is intentionally visible. `jan-language-status` distinguishes
delivered factory-native capabilities from 19 `Future_Stage` records. Missing
behavior is explicit rather than represented by commands that silently do
nothing or partially mutate a document.

## Source remains canonical

The editor buffer owns canonical text. Tree-sitter owns a private concrete
tree, and Jan publishes copied typed records for one exact revision. Neither
representation serializes the document during an unchanged save.

For a later structured mutation, Jan can select an owned range and minimize a
replacement, but the ordinary transaction and history owners still validate,
publish, undo, and redo the canonical bytes. This preserves unrelated spelling,
whitespace, line endings, unknown forms, and malformed recovery text.

## Failures cannot weaken the boundary

Parser, configuration, resource, cancellation, timeout, and allocation failures
reject a candidate atomically. The last confirmed analysis may remain available
for diagnosis, but it cannot authorize work over a newer revision. Ordinary
editing and saving remain available because they do not depend on successful
Jan analysis.

This makes later stages additive. Structured editing, planning, computable
documents, and publishing can expand operational authority without changing
what the original document bytes meant or who owns them.
