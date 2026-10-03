<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Outline Editing Reference

Jan outline editing is the Stage 2 package boundary for visibility, structural
navigation, sparse projection, and heading or subtree mutation. It consumes the
exact copied analysis published by Jan Document Language. The public `jan-*`
commands route through the active buffer, view, and analysis generation.

## Exact inputs

Every operation carries `jan_editing.Scope`, which identifies the source
revision, analysis generation, view handle and generation, visibility
generation, configuration generation, and provider generation. Navigation and
rewrite targets are copied node identities and half-open source ranges. No
operation retains a Tree-sitter node or creates another editable document tree.

An analysis, view, or visibility mismatch is stale. Read-only navigation returns
an inspectable no-target result when no destination exists. A source mutation
rejects before creating a rewrite plan when its target is stale, malformed,
outside the admitted hierarchy, or over a resource limit.

## Structural navigation

`jan_editing.navigation_resolve` derives one canonical source position for:

- next or previous visible heading;
- next or previous same-level heading;
- parent and first child;
- subtree start and end;
- next or previous structural element; and
- list items, table rows and cells, drawers, blocks, and footnotes.

Visibility filtering uses copied hidden ranges. Parent and sibling resolution
uses the Stage 1 heading forest's copied `parent_id`, structural depth, and
subtree range. A selected destination that intersects recovery ownership is a
checked malformed result rather than an approximate position.

## Outline visibility

`jan_editing.outline_visibility_prepare` derives a complete hidden-range
candidate and passes it to the generic prepared visibility transition.

Local states are:

```text
Heading_Only -> Direct_Children -> Complete_Subtree -> Heading_Only
```

Global states are:

```text
Overview -> Contents -> Show_All -> Overview
```

A direct selected state supports configured startup visibility without
advancing a cycle. Local replacement preserves hidden ranges outside the
selected subtree. Global replacement derives a complete view generation. The
generic `src/view` owner normalizes and anchors the result, so two views over one
buffer remain independent and confirmed source edits transform their ranges.

`outline_visibility_reveal_target` revalidates the exact view and removes only
hidden ranges intersecting the admitted target before movement or editing.

## Heading and subtree rewrites

`jan_editing.heading_edit_plan_prepare` supports:

- heading insertion before, after, or below a heading;
- heading split and promotion of paragraph text;
- promotion or demotion of a complete heading subtree;
- movement among siblings;
- subtree clone and kill;
- deterministic child sorting; and
- representable heading-to-list-item and list-item-to-heading conversion.

`Subtree_Copy` owns copied source bytes independently from analysis. It can be
inserted beside an exact current heading and must be closed explicitly.

Each mutation produces one bounded `language.Jan_Rewrite_Plan`. Descendant
heading levels change together. Move may contain two non-overlapping owned
requests, but the rewrite owner normalizes them into one transaction batch and
one undo unit. Tests exercise commit, undo, and redo through the ordinary
transaction and history owners.

Refile, archive, cross-document movement, task transitions, properties, and
time semantics remain unavailable.

## Sparse outline views

`Sparse_View` copies one predicate and an ordered set of heading targets. The
admitted predicate families are:

| Predicate | Input |
| --- | --- |
| Heading level | Copied structural depth |
| Node kind | Copied Stage 1 node kind |
| Text contains | Exact UTF-8 heading-line bytes |
| Indexed fact | Existing read-only Stage 1 index fact |

A direct match includes the minimum heading ancestor chain. Indexed task, tag,
property, timestamp, and other facts remain read-only inputs; matching one does
not acquire its later-stage semantics.

Refresh builds a complete replacement state and publishes it only after all
allocations and limits succeed. Source navigation requires the exact sparse,
analysis, and view scope. Stale results cannot move point or authorize a
mutation. `sparse_view_close` releases copied predicate and match storage.

## Limits and failures

One navigation command admits at most 4,096 semantic candidates. One sparse
view retains at most 16,384 matches and 4 KiB of predicate text. Iteration checks
cancellation at least every 4,096 entries. The stricter Stage 1 rewrite and
transaction limits continue to win.

Tests cover malformed analysis, stale scope, missing targets, Unicode source,
range limits, cancellation, every retained sparse allocation, subtree-copy
allocation, atomic refresh, and exact cleanup.

## Focused validation

Use:

```sh
make jan-structured-editing-focused-test
odin check src/view -no-entry-point -vet -warnings-as-errors
odin check src/jan_editing -no-entry-point -vet -warnings-as-errors
```

These focused commands do not import or build `src/odra`. Linked direct and
modal application behavior is covered by `jan-structured-editing-acceptance`.

Plain-list, drawer, block, and complete-region operations are specified in the
[Jan List and Structure Editing Reference](../jan-list-and-structure-editing/index.md).
