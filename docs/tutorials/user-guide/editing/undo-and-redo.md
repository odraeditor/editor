<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Undo and Redo Changes

This chapter creates one semantic typing unit, reverses and reapplies it,
creates a retained alternate future, and identifies the current interactive
boundary for branch and selective history operations.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../getting-started/prepare-exercises.md).

Complete [Transfer Text](transfer-text.md). Reopen the unchanged kit-supplied
editing-practice file if necessary:

```sh
odra ~/odra-guide/work/dirs/notes/editing-practice.txt
```

Point begins before `Editing Practice`.

## Create One Typing Unit

Type `ax`, press Backspace, then type `界`. The first line becomes:

```text
a界Editing Practice
```

These input events form one semantic typing unit. The local Backspace remains
in the unit because it corrects text inserted by that same compatible typing
sequence.

Cursor movement, a separate semantic command, or an incompatible edit ends the
current typing unit.

## Undo the Complete Unit

Press `C-/`. The complete `a界` insertion disappears in one operation, and
point returns to the position recorded before the unit.

`C-_` and `C-x u` invoke the same `undo` command. Undo at the initial history
state is a checked no-op: it does not change text or create another history
entry.

## Redo Through Command Navigation

The factory profile has no direct redo binding. Press `M-x`, enter `redo`, and
press Enter. The complete typing unit returns, including its final cursor
context.

Undo and redo publish fresh revisions. Returning to identical text does not
reuse an older revision or make stale positions current again.

## Record a Keyboard Macro

Press `C-x (` to start recording, perform a short sequence, and press `C-x )`
to finish. Press `C-x e` to replay the last macro. `F4` finishes an active
recording or replays the last completed macro. Repetition is bounded, and a
failed step stops replay without executing later steps.

## Create an Alternate Future

Press `C-/` to return to the file's initial text. Type `note ` instead of
redoing `a界`. This creates a new child from the same earlier state; it does not
erase the retained `a界` history branch.

Run `redo` through `M-x` while positioned at the new leaf. Nothing changes
because that active node has no preferred child. Press `C-/` to undo `note `,
then run `redo` again. The preferred `note ` unit returns.

Odra currently exposes ordinary undo and preferred-child redo through the
interactive command surface. Retained alternate-child selection and selective
undo are checked native capabilities without an ordinary interactive selector,
so this User Guide does not invent keys or ask you to manipulate internal node
identities. Their exact contracts remain documented in the history reference.

## Restore Editing Context

History records the initiating cursor context around a logical edit. When an
edit begins with point, mark, and an active region, undo restores their before
state and redo restores their after state. Other views of the same buffer keep
their own stored points and viewports.

An explicitly linked multibuffer edit is also retained as one logical unit and
cannot be partially traversed. User-facing workflows that create such edits,
including editable result application, teach the visible behavior where those
workflows are introduced.

## Recover from History Surprises

- Undo at the root and redo without a preferred child are safe no-ops.
- If one undo removes more characters than expected, the edits belonged to one
  semantic typing unit; movement or another semantic command ends future
  groups.
- If editing after undo changes what ordinary redo reapplies, you created a new
  preferred branch. The older branch remains retained but has no current
  interactive selector.
- Save only after the buffer shows the intended state. Exit cancellation still
  protects any modified result.

## Verify the Result

You have completed this chapter when one undo removes the complete corrected
`a界` unit, `M-x redo` restores it, editing after undo creates a new preferred
future, and undo plus redo traverses that new `note ` unit as one operation.

Undo `note ` before leaving the file, then continue with
[Save and Revisit Editor State](save-and-revisit-state.md).

For topology, grouping, limits, linked units, branch selection, and selective
recovery contracts, see the
[Reversible Editing History Reference](../../../reference/reversible-editing-history/index.md).

---

[Previous: Transfer Text](transfer-text.md) ·
[User Guide](../index.md) ·
[Next: Save and Revisit Editor State](save-and-revisit-state.md)
