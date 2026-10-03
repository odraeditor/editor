<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Time Workflows Reference

Jan time workflows operate over exact Planning and Agenda scopes. Canonical
document text remains the source of truth; locale, time-zone providers,
notifications, and in-memory timers cannot mutate it without a checked rewrite
plan.

## Timestamp entry and ranges

`Timestamp_Spec` describes one active or inactive civil timestamp, optional
time, compatible repeater, and warning interval. `timestamp_text_format`
produces canonical Jan/Org syntax with an English weekday independent of the
presentation locale. `timestamp_range_text_format` joins two compatible
endpoints only when their activity class matches and the end is not before the
start.

`civil_date_shift_days` provides bounded positive and negative relative
calendar navigation. Invalid civil dates reject before source mutation.

## Time-zone interpretation

`time_zone_resolve` applies this fixed precedence:

1. invocation;
2. document;
3. Project;
4. Workspace;
5. user configuration; and
6. system zone captured at operation start.

The function copies the selected zone identity. A zone provider classifies a
local value as valid, a daylight-saving gap, or a fold. `local_time_resolve`
rejects gaps and requires an explicit earlier/later choice for folds. The
result retains the civil value, selected zone, absolute instant, and fold
decision.

## Recurrence and planning facts

`recurrence_advance` implements compatible repeater semantics:

- `Stored_Base` (`+N`) advances exactly one interval from the stored value;
- `Catch_Up` (`++N`) advances whole intervals until the value is after the
  captured comparison time; and
- `Completion_Base` (`.+N`) advances exactly once from completion time.

Day, week, month, and year units use Gregorian calendar arithmetic. Month and
year overflow either rejects or clamps according to the explicit invalid-date
policy. Catch-up is bounded to 4,096 steps.

`time_source_plan_prepare` accepts up to 64 related replacements on one exact
heading. It requires every prior source value to occur uniquely, rejects
overlap and stale ownership, constructs one node-owned replacement, and lets
the Jan rewrite owner minimize it to one ordinary transaction. Scheduling,
deadline, closure, repeating-task, clock, and timer source updates therefore
share the canonical transaction and undo path.

Read-only recurrence, warning, deadline, and agenda calculations do not rewrite
source.

## Durable clocks

`Active_Clock_Record` remains the versioned persistence boundary. The clock
workflow provides start, stop, cancel, resume, switch, idle resolution, restart
recovery, and table aggregation while admitting at most one unresolved record
per clock domain.

Stopping returns a closed `Clock_Entry`. Switching closes the old target and
starts the new target as one attributable in-memory decision for the caller to
persist and publish. Idle handling requires `Keep`, `Subtract`, or `Cancel`;
there is no implicit activity. Restart recovery requires `Resume`, `Close`, or
`Discard`, and resume must supply a re-resolved exact target.

Clock tables group valid closed entries by exact semantic target and subtract
only explicitly recorded idle seconds. Continuous clocking is represented by
the same explicit switch operation and remains inspectable.

## Effort and relative timers

Effort values accept bounded `H:MM`, minute, hour, day, and week forms and
normalize to seconds. Deterministic formatting returns `H:MM` for properties,
columns, sorting, and agenda constraints.

Relative timers are independent from task clocks. Stopwatch and countdown
records support start, pause, resume, stop, reset, elapsed insertion, and
bounded tick inspection. A completed countdown reports notification delivery
as requested or unavailable. Notification failure does not roll back or corrupt
the completed timer state. Cancellation rejects the tick without mutating the
input record.

## Current composition boundary

This slice supplies native domain behavior, the independent Racket model,
checked source plans, and identical `.org`/`.jan` fixtures. Public commands,
bindings, bridge records, agenda interaction, persistence wiring, and linked
application acceptance remain assigned to the planning and product closure
slices.

## Focused validation

Use:

```sh
make jan-planning-focused-test
```

The target runs the independent Racket model, parity fixtures, resource study,
configuration checks, and strict unoptimized `src/jan_planning` tests. This
keeps the inner loop outside the expensive LLVM optimization pass while
preserving source checking and every runtime assertion. It does not build
`src/odra` or run PTY acceptance.
