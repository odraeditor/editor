<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Select Text

This chapter creates a selection from point and mark, exchanges its endpoints,
selects larger semantic units, restores an earlier selection location, and
deactivates the selection while retaining the mark.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../getting-started/prepare-exercises.md).

Complete [Move and Edit Text](move-and-edit-text.md). Open the same
kit-supplied practice file:

```sh
odra ~/odra-guide/work/dirs/notes/editing-practice.txt
```

In Odra, point is the active text position. Mark is a retained second position.
An active region is the ordered text between them, regardless of which
endpoint comes first.

## Set Mark and Move Point

Press `C-SPC` at the start of the file. Mark is set at point and the region is
active, although the two endpoints initially enclose no text.

Press `C-f` eight times. Point moves after `Editing`, while mark remains at the
file start. The active non-empty region is highlighted with the current theme's
selection style.

Ordinary movement preserves the active region. It never moves mark unless the
command explicitly says so.

## Select with a Pointer

With pointer reporting available, press the primary pointer button over text
to place point at the represented text boundary. A simple press and release
deactivates the active region while retaining mark, like ordinary
non-extending point movement.

Press and drag the primary button across visible text to create the same
linear region used by `C-SPC` followed by movement. Release the button to leave
the resulting region active. The selected value comes from the buffer, so line
numbers, gutters, Status Bars, separators, padding, popups, and neighboring
panes are not included even when the physical drag crosses them.

The first pointer delivery clamps a drag to the visible text in its starting
pane. It does not provide drag autoscroll, rectangular or multiple gestures,
double-click or triple-click semantic selection, ordinary editor wheel
scrolling, or a secondary-button context menu. Use the keyboard selection
commands in this chapter for the same selection state and for operations that
do not yet have a pointer gesture.

## Exchange the Endpoints

Press `C-x C-x`. Point and mark exchange positions and the region remains
active. The same text stays highlighted because its ordered bounds have not
changed.

Press `C-g`. The highlight disappears and editing remains at point. This
deactivates the region but retains mark for later commands.

## Narrow the Active View

Create a region and press `C-x n n`. The active view shows only that range;
the complete buffer remains authoritative for saving and for other views.
Press `C-x n w` to widen it again.

In a supported source file, place point inside a definition and press
`C-x n d` to narrow to the definition supplied by the active language
provider. Widen with `C-x n w`.

## Use a Rectangular Selection

Set mark on one line, move point to a different line and column, then run
`M-x select-rectangle`. Odra derives one half-open range per logical line from
the two grapheme columns. Short lines clamp at their available text instead of
adding padding.

Run `M-x copy-rectangle` to copy those ranges as newline-separated text,
`M-x kill-rectangle` to remove and retain them, or
`M-x replace-rectangle-text` to replace each range with the entered text.
Rectangle mutation is one transaction, so one `C-/` restores both the text and
the rectangular selection. Run `C-g` to return to an inactive linear region.

## Select Semantic Text Units

Move point onto a word and press `M-@` to select that word. Press `C-g`, move to
one of the observation paragraphs, and press `M-h` to select its paragraph.

Press `C-x h` to select the complete buffer. Use `C-g` after each experiment
to return to ordinary editing.

For syntax-aware selection, exit the unchanged practice file with `C-x C-c`,
then open the kit-supplied Odin file:

```sh
odra ~/odra-guide/work/projects/forecast-engine/main.odin
```

Move point inside `main` and press `C-M-h` to select the containing definition.
Press `C-g`, then use `C-M-SPC` to select the enclosing named structural unit.
Repeated structural selection expands through available containing units.

If current language analysis cannot identify a definition or structural unit,
the command leaves the text unchanged and reports the unavailable target.

## Observe Selection During Editing

Exit the unchanged Odin file with `C-x C-c`, then reopen the practice file.
Set mark with `C-SPC`, move point twice with
`C-f`, and type `Z`.

Insertion occurs at point; it does not replace the active region implicitly.
After the successful edit, the region deactivates while mark remains retained.
Press `C-/` to undo. Undo restores the text together with the recorded point,
mark, and active-region state, so the two-grapheme selection is highlighted
again.

Press `C-g` to deactivate it, then discard the practice edit on exit or leave
the buffer open for the next chapter.

## Return Through Recent Selection Locations

Create a word selection with `M-@`, deactivate it, move to another paragraph,
and select that paragraph with `M-h`. Press `C-u C-SPC` to return through the
bounded session-local selection and location history. Repeating the sequence
continues toward older retained locations.

This history is immediate session navigation. Persistent named locations are
introduced later in this part.

## Recover from Selection Problems

- Press `C-g` to deactivate an unwanted region without deleting text.
- If no highlight appears, confirm that point and mark enclose non-empty text;
  an active empty region is valid but has nothing to draw.
- If a semantic selection is unavailable, move point into a supported unit or
  use point and mark directly.
- If typed text deactivates the region, undo restores the recorded selection
  context together with the edit.

## Verify the Result

You have completed this chapter when you can highlight text with point and
mark or a primary-button drag, exchange endpoints without changing the region,
derive and copy a logical rectangle, select a word, paragraph, buffer, and
available structural unit, cancel with `C-g`, and restore a recent selection
location.

Continue with [Transfer Text](transfer-text.md).

For exact state, display, and restoration behavior, see the
[Selection Reference](../../../reference/selection/index.md).

---

[Previous: Move and Edit Text](move-and-edit-text.md) ·
[User Guide](../index.md) ·
[Next: Transfer Text](transfer-text.md)
