<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Browse Directory Listings

This chapter opens a directory in Maksym, navigates its observed entries,
visits parent and child directories, opens files deliberately, and changes the
listing presentation without changing the filesystem.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../../getting-started/prepare-exercises.md).

Complete the [Darek module](../darek/index.md). The kit-supplied tutorial files
must exist below `~/odra-guide/work`; recreate them with the setup helper if
needed.

Launch Odra from the activated guide shell with one tutorial file:

```sh
odra ~/odra-guide/work/projects/forecast-engine/main.odin
```

## Open the Listing

Press `C-x d`. Filter the filesystem candidates for
`~/odra-guide/work/projects/forecast-engine`, use the arrow keys to move, press
`TAB` to complete the first candidate when useful, and press `RET` on the
directory.

Maksym replaces the active pane content with a detailed directory listing.
The buffer owns one bounded observation of that directory and one selection
identified by the underlying filesystem resource.

Press `C-x 4 d` to select a directory and open it in another eligible pane.
Run `M-x maksym-open-directory-below` or
`M-x maksym-open-directory-right` when the split orientation must be explicit.
A rejected selection or insufficient geometry preserves the existing layout.

From an ordinary file, `C-x C-j` opens its containing directory in the current
pane and `C-x 4 C-j` opens that directory in another pane.

## Move Through Entries

Press `n`, `C-n`, or `SPC` to select the next entry. Press `p` or `C-p` to
select the previous entry. Movement stops at the first and last row.

Press `j`, type part of an entry name, and use the shared candidate controls to
choose a filtered row. Acceptance returns to the same listing with that
filesystem identity selected; it does not open a second copy of the listing.

## Visit Directories and Files

Select `src` and press `RET`, `f`, or `e`. Maksym replaces the listing with the
child directory observation. Press `^` to open its parent and return to the
`forecast-engine` listing.

Select `README.md` and press `RET` to open it in the active pane. Reopen the
containing directory with `C-x C-j`, select `main.odin`, and press `o` to open
it in another pane and focus that pane.

Return to Maksym, select another file, and press `C-o`. The file appears in an
eligible ordinary pane while Maksym retains input focus. Directory rows always
open as directories under these visit commands.

## Read the Detailed Listing

Each detailed row presents a theme-colored directory marker when applicable,
permission characters, byte size, modification date, and filename. These
columns describe the current observation; rendered text is not authority for
a later filesystem change.

Press `(` to switch to the simplified listing. The filename and the trailing
`/` that distinguishes a directory remain visible. Press `(` again to restore
the metadata columns. Narrow panes clip through the shared renderer without
discarding names, selection, or listing state.

## Sort and Refresh

Press `s` to cycle between directories-first and name ordering. The selected
resource stays selected even when its row moves.

Press `g` to replace the listing from one new complete directory observation.
Selection remains on the same resource when it still exists. If it disappeared,
Maksym resolves a valid nearby row instead of retaining a stale display
identity.

Detailed versus simplified presentation and the current sort order belong to
this live Maksym buffer. They are not durable personal settings in the current
delivery.

## Understand Hidden Entries

Local directory observations exclude hidden filesystem entries. Refresh does
not reveal them, and the current Maksym buffer has no hidden-entry toggle. Use
the filesystem path navigator and begin the current segment filter with `.` to
open an explicitly selected hidden directory when it is otherwise admissible.

## Recover from Browsing Problems

- If the directory candidate becomes stale, reopen `C-x d` and select the
  current filesystem identity.
- If a directory becomes unreadable, correct its filesystem permissions and
  press `g`; the prior complete observation remains until refresh succeeds.
- If another pane cannot be created, enlarge the terminal, close an unused
  pane, or use the current-pane command.
- If a resource disappears after selection, refresh before opening it again.
- Press `C-g` to cancel directory or jump candidates without changing the
  current listing.

## Verify the Result

You have completed this chapter when Maksym opens in the active and another
pane, moves by row and filtered identity, visits parent and child directories,
opens files with and without transferring focus, explains every detailed
column, preserves selection through sort and refresh, and switches between
detailed and simplified presentation without filesystem changes.

For exact browsing commands, presentation, and bounds, see the
[Maksym Reference](../../../../reference/maksym/index.md).

---

[Previous: Maksym](index.md) ·
[Files, Projects, and Workspaces](../index.md) ·
[Next: Edit Filenames](edit-filenames.md)
