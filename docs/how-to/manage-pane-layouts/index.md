<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Manage Pane Layouts

Use these commands while an editing buffer is visible.

## Split the active pane

- Press `C-x 2` to create a pane below the active pane.
- Press `C-x 3` to create a pane to the right of the active pane.

The original pane remains active. A split is accepted only when every resulting
pane satisfies the operating minimum.

## Move focus

Press `C-x o` to focus the next pane in spatial reading order. The order wraps
after the final visible pane. The leading `*` on a pane status line identifies
the active pane.

## Resize the active pane

- Press `C-x ^` to enlarge the active pane by one row.
- Press `C-x }` to enlarge the active pane by one column.
- Press `C-x {` to shrink the active pane by one column.

Each command moves the nearest divider with the requested orientation by
exactly one terminal cell. Odra stores the resulting spans as the partition's
new exact ratio, so a later terminal resize preserves that proportion.

The command rejects without changing the layout when the active pane has no
compatible ancestor divider or when moving the nearest compatible divider
would place either subtree below its operating minimum. It does not try a
farther divider after the nearest compatible one rejects. Vertical shrinking
has no factory key binding.

## Balance pane dimensions

Press `C-x +` to rebalance the visible pane dimensions. Odra preserves the
existing split tree, respects pane minima and separator cells, and chooses a
deterministic best valid layout when exact equality is impossible. Running the
command again is a no-op when the current proportions already match that
result.

## Balance pane areas

1. Press `M-x`.
2. Enter `balance-pane-areas`.
3. Press Enter.

Odra preserves the split tree and chooses the valid proportions that minimize
differences between final pane areas. This objective is distinct from `C-x +`:
`balance-panes` balances visible rows and columns and may favor panes spanning
a full axis, while `balance-pane-areas` compares each pane's final height times
width.

There is no factory key binding for area balance. Both commands respect
operating minima and separators, resolve integer ties deterministically, and
leave the layout unchanged when it already matches their result. Area balance
also rejects without change when its bounded search would exceed the geometry
work ceiling.

## Change the active pane's buffer

1. Press `C-x b`.
2. Select an existing buffer or enter a new unique name.
3. Press Enter.

Only the active pane changes. Returning to a buffer restores the point and
viewport retained by that pane. If another pane already displays the selected
buffer, both panes share canonical text while keeping independent presentation
state.

When `C-x k` kills a buffer displayed in several panes, Odra replaces every
occurrence together. Each pane prefers its own previous live buffer, then the
layout-wide recency order. Killing the final editing buffer creates
`*scratch*`; it does not return to the pathless Startup list.

## Display a buffer in another pane

- Press `C-x 4 f`, choose a path, and press Enter to open or reuse that file in
  another pane and focus the destination.
- Press `C-x 4 b`, choose a live buffer or enter a new unique name, and press
  Enter to show it in another pane and focus the destination.
- Press `C-x 4 C-o`, choose a buffer, and press Enter to show it in another
  pane while retaining focus in the current pane.

The display policy may reuse a non-active pane or create one. Factory policy
prefers an existing pane already showing the requested buffer, then a split
below, then a split right, and finally the least-recently used eligible pane.
If none is possible, the command rejects without changing the active pane or
its buffer.

Use `C-x 2` or `C-x 3` when orientation is the task. Other-pane commands choose
a destination according to policy; they do not guarantee that a new pane is
created or that it appears below or to the right.

## Remove panes

- Press `C-x 0` to close the active non-final pane without killing its buffer.
- Press `C-x 1` to keep only the active pane.

`C-x 0` rejects when only one pane remains. `C-x 1` is a no-op in that state.

## Recover from insufficient geometry

When the terminal cannot fit every pane's semantic floor, resize the terminal
or use `C-x 0` or `C-x 1` to reduce the tree. `C-x C-c` remains available for
orderly exit. Manual resize, balance, and other commands are rejected until the
complete tree fits again. This includes both balance commands.

To verify the workflow and terminal restoration, run:

```sh
make terminal-presentation-test
```

See [Work with Multiple Terminal Panes](../../tutorials/multiple-panes/index.md)
for a guided nested-layout session. See
[Configure Other-Pane Display Policy](../configure-pane-display-policy/index.md)
to replace the automatic destination order and thresholds through Racket.
