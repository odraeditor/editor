<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Edit Filenames

This chapter turns a Maksym listing into an editable filename projection,
prepares several renames and relative moves as ordinary text, and cancels the
projection to prove that preparation alone does not change the filesystem.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../../getting-started/prepare-exercises.md).

Complete [Browse Directory Listings](browse-directory-listings.md). From the
guide terminal session, create one disposable directory below the tutorial
Project:

```sh
"$HOME/odra-guide/kit/bin/odra-guide" reset forecast-engine
mkdir -p ~/odra-guide/work/projects/forecast-engine/maksym-practice/archive
printf 'first practice file\n' \
  > ~/odra-guide/work/projects/forecast-engine/maksym-practice/alpha.txt
printf 'second practice file\n' \
  > ~/odra-guide/work/projects/forecast-engine/maksym-practice/beta.txt
```

Open `~/odra-guide/work/projects/forecast-engine/maksym-practice` with `C-x d`.
The detailed listing shows `archive/`, `alpha.txt`, and `beta.txt`.

## Enter Filename Editing

Press `C-x C-q`. Maksym reports that filename editing is enabled. Metadata
columns and structural separators remain visible but protected; ordinary text
commands operate only inside the filename fields.

Use `C-n` or `Down` and `C-p` or `Up` to move among editable filename rows.
The active point follows the selected row without turning metadata into
editable buffer content.

Press `C-x C-q` again without making a change to leave filename editing. Enter
it once more for the exercise. After a name changes, the same command refuses
to leave until the prepared changes are applied or cancelled.

## Prepare Two Renames

Move to `alpha.txt` and use ordinary character, word, deletion, and insertion
commands to replace the field with `first.txt`. Move to `beta.txt` and replace
it with `second.txt`.

At this point the Maksym text shows both proposed names, but the filesystem
still contains `alpha.txt` and `beta.txt`. Ordinary undo and redo can reverse
or restore these uncommitted filename edits.

Do not press `C-c C-c` yet. That command validates and applies the current
projection in the delivered direct workflow.

## Prepare a Relative Move

Change `second.txt` to `archive/second.txt`. A relative path prepares a move
below the directory represented by this Maksym buffer. The destination parent
must already exist and remain inside that directory.

Absolute destinations, empty path segments, `.` or `..` segments,
cross-device moves, recursive moves, duplicate destinations, and collisions
are invalid editable projections. Maksym does not infer or create a missing
destination directory from edited text.

## Preserve Directory Semantics

Directory rows end in `/`. Keep that suffix when changing a directory name.
Removing an entire directory field is invalid because recursive directory
deletion is outside the delivered editable-listing workflow.

An empty regular-file field has a different meaning: it prepares permanent
deletion. The next chapter introduces that destructive operation with an
explicit disposable file.

## Cancel the Prepared Projection

Press `C-c C-k` or `C-c C-[`. Maksym discards every edited filename, closes the
editable projection, and refreshes the directory from filesystem truth.

The listing again shows `alpha.txt` and `beta.txt`; neither rename nor the
relative move occurred. Cancellation does not need to reverse filesystem
effects because preparation never published them.

## Recover from Invalid Editing

- If Maksym reports `Editable Maksym text is invalid`, restore the protected
  row structure, a valid filename, and every directory suffix.
- If a destination would collide, choose a distinct relative name before
  application.
- If a destination parent is missing, cancel, create or select the directory
  through a filesystem workflow, refresh, and prepare the move again.
- If the directory changed externally, cancel and press `g` before preparing a
  new projection from the refreshed generation.
- Use ordinary undo only before filesystem application; it changes projection
  text, not canonical resources.

## Verify the Result

You have completed this chapter when metadata remains protected, several
filename fields can be edited with ordinary text commands, a relative move is
represented as a path below the open directory, directory suffix semantics
remain intact, undo changes only the projection, and cancellation restores
the original listing without changing the filesystem.

For exact editable commands and rejected forms, see the
[Maksym Reference](../../../../reference/maksym/index.md).

---

[Previous: Browse Directory Listings](browse-directory-listings.md) ·
[Files, Projects, and Workspaces](../index.md) ·
[Next: Apply Filesystem Changes](apply-filesystem-changes.md)
