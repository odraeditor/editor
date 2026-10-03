<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Structural Editor Operations Reference

The `command` package adapts copied structural language results into checked
editor-view changes and atomic text transactions. The factory application,
direct profile, `M-x`, and Racket boundary all reach these six semantic
operations through the canonical command registry.

## Exact Turn Scope

`Structural_Editor_Scope` captures the invoking view handle and state
generation, buffer and revision, canonical selection generation, complete
`Structural_Scope`, transaction identity, and undo-unit identity. A
`Structural_Editor_Request` must present that exact copied scope with one
operation.

`Structural_Editor_Context` borrows the live native owners, retained source
snapshot, Tree-sitter owner, and exact analysis scope for one synchronous turn.
The caller keeps those owners alive until the operation returns. The command
retains no syntax node, cursor, source bytes, view pointer, or parser object.

Before a query, the adapter verifies that the view, buffer, source snapshot,
editor revision, selection generation, and analysis scope agree. It repeats
the editor-scope check after the language query and before publication. A stale
identity rejects the operation without changing canonical state.

## Navigation

`Forward`, `Backward`, `Up`, and `Down` consume one copied
`Structural_Target`. Forward movement publishes the target end; the other
directions publish the target start. `view.move_point` synchronizes the
invoking view's stored point with the buffer-owned effective point.

The adapter computes the target display column, resets the desired column to
that value, and derives a checked viewport reveal plan before moving. A missing
sibling, parent, or child is a successful `No_Op`. It changes neither point nor
viewport and returns the query usage that established the boundary.

## Selection

`Select` sends point plus the ordered active region, when present, to the
language owner. The first successful selection chooses the smallest containing
named node. An exact active-node range expands to its strict named ancestor.

`view.select_range` atomically stores mark at target start, point at target end,
and activates the region. It reserves a mark anchor before publication when
the buffer does not already own one. Allocation or validation failure releases
that reservation and preserves the previous selection.

Canonical selection is buffer-owned. Every view observes the new effective
point, mark, and activation, while non-invoking views retain their independent
stored points and viewport state. Selection creates no history node.

## Indentation Transaction

`Indent` requests one copied grammar-owned indentation plan for the current
line or the active-region lines. The adapter materializes only the planned
leading-space replacements and submits the complete ordered batch through one
root transaction with origin `Language_Tool`, command `structural-indent`, and
one undo-unit identity.

The transaction validates every base position, transforms point and mark
through the ordinary anchor rules, prepares the invoking logical view, and
records one history node when a history store is present. Commit publication is
all-or-nothing. Undo and redo use the existing history-navigation path and
restore the complete text and logical selection result.

An empty plan is a checked `No_Op`. Blank lines and lines contained by syntax
errors remain unchanged according to the language plan. After a commit, the
result scope reports the new editor revision and selection state while its
analysis field identifies the tree that produced the transaction. That tree is
then stale by construction; the application coordinator refreshes analysis
before accepting another structural turn.

## Factory Commands and Inspection

| Command | Direct-profile binding | Effect |
| --- | --- | --- |
| `structural-forward` | `C-M-f` | View |
| `structural-backward` | `C-M-b` | View |
| `structural-up` | `C-M-u` | View |
| `structural-down` | `C-M-d` | View |
| `structural-select` | `C-M-SPC` | View |
| `structural-indent` | `M-x` | Buffer, View, Text Mutation |

The direct bindings are ordinary replaceable profile entries. `M-x` resolves
every canonical identity, including `structural-indent` without replacing the
ordinary editable-buffer `Tab` command. `describe-structural-state` presents copied scope,
analysis, grammar, selection, target, operation, indentation, usage, limits,
and latest-rejection rows through the shared list UI without triggering
analysis.

Unavailable, unsupported, failed, stale, or over-limit analysis records a
contained rejection and preserves the ordinary editing workflow.

## Results, Failures, and Ownership

`Structural_Editor_Result` copies the operation, before and result scopes,
target, usage, and native completion. Indentation results retain the committed
transaction so consumers can inspect copied commit splices. Call
`structural_editor_result_close` exactly once after consuming that result.

`Structural_Editor_Failure_Code` distinguishes invalid context or operation,
wrong or stale view, buffer, revision, selection, or analysis, language-query
rejection, view publication rejection, and transaction rejection. The common
command failure also preserves the subordinate language, editor, view,
display, transaction, and history code where applicable.

Cancellation, stale scope, resource exhaustion, allocation failure, syntax
containment, transaction conflict, and publication rejection leave text,
selection, viewport, history, and analysis ownership unchanged. Movement and
selection never create text revisions. Indentation changes text only after the
root transaction reaches allocation-free publication.

## Validation

Run the focused gates from the repository root:

```sh
make native-command-test
make terminal-presentation-test
odin test src/editor -vet -warnings-as-errors
odin test src/view -vet -warnings-as-errors
odin test src/transaction -vet -warnings-as-errors
odin test src/language -vet -warnings-as-errors \
  -define:ODRA_TREE_SITTER_LIBRARY="../../.build/syntax-vendor/libtree-sitter-odin.a"
```

Coverage includes all four movement directions, boundary no-ops, smallest-node
selection, repeated expansion, reversed regions, multiple views, mark-anchor
creation, multi-splice commit, undo, redo, stale scopes, transaction conflict,
syntax errors, line limits, cancellation, allocation failure, and cleanup.

See the
[Structural Syntax Contract Reference](../structural-syntax-contracts/) for
language-query ownership and the
[Atomic Edit Transaction Reference](../atomic-edit-transactions/) for commit
and history publication. Follow
[Navigate and Indent Odin Structure](../../tutorials/structured-syntax-workflow/)
for the complete factory workflow.
