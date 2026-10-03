<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan List and Structure Editing Reference

Jan list and structure editing is the Stage 2 package boundary for plain-list,
drawer, block, and complete-region mutation. It consumes exact copied Jan
Document Language analysis and produces bounded rewrite plans; it does not
retain parser nodes or create another document tree. Public commands coordinate
the package through the current Jan analysis and ordinary transaction owner.

## Plain lists

`jan_editing.list_edit_plan_prepare` accepts one exact `List_Item`,
`Plain_List`, or paragraph target according to the requested operation. It
supports:

- ordered, unordered, and descriptive item insertion;
- complete-item deletion, promotion, demotion, movement, and duplication;
- deterministic direct-item sorting;
- explicit bullet and ordered-counter selection;
- continuation indentation repair; and
- paragraph-region conversion to list items.

Complete-item operations derive the owned source extent from copied list-item
anchors and source indentation. Continuation paragraphs, nested items, blank
lines, drawers, blocks, checkbox tokens, and Unicode bytes move with the item.
The package does not build a parallel list tree or reparse source. Ordinary
save never renumbers or reformats a list.

Every admitted mutation becomes one `language.Jan_Rewrite_Plan` and one normal
transaction/history unit. Promotion that would cross the left margin, movement
without a sibling, an incompatible counter, stale analysis, or recovery-owned
source rejects before publication.

## Drawers and blocks

`jan_editing.structure_inspect` returns a copied complete selection range, body
range, and view-compatible hidden range for a drawer or block. Existing
structural navigation resolves next and previous drawer or block destinations.

`jan_editing.drawer_visibility_prepare` preserves the active view's unrelated
hidden ranges and toggles only one exact drawer body through the ordinary
visibility publication boundary. `jan-toggle-drawer` exposes that operation by
name in direct and modal command launchers. Another view remains independent;
an enclosing or overlapping fold, stale generation, malformed drawer, limit,
or allocation failure preserves the prior visibility state.

`jan_editing.structure_edit_plan_prepare` supports complete insertion,
factory-template expansion, rename, movement, and deletion. Factory templates
cover drawers, source, example, quote, center, comment, export, special, and
dynamic blocks. A single admitted name generates both begin and end block
delimiters; drawer close syntax remains `:END:`. Arguments and body bytes are
copied without interpretation. Rename changes delimiter names while preserving
arguments, indentation, body bytes, line endings, and the rest of the selected
structure.

An unterminated or recovery-owned structure is malformed. Invalid names,
unsupported rename forms, stale scopes, missing siblings, and allocation
failures reject without retaining a partial plan.

## Complete structural regions

`Structural_Region` owns a copied, source-ordered set of complete targets.
`structural_region_prepare` verifies every node identity, exact half-open range,
scope, recovery boundary, target kind, overlap, and the 4,096-target limit
before publishing the region. Partial nodes, ancestor/descendant pairs, stale
ranges, and over-limit sets reject atomically.

`structural_region_plan_prepare` revalidates the complete owned set against the
current analysis before constructing one multi-splice rewrite plan. The number
of replacements must equal the target count. Stage 1 rewrite and transaction
limits remain authoritative. `structural_region_close` releases all copied
targets.

## Planning boundary

Checkbox tokens and property drawers are structurally preserved and editable.
Their semantic operations are owned by the linked Planning and Agenda domain:

| Capability | Availability | Owner |
| --- | --- | --- |
| `jan-task-planning` | `factory-native`, operational | Planning and Agenda |
| `jan-property-operations` | `factory-native`, operational | Planning and Agenda |

This editing package does not redefine planning semantics, execute a dynamic
block, generate results, follow links, or perform external effects.

## Focused validation

Use:

```sh
make jan-structured-editing-focused-test
odin check src/jan_editing -no-entry-point -vet -warnings-as-errors
```

The focused target runs the implementation-independent Racket list, delimiter,
region, visibility, and resource models plus strict `src/view` and
`src/jan_editing` package tests. It does not import or build `src/odra`; linked
application behavior is covered by `jan-structured-editing-acceptance`.

Non-executing pipe-table authoring continues in the
[Jan Table Editing Reference](../jan-table-editing/index.md).
