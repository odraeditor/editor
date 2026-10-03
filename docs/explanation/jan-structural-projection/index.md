<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Jan Projects Structure in Odin

Jan needs both a concrete incremental parser and a stable product model. The
generated Tree-sitter grammar recognizes source shapes and exact boundaries;
the Odin language owner decides which copied records are valid for one exact
document, parser, configuration, and analysis generation.

## Dynamic outlines do not belong in fixed parser tables

A heading's star count is an open-ended source value. Its subtree ends at the
next heading with the same or a shallower level, not at a fixed grammar depth.
Encoding every possible level as a generated grammar state would impose an
arbitrary syntax ceiling and complicate error recovery.

Tree-sitter therefore recognizes ordered heading tokens and their immediate
sections. Odin validates the marker, applies the selected depth limit, assigns
the nearest lower-level parent, and closes subtree ranges in one source-order
pass. The result is a deterministic heading forest without duplicating the
concrete parser.

## Concrete recognition is not contextual authority

Some line shapes only have meaning in a specific owner. A planning field is
syntax inside a heading section but ordinary text in the zeroth section. A node
property belongs to a property drawer; a row belongs to a table; an item
belongs to a list.

Keeping that admission explicit prevents punctuation-like near matches from
silently changing document meaning. It also gives later configuration-sensitive
classification one confirmed Odin boundary instead of distributing policy
through generated C tables.

## Losslessness is checked before publication

Tree-sitter retains delimiter, body, whitespace, and line-ending ranges. Odin
rejects ranges that escape their parent or split a UTF-8 sequence, then copies
the accepted taxonomy and lexical fields into pointer-free records. The root
continues to own every canonical source byte, including unknown and malformed
text.

An unclosed block can still have a useful structural boundary, but it receives
an explicit recovery record. This is preferable to either discarding the text
or pretending the construct was complete. Parsing remains read-only; unchanged
save still publishes the editor's canonical bytes.

## Parser lifetime stays private

`Jan_Structural_Owner` retains the C parser and latest tree under the existing
Tree-sitter memory-accounting boundary. No foreign node or pointer enters a
public Jan record. Copied analyses have their own deterministic lifetime, so a
caller can close an analysis independently from replacing or closing the
parser tree.

This separation prepares Slice 4 incremental publication without making the
parser application-visible. Slice 3 adds inline objects, confirmed
configuration, and indexes over the same owned structure, while Slice 5
remains the only stage that registers Jan for actual buffers.
