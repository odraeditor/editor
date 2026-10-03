<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Use Commands and Interactions

This chapter invokes named commands, filters candidate lists, responds to a
prompt, inspects a binding, and returns safely to the editing pane.

## Before You Begin

If you enter this chapter directly, first complete
[Prepare the User Guide Exercises](prepare-exercises.md).

Complete [the first editing session](first-editing-session.md), then open the
tutorial notes again:

```sh
odra "$HOME/odra-guide/work/dirs/notes/review.md"
```

## Read Key Notation

The User Guide spells out a key sequence when first introducing it and uses
compact notation where it improves a table or repeated instruction:

| Notation | Meaning |
| --- | --- |
| `C-g` | Hold Control and press `g`. |
| `M-x` | Hold Meta and press `x`; Alt commonly produces Meta in terminals. |
| `C-x C-s` | Press `C-x`, release it, then press `C-s`. |
| `RET` | Press Enter. |
| `SPC` | Press Space. |

A hyphen joins simultaneous modifiers to one key. Spaces separate successive
keys. Named keys such as Up, Down, Home, End, Backspace, Delete, and Tab refer
to their terminal keys.

Odra also accepts pointer input when the frontend reports that capability. The
primary button can focus visible panes and areas, place point in ordinary text,
and create a linear selection by dragging. Frontends without pointer reporting
retain every required focus, movement, selection, copy, paste, and command path
through the keyboard; unavailable pointer gestures do not change keyboard
behavior.

## Open Command Navigation

Press `M-x`. Odra keeps the editing pane visible and opens command navigation
from the bottom of the window. The interaction shows an editable query and the
commands that currently match it.

Type:

```text
status bar inspect
```

Query words may match the command name or its searchable description. The
matching row is `status-bar-inspect`; punctuation in the canonical command
name does not have to be typed as punctuation in the query.

Use Up, Down, `C-p`, or `C-n` to move the highlighted row. Press Enter to run
the selected command. Odra presents the visible Status Bar segments in a
read-only result surface. Press `q` to close that surface and return to the
file.

## Filter and Cancel a Candidate List

Open `M-x` again and type `theme`. Each character narrows the candidate list.
Press Backspace to remove one query character and broaden it again.

Press `C-g` without accepting a row. The candidate interaction closes, no
command runs, and the cursor returns to the same editing location.

Candidate keys are local to the active interaction. For example, `C-n` moves
the selected candidate while `M-x` is open, then resumes moving the document
cursor after the interaction closes.

## Respond to a Command Prompt

Open `M-x`, run `where-is`, and enter this canonical command name at the
prompt:

```text
save-associated-document
```

Press Enter. The result surface lists the active binding `C-x C-s` and its
effective context. Press `q` or `C-g` to return to editing.

A prompt collects one bounded value for a command. A candidate list selects
one checked item from a visible set. Both keep their own input rules until they
are accepted or cancelled.

## Inspect an Unknown Binding

Open `M-x`, run `describe-key`, then press `C-x C-s` when the capture prompt
appears. The resulting list identifies `save-associated-document` as the
effective command.

Press `q` to close the list. The same discovery family includes:

- `where-is` for the active bindings of one command;
- `describe-bindings` for the active binding set;
- `describe-keymap` for one named map; and
- `describe-keymap-state` for the active profile and interaction state.

These are ordinary named commands, so they remain discoverable through `M-x`.

## Recover from an Interaction

`C-g` is the protected cancellation command. It first closes an active prompt,
candidate list, or read-only result. With no transient interaction active, it
clears a pending key sequence or deactivates the current selection.

An unavailable or stale candidate is rejected rather than invoking a different
command. Read the short diagnostic, close or refresh the interaction, and
choose again from the current list.

## Verify the Result

You have completed this chapter when you can open and cancel `M-x`, run
`status-bar-inspect`, use `where-is` to find `C-x C-s`, and use `describe-key`
to resolve that sequence back to `save-associated-document`.

Continue with [Editing](../editing/index.md).

For the complete command and factory binding catalog, see the
[Programmable Command Reference](../../../reference/programmable-commands/index.md).
For candidate matching and failure behavior, see the
[Candidate Session Reference](../../../reference/candidate-session/index.md).

---

[Previous: Complete the First Editing Session](first-editing-session.md) ·
[User Guide](../index.md) ·
[Next: Editing](../editing/index.md)
