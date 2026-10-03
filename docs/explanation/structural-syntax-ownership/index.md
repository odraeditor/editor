<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Structural Syntax Reuses Canonical Editor Ownership

Structural editing derives useful targets from a syntax tree, but the tree is
not editor state. Odra keeps the retained Tree-sitter owner inside language
analysis and applies copied results through the same point, selection,
transaction, history, and display contracts used by ordinary editing.

## One retained tree serves presentation and editing

The buffer-owned analysis lifecycle already retains one exact-revision Odin
tree for syntax presentation. Structural queries borrow that owner for one
synchronous command turn. They do not parse again, retain another tree, or
create a worker or queue.

Every query includes the buffer revision plus language, provider, selection,
parser, and tree generations. A mismatch rejects the complete operation. This
keeps highlighting and structural editing on one syntax truth and prevents a
target derived from old text from moving point or changing current text.

## Copied targets separate parsing from editing

Only `src/language` traverses Tree-sitter nodes. It returns pointer-free byte
ranges, node kinds, depth, indentation plans, usage, and diagnostics. Foreign
nodes and cursors expire before the command adapter publishes anything.

`src/command` then validates canonical UTF-8 positions and applies the copied
result through editor-view or transaction operations. This separation permits
a later admitted language provider to implement the same semantic commands
without acquiring editor ownership.

## Semantic commands outlive bindings

The six structural operations have one canonical command identity. The
factory direct profile, `M-x`, and Racket composition all invoke those same
identities. Keymaps select commands but contain no traversal or indentation
algorithm, so another interaction profile can bind the operations without
creating another structural editor.

Racket receives fixed copied records and one dynamically scoped capability.
It may compose commands and bindings during that turn, but it cannot retain a
parser node, mutate an unchecked position, or publish text outside the native
transaction owner.

## Indentation remains an ordinary transaction

The Odin grammar owner computes leading-whitespace replacements for the
current line or active-region lines. The command adapter publishes the complete
plan as one transaction and one undo unit. Validation, allocation, conflict,
or syntax-containment failure publishes nothing.

After a successful indentation, canonical text advances before analysis. The
application refreshes the retained tree for the new revision before another
structural command can succeed. Undo and redo remain ordinary history
navigation rather than parser-specific recovery paths.

## Shared selection requires effective point

Selection is buffer-owned even when several panes show the same buffer. Each
pane keeps an independent stored point, while the active region uses the
buffer's effective point and mark. Display projection therefore derives the
region from the effective point so movement in one pane cannot make another
pane publish an inconsistent selection range.

## Rejection preserves the plain-text editor

Unsupported files, unavailable or stale analysis, missing structural targets,
resource limits, and hosted failures record copied diagnostics without
changing point, selection, text, history, viewport, or analysis ownership.
The user can continue ordinary editing and inspect the rejection through
`describe-structural-state`.

This fallback is part of the ownership model: syntax information may disappear
temporarily, but canonical editing does not depend on parser success.
