<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Save and Revisit Editor State

This chapter saves and revisits a document location, stores selected and typed
text, retains and updates a named number, and restores one pane layout through
the shared named-state workflows.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../getting-started/prepare-exercises.md).

Complete [Undo and Redo Changes](undo-and-redo.md). Use the isolated
configuration root activated during exercise setup so the tutorial entries do
not mix with your ordinary Odra state:

```sh
odra ~/odra-guide/work/dirs/notes/editing-practice.txt
```

The exercise kit supplies the practice file. The named locations, slots, and
layout created below belong to this chapter and remain inside the isolated
guide configuration.

Restart Odra from the same activated guide shell. Named locations and slots
persist across sessions under that root.

## Save and Visit a Location

Use Next or Down to reach `Page 2 checkpoint`. Press `C-x r m`, enter
`guide-page-two`, and press Enter. The saved location records the current file,
point, mark when present, and active-region state.

Move away with Prior or several Up presses. Press `C-x r b`, type part of
`guide-page-two`, and press Enter on the matching candidate. Odra reopens or
activates the target document and restores its saved editing location.

Press `C-x r l` to inspect the complete named-location inventory. Type to
filter, move with Up or Down, and press Enter to visit a row. Press `C-g` to
close the list without moving.

## Store Selected Text

Return to the beginning of `Page 2 checkpoint` with Home. Press `C-SPC`, then
End to select the line. Press `C-x r s`, enter `guide-page-heading`, and
press Enter.

The selected text is stored as a named text slot. A successful store
deactivates the region while retaining mark.

Move point to a temporary insertion position and press `C-x r i`. The selector
shows only compatible text slots and includes a short preview. Filter for
`guide-page-heading` and press Enter. The retained heading is inserted as an
ordinary reversible edit. Press `C-/` to remove the practice insertion.

## Store Typed Text and Numbers

Run `M-x store-text`, enter `guide-publication-note`, press Enter, enter
`ready for publication`, and press Enter again. This stores text supplied by a
prompt rather than copied from the buffer.

Press `C-x r n`, enter `guide-retry-count`, press Enter, enter `2`, and press
Enter again. To update it, press `C-x r +`, select `guide-retry-count`, enter
`3`, and press Enter. The checked result is `5`; integer candidates show their
current value as a preview.

Text and integer retrieval lists are type-specific. Rows do not repeat a type
label that is already invariant for the active command.

## Store and Restore a Layout

With the current file in one pane, press `C-x r w`, enter
`guide-single-pane`, and press Enter. Press `C-x 2` to split the active pane
below.

Press `C-x r j`, filter for `guide-single-pane`, and press Enter. The stored
single-pane arrangement returns. Layout entries remain name-only because their
portable tree is not useful as a text preview.

The later Buffers and Panes part teaches complete layout composition. Here the
exercise establishes that layout state uses the same persistent named
selection model as other saved editor state.

## Understand Names and Persistence

Names are unique in the shared persistent collection. Reusing a name for the
same kind replaces that value atomically. Reusing it for a different kind
requires explicit confirmation rather than silently changing its meaning.

`C-x r SPC` stores the current file and point as a position slot. Press
`C-x r j` to visit that position later. The same typed selector restores a
stored layout and rejects text or integer slots as non-visitable.

Close Odra, then launch it again with the same isolated configuration root and
file. `C-x r b`, `C-x r i`, `C-x r +`, and `C-x r j` show the compatible
entries created in the prior session.

## Recover from Saved-State Problems

- A named location or position requires a regular local-file target.
- An unavailable file or stale position leaves the current location intact.
- Storing selected text requires an active non-empty region.
- Integer parsing or overflow leaves the prior stored value unchanged.
- Layout restoration may use only the compatible portion when current terminal
  geometry cannot display the complete tree.
- Press `C-g` to cancel any name, value, or candidate interaction without
  applying it.

## Verify the Result

You have completed this chapter when `guide-page-two` restores its file
location, `guide-page-heading` can be inserted and undone, the typed text and
integer slots survive restart, and `guide-single-pane` removes the temporary
split through layout restoration.

Continue with [Recover Unsaved Work](recover-unsaved-work.md).

For exact persistent state, replacement, preview, and failure rules, see the
[Selection Reference](../../../reference/selection/index.md). Layout details
are defined by the
[Pane Layout Reference](../../../reference/pane-layout/index.md).

---

[Previous: Undo and Redo Changes](undo-and-redo.md) ·
[User Guide](../index.md) ·
[Next: Recover Unsaved Work](recover-unsaved-work.md)
