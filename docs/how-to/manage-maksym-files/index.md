<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Manage Maksym Changes

Use these procedures after learning the editable projection in the
[Maksym User Guide module](../../tutorials/user-guide/files-projects-workspaces/maksym/index.md).
For the complete command and behavior contract, see the
[Maksym Reference](../../reference/maksym/index.md).

## Rename several entries

1. Open the directory with `C-x d`.
2. Press `C-x C-q`.
3. Edit the filename fields as ordinary text.
4. Inspect every changed filename in the editable projection.
5. Press `C-c C-c` once to validate and apply the current revision.

The edited projection is the review surface. There is no second confirmation
for an ordinary admitted batch, so cancel before application when any row does
not express the intended change.

## Move an entry below the open directory

Replace its filename with a relative destination such as
`archive/finished.odin`. The destination parent must already exist below the
open directory. Inspect the complete projection, then apply it once with
`C-c C-c`.

## Permanently delete a regular file

Remove its complete filename field while preserving the row structure, inspect
the blank field, and press `C-c C-c`. Empty regular-file fields mean permanent
deletion. Empty directory fields are rejected because recursive directory
deletion is unavailable in the delivered workflow.

## Cancel prepared changes

Press `C-c C-k`. Maksym discards the edited projection and refreshes from the
filesystem. Use this after an accidental edit or when a review does not match
the intended operation.

## Resolve a rejected application

- For `Editable Maksym text is invalid`, restore protected row structure and
  directory suffixes.
- For a collision, choose a destination that does not exist outside the same
  checked rename or move batch.
- For a missing destination parent, create or select an existing directory and
  prepare the relative move again.
- For an external change, press `g`, locate the resource again, and prepare a
  new projection from the refreshed generation.
- For directory deletion, cancel the edit. Recursive deletion is unavailable
  in the delivered core.

Preflight rejection applies nothing. Applied filesystem changes are not
reversed by text undo. Use ordinary undo only while editing the uncommitted
filename projection.
