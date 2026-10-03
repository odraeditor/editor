<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Replace Text

This chapter confirms, skips, batches, exits, and reverses literal and
regular-expression replacements through the current interactive workflow.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../getting-started/prepare-exercises.md).

Complete [Search Text](search-text.md). The practice file is supplied by the
exercise kit. Restore the `notes` group, then open the fresh working copy:

```sh
~/odra-guide/kit/bin/odra-guide reset notes
odra ~/odra-guide/work/dirs/notes/editing-practice.txt
```

All changes in this chapter remain inside the disposable copy.

## Start Literal Query Replacement

Press `M-%`, enter `stable`, and press Enter. Enter `steady` at the replacement
prompt and press Enter again.

Odra highlights the current occurrence and reports the pattern, replacement,
effective case behavior, confirmed count, skipped count, and local response
keys. The complete buffer is the captured scope because no region is active.

## Confirm, Skip, and Replace the Remainder

Press `y` to replace the first occurrence. Press `n` to skip the second. Press
Space to replace the third. `DEL` is an alternative skip input.

Press `!` at the fourth occurrence. Odra replaces every remaining admitted
match as one checked batch and finishes the interaction. Three `stable`
occurrences are now `steady`; the skipped occurrence remains unchanged.

The individual confirmations and final batch belong to one uninterrupted
replacement history group. Press `C-/` once. All changes from the complete
session are undone together.

## Keep Confirmed Work When Leaving

Start `M-%` again with `stable` and `steady`. Press `y`, then `q`. The
interaction ends and the confirmed replacement remains. Enter has the same
finish behavior while a match is awaiting a response.

Press `C-/` to reverse that retained replacement. Start the workflow once more
and press `.` at the first response. Odra replaces the current occurrence and
exits immediately. Undo it before continuing.

`C-g` also ends an active replacement interaction without reversing already
confirmed work. It cancels pattern or replacement entry before a live response
session begins.

## Replace with Regular-Expression Captures

Move to the first `Observation` line and press `C-M-%`. Enter:

```text
Observation ([0-9]+): ([a-z ]+)
```

At the replacement prompt, enter:

```text
Reading \1: \2
```

Press `.` to replace the current complete match and exit. Capture `1` supplies
the observation number and capture `2` supplies its description. Press `C-/`
to restore the original line.

An invalid expression returns to pattern entry with its diagnostic and byte
offset. It creates no replacement session and changes no buffer text.

## Restrict Replacement to a Region

Use `C-SPC` and movement commands to select two complete `Observation` lines.
Run `M-%` inside the active region. Only matches between point and mark are
eligible. Without an active region, the complete buffer is the captured scope.

Press `C-g` before confirming a replacement, then press `C-g` again if needed
to deactivate the retained region.

## Understand the Atomic Boundary

The direct profile currently exposes query-driven literal and expression
replacement through `M-%` and `C-M-%`. Each confirmation is checked, while
`!` prepares the remaining matches against one revision and publishes that
remainder completely or not at all.

The public `replace-string` and `replace-regexp` operations apply a complete
non-query replacement as one transaction. They are currently programmable
operations rather than complete factory prompt workflows, so this User Guide
does not invent direct invocation steps for them.

## Recover from Replacement Problems

- A changed source revision is revalidated before another response publishes.
- An invalid capture reference, malformed template, overflow, or preparation
  failure changes no additional text.
- Confirmed replacements made before a later cancellation remain ordinary
  reversible history.
- A no-match complete operation is a successful no-op and creates no history
  unit.
- Press `C-g` before confirmation to leave pattern or replacement entry without
  changing text.

## Verify the Result

You have completed this chapter when you can confirm and skip individual
matches, replace the remainder, undo one complete session, keep or reverse
confirmed work after leaving, use regular-expression captures, restrict scope
with a region, and distinguish the direct query workflow from programmable
complete atomic replacement.

Continue with [Navigate Result Sets](navigate-results.md) to preserve matches as
a filterable, revisitable surface.

For exact response, grouping, capture-template, atomicity, and failure rules,
see the [Search and Replacement Reference](../../../reference/search-and-replacement/index.md).

---

[Previous: Search Text](search-text.md) ·
[User Guide](../index.md) ·
[Next: Navigate Result Sets](navigate-results.md)
