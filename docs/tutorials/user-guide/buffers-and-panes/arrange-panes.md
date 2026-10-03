<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Arrange Panes

This chapter splits the editing surface, moves focus, changes pane geometry,
balances a nested layout, and safely reduces it again.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../getting-started/prepare-exercises.md).

Complete [Work with Buffers](work-with-buffers.md). Open the same kit-supplied
editing-practice file if it is not already active:

```sh
odra ~/odra-guide/work/dirs/notes/editing-practice.txt
```

Start with a terminal large enough to display three editing panes. Each pane
reserves content space and one Status Bar row.

## Build a Three-Pane Layout

Press `C-x 2`. The active pane splits into an upper pane and a new pane below.
The original pane remains active, and the lower pane begins with an independent
view of the same buffer.

Press `C-x 3`. The active upper pane splits again, this time into left and
right panes. The result has two panes across the top and one pane across the
bottom. A vertical separator identifies the left and right panes; each pane's
Status Bar separates rows of panes.

The active pane has the active Status Bar treatment. All three panes show the
same canonical text initially, but each pane has its own view state.

## Move Focus

Press `C-x o` to focus the next pane in spatial reading order. Repeated presses
move left to right, then top to bottom, and wrap to the first pane.

With pointer reporting available, press the primary pointer button anywhere in
a visible pane to focus it directly. A press over ordinary text also places
point at the represented text boundary. A press over a gutter, Status Bar, or
other non-text part of the pane changes focus without fabricating a text
position. `C-x o` remains the complete keyboard path when pointer reporting is
unavailable.

Move the cursor to a distinct line in each pane before changing focus again.
The active buffer point follows the newly focused view; inactive panes retain
their own cursor and viewport positions.

## Resize One Divider

Focus the upper-left pane. Press `C-x }` twice to enlarge it horizontally by
one terminal column per command. Press `C-x {` once to shrink it horizontally
by one column.

Press `C-x ^` to enlarge the upper pane vertically by one row at the nearest
above-and-below divider. Each successful command moves exactly one compatible
divider by one cell.

If no divider with the required orientation exists, or moving the nearest one
would make a subtree too small, Odra rejects the resize and preserves the
complete layout.

## Balance Dimensions and Areas

Press `C-x +` to balance pane dimensions without changing the three-pane
topology. Integer terminal cells, nested splits, minimum sizes, and the
vertical separator may prevent exact equality. Repeating the command on an
already balanced layout is a no-op.

Open `M-x`, run `balance-pane-areas`, and press Enter. This command balances
the final visible pane areas rather than the dimensions of each split. With
two top panes and one full-width lower pane, its result may differ from
`C-x +`.

Both balancing commands retain buffers, cursor positions, focus, and split
topology. They change only admitted layout proportions.

## Close and Maximize

Focus a pane that you no longer need and press `C-x 0`. The pane closes, its
buffer remains live, and the surrounding layout collapses around the removed
leaf. Focus moves to the most recently used surviving pane.

Create another split, focus the pane you want to keep, and press `C-x 1`.
Every other pane closes and the active pane fills the editing area. This is a
structural reduction, not a temporary zoom: no hidden pane tree remains for a
later toggle.

## Recover from Insufficient Geometry

Create several panes again, then make the terminal too small to retain at
least one content row, one Status Bar row, and one content cell for every
pane. Odra replaces the pane frame with one insufficient-geometry diagnostic
while preserving the complete tree and its view state.

In that state, enlarge the terminal, press `C-x 0` to remove the active pane,
press `C-x 1` to keep only it, or press `C-x C-c` to exit. Other editing,
movement, resize, and balance commands are rejected without changing text or
topology until the layout fits again.

## Verify the Result

You have completed this chapter when you can create the three-pane topology,
cycle focus, move both divider orientations, distinguish dimension and area
balancing, close one pane, keep only another, and recover from constrained
terminal geometry without losing text.

Continue with [Understand Pane-Local State](understand-pane-state.md) to
compare independent views and selecting versus display-only commands.

For exact topology, geometry, operating minima, command, and failure behavior,
see the [Pane Layout Reference](../../../reference/pane-layout/index.md).

---

[Previous: Work with Buffers](work-with-buffers.md) ·
[User Guide](../index.md) ·
[Next: Understand Pane-Local State](understand-pane-state.md)
