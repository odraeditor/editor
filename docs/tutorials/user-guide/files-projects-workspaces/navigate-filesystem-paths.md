<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Navigate Filesystem Paths

This chapter opens files and Dirs through the filesystem candidate navigator,
using completion and filtering instead of requiring a complete path from
memory.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../getting-started/prepare-exercises.md).

Complete [Choose a Working Context](choose-a-working-context.md). Keep the
disposable tutorial workspace at `~/odra-guide/work/`.

The exercise kit supplies every Project and file path used below; this chapter
does not create or overwrite them.

Start Odra with the same isolated configuration used by earlier chapters:

```sh
odra
```

## Start from Your Home Dir

Select `Open File` on Startup. Type either `~` or `/` as the first character.
The editable path becomes `~/`, and the rows below it show the immediate
visible children of your home Dir.

This initial `/` shortcut means home only when it is entered by itself at the
start of the interaction. Pasting or supplying a longer absolute path retains
its absolute meaning. Named-user forms such as `~someone` are not supported.

The first matching row is selected. Each Dir name ends in `/`. When the
terminal is wide enough, rows also show permissions, size, and last-modified
time; narrow layouts remove complete metadata columns before reducing the
visible name.

## Filter One Path Segment

Type enough of `Projects` to narrow the current home-level rows. Typing filters
the copied children of the current Dir; it does not enter every partial path
or repeatedly scan the complete filesystem.

Use any of these keys to choose a different visible row:

- Down or `C-n` selects the next candidate.
- Up or `C-p` selects the previous candidate.
- Tab completes the selected candidate.

Completing a Dir appends `/`, enters that level, and presents its immediate
children. Completing a file inserts its complete name but does not open it.
Press Enter only when the intended file is selected.

## Open the Tutorial File

Press `C-g` to cancel the home exercise, select `Open File` again, and enter:

```text
~/odra-guide/work/projects/forecast-engine/src/forecast/sum
```

The complete absolute prefix is preserved. Select `summary.odin`, press Tab,
and then press Enter. Odra revalidates the selected path and opens or reuses
the document through the ordinary file lifecycle.

Later, `C-x C-f` opens the same navigator from an editing pane. The current
document remains visible above the bottom-anchored panel until a file is
accepted or the interaction is cancelled.

## Move Back to a Parent

Open `C-x C-f` again and enter:

```text
~/odra-guide/work/projects/forecast-engine/src/
```

Press Backspace while the current filter is empty. Odra removes the final
resolved segment and restores candidates from the parent Dir. When a filter
contains text, Backspace removes one complete input character and broadens the
current list instead.

The candidate panel uses no more than half the terminal height. Long lists
scroll within that bound; short lists do not reserve empty rows.

## Open a Dir

Press `C-g` to close file navigation. Run `M-x open-directory`, enter:

```text
~/odra-guide/work/projects/report-console
```

Press Enter on the selected Dir. The filesystem navigator supplies the path,
and the command opens a Maksym directory buffer without creating or replacing
Project identity. The Maksym module later teaches operations inside that
listing.

Startup `Open Dir` uses the same path navigation but admits the selected root
as the active Dir or its existing Project, then presents files below that
root.

## Show Hidden Entries Deliberately

Hidden names are absent from the default candidate generation. Type `.` as the
first character of the current filter to request them. Removing that leading
character restores the ordinary visible set.

Selecting a hidden Dir permits entering it. Its own hidden children remain
omitted until the next filter also begins with `.`.

## Recover from Path Problems

- An empty or unmatched Dir path does not replace the active editor state.
- If a selected entry disappears or changes kind, Enter rejects the stale
  candidate and leaves the navigator recoverable.
- An unreadable or unavailable Dir reports a bounded error and retains the
  last valid parent view when possible.
- A source with more than 4,096 immediate entries is rejected rather than
  shown as a silently incomplete list.
- Press `C-g` to cancel without opening a file or Dir.

For file opening only, one exact nonempty leaf that does not yet exist may be
admitted as a future document target when its parent Dir exists. The file is
not created until the ordinary save workflow succeeds.

## Verify the Result

You have completed this chapter when you can start from home, filter and
complete several levels, move between candidates, return to a parent with
Backspace, open `summary.odin`, open `report-console` as a directory listing,
and cancel without changing context.

Continue with [Manage a Project](manage-a-project.md).

For the concise Dir procedure, see [Open Dirs](../../../how-to/open-dirs/index.md).
For exact candidate identity, matching, selection, and bounds, see the
[Candidate Session Reference](../../../reference/candidate-session/index.md).

---

[Previous: Choose a Working Context](choose-a-working-context.md) ·
[User Guide](../index.md) ·
[Next: Manage a Project](manage-a-project.md)
