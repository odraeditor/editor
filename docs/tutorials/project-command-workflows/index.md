<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Navigate and Operate on an Active Project

This tutorial uses the factory Project command family to open Project files,
move between Project-owned buffers, save them together, and inspect the active
bindings.

## 1. Open a Project

Run Odra without arguments:

```sh
make odra
.build/odra
```

Select `Open directory`, enter an existing directory, and press Enter. Odra
opens the exact local Project when a valid matching `.odra/project.rkt` is
present and presents its file candidates immediately. Without that record the
same action opens an ordinary Dir; follow
[Open and Navigate a Dir](../dir-first-opening/) instead because the
Project-scoped commands below intentionally remain unavailable.

## 2. Open a Project file

If the initial landing remains visible, use it directly. Later, press
`Control-C p f`. Odra traverses the active Project root in bounded native
turns, normalizes regular files, and then presents one complete candidate
generation. Each label is relative to the root while the canonical normalized
path remains the identity.

Type case-insensitive path components to filter. Use `Control-N`, `Control-P`,
Down, or Up to move, and `Backspace` or `DEL` to remove one UTF-8 scalar. Press
Enter to open the selected canonical path. If it is already open, Odra
activates its existing buffer instead of opening a duplicate. `Control-G`
cancels without opening a file.

## 3. Switch among Project buffers

Open another Project file, then press `Control-C p b`. The list includes only
live file-backed buffers whose normalized paths belong to the active Project.
External and unassociated buffers are absent. Select a row and press Enter.

## 4. Save Project buffers together

Modify one or more Project-owned file buffers and press `Control-C p S`. Odra
saves only modified, file-backed, Project-owned buffers. The diagnostic reports
the number examined, modified, and saved.

## 5. Inspect commands and bindings

Press `Control-C p m` to open command navigation already filtered to
`project-`. Press `Control-G` to leave it.

Press `Control-C p Control-H` to inspect the Project map. Active commands show
their binding, availability, map, and source. Reserved future sequences appear
as masked policy rather than executable placeholders. Press `q` to return.

## 6. Refresh and close

Press `Control-C p i` to reconcile the current Project root. The result
reports the published observation generation and root availability.
The same binding works while Project-file navigation is open: Odra builds a
complete replacement generation, preserves the selected file when it remains,
and keeps the prior candidate view if refresh or admission fails.

Press `Control-C p k` to close Project-owned buffers. A modified buffer requires
one decision: `s` saves it, `d` discards its changes, and `c` or `Control-G`
cancels the complete close operation. Decisions are collected before the
Project buffer set is closed atomically.

Continue with [Operate on Project Content](../../how-to/operate-on-project-content/)
for concise task procedures and failure handling.
