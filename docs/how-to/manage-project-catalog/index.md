<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Inspect Project Discovery

Project discovery records live under the global Odra configuration root:

```text
$XDG_CONFIG_HOME/odra/projects/<project-id>.rkt
```

When `XDG_CONFIG_HOME` is absent, inspect
`$HOME/.config/odra/projects/`.

Each record is a rebuildable reference to one authoritative local
`<project-dir>/.odra/project.rkt`. A global record alone cannot turn a Dir into
a Project.

## Check one reference

1. Read its Project identity, expected local generation, and last known root.
2. Open the referenced root.
3. Invoke `describe-project`.
4. Confirm that the local identity and generation match the reference.

A missing root, missing local record, identity mismatch, or generation
mismatch is stale discovery. Odra reports the condition without rewriting the
local record.

## Recover legacy records

Do not copy records from `$HOME/.odra/projects/` into the current discovery
catalog. Use the explicit migration command so single-root and multi-root
state is mapped, validated, journaled, and kept retryable.

See [Migrate Legacy Project State](../migrate-project-workspaces/) for the
procedure.
