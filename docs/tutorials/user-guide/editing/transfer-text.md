<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Transfer Text

This chapter copies and kills selected text into Odra's internal kill ring,
yanks the newest entry, rotates to an older entry, and restores the intended
text with undo.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../getting-started/prepare-exercises.md).

Complete [Select Text](select-text.md), then open the kit-supplied editing
practice file:

```sh
odra ~/odra-guide/work/dirs/notes/editing-practice.txt
```

The first line is `Editing Practice`, and point begins before `Editing`.

## Copy Without Changing Text

Press `C-SPC`, then press `C-f` seven times to select `Editing`. Press `M-w` to
run `copy-region`.

The text remains unchanged and `Editing` becomes the newest internal kill-ring
entry. Copying creates no text revision or undo entry. The region remains
active, so press `C-g` before preparing the next selection.

## Kill a Second Region

Point remains after `Editing`. Press `C-f` once to cross the space, press
`C-SPC`, then press `C-f` eight times to select `Practice`.

Press `C-w` to run `kill-region`. Odra retains the complete selection before
publishing its deletion. The first line becomes:

```text
Editing
```

The deletion is one reversible edit, and `Practice` is now the newest internal
entry.

## Yank and Rotate

Press `C-y` to yank the newest entry at point. The first line returns to:

```text
Editing Practice
```

Immediately press `M-y`. Odra replaces only the preceding yank range with the
next retained entry, `Editing`. The first line becomes:

```text
Editing Editing
```

The ring order does not change. Press `C-/` to undo the rotation and restore
`Editing Practice`.

`M-y` applies only to the immediately preceding yank chain. Moving point or
performing another edit ends that chain so an unrelated range cannot be
replaced accidentally.

## Understand Clipboard Export

The internal kill ring is always available and is the source used by `C-y`.
On a supported direct Herdr presentation path, `M-w` and `C-w` also export the
retained text to the outer terminal clipboard after the internal operation
succeeds.

Clipboard export is optional transport behavior. Its absence does not weaken
copy, kill, yank, rotation, or undo inside Odra, and the current direct path
does not import arbitrary external clipboard text before a yank.

## Recover from Transfer Problems

- `M-w` and `C-w` require an active region. Without one, Odra reports that the
  region is unavailable and leaves the editor open and unchanged.
- Use `C-g` to deactivate a region without altering the ring or document.
- Use `C-/` if a kill, yank, or rotation changed the wrong text.
- If external clipboard export is unavailable, continue with the internal
  ring and verify the frontend-specific transport separately.

## Verify the Result

You have completed this chapter when copy leaves the document unchanged, kill
removes and retains `Practice`, yank restores it, rotation substitutes the
older `Editing` entry, and undo returns the first line to `Editing Practice`.

Continue with [Undo and Redo Changes](undo-and-redo.md).

For retention limits and yank-chain rules, see the
[Text Transfer Reference](../../../reference/text-transfer/index.md). For
frontend-specific clipboard checks, see
[Use the System Clipboard](../../../how-to/use-system-clipboard/index.md).

---

[Previous: Select Text](select-text.md) ·
[User Guide](../index.md) ·
[Next: Undo and Redo Changes](undo-and-redo.md)
