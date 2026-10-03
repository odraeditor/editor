<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Syntax Presentation Is Revision-Bound

Syntax highlighting looks visual, but its correctness depends on text identity.
A byte range derived from one buffer revision can point at different characters
after even a small edit. Odra therefore treats syntax as a revisioned derived
projection rather than mutable editor state.

## Canonical text publishes first

Transactions remain the only authority that changes canonical text. After a
commit publishes, its observer copies the buffer identity, base and result
revisions, and normalized splices into bounded syntax work. The observer does
not parse, render, or delay the commit.

The application maintenance step attempts incremental parsing against an
immutable base snapshot and immutable result snapshot. If identities do not
match, work is cancelled, or the incremental budget is exhausted, Odra keeps
the prior confirmed parser owner and coalesces one full refresh for the newest
revision.

## Stale syntax becomes ordinary text

A syntax snapshot is publishable only when its buffer and source revision equal
the `TextView` projection. As soon as text advances, old syntax decorations are
unavailable for display. Until analysis confirms the exact current revision,
the affected text uses `Text_Normal`.

This choice avoids approximate highlighting over the wrong bytes. Parser,
query, allocation, or resource failure can temporarily remove color, but it
cannot block editing, undo, redo, search, selection, saving, switching buffers,
or closing the document.

## One analysis owner serves every view

Language association belongs to the file-backed document and analysis state
belongs to its buffer. Views request bounded visible ranges from that shared
owner and project the returned semantic spans through their own viewport.
Splitting a pane therefore does not create another parser or another syntax
truth.

Closing or replacing the buffer association releases its source snapshot,
query result, parser, query cursor, tree, and accounting owner in a defined
order. Provider disable, replacement, failure recovery, and factory restoration
replace the one active selection rather than retaining duplicate background
analysis.

## Semantic roles separate analysis from presentation

Tree-sitter capture names are normalized into stable Odra syntax roles.
Language code does not know terminal colors. The UI maps roles to generic
styles and `Text_Range` decorations, and the terminal lowers those styles for
true-color, indexed, basic, or monochrome output.

Search-current and active-region layers remain independent and have higher
precedence than syntax. A later theme can replace role-to-style mappings
without changing parser queries, syntax identities, or editor text.

This separation leaves later languages, themes, structural navigation, and
language services with one shared revision and ownership model instead of a
parallel rendering path.
