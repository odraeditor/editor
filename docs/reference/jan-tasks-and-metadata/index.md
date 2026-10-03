<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Tasks and Metadata Reference

`src/jan_planning` derives task and metadata behavior from one exact Jan
analysis scope and one confirmed planning configuration generation. The source
document remains canonical; this package neither creates a task database nor
retains syntax-tree pointers.

## Task workflows

`Task_Transition_Request` identifies one heading, workflow, current state,
optional direct destination or cycle direction, dependency policy, copied
dependency counts, optional compatible log record, and rewrite generation.

`task_transition_resolve` checks the planning and provider generations, finds
both states in the named ordered workflow, and rejects a finished destination
when required children or checkboxes remain incomplete. The failure reports
the exact unsatisfied count and publishes no partial state.

`task_transition_plan_prepare` additionally verifies that the source heading
still contains the requested current keyword. It prepares one node-owned Jan
rewrite containing the keyword transition and any requested closure or log
record. The language rewrite owner minimizes that replacement and exposes the
ordinary transaction batch, so the change is atomic and participates in
normal undo and redo.

Checkbox helpers preserve unchecked, intermediate, and checked states.
Statistics count only checked members as complete. Habit summaries derive
completion, misses, and the current streak from bounded occurrence facts and
never rewrite prior history. Priority normalization accepts alphabetic and
numeric source forms while leaving the original representation in source.

## Effective tags

`tag_set_resolve` combines case-sensitive local, inherited, file, and computed
tag candidates. It applies explicit inheritance exceptions, expands named
member groups, compiles configured regular-expression groups, and deduplicates
the result while retaining the first membership origin and owner.

`tag_query_matches` evaluates a bounded postfix expression containing tag,
`and`, `or`, and `not` tokens. Inspection can therefore distinguish local,
inherited, file-level, grouped, and computed membership. A local tag edit uses
`tag_local_edit_plan_prepare`; inherited membership is rejected until its
explicit owning target is selected.

## Properties

`property_resolve` consumes property candidates in confirmed precedence order.
It retains the primary stored, inherited, or derived value, its semantic owner,
the configuration generation, and every additive component with its origin.
Only a stored owner is editable. Derived and inherited values remain queryable
but cannot be mutated as local storage.

`property_edit_plan_prepare` checks the stored origin, optional allowed values,
exact scope, and unique current value before creating a node-owned rewrite.
Ambiguous, stale, inherited, derived, or disallowed edits fail without a plan.

## Column views

`column_view_project` maps property resolutions to bounded cells. Each cell
retains its row and column, displayed value, origin, canonical owner, and
editability. Empty cells still point at the row heading where a later admitted
property insertion belongs.

`column_snapshot_capture` serializes headings and cells as a deterministic
tab-separated snapshot. The snapshot owns its copied bytes, is capped at 4
MiB, records its configuration generation and dimensions, and must be released
with `column_snapshot_close`. Agenda column views can consume the same property
and cell contracts without introducing another metadata model.

## Limits and failures

- One task statistics, habit, tag, or column operation is bounded by the
  planning semantic-target ceiling.
- One additive property resolution retains at most 32 components.
- One Boolean tag expression contains at most 256 tokens.
- Tag expressions use the Odin Unicode regular-expression engine and reject a
  malformed expression without publishing a partial set.
- Exact scope, generation, owner, UTF-8, resource, allocation, and ambiguity
  failures are explicit.

## Current composition boundary

This slice provides the native domain behavior, independent Racket model,
checked rewrite plans, and `.org`/`.jan` parity fixtures. Public commands,
bindings, bridge records, agenda interaction, and linked application
acceptance remain assigned to the planning and product closure slices.

## Focused validation

Use:

```sh
make jan-planning-focused-test
```

The target runs the independent Racket task and metadata model, fixture parity,
resource studies, configuration checks, and strict `src/jan_planning` tests.
It does not build `src/odra` or launch a PTY acceptance run.
