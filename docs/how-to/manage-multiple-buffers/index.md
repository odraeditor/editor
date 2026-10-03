<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Manage Multiple Buffers

Use these procedures to create, open, select, kill, and safely exit live
buffers in the terminal frontend.

## Start without opening a buffer

1. Run `.build/odra` without a path.
2. Keep `Create a new buffer` selected and press Enter to enter a unique name,
   or move to `Open File` and press Enter to enter a path.
3. Complete the ordinary `Switch to buffer:` or `Find file:` prompt.

The startup surface is a shared list root, not an editable buffer. It owns no text,
document, history, or primary-view graph.

## Create a named unassociated buffer

1. Press `Control-X`, then `b`.
2. Enter a nonempty UTF-8 name. The highlighted `create` row is the only
   synthetic candidate when no exact label exists.
3. Press Enter on that row.

If the exact selection label does not exist, `switch-to-buffer` creates an
empty unassociated buffer and selects it. Names are not numbered or rewritten
to avoid a collision.

## Switch to an existing buffer

1. Press `Control-X`, then `b`.
2. Type any case-insensitive part of the name or path.
3. Move with `Control-N`, `Control-P`, Down, or Up, then press Enter.

For an unassociated buffer, the label is its explicit name. For a file-backed
buffer, the label is its complete normalized absolute path. Equal basenames in
different directories therefore remain unambiguous.

Without a pane layout, switching restores the retained primary view's stored
point, desired column, viewport, layout policy, and view-local search state.
With panes visible, switching replaces only the active pane. Returning to a
buffer restores that pane's retained point, viewport, horizontal column, and
desired column. Other panes keep their current buffers and presentation state.
The buffer retains its effective point, mark, and active-region state. Undo and
redo continue through that buffer's independent history.

## Open or select a file

1. Press `Control-X`, then `Control-F`.
2. Enter a relative or absolute local path.
3. Press Enter.

Odra normalizes the path before filesystem inspection. If the normalized
target is already open, it selects the existing buffer without reading the
file again. Otherwise it privately prepares the document, buffer, history,
and primary view and publishes the complete graph together.

A missing final target opens as an empty file-backed buffer. Edit it and press
`Control-X`, then `Control-S` to create it through the safe save path.

## Cancel a prompt

Press `Control-G` while `Find file:` or the buffer navigator is active. Odra
cancels without creating, opening, or activating a buffer. `Backspace` or
`DEL` removes one complete UTF-8 scalar from the buffer query.

An empty creation query, malformed UTF-8, an oversized path or name, an
unsupported filesystem target, a duplicate label, exhausted session capacity,
or an allocation failure produces a bounded diagnostic and preserves the
previously visible entry.

## Kill a buffer

1. Press `Control-X`, then `k`.
2. Keep the prefilled current label or replace it with another complete
   selection label.
3. Press Enter.

A clean target closes immediately. Killing an inactive, undisplayed target
leaves the visible panes unchanged. When the target appears in one or more
panes, every occurrence is replaced atomically. Each pane first uses its own
most recently shown surviving buffer, then the layout-wide recency list.

For a modified file-backed target, press `y` to discard its changes and kill
it, or `n` to keep it live. For a modified unassociated target, press `s` to
choose a path and save before killing, `d` to discard, or `c` to cancel. A
failed or canceled first save keeps the buffer live.

After editing has begun, killing the final buffer creates and displays the
unassociated `*scratch*` buffer. The pathless Startup list is reserved for
the distinct state before the first editing buffer is created or opened.

## Inspect and select live buffers

1. Press `Control-X`, then `Control-B`.
2. Move with Up or Down.
3. Press Enter to activate the highlighted buffer, or press `q` or `Control-G`
   to return to the buffer that opened the menu.

Rows appear in active-then-most-recently-used order. File-backed entries use
their complete normalized path; unassociated entries use their complete name.

## Execute marked saves and kills

1. Open the Buffer Menu with `Control-X`, then `Control-B`.
2. Press `s` to mark the current row for save, `d` or `k` to mark it for kill,
   or `u` to remove its mark. Setting a mark advances to the next row.
3. Repeat for every intended entry.
4. Press `x` to execute the complete marked set.

Save marks are published in menu order. If a later save fails, earlier saves
remain externally true, completed rows are unmarked, and the diagnostic reports
the remaining failure.

Before marked kills detach any graph, Odra resolves every modified entry. At
`Marked buffer: [s]ave [d]iscard [c]ancel`, press `s`, `d`, or `c`. Saving an
unassociated entry opens `Save marked buffer as:`. Cancellation or a required
save failure kills none; any earlier successful save remains on disk.

The menu refreshes after execution. Stale rows and marks never apply to a
replacement entry.

## Exit with several modified buffers

1. Press `Control-X`, then `Control-C`.
2. For each modified buffer, press `s` to save, `d` to discard, or `c` to
   cancel exit.
3. When saving an unassociated buffer, enter its target at `Save as:` and
   press Enter.

Buffers are considered in deterministic most-recently-used order. No buffer
graph is detached while the decisions are in progress. Cancellation or save
failure aborts exit and keeps all buffers live. Saves already completed before
the abort remain published to their targets.

Press `Control-G` at a choice or path prompt to cancel the current kill or
complete exit request.

## Validate programmable buffer access

Run the contracted Racket facade, native callback integration, focused batch
benchmark, and complete acceptance matrix:

```sh
raco test src/hosting/buffer-session-bridge.rkt src/command/buffers.rkt
make native-command-test
make buffer-session-command-benchmark
make buffer-session-acceptance
```

The benchmark passes only when its 512 measured descriptor batches remain
below the 8 ms p99 gate and every callback is released. The acceptance target
also checks selected and maximum aggregate session policies, normalized-path
reuse, dirty lifecycle decisions, Buffer Menu batches, generation invalidation,
and deterministic teardown.

See the [Editor Session Reference](../../reference/editor-session/index.md)
for exact identities, limits, activation behavior, and failure classes.

See the [Programmable Buffer Session Reference](../../reference/programmable-buffer-sessions/index.md)
for the copied Racket values and checked operation contracts.
