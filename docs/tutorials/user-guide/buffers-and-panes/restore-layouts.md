<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Restore Layouts

This chapter stores a portable three-pane arrangement, changes the active
working set, restores the saved topology and focus, and verifies that unrelated
modified buffers remain live.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../getting-started/prepare-exercises.md).

Complete [Understand Pane-Local State](understand-pane-state.md). Use the
isolated state activated during exercise setup so the tutorial layout does not
mix with ordinary named entries:

```sh
odra ~/odra-guide/work/dirs/notes/editing-practice.txt
```

The exercise kit supplies `editing-practice.txt`, `review.md`, and the Report
Console Project opened below.

Restart Odra from the same activated guide shell during this chapter.

## Build a Portable Layout

Press `C-x 3` to create a pane to the right. Press `C-x 4 f`, open
`~/odra-guide/work/dirs/notes/review.md`, and keep that right pane
active.

Press `C-x 2` to split the right pane below. The active upper-right pane and
the new lower-right pane initially show `review.md`. In the upper-right pane,
press `C-x C-f` and open:

```text
~/odra-guide/work/projects/report-console/main.rkt
```

The layout now contains `editing-practice.txt` on the left, `main.rkt` in the
upper-right pane, and `review.md` in the lower-right pane. Keep `main.rkt`
active so its pane becomes the saved focus.

Every pane in a portable snapshot must show a file-backed buffer. Save a
pathless buffer first or replace it before storing the layout.

## Store the Layout

Press `C-x r w`, enter `guide-three-files`, and press Enter. Odra stores the
portable pane topology, each file target, the active pane, and pane dedication
state under that name.

Split proportions, terminal dimensions, cursor positions, and buffer contents
are not copied into the named entry. Existing live buffers continue to own
their text and history independently.

## Change the Working Set

Press `C-x 1` to keep only `main.rkt`. Then press `C-x b`, create
`layout-draft`, and type:

```text
This modified buffer must survive layout restoration.
```

Do not save or close this buffer. The visible layout now differs from the
stored arrangement, and one unrelated pathless buffer contains unsaved text.

## Restore the Saved Layout

Press `C-x r j`. The candidate surface includes every typed slot; filter for
`guide-three-files` and press Enter. Layout rows are name-only because encoded
pane trees are not useful as inline text previews.

Odra restores the three-pane topology and file targets, then focuses the pane
that held `main.rkt` when the layout was stored. Existing normalized file
targets are reused; unavailable ones are opened through the ordinary checked
file workflow.

Press `C-x b` and select `layout-draft`. Its unsaved text remains intact.
Restoration changes visible pane composition; it does not silently save,
discard, or close unrelated live buffers. Switch back to `main.rkt` to return
the active pane to a stored target.

## Revisit the Layout After Restart

Exit safely, discarding `layout-draft` only when prompted. Start Odra again
from the same activated guide shell with any tutorial file, then press
`C-x r j`. The `guide-three-files` candidate remains available because named
layout state persists across sessions.

Select it to reopen the three file targets and reconstruct the admitted
topology. The restored cell proportions adapt to the current terminal rather
than reproducing old dimensions.

## Recover from Restoration Problems

- If any stored file target is unavailable, restoration reports failure and
  preserves the current pane layout.
- If current geometry cannot admit the complete tree, Odra restores the
  compatible portion and reports that the result is partial.
- Existing modified buffers remain live even when they are not displayed by
  the restored tree.
- A malformed, stale, or missing layout entry does not grant authority to
  discard text or replace persistent state.
- Press `C-g` in the candidate surface to leave the current layout and focus
  unchanged.

## Verify the Result

You have completed this chapter when `guide-three-files` restores the saved
three-pane topology, file targets, and active pane; `layout-draft` survives
with unsaved text; the layout remains available after restart; and cancelling
or failing restoration preserves the current visible arrangement.

Continue with [Search and Navigation](../search-and-navigation/index.md).

For exact portable snapshot, compatibility, geometry, and persistent-slot
behavior, see the [Pane Layout Reference](../../../reference/pane-layout/index.md)
and [Selection Reference](../../../reference/selection/index.md).

---

[Previous: Understand Pane-Local State](understand-pane-state.md) ·
[User Guide](../index.md) ·
[Next: Search and Navigation](../search-and-navigation/index.md)
