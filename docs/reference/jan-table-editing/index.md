<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Table Editing Reference

Jan table editing is the Stage 2 package boundary for non-executing pipe-table
authoring. It consumes one exact copied `Pipe_Table` from Jan Document Language
analysis and produces bounded rewrite plans or copied presentation state. It
does not retain parser nodes, create another document tree, or evaluate
formulas. Public commands coordinate the package through the current Jan
analysis and ordinary transaction owner.

## Table construction and structure

`jan_editing.table_edit_plan_prepare` creates empty tables, converts bounded
comma- or tab-delimited text, and edits existing pipe tables. Structural
operations cover:

- next and previous row or cell navigation;
- row and column insertion, deletion, movement, and duplication;
- separator-row insertion and removal; and
- rectangular copy, cut, paste, import, and export through tab-separated text.

Table parsing is derived transiently inside the exact Stage 1 `Pipe_Table`
range. Rows and cells are checked against their source delimiters, column
counts, recovery state, and copied analysis scope. No derived row or cell model
survives the operation.

Every admitted mutation becomes one `language.Jan_Rewrite_Plan` and one normal
transaction/history unit. A stale scope, malformed row, inconsistent separator,
invalid rectangle, unsupported delimiter, cancellation, allocation failure, or
resource overflow rejects before publication.

## Rectangular transfer

`Table_Rectangle` uses half-open data-row and column coordinates. Separator rows
do not consume data-row coordinates. `table_rectangle_copy_prepare` retains one
bounded tab-separated copy until `table_rectangle_copy_close` releases it.

Cut clears the selected cells after producing the same rectangular text. Paste
requires a rectangular tab-and-line-delimited payload that fits the destination
table. Import and export use this same representation and do not grant file or
clipboard authority.

## Presentation and focused cells

`table_presentation_prepare` derives copied display text with the repository's
Unicode 17 width profile. Per-column policy can set compatible width,
truncation, left/center/right alignment, and visual grouping markers. Display
width and stored cell bytes remain distinct.

`table_source_alignment_plan_prepare` changes padding only. It rejects
display-only truncation and grouping policies so source alignment cannot alter
cell values. `table_focused_cell_inspect` exposes the exact stored value range,
and `table_focused_cell_plan_prepare` replaces only that value.

Affiliated names, captions, formula lines, and settings remain outside the
owned table rewrite range and are preserved byte-for-byte.

## Formula boundary

`table_formula_inspect` reports whether an adjacent `#+TBLFM:` line is present
and returns its exact copied range. `table_future_stage_availability` retains
its Stage 2 API name but now reports the final linked Computable Documents
availability for `jan-computable-tables`.

This editing package only inspects formula ownership. Calculation and plotting
remain with the linked Computable Documents coordinator.

## Bounds and lifecycle

One table operation admits at most 65,536 cells and 16,384 rewrite splices.
Long scans observe cancellation at least every 4,096 entries. The stricter Jan
Document Language rewrite or editor transaction limit remains authoritative.

Copied rectangles and presentations own their retained bytes and require
explicit close. Tests cover malformed and stale input, Unicode widths, limit
rejection, cancellation, allocation faults, atomic rewrite publication, and
cleanup.

## Focused validation

Use:

```sh
make jan-structured-editing-focused-test
odin check src/jan_editing -no-entry-point -vet -warnings-as-errors
```

The focused target runs the implementation-independent Racket table model,
resource profiles, and strict `src/view` and `src/jan_editing` package tests. It
does not import or build `src/odra`; linked application behavior is covered by
`jan-structured-editing-acceptance`.

Display-only document projection, local footnotes, and bounded preview adapters
continue in the [Jan Rich Presentation Reference](../jan-rich-presentation/index.md).
