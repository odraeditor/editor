<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Work with Buffers

This chapter keeps several file-backed and pathless buffers live, switches
among their retained editing states, inspects the complete Buffer Menu, and
uses the protected save and close workflows.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../getting-started/prepare-exercises.md).

Complete [Editing](../editing/index.md). Restore the `notes` group so the
kit-supplied practice files are fresh and the chapter-created
`session-notes.txt` is absent, then open `editing-practice.txt`:

```sh
~/odra-guide/kit/bin/odra-guide reset notes
odra ~/odra-guide/work/dirs/notes/editing-practice.txt
```

Odra starts with one file-backed buffer. A buffer owns live text and editing
history; a pane presents a view of a buffer. This chapter changes the live
buffer set without arranging panes yet.

## Create a Pathless Buffer

Press `C-x b` to run `switch-to-buffer`. Existing buffers appear as filtered
candidates. Enter this unmatched name:

```text
session-notes
```

The candidate surface exposes one `create` row. Press Enter to create and
activate the empty pathless buffer, then type:

```text
Review the afternoon forecast.
```

Press `C-x C-s`. Because the buffer has no file yet, Odra opens `Save as:`.
Enter:

```text
~/odra-guide/work/dirs/notes/session-notes.txt
```

This path is created by the current chapter; it is not supplied by the kit.
The `notes` reset group removes it.

Press Enter. The buffer becomes file-backed without losing its text, cursor,
or history.

## Open and Reuse Files

Press `C-x C-f`, enter the following path, and press Enter:

```text
~/odra-guide/work/dirs/notes/review.md
```

Odra opens the file as another live buffer and selects it. Opening the same
normalized path again reuses this buffer instead of rereading the file into a
duplicate editing state.

Press `C-x b`, type `editing-practice`, and select the matching file-backed
candidate. The cursor and viewport return to the state retained when you left
that buffer. Switch to `session-notes.txt` and back to `review.md` to verify
that each buffer retains its own cursor and undo history.

An unmatched nonempty `C-x b` query means create a pathless buffer. `C-x C-f`
always resolves a file path. Press `C-g` to cancel either interaction without
changing the active buffer.

`C-x Right` and `C-x Left` select the next or previous live buffer. Traversal
wraps in stable session order; revisiting a buffer does not reorder that cycle.
With only one live buffer, either command reports that no other buffer exists.

## Replace, Write, and Insert Files

Press `C-x C-v` to replace the current clean buffer with another file. A
modified buffer remains active until it is saved or explicitly discarded, so
the replacement cannot hide unsaved work.

Press `C-x C-w` to write the current buffer to a new path and continue visiting
that path. Existing destination files use the same protected publication path
as other saves; a rejected publication leaves the current association intact.

Press `C-x i` to choose a UTF-8 text file and insert its contents at point. The
complete insertion is one undoable edit. Empty files and non-UTF-8 input are
rejected without changing the buffer.

Press `C-x C-q` to toggle mutation of the active text buffer. While read-only,
editing commands fail without creating history; the same binding restores
editing.

## Read the Buffer Menu

Press `C-x C-b`. The Buffer Menu lists the active buffer first, followed by
the remaining buffers in most-recently-used order. Each row contains a mark,
compact state flags, and the complete buffer label.

| Indicator | Meaning |
| --- | --- |
| `S` or `D` | The row is marked for save or close. |
| `.` | This is the active buffer. |
| `*` | The buffer has unsaved changes. |
| `F` or `U` | The buffer is file-backed or pathless. |
| `!` | The buffer currently owns an unfinished operation. |

Use Up or Down to move between rows. Press Enter to activate the highlighted
buffer, or press `q` or `C-g` to close the menu and return to the buffer that
opened it.

## Save and Close Marked Buffers

Press `C-x s` to open the Buffer Menu with every modified file-backed buffer
premarked for save. Review or change the marks, then press `x`. A prefix
argument, `C-u C-x s`, executes that save batch immediately. Pathless modified
buffers remain explicit because they require a destination decision.

Activate `review.md`, add one checklist line, and reopen the Buffer Menu. Move
to the modified `review.md` row and press `s`; the row gains an `S` mark and
selection advances when another row is available.

Move to `session-notes.txt` and press `d`; the row gains a `D` mark. Press `u`
once to remove that mark, then press `d` again. This changes only the pending
operation set.

Press `x` to execute all current marks. The review file is saved and its
modified indicator clears. The clean `session-notes.txt` buffer closes, but
its saved file remains on disk. The menu refreshes from the surviving live
buffers after the complete operation.

If a marked pathless buffer must be saved before closing, choose `s` at the
`Marked buffer:` decision and complete the `Save marked buffer as:` path
interaction. Choose `d` to discard its unsaved text, or `c` to cancel the
complete marked operation.

## Close One Buffer Safely

Press `C-x b`, create `temporary-draft`, and type `discard this draft`. Press
`C-x k`, filter for `temporary-draft`, and press Enter.

The buffer is modified and pathless, so Odra presents:

```text
Modified buffer: [s]ave [d]iscard [c]ancel
```

Press `c` first. The buffer remains live and active state is preserved. Run
`C-x k` again, select `temporary-draft`, and press `d`. Odra closes it and
activates a surviving buffer.

A modified file-backed buffer instead asks whether to discard its changes.
Declining leaves it live. A clean buffer closes without a content decision.

## Exit with Several Buffers

Press `C-x C-c` when the practice session is complete. Odra checks modified
buffers in most-recently-used order. Save or explicitly discard each one; a
single cancellation aborts the exit and keeps the remaining buffer set live.

Successful saves completed before a later cancellation remain saved. Odra
does not silently discard modified file-backed or pathless text.

## Verify the Result

You have completed this chapter when you can create and save a pathless
buffer, open and revisit several files with independent editing state, read
the Buffer Menu indicators, execute a mixed marked save-and-close operation,
cancel a protected close, and exit without losing modified text.

Continue with [Arrange Panes](arrange-panes.md) to present the live working set
through a nested layout.

For exact session, candidate, Buffer Menu, dirty-close, and resource behavior,
see the [Editor Session Reference](../../../reference/editor-session/index.md).

---

[Previous: Save and Revisit Editor State](../editing/save-and-revisit-state.md) ·
[User Guide](../index.md) ·
[Next: Arrange Panes](arrange-panes.md)
