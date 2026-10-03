<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Plan Work

This chapter turns one supplied Jan file into a task plan and a revision-bound
agenda.

## Before You Begin

Prepare or reset the supplied exercise project as described in
[Prepare the User Guide Exercises](../getting-started/prepare-exercises.md):

```sh
"$HOME/.local/bin/odra-guide" reset forecast-engine
```

Open the supplied
`~/odra-guide/work/projects/forecast-engine/notes/jan-workflows/planning/tasks.org`
file. Run `M-x jan-planning-status`. Continue when task planning, metadata,
time, capture, and agenda capabilities are operational.

## Update a Task

Place point on `Review observation model` and run `M-x jan-todo`. Select the
next admitted state. Run `M-x jan-set-priority`, then `M-x jan-set-tags` and
add a project tag. Each accepted command changes one exact source range through
ordinary undoable editor history.

Move to the checklist item and run `M-x jan-toggle-checkbox`, followed by
`M-x jan-update-statistics`. The parent statistics cookie now matches the
completed children.

Use `M-x jan-set-property` to change the supplied `OWNER` value. Run
`M-x jan-property-search` to find the task by its current property. Use
`M-x jan-column-view` to inspect captured property values without replacing
the document.

## Add Time and Effort

Run `M-x jan-schedule` and select a valid date. Add a deadline with
`M-x jan-deadline`, then set an estimate with `M-x jan-set-effort`.

Start work with `M-x jan-clock-in` and finish it with `M-x jan-clock-out`.
`M-x jan-clock-report` derives a report from confirmed clock records. Relative
timers use `jan-timer-start`, `jan-timer-pause`, `jan-timer-resume`, and
`jan-timer-stop`; they do not edit the document unless a separate command
requests an edit.

## Refile, Capture, and Attach

Run `M-x jan-copy-subtree` before trying `M-x jan-refile`. Review the exact
destination and operation. Cross-document changes remain recoverable and do
not remove the source until the destination outcome is accepted.

Run `M-x jan-capture`, choose a supplied template, and review the preview. Use
`M-x jan-capture-finalize` to publish it or `M-x jan-capture-abort` to leave
all targets unchanged. Attachments use `jan-attach`; opening and revealing use
`jan-attachment-open` and `jan-attachment-reveal`. Network-backed attachment
and feed work requires an available provider and an explicit command such as
`jan-feed-refresh`.

## Build an Agenda

Run `M-x jan-agenda`. The result identifies its source and revision. Use
`jan-agenda-next-entry`, `jan-agenda-previous-entry`, and
`jan-agenda-reveal-source` to navigate. `jan-agenda-filter` changes the view;
it does not mutate source.

Agenda edits such as `jan-agenda-todo`, `jan-agenda-schedule`, and
`jan-agenda-set-property` recheck the target revision before preparing a
document edit. If a source changed, refresh with `M-x jan-agenda-refresh`
instead of forcing the stale operation.

## Verify the Result

You have completed this chapter when the task, metadata, and schedule survive
save; the agenda reveals the exact source; one stale edit is rejected without
changing text; and undo reverses one accepted semantic edit.

For the full command catalog and limits, see the
[Jan Product Surface Reference](../../../reference/jan-product-surface/index.md).

---

[Previous: Structured Documents](index.md) ·
[Structured Documents](index.md) ·
[Next: Compute in Documents](compute-in-documents.md)
