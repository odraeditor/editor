<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Navigate Result Sets

This chapter materializes active-buffer matches, filters and visits their
source locations, refreshes the result set, prepares one result-set edit, and
applies or discards it safely.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../getting-started/prepare-exercises.md).

Complete [Replace Text](replace-text.md). The practice file is supplied by the
exercise kit. Restore the `notes` group, then open the fresh working copy:

```sh
~/odra-guide/kit/bin/odra-guide reset notes
odra ~/odra-guide/work/dirs/notes/editing-practice.txt
```

## Materialize Search Matches

Press `C-s`, type `Observation`, then press `M-s o` while search remains
active. Odra closes the transient search prompt and opens a persistent result
surface containing the retained matches.

The source buffer remains live. The result surface temporarily owns input and
remembers the editing location to which it will return. Each row includes the
source location and nearby text, with the exact match styled by the active
theme:

```text
11:01   Observation 01: clear
12:01   Observation 02: clear
```

Line and column fields are independently zero-padded to the widths required by
the source file. This aligns decimal positions and separators without making
the rendered text into navigation authority.

## Filter and Move Through Results

Use Down, Up, `M-n`, or `M-p` to move the selected result. Press `>` to select
the last row and `<` to return to the first.

Type `rain` to show only rows whose copied candidate text matches that filter.
Press Backspace to broaden the list again. Filtering changes the visible
projection; it does not run another source search or create another result set.

Press Enter on one selected row. Odra revalidates its buffer revision and exact
range, returns to the source document, and places point at that match.

## Continue from the Editor

After visiting one row, press `M-g M-n` to move to the next location in the
active result source. Press `M-g M-p` to move to the previous one. These
commands use the same ordered result identities without reopening the list.

If a target becomes stale or unavailable, Odra reports it and preserves the
current editing location instead of deriving authority from the displayed row.

## Refresh the Result Set

Materialize `Observation` again with `C-s`, the query, and `M-s o`. Move to a
middle row and press `g`.

Odra reruns the captured query and replaces the result generation. It retains
the selected logical location when that match still exists, removes stale
matches, and adds newly discovered ones. Refresh is rejected while staged
result edits remain unapplied.

## Stage and Apply an Edit

With a clean active-buffer result set open, select one row and press `e`. The
bottom prompt contains the exact matched source text. Replace `Observation`
with `Reading` and press Enter.

The result row now carries a staged replacement, but the source buffer has not
changed. Press `q`; Odra refuses to close because unapplied edits are
protected.

Press `C-g` on the result surface to discard the staged edit. The result set
becomes clean and the source remains unchanged.

Stage the same replacement again, then press `C-c C-c`. Odra preflights the
source revision and range and applies the staged proposal as one transaction.
The result set refreshes or marks its generation stale according to the
result. Return to the source and press `C-/` once to undo the applied edit.

`C-g` inside the edit prompt cancels only that prompt and preserves edits
staged earlier in the same result projection.

## Close the Result Surface

Open a clean result set and press `q`. Odra releases that result generation and
returns to the checked editing context that opened it. Source buffers remain
live, and search history is unchanged.

Closing does not delete source buffers or discard staged changes silently.
Use `C-c C-c` to apply staged edits or `C-g` on the result surface to discard
them explicitly before closing.

## Verify the Result

You have completed this chapter when you can materialize aligned source
previews, filter and move without losing result identity, visit and continue
through locations, refresh a captured query, distinguish staged from published
text, protect dirty results from closing, discard one proposal, apply another,
and undo the applied transaction.

Continue with [Search Projects and Symbols](search-projects-and-symbols.md) to
extend the common location workflow beyond one active buffer.

For exact result identity, revision checks, edit capability, publication,
refresh, and unified-location behavior, see the
[Search Result Navigation Reference](../../../reference/search-result-navigation/index.md).

---

[Previous: Replace Text](replace-text.md) ·
[User Guide](../index.md) ·
[Next: Search Projects and Symbols](search-projects-and-symbols.md)
