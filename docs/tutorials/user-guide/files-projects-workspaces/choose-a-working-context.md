<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Choose a Working Context

This chapter opens the same tutorial material as a Dir and as a Project, then
explains when a Workspace is the appropriate context for several Projects.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../getting-started/prepare-exercises.md).

Complete [Search Projects and Symbols](../search-and-navigation/search-projects-and-symbols.md)
and keep the kit-supplied Project roots created during exercise setup:

```sh
"$HOME/odra-guide/kit/bin/odra-guide" reset report-console-promotion
```

```text
~/odra-guide/work/projects/
|-- forecast-engine/
`-- report-console/
```

The reset leaves Report Console as an ordinary Dir and restores Forecast
Engine as the maintained Project used below.

## Open an Ordinary Dir

Start Odra without a path:

```sh
odra
```

Select `Open Dir`. Enter `~/odra-guide/work/projects/report-console`, select
`notes/review.md`, and press Enter.

Odra can list, open, and edit files below the root. It does not save the Dir in
the Project catalog, assign Project trust, or enable Project-scoped commands.
Running `M-x describe-project` reports that no Project is active.

Use a Dir when you want temporary filesystem scope without persistent editor
identity.

## Open a Project

Exit the unchanged session, restart Odra, select `Open Project`, and choose
`forecast-engine`. The Project was created in the preceding part; if you
started here directly, open its Dir and run `M-x project-promote` first.

Select `main.odin`. The pane Status Bar shows `P:forecast-engine` when space
permits. Run `M-x describe-project` to inspect the active Project name, root,
and trust state.

A Project gives one Dir a durable identity and makes it discoverable from
`Open Project`. Its commands can find files, switch among owned buffers,
search the root, save or close owned buffers, and refresh the observed file
set. Trust remains a separate Project decision.

Use a Project when one root should be reopened and operated on as a stable
unit.

## Recognize a Workspace

A Workspace is an ordered group of one or more existing Projects. It does not
turn several Dirs into one Project and does not combine their trust decisions.

Select `Open Workspace` on Startup when a Workspace is already registered.
The candidate row shows its display name and Project count. Opening it admits
all member roots together, displays them in Darek, and restores the most recent
compatible file when one is available. The Status Bar shows both `W:<name>`
and the Project that owns the active file.

Use a Workspace when one task needs files from several Projects or when the
order of those Projects should be reusable. Opening is atomic: an unavailable
or stale member prevents the new root set from replacing the current context.

The current factory interaction can open and modify registered Workspaces but
does not yet create the first Workspace from an editor command. The Workspace
Lifecycle chapter will distinguish the available workflow from this boundary.

## Compare the Three Contexts

| Context | Roots | Persistent identity | Project commands | Typical use |
| --- | ---: | --- | --- | --- |
| Dir | one | no | no | Inspect or edit one filesystem root temporarily. |
| Project | one | yes | yes | Reopen and operate on one stable root. |
| Workspace | one or more Projects | yes | delegated to the active member Project | Restore an ordered multi-Project task. |

Files and buffers remain ordinary editor resources in every context. Changing
context changes scope and discovery; it does not duplicate an already open
document or transfer text ownership.

## Recover from a Scope Mismatch

- If `Open Project` does not list a Dir, open it as a Dir and promote it, or
  verify that its local Project identity is still valid.
- If a Project-only command is unavailable, run `describe-project` and reopen
  the exact Project root.
- If a Workspace reports an unavailable member, restore or repair that Project
  before opening the Workspace again.
- Press `C-g` to cancel any context candidate surface without replacing the
  active roots.

## Verify the Result

You have completed this chapter when the ordinary Dir remains usable without
Project commands, the promoted root reopens through `Open Project`, and you
can explain why several independently trusted Projects belong in a Workspace
rather than in one multi-root Project.

Continue with [Navigate Filesystem Paths](navigate-filesystem-paths.md).

For exact scope and storage behavior, see the
[Project Context Reference](../../../reference/project-context/index.md) and
[Workspace Composition Reference](../../../reference/workspace-composition/index.md).

---

[Previous: Files, Projects, and Workspaces](index.md) ·
[User Guide](../index.md) ·
[Next: Navigate Filesystem Paths](navigate-filesystem-paths.md)
