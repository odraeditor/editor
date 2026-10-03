<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Inspect Local Project Authority

This tutorial compares the local authoritative Project record with its global
discovery reference.

## Promote an isolated Dir

Open an ordinary Dir and run `project-promote`. After publication, inspect:

```text
<dir>/.odra/project.rkt
$XDG_CONFIG_HOME/odra/projects/<project-id>.rkt
```

If `XDG_CONFIG_HOME` is absent, the global base is `$HOME/.config/odra/`.

The local record contains the Project identity, generation, name, exact root,
and trust. The global record contains only the identity, expected local
generation, and last known root.

## Compare resolution

Reopen the exact root and invoke `describe-project`. Odra validates local
authority first and uses discovery only as a bounded index. Moving or deleting
the local record prevents the global reference from establishing Project
scope.

## Compare a Workspace

A Workspace stores ordered references with the same identity, expected
generation, and last-known-root shape. Opening it validates every member's
local record before publishing any root composition.

Continue with the [Dir, Project, and Workspace Storage Reference](../../reference/dir-project-workspace-storage/)
for exact schemas and publication rules.
