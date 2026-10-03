<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Jan Publishes Revisions Before Rewrites

Jan analysis is useful only when every derived record describes the same
canonical document revision. Concrete parsing, configured classification,
indexes, diagnostics, and resource accounting therefore form one candidate;
none of them becomes current independently.

## Incremental parsing edits a copy

Tree-sitter can reuse an old tree, but `ts_tree_edit` mutates the tree it
receives. Editing the confirmed tree directly would let a forged splice,
cancellation, resource failure, or invalid projected range damage the last
known-good state. Jan first copies the confirmed tree, applies the exact
normalized transaction edits to that copy, and parses the result source from
the edited candidate.

This is why a failed incremental update can be discarded without rollback. The
previous tree and its copied inspection summary were never changed.

## Last confirmed does not mean current

Keeping the last confirmed scope is valuable for diagnosis after malformed or
over-limit input, but it cannot authorize a command over newer text.
`jan_structural_owner_inspect` compares the caller's scope with the retained
scope. A mismatch returns the retained details as incomplete rather than
pretending that the old nodes are current.

Full refresh uses the same confirmation boundary. It can replace invalidated
grammar or configuration state, but only with a strictly newer analysis
generation for the same buffer and document and without moving the source
revision backward.

## A rewrite owns bytes, not formatting policy

A structured operation begins with an exact Jan node range. The rewrite
planner compares the replacement with the owned source and removes equal
prefix and suffix bytes on canonical UTF-8 boundaries. The resulting splice is
the smallest byte change that expresses the requested replacement.

This avoids reserializing the document. Comments, whitespace, line endings,
directive spelling, unknown forms, and unrelated malformed text remain outside
the declared splice and are therefore preserved by construction.

Multiple requests remain separate only when their minimized ranges do not
overlap. Ambiguous ownership, overlap, equal-start ordering, stale scopes, or
resource exhaustion rejects the complete plan rather than guessing which
source should win.

## Transactions remain the publication owner

Jan produces an edit plan; it does not mutate editor text. The adapter uses the
same base-relative splice and optimistic proposal contracts as other language
tools. The transaction layer rechecks live buffer identity, revision, UTF-8
positions, ordering, memory, and complete admission before publication.

Because the final mutation is an ordinary transaction, Jan edits receive the
same atomicity and history behavior as direct edits. Undo and redo publish new
canonical revisions; Jan then analyzes those revisions through the same full
or incremental lifecycle.

The division is deliberate: Jan owns semantic range selection and minimal
replacement text, while the editor and transaction packages own canonical
bytes, conflict detection, publication, and reversible history.
