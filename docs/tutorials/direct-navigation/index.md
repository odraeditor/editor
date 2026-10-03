<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Navigate and Edit Directly

The factory direct profile supplies ordinary text navigation and editing through
one consistent command set. These bindings work in an editable view; a prompt,
candidate list, search, or other active interaction may temporarily own its
documented local keys.

## 1. Open a text file

```sh
make odra
.build/odra path/to/file.txt
```

The factory catalog selects profile `direct` with state `direct-editing`.

## 2. Move by grapheme and line

Use `C-f` and `C-b` to move forward and backward by complete graphemes. Use
`C-n` and `C-p` to move by logical lines. Arrow keys provide the corresponding
four movements.

`C-a` and `C-e`, or `Home` and `End`, move to the start and end of the current
logical line. Repeated vertical movement keeps the desired display column when
the target line permits it.

## 3. Move by word or indentation

Use `M-f` and `M-b` to move to the next or previous word boundary. `C-Right`
and `C-Down` move forward by word; `C-Left` and `C-Up` move backward by word.

Use `M-m` to move to the first non-whitespace grapheme on the current line. On
a whitespace-only line it moves to the line end.

## 4. Edit and page

Press `Tab` to insert one indentation unit at point. The active view policy
selects its representation and width; the factory policy inserts four spaces.
Repeated input and mid-line input use the same ordinary undoable edit path as
typed text. In leading indentation, Backspace removes to the previous logical
indentation boundary; after line content it removes one complete grapheme.

Run `normalize-indentation-to-tabs` or
`normalize-indentation-to-spaces` through `M-x` to convert only the leading
indentation of the current line or active range. Interior alignment remains
unchanged, and the complete conversion is one undo unit.

`Delete` removes the complete grapheme after point. Press `Insert` to toggle
overwrite input for the active view. While overwrite is enabled, each complete
input grapheme replaces the next complete grapheme; typing at buffer end still
inserts text. Press `Insert` again to return to ordinary insertion.

`Prior` and `Next` move through the current viewport while retaining one line
of visible context when the viewport permits it. They change only the active
view and do not create an edit-history entry.

## 5. Work inside a prompt or list

Press `M-x` to open command navigation. While that list is active, `C-n`,
`C-p`, `Up`, and `Down` move its current row instead of moving the editor
cursor. `C-g` cancels the list and returns to the prior editor view.

This local ownership does not alter the direct profile. After the interaction
ends, the same direct bindings apply to the editable view again.

## 6. Validate the terminal workflow

```sh
make terminal-presentation-test
```

The terminal acceptance scenario exercises direct grapheme, line, word,
indentation insertion, arrow, control-arrow, overwrite, delete, and page input together
with contextual command-list ownership and terminal restoration.

See the [Direct Navigation Reference](../../reference/direct-navigation/index.md)
for the complete binding table and compatibility boundary.
