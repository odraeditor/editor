<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Manage a Project

This chapter promotes an ordinary Dir, reopens the resulting Project through
global discovery, inspects and refreshes it, and removes a disposable Project
from discovery without deleting its files.

## Before You Begin

Complete [Navigate Filesystem Paths](navigate-filesystem-paths.md). The
disposable tutorial workspace should still contain `forecast-engine` and
`report-console` below `~/odra-guide/work/projects/`, and the guide shell must
still use the isolated configuration activated during
[exercise setup](../getting-started/prepare-exercises.md#activate-the-guide-session).

Restore the ordinary-Dir starting state for Report Console:

```sh
"$HOME/odra-guide/kit/bin/odra-guide" reset report-console-promotion
```

## Promote a Dir

Start Odra and select `Open Dir`:

```sh
odra
```

Enter `~/odra-guide/work/projects/report-console`, select `main.rkt`, and
press Enter. Run `M-x project-promote`. The prompt proposes `report-console`;
replace it with `Report Console` and press Enter.

The message `Dir promoted to Project` confirms one durable transition. The
current files, buffers, panes, and text remain in place. The Project begins
untrusted.

Promotion also makes the Project available to global discovery. It does not
initialize version control, infer identity from source files, or add another
root.

## Inspect and Use Project Scope

Run `M-x describe-project`. Confirm the `Report Console` name, its one root,
and untrusted state.

Press `C-c p f`, filter for `templates/daily.txt`, and press Enter. The candidate
source contains regular files below the Project root. Press `C-c p b` to see
only open buffers owned by this Project.

Press `C-c p i` to run `project-refresh`. Refresh replaces the complete
observed file generation while preserving Project identity and existing
buffers. Missing or unreadable content is reported without publishing a
partial generation.

## Reopen Through Discovery

Exit the unchanged session and launch Odra again with the same configuration
root. Select `Open Project`.

The candidate list contains `Report Console`. Type any part of its name or
root to filter, move with the ordinary candidate keys, and press Enter. Select
`main.rkt` if file navigation appears. The Status Bar shows the active Project
when width permits.

`Open Project` validates each discovery row against its current local Project
identity. A missing root, invalid local identity, root mismatch, or stale
generation is omitted rather than opened from display text alone.

## Understand Project Trust

Promotion does not admit executable Project behavior. `describe-project`
continues to report `untrusted` until the exact local Project generation is
published as trusted through the checked trust workflow.

The current factory editor has no interactive command for changing trust.
Ordinary editing, navigation, and file management remain available while
Project-local configuration, tools, language services, and extensions remain
inactive. Follow [Manage Project Trust and Refresh](../../../how-to/manage-project-trust/index.md)
when a later chapter requires a trusted Project.

Trust belongs to each Project independently. Opening it inside a Workspace
cannot grant or inherit trust.

## Remove a Disposable Project from Discovery

Create a separate disposable root so this exercise does not remove either
tutorial Project:

```sh
mkdir -p "$HOME/odra-guide/work/dirs/project-removal-demo"
printf 'temporary project lifecycle exercise\n' \
  > "$HOME/odra-guide/work/dirs/project-removal-demo/notes.txt"
```

Open that Dir, select `notes.txt`, run `M-x project-promote`, and name it
`Removal Demo`. Exit, relaunch with the same configuration root, and confirm
that `Open Project` lists it.

Run `M-x project-unregister`, select `Removal Demo`, and press Enter. Odra
reports `Project removed from registry`. This operation removes global
discovery and removes the Project from every registered Workspace. It does not
delete files or erase the local Project identity.

Open `~/odra-guide/work/dirs/project-removal-demo` through `Open Dir` and run
`describe-project`. The valid local identity still establishes Project scope,
but `Removal Demo` no longer appears under `Open Project`. The current factory
interaction does not expose a separate command to rebuild that discovery
entry.

After leaving Odra, remove only the disposable exercise root:

```sh
"$HOME/odra-guide/kit/bin/odra-guide" reset working-context-demos
```

## Recover from Project Problems

- If promotion finds existing unrelated `.odra/` content, it rejects the
  operation instead of overwriting it.
- If Project discovery omits a root, open the exact Dir and inspect its local
  identity with `describe-project`.
- If a candidate becomes stale before acceptance, reopen the Project list.
- If refresh fails, correct the filesystem problem and retry; the prior valid
  observation remains active.
- Use `C-g` to cancel a Project candidate or naming prompt without changing
  the current context.

## Verify the Result

You have completed this chapter when `Report Console` opens through global
Project discovery, its scoped file and buffer commands work, refresh preserves
identity, trust is understood as a separate admission decision, and removing
`Removal Demo` from discovery leaves its local files untouched.

Continue with [Manage a Workspace](manage-a-workspace.md).

For concise operations and exact lifecycle behavior, see
[Promote Dirs to Projects](../../../how-to/promote-dirs/index.md),
[Manage a Project Root](../../../how-to/manage-project-directories/index.md),
and the [Project Context Reference](../../../reference/project-context/index.md).

---

[Previous: Navigate Filesystem Paths](navigate-filesystem-paths.md) ·
[User Guide](../index.md) ·
[Next: Manage a Workspace](manage-a-workspace.md)
