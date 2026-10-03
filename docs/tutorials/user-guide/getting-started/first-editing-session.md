<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Complete the First Editing Session

This chapter edits the tutorial notes, saves the change, handles a protected
exit with unsaved work, and verifies the saved file after reopening it.

## Before You Begin

Complete [Prepare the User Guide Exercises](prepare-exercises.md) in the
current shell. The starting file is supplied by the verified kit at
`~/odra-guide/work/dirs/notes/review.md`.

## Open the Tutorial File

Run:

```sh
odra "$HOME/odra-guide/work/dirs/notes/review.md"
```

The cursor starts at the beginning of the file. The Status Bar shows no buffer
state marker because the file is writable and unchanged.

## Add One Review Item

Press Down until the cursor reaches the final bullet. Press End, then Enter,
and type:

```text
- Record the publication time.
```

The new line appears immediately. The Status Bar now shows `**` before the
buffer size, indicating a writable modified buffer.

## Save the File

Press `Control-X`, then `Control-S`.

Odra saves the current document to its existing path. The `**` marker clears
when the saved revision matches the live buffer revision.

## Cancel an Unsaved Exit

Type one temporary `x`, then press `Control-X`, followed by `Control-C`. Odra
does not discard the modified buffer. It presents:

```text
Save changes? [s]ave [d]iscard [c]ancel
```

Press `c`. The prompt closes and the editor returns to the same buffer with the
temporary character intact.

Press Backspace to remove the temporary character. Save again with
`Control-X`, then `Control-S`, and request exit with `Control-X`, then
`Control-C`. The clean session exits without another decision.

`Control-G` also cancels the active exit decision. Choosing `s` saves before
continuing, while `d` authorizes exit without saving the modified buffer.

## Verify and Reopen the File

Back in the shell, verify the final line:

```sh
tail -n 1 "$HOME/odra-guide/work/dirs/notes/review.md"
```

The output is:

```text
- Record the publication time.
```

Reopen the file:

```sh
odra "$HOME/odra-guide/work/dirs/notes/review.md"
```

The saved review item is present and the Status Bar begins in the clean state.
Exit with `Control-X`, then `Control-C`.

## Recover from Save Problems

A failed save leaves the buffer open and modified. Read the bounded diagnostic,
correct the path or filesystem permission problem, and invoke the same save
sequence again. Odra does not replace the current buffer with partial output.

An unassociated buffer opens a `Save as:` prompt on its first save. Enter a
relative or absolute path and press Enter, or press `Control-G` to cancel
without creating a file.

## Verify the Result

You have completed this chapter when the added bullet survives a clean exit and
reopen, and cancelling the deliberate dirty exit preserves the live edit.

Continue with [Use Commands and Interactions](commands-and-interactions.md).

For exact save and exit behavior, see the
[Local Document Lifecycle Reference](../../../reference/document-lifecycle/index.md).

---

[Previous: Prepare the User Guide Exercises](prepare-exercises.md) ·
[User Guide](../index.md) ·
[Next: Use Commands and Interactions](commands-and-interactions.md)
