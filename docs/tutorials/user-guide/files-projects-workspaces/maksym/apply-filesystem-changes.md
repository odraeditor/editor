<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Apply Filesystem Changes

This chapter applies one prepared Maksym filename revision, verifies collision
rejection, performs one supported permanent file deletion, and removes the
remaining disposable exercise outside the editor.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../../getting-started/prepare-exercises.md).

Complete [Edit Filenames](edit-filenames.md). Its cancelled projection leaves
`alpha.txt`, `beta.txt`, and `archive/` below:

```text
~/odra-guide/work/projects/forecast-engine/maksym-practice/
```

Create one additional disposable file from the guide terminal session:

```sh
printf 'permanent deletion exercise\n' \
  > ~/odra-guide/work/projects/forecast-engine/maksym-practice/delete-me.txt
```

Open `maksym-practice` with `C-x d`.

## Apply a Rename and Move Together

Press `C-x C-q`. Change `alpha.txt` to `renamed.txt`, then change `beta.txt` to
`archive/moved.txt`.

Inspect the complete editable projection before continuing. The changed fields
are the review surface for this direct workflow: verify every proposed name,
relative destination, and unchanged row.

Press `C-c C-c` once. `C-x C-s` invokes the same command. Maksym calculates the
current revision, validates source identities, destination parents,
collisions, and the directory generation, then applies the admitted batch and
refreshes from filesystem truth.

The Status Bar reports:

```text
Applied 1 rename(s), 1 move(s), and 0 permanent deletion(s)
```

The refreshed root listing contains `renamed.txt` and no `alpha.txt` or
`beta.txt`. Open `archive` and confirm that it contains `moved.txt`.

There is no second confirmation step for an ordinary editable-listing apply.
Use `C-c C-k` before application whenever the projection is not exactly the
change set you intend to publish.

## Reject a Collision

Return to `maksym-practice`, enter filename editing, and change `renamed.txt`
to `archive/moved.txt`. Press `C-c C-c`.

The existing destination causes the rename or move preflight to reject the
complete change set. `renamed.txt` and `archive/moved.txt` remain unchanged.
Press `C-c C-k` to discard the invalid projection and refresh observed truth.

Preflight rejection applies nothing. If a provider fails after a batch has
started, Maksym reports the exact partial outcome and refreshes the listing
rather than retaining a stale projection.

## Permanently Delete a Regular File

Select `delete-me.txt`, press `C-x C-q`, and remove its complete filename field.
Leave the row structure intact, then inspect the blank field before applying.

Press `C-c C-c`. An empty regular-file field means permanent deletion, so the
validated operation removes `delete-me.txt` and reports one permanent
deletion. Text undo cannot recover the applied file.

An empty directory field is rejected. The delivered editable-listing workflow
does not perform recursive directory deletion.

## Recover from Changed Inputs

- If a source changes after the projection is prepared, application rejects
  the stale identity. Cancel, press `g`, and prepare a new revision from the
  refreshed listing.
- If a destination parent is missing or outside the open directory, cancel and
  choose an existing relative destination below the listed root.
- If the projection is invalid, repair it with ordinary editing or press
  `C-c C-k` to restore filesystem truth.
- If application reports a partial provider outcome, trust the refreshed
  listing and inspect every reported resource before preparing another batch.
- Ordinary undo and redo apply only before publication. They never claim to
  reverse an applied rename, move, or permanent deletion.

## Remove the Remaining Exercise

Exit filename editing with no pending changes, leave Odra, and remove only the
known disposable directory:

```sh
rm -r ~/odra-guide/work/projects/forecast-engine/maksym-practice
```

The maintained tutorial source and both Project identities remain unchanged.

## Verify the Result

You have completed this chapter when one `C-c C-c` applies a checked rename and
relative move together, a destination collision applies nothing, cancellation
restores observed truth, an empty regular-file field performs the documented
permanent deletion, and the disposable directory is removed without changing
maintained tutorial files.

For exact editable-listing commands, preflight bounds, and failure semantics,
see the [Maksym Reference](../../../../reference/maksym/index.md). For focused
recovery, see
[Manage Maksym Changes](../../../../how-to/manage-maksym-files/index.md).

---

[Previous: Edit Filenames](edit-filenames.md) ·
[Files, Projects, and Workspaces](../index.md) ·
[Next: Language Intelligence](../../language-intelligence/index.md)
