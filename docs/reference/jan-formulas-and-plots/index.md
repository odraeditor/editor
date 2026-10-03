<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Formulas and Plots Reference

Jan formulas and plots operate on exact copied table snapshots. They produce
candidate cell replacements, debug traces, text output, or bounded provider
requests; they never mutate a document or launch an external process directly.

## Table snapshots and references

A table snapshot carries a stable table identity, exact Jan analysis scope,
row and column dimensions, optional unique column names, and row-major copied
cell values. Values distinguish empty, number, duration, Boolean, and explicit
error states.

References support:

- relative fields from the current formula cell;
- absolute row and column coordinates;
- current-row and current-column coordinates;
- uniquely named columns;
- inclusive rectangular ranges; and
- another admitted snapshot selected by its stable table identity.

A missing, ambiguous, out-of-range, or mismatched-table reference rejects. It
never selects a nearby table or silently treats the value as zero.

## Algebraic evaluation

The language owner parses source-preserved formula syntax into a bounded copied
program. The computation package evaluates literal and referenced values,
addition, subtraction, multiplication, division, negation, comparisons,
conditional selection, and sum, average, minimum, and maximum over ranges.

Numbers and durations retain distinct types. Durations add and subtract only
other durations and format as signed hours and minutes. Numeric division by
zero, mixed incompatible values, invalid stacks, excessive programs, and
failed references reject without producing a replacement.

Exact, relational, associative, and inclusive-range lookup operate only over
the supplied copied table. Dependency planning is stable and rejects missing
or cyclic nodes. Explicit iterative calculations carry a positive epsilon and
step ceiling; reaching the ceiling without convergence is a visible failure,
not an infinite loop.

## Recalculation and source preservation

Recalculation validates unique target cells and evaluates every requested
program into scratch storage. Only a complete successful set is copied into
the candidate replacement buffer. A failed formula leaves the output buffer,
prior cell values, formula lines, and unrelated source unchanged.

The caller may target a field, row, column, table, region, or admitted
multi-table scope by constructing the corresponding ordered target set. Actual
document publication remains owned by the transaction and editing layers.

## Inspection and debugging

Optional debug traces record each instruction, stack depth, current candidate
value, and resolved source cell. Tracing consumes the same copied snapshot and
never changes table data. The trace is bounded by 65,536 steps.

## Text plots

Text plots scale copied numeric points to a requested width no greater than 256
columns. Positive and negative values remain visibly distinct, zero remains
empty, and insufficient output storage rejects rather than truncating an
unattributed row.

## Gnuplot handoff

Gnuplot adaptation creates a request containing:

- the originating operation and exact computation scope;
- adapter generation and copied table identity;
- the copied snapshot digest and point count;
- PNG, SVG, or PDF output selection;
- a provider-owned copied output resource;
- requested dimensions and serialized input size; and
- complete process and resource limits.

The request contains no mutable buffer pointer and does not grant process,
filesystem, network, or publication authority. The
[Jan Execution Adapters Reference](../jan-execution-adapters/index.md) defines
adapter selection, authority, process requests, cancellation, and quarantine.
Process failure therefore cannot change the source table.

## Current boundary

Slice 10 provides native formula, lookup, recalculation, trace, text-plot, and
Gnuplot-request behavior. It does not execute source blocks or Gnuplot, insert
results, create sessions, retain cache entries, or compose commands into the
editor. Those responsibilities remain in later computation slices and final
linked acceptance remains in Slice 24.
