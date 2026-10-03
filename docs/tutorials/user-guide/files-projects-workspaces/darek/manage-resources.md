<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Manage Resources

This chapter creates disposable files and directories from Darek, renames and
moves them, copies content and path forms, and removes the complete disposable
exercise. The maintained tutorial files remain intact.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../../getting-started/prepare-exercises.md).

Complete [Preview and Open Files](preview-and-open.md). Exit Odra, then restore
the Project before creating this chapter's disposable resources:

```sh
"$HOME/odra-guide/kit/bin/odra-guide" reset forecast-engine
```

Open the maintained `User Guide` Workspace, show Darek with `C-x t t`, and
select the `Forecast Engine` Project root.

All changes in this chapter stay below a new `darek-practice` directory. Do
not substitute a directory that contains work you intend to keep: Darek
deletion is permanent.

## Create a Directory and File

Press `c d`, enter `darek-practice`, and press `RET`. Darek creates the
directory beneath the selected Project root and publishes a refreshed tree.

Select `darek-practice`, press `c d`, and create an `archive` directory. Return
to `darek-practice`, press `c f`, enter `draft.txt`, and press `RET`. The new
empty file appears without replacing the active editing document.

Creation resolves a selected directory directly and a selected file through
its parent directory. An existing name, stale selection, permission failure,
or resource bound rejects the operation without publishing a partial tree.

## Rename the File

Select `draft.txt` and press `R`. Replace the proposed name with `notes.txt`
and press `RET`. The node changes in place after the filesystem operation is
validated.

If the file is open, Odra updates its document path with the successful rename.
It never overwrites an existing destination implicitly.

## Move and Copy the File

Select `notes.txt` and press `m`. The filesystem candidate surface opens for a
destination directory. Filter for
`~/odra-guide/work/projects/forecast-engine/darek-practice/archive`, use `TAB` to
complete candidates as needed, and press `RET` on `archive`.

Expand `archive`, select `notes.txt`, and press `y f`. Choose
`~/odra-guide/work/projects/forecast-engine/darek-practice` as the destination. The
copy appears beside `archive`, while the original remains inside `archive`.

Repeat the same copy without changing either name. Darek rejects the existing
destination instead of overwriting it. Refresh with `r` if an external
filesystem change makes the displayed generation stale.

## Copy Useful Path Forms

Select `archive/notes.txt` and use the following commands:

| Binding | Retained text |
| --- | --- |
| `y a` | Absolute path. |
| `y r` | Path relative to the containing Project root. |
| `y p` | Containing Project root path. |
| `y n` | Selected resource name only. |

After each command, move focus to an ordinary scratch or disposable text
buffer and press `C-y` to inspect the retained value. Undo the insertion with
`C-/`, then return to Darek with `C-x t o` for the next form.

A Project-relative or Project-root copy requires Project ownership. On an
ordinary Dir outside a Project, use the absolute path or name form instead.

## Remove the Exercise

Select the copied `darek-practice/notes.txt`, press `d`, read the permanent
deletion prompt, and confirm. Delete `archive/notes.txt` in the same way, then
delete the empty `archive` directory and finally `darek-practice`.

Deletion revalidates the selected resource before changing the filesystem. It
is rejected while an affected document remains open, and it never treats the
operation as recoverable. Close any exercise document explicitly before
retrying.

## Recover from Resource Problems

- If creation or rename reports an existing destination, choose a distinct
  name; Darek does not offer an implicit overwrite path.
- If move or copy destination filtering is too broad, keep typing the path or
  use `TAB` to complete the first candidate before accepting.
- If a selected resource changed externally, press `r`, locate the current
  node, and issue the operation again.
- If deletion reports an open document, return to the ordinary pane, close
  that document through the normal protected workflow, and retry.
- Press `C-g` to cancel a name, destination, or confirmation interaction
  before publication.

## Verify the Result

You have completed this chapter when `darek-practice` can be created entirely
through Darek, its file can be renamed, moved, and copied, a duplicate copy is
rejected without overwrite, every path form can be inspected in a disposable
buffer, and confirmed deletion removes only the complete exercise tree.

For exact filesystem action semantics, bounds, and ownership, see the
[Darek Reference](../../../../reference/darek/index.md). For targeted recovery,
see [Troubleshoot Darek](../../../../how-to/troubleshoot-darek/index.md).

---

[Previous: Preview and Open Files](preview-and-open.md) ·
[Files, Projects, and Workspaces](../index.md) ·
[Next: Use Contextual Operations](use-contextual-operations.md)
