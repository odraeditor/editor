<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Manage a Workspace

This chapter prepares one durable Workspace from the two tutorial Projects,
opens and switches it, changes Project membership and order, and dissolves the
Workspace without deleting its Projects.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../getting-started/prepare-exercises.md).

Complete [Manage a Project](manage-a-project.md). Both
`~/odra-guide/work/projects/forecast-engine` and
`~/odra-guide/work/projects/report-console` must be present.

Restore both maintained Project identities and the original ordered Workspace
through the installed helper:

```sh
"$HOME/odra-guide/kit/bin/odra-guide" reset workspace-state
```

The helper restores only the two declared Project records and the `User Guide`
Workspace. It does not require a source checkout or Racket installation.

## Open the Workspace

Launch Odra with the same isolated configuration base:

```sh
odra
```

Select `Open Workspace`, filter for `User Guide`, and press Enter. The row
shows `2 Projects`. Opening validates every member before replacing the active
root set.

Darek appears with `Forecast Engine` and `Report Console` as ordered top-level
roots. If a compatible recent document exists, Odra restores it; otherwise it
shows the first Project context. The Status Bar identifies `W:User Guide` and
the Project that owns the active file when space permits.

## Switch Between Registered Workspaces

With Darek focused, press `C-c C-w s` to open Workspace candidates. Select the
current Workspace to confirm the workflow without changing composition.

When several Workspaces exist, `C-c C-w n` opens the next registered entry.
Both commands validate the complete target before activation. Dirty buffers
must be resolved before an incompatible root set can replace the current one.

## Add a Project

Create and promote one disposable Project:

```sh
mkdir -p "$HOME/odra-guide/work/dirs/workspace-notes"
printf 'Workspace membership exercise\n' \
  > "$HOME/odra-guide/work/dirs/workspace-notes/notes.txt"
```

Open the new Dir, select `notes.txt`, run `M-x project-promote`, and name it
`Workspace Notes`.

Run `M-x workspace-add-project`. Select `Workspace Notes`, then select
`User Guide`. Odra publishes one new Workspace generation and reports
`Workspace updated`. Reopen the Workspace and confirm that Darek now shows
three Project roots.

Adding the same Project twice, adding an unavailable Project, or acting on a
stale Workspace generation is rejected without publishing a partial member
set.

## Reorder Projects

In Darek, select the `Workspace Notes` top-level Project. Press `M-Up` to move
it one position earlier or `M-Down` to move it later. Movement at the first or
last boundary leaves the order unchanged.

The new order is durable. Reopen `User Guide` and confirm that its top-level
Project roots retain the published sequence. The next User Guide module
teaches Darek navigation in depth; here it provides the current checked
Workspace reorder action.

## Remove a Project

Run `M-x workspace-remove-project`. Select `Workspace Notes`, then select
`User Guide`. Reopen the Workspace and confirm that the two maintained
tutorial Projects remain.

Removing a Project from a Workspace does not unregister that Project or delete
its files. The Workspace must retain at least one Project.

## Dissolve the Workspace

Run `M-x workspace-unregister`, select `User Guide`, and press Enter. Odra
reports `Workspace removed from registry`. `Open Workspace` no longer lists
it, while `Open Project` still lists both member Projects.

This is the Workspace dissolution operation: it removes only the durable
composition. It does not remove Project identity, trust, metadata, files,
buffers, or text.

Recreate the tutorial Workspace for later Darek and cross-Project chapters.
Remove the separate exercise Project from discovery with
`M-x project-unregister`, then reset its declared disposable root:

```sh
"$HOME/odra-guide/kit/bin/odra-guide" reset workspace-state
"$HOME/odra-guide/kit/bin/odra-guide" reset working-context-demos
```

## Recover from Workspace Problems

- If setup reports that a Project is invalid, reopen that root and verify its
  local Project identity and discovery entry.
- If opening reports unavailable members, restore or repair every listed
  Project before retrying; no subset is activated.
- If a member changed generation, update or recreate the Workspace through a
  checked workflow rather than trusting an old row.
- If modified buffers block activation, save, discard, or cancel through the
  ordinary dirty-state prompt.
- Press `C-g` to leave Project or Workspace candidate selection without
  publishing a change.

## Verify the Result

You have completed this chapter when `User Guide` opens both maintained
Projects atomically, its Project order survives reopening, a disposable
Project can be added and removed without file loss, dissolution preserves its
member Projects, and the maintained helper recreates the original composition.

Continue with
[Manage Repository Changes with Ksawery](manage-changes-with-ksawery.md).

For exact composition, generation, membership, trust, bounds, and failure
behavior, see the
[Workspace Composition Reference](../../../reference/workspace-composition/index.md).

---

[Previous: Manage a Project](manage-a-project.md) ·
[User Guide](../index.md) ·
[Next: Manage Repository Changes with Ksawery](manage-changes-with-ksawery.md)
