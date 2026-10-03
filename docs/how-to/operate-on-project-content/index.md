<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Operate on Project Content

These procedures apply to the one active Project.

## Open or reuse a Project file

1. Press `Control-C p f`.
2. Type any case-insensitive components of the relative label or canonical
   path. Component order does not matter.
3. Move with `Control-N`, `Control-P`, Down, or Up.
4. Press Enter.

The selector enumerates the one Project root. Selection rejects a stale Project
generation, and an already open canonical path reuses its existing buffer.
Press `Backspace` or `DEL` to remove one UTF-8 scalar. Press `Control-G` to
leave the candidate root without opening a file; printable `q` is query
text.

For a local Project, later candidate sessions rank successfully selected
commands, file-backed buffers, and Project files using that Project's private
usage history. Cancelling, selecting a stale row, or receiving an action
failure does not change the history. If the private record cannot be loaded or
saved, continue using the selector; persistence is advisory and navigation
remains available.

## Switch to a Project-owned buffer

Press `Control-C p b`, type any case-insensitive part of a live buffer path,
and press Enter. Move with `Control-N`, `Control-P`, Down, or Up; use
`Backspace` or `DEL` to remove one UTF-8 scalar and `Control-G` to cancel. The
list excludes external files and unassociated buffers even when they remain
live in the same editor session, and it never offers a creation row.

## Save every modified Project buffer

Press `Control-C p S`. Saving is scoped to modified file-backed buffers owned by
the active Project. A save failure stops the operation and reports the checked
failure; external buffers are never admitted.

## Close Project buffers safely

Press `Control-C p k`. For each modified Project buffer, choose:

- `s` to save and continue;
- `d` to authorize discard and continue; or
- `c` or `Control-G` to cancel without closing the set.

Odra validates all dirty decisions before publishing one atomic close set. If
the set removes the last live buffer, the startup list becomes visible.

## Refresh Project observations

Press `Control-C p i`. Refresh reconciles the one Project root and publishes
only a complete observation generation. A missing or unreadable root remains
the Project root and is reported as unavailable.

The same binding refreshes an open Project-file candidate session. A complete
new source replaces the old one atomically. Selection follows the same
canonical file when it remains, falls back to the first ranked row after
disappearance, and preserves the prior view after overflow, stale scope,
filesystem failure, or allocation failure.

## Discover Project commands

Press `Control-C p m` to open `Meta-X` command navigation with the `project-`
query prefilled. Press `Control-C p Control-H` to inspect the Project keymap,
including masked reservations and binding provenance.

See the [Project Context Reference](../../reference/project-context/) for the
complete command, limit, and failure contracts.
