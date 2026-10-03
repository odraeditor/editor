<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Work with Multiple Terminal Panes

This tutorial creates and resizes a nested pane layout, compares its two
balance objectives, displays independent buffers with selecting and
non-selecting other-pane commands, restores pane-local presentation,
coordinates buffer kill, reduces the layout, and observes geometry recovery.

## Start the terminal editor

Build Odra and open a local UTF-8 document:

```sh
make odra
./.build/odra path/to/document.txt
```

The initial presentation is a single editor view. Pane layout state is created
when the first pane command runs.

## Create a nested layout

Press `C-x 2` to split the active pane below. The original pane remains active,
and the new lower pane starts with an independent copy of its view state.

Press `C-x 3` to split the active upper pane to the right. The result has two
panes across the top and one pane across the bottom. A vertical separator marks
the left/right partition. Above/below panes need no extra separator row because
the upper pane's status line is already the boundary.

Each status line begins with `*` when its pane is active. It also shows the
buffer selection label, a modification indicator when applicable, and the
current point offset.

## Resize and balance the layout

Keep the upper-left pane active and press `C-x }` twice. Its nearest
left/right divider moves right by one column on each invocation. Press
`C-x {` once to move that divider back by one column, then press `C-x ^` to
enlarge the active pane by one row at its nearest above/below divider.

Each successful command changes exactly one row or column. If the nearest
compatible divider cannot move without taking a subtree below its operating
minimum, Odra rejects the command and leaves the complete layout unchanged.
It does not try a farther compatible divider.

Press `C-x +` to balance visible pane dimensions. The split topology remains
the same, but its proportions change to the deterministic closest valid
result. Exact equality may be impossible because of nesting, integer terminal
cells, pane minima, or separator columns. Pressing `C-x +` again is a no-op
when the layout is already balanced.

Now press `M-x`, enter `balance-pane-areas`, and press Enter. This second
balance command changes proportions to make the final pane areas as equal as
the current topology and terminal geometry permit. In the three-pane layout,
that result may differ from `C-x +`: dimension balance can favor a pane that
spans the full width, while area balance compares the final height multiplied
by width of every pane. The command intentionally has no factory key binding.

Run `balance-pane-areas` again. The command succeeds without changing the
layout when the current proportions already produce its deterministic optimum.

## Let display policy choose a pane

Press `C-x 4 b`, enter `notes`, and press Enter on the `create` row. Factory
policy reuses an eligible pane when possible or creates one below or to the
right. The destination becomes active because `switch-to-buffer-other-pane`
is a selecting command. Type a short line into `notes`.

Press `C-x 4 C-o`, choose the original file buffer, and press Enter. The file
is displayed in a policy-selected non-active pane, but `notes` remains active.
Type another character to confirm input still reaches `notes`.

Press `C-x 4 f`, enter another local path, and press Enter. Odra opens or
reuses the file in a policy-selected non-active pane and focuses that
destination.

These commands express other-pane intent, not orientation. Use `C-x 2` for an
explicit below split or `C-x 3` for an explicit right split. Automatic display
may instead reuse a pane, and its split thresholds do not constrain either
explicit split command.

## Move focus and edit

Press `C-x o` to focus the next pane in spatial reading order. Repeating the
command moves top to bottom and left to right, then wraps to the first pane.

Type a character. Canonical text changes in every pane because the panes show
the same buffer, while cursor position and viewport state remain pane-local.
The buffer's point is synchronized with the newly active pane whenever focus
changes.

Odra selection remains buffer-semantic: point, mark, and region belong to the
active buffer. A terminal emulator may independently select visible cells
across several panes and separators; that geometric selection is not an Odra
region.

## Restore pane-local buffer presentation

Return to the `notes` pane, move point away from the start, then switch that
pane back to the original file with `C-x b`. Switching once more to `notes`
restores the point and viewport retained by that pane. Another pane showing
the same buffer sees the same canonical text but keeps its own point and
viewport.

Press `C-x k` and kill `notes`. If it is shown in more than one pane, all of
those panes change together. Each uses its own previous live buffer when
available; otherwise Odra uses the layout-wide buffer recency order. The
killed buffer is removed from every pane history.

If you kill the final editing buffer, Odra creates the unassociated
`*scratch*` buffer and keeps the panes editable. This differs from initial
pathless startup, which displays a non-buffer list root before editing begins.

## Close and maximize panes

Press `C-x 0` to close the active pane. Its buffer remains live. The tree
collapses around the removed leaf, and focus moves to the most recently used
surviving pane.

Press `C-x 1` to keep only the active pane. Other panes and their additional
views are released. No hidden restorable layout is retained.

## Observe resize recovery

Create several panes again, then reduce the terminal size. Odra first preserves
the tree with reduced semantic geometry. If every pane can no longer retain one
content row, one status row, and one content cell, the pane frame is replaced by
one global insufficient-geometry diagnostic.

In that state, only these actions are admitted:

- enlarge the terminal;
- `C-x 0` to close the active pane;
- `C-x 1` to keep only the active pane; or
- `C-x C-c` to exit.

Other editing and navigation commands are rejected without changing text,
focus, or topology. This includes manual resize and balance commands. Normal
pane rendering resumes as soon as the complete tree fits its semantic floors
again.

See [Manage Pane Layouts](../../how-to/manage-pane-layouts/index.md) for the
compact command procedure and [Pane Layout Reference](../../reference/pane-layout/index.md)
for exact geometry and failure contracts.
