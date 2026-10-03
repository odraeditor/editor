<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Compute in Documents

This chapter recalculates one table and executes one source block. It shows
when Jan calculates, runs code, publishes results, and changes source text.

## Before You Begin

The supplied exercise kit is prepared by
[Prepare the User Guide Exercises](../getting-started/prepare-exercises.md).
Open
`~/odra-guide/work/projects/forecast-engine/notes/jan-workflows/computation/report.jan`.
Run `M-x jan-computation-status`. Continue when table calculation is
operational. Source execution also requires an available adapter and admitted
execution policy.

## Recalculate the Table

Place point in the `Total` table and run `M-x jan-table-recalculate`. Jan
resolves references, evaluates the dependency graph, and prepares one checked
result update. Use `M-x jan-table-debug-formula` to inspect the formula without
changing the document.

`jan-table-recalculate-all` calculates all admitted tables in dependency
order. A cycle, invalid reference, stale revision, or limit failure preserves
the previous cells and source. `jan-table-plot` always supports a bounded text
plot; Gnuplot output is optional and reports unavailable when its adapter is
absent.

## Execute One Source Block

Move to the supplied Racket block and run `M-x jan-execute`. Review the
language, adapter, session, input, result, time, memory, filesystem, process,
and network policy before confirmation. Opening, parsing, presenting, saving,
exporting, or publishing the document never executes the block.

Accept the operation only when the request matches the supplied safe example.
The result is typed before publication. Inspect it with
`M-x jan-result-inspect`; remove only the result with
`M-x jan-result-remove`. A missing adapter or denied authority is a valid
unavailable outcome and leaves the source unchanged.

Use `jan-execute-subtree`, `jan-execute-buffer`, or `jan-execute-batch` only
after inspecting the larger target set. `jan-call` invokes one named admitted
target. Cancellation and timeouts stop through the process owner and do not
turn partial output into an accepted result.

## Edit and Extract Source

Run `M-x jan-edit-source` to edit the block through a focused owner. Return
with `M-x jan-return-from-source`; the checked edit keeps block delimiters and
indentation intact.

Inspect named expansion with `M-x jan-noweb-inspect`. `jan-tangle` and
`jan-tangle-file` prepare checked output plans. They do not overwrite a
resource with a stale expected revision. `jan-library-load` admits an exact
shared-library source; it does not execute it.

## Verify the Result

You have completed this chapter when table recalculation updates only the
expected result range, formula inspection is non-mutating, an unavailable or
denied adapter preserves source, and an accepted safe execution produces a
typed result that can be inspected and removed independently.

See the [Jan Computation Operations Reference](../../../reference/jan-computation-operations/index.md)
for commands, batch policy, sessions, caches, and failure guarantees.

---

[Previous: Plan Work](plan-work.md) ·
[Structured Documents](index.md) ·
[Next: Export and Publish](export-and-publish.md)
