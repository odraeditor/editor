<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Move and Edit Text

This chapter moves through text by grapheme, word, line, and page, then uses
the direct editing keys for indentation, deletion, line breaks, and overwrite
input.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../getting-started/prepare-exercises.md).

Complete [Getting Started](../getting-started/index.md). The exercise kit
supplies the editing-practice file. Restore it before beginning:

```sh
~/odra-guide/kit/bin/odra-guide reset notes
```

Open the editing practice file:

```sh
odra ~/odra-guide/work/dirs/notes/editing-practice.txt
```

The cursor begins before `Editing Practice`.

## Move by Grapheme

Use `C-f` or Right to move forward by one complete displayed grapheme. Use
`C-b` or Left to move backward.

Move to the `Symbol:` line and cross `🌦️` one step at a time. The emoji and its
variation marker remain one visible unit: movement does not stop inside the
cluster. At the start or end of the buffer, movement beyond the available text
is a no-op.

## Move by Line and Column

Use `C-n` or Down for the next logical line and `C-p` or Up for the previous
one. Vertical movement remembers the desired display column. Move near the end
of the long line below `short`, press Up to visit the shorter line, then press
Down. The cursor returns to the remembered column when that column exists.

Use `C-a` or Home for the start of the current logical line. Use `C-e` or End
for its end. On the indented observation line, press `M-m` to move directly to
the first non-whitespace grapheme.

## Move by Word

Use `M-f` to move to the next word boundary and `M-b` to move to the previous
one. The factory policy treats Unicode letters, digits, and `_` as word
graphemes.

`C-Right` and `C-Down` also move forward by word. `C-Left` and `C-Up` move
backward by word. `M-Right` and `M-Left` provide the familiar aliases. These
keys operate on the document only while an editing pane owns input; a prompt or
candidate list may give them a local meaning.

## Move to Direct Targets

Use `M-<` and `M->` to move to the beginning or end of the buffer. Use `M-g g`
to enter a one-based logical line number and `M-g c` to enter a one-based
grapheme position. A target beyond the available text clamps to the final line
or buffer end. Zero, negative, and non-numeric targets remain in the prompt as
invalid input.

## Move by Page

Press Next, commonly labelled Page Down, to move through approximately one
viewport while retaining one line of context. Press Prior, commonly labelled
Page Up, to move back. Paging changes only the active view and creates no edit
history.

The Status Bar position changes from `Top` to a percentage and eventually to
`Bot` as the cursor moves through the practice file.

Press `C-l` to center point vertically in the active viewport without moving
point or changing the buffer.

## Insert and Delete Text

Return to the first line with Prior and Up. Type a short word. Printable UTF-8
inserts at the cursor. Press Backspace to remove the complete grapheme before
the cursor, or Delete to remove the complete grapheme after it. While the
cursor remains in leading whitespace, Backspace instead returns to the
previous logical indentation boundary.

Press Enter to insert one line break. Press Tab to insert one indentation unit.
The factory width is four spaces, and the insertion follows the same reversible
editing path as ordinary text.

Run `normalize-indentation-to-tabs` or
`normalize-indentation-to-spaces` through `M-x` to convert leading indentation
on the current or selected lines. Interior alignment remains unchanged, and
the complete conversion is one undo unit.

Press `C-/` to undo the practice edits before continuing. `C-_` and `C-x u`
invoke the same `undo` command.

## Use Overwrite Input

Place the cursor before `morning` on the `Forecast window:` line. Press Insert
to enable overwrite input for the active view, then type `M`. The next complete
grapheme is replaced rather than shifted to the right.

Press Insert again to restore ordinary insertion. Overwrite state belongs to
the current view; enabling it does not change the file until text is typed.
Input at the end of the buffer still inserts because there is no following
grapheme to replace.

Undo the replacement with `C-/`. Save only if you want to retain other
practice edits; otherwise exit with `C-x C-c` and choose `d` when asked about
the modified buffer.

## Recover from Unexpected Movement

If a key moves a prompt selection or candidate row instead of the document,
finish that interaction or press `C-g`. Direct movement resumes when the
editing pane owns input again.

Movement at a text or page boundary is a checked no-op. It does not wrap,
change the buffer, or create an undo entry.

## Verify the Result

You have completed this chapter when you can cross the emoji as one unit,
restore a desired column after visiting a short line, move by word and page,
visit a numbered line or grapheme position, insert four factory spaces with
Tab, and toggle overwrite behavior without leaving a retained text change.

Continue with [Select Text](select-text.md).

For the complete command table and context rules, see the
[Direct Navigation Reference](../../../reference/direct-navigation/index.md).

---

[Previous: Getting Started](../getting-started/index.md) ·
[User Guide](../index.md) ·
[Next: Select Text](select-text.md)
