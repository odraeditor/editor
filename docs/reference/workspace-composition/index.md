<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Workspace Composition Reference

A Workspace is a durable ordered composition of at least one distinct
Projects. It restores Project roots together without transferring Project
identity, trust, configuration, or local metadata into the Workspace.

## Durable identity and storage

Each Workspace has an opaque identifier, a display name, a positive
generation, and an ordered list of Project references. The canonical record is
stored under:

```text
$XDG_CONFIG_HOME/odra/workspaces/<workspace-id>.rkt
```

When `XDG_CONFIG_HOME` is absent, Odra uses
`$HOME/.config/odra/workspaces/<workspace-id>.rkt`.

Each member reference copies the expected Project identity, generation, and
last known normalized root. The Project's local `.odra/project.rkt` record
remains authoritative for its identity, name, root, and trust state.

## Operations

The Workspace command boundary provides these checked operations:

- `workspace_create` persists the current ordered roots when every root is a
  Project and the composition contains at least one Project.
- `workspace_open` resolves every member and atomically activates the complete
  composition.
- `workspace_update` replaces the name or ordered member set only when the
  expected Workspace generation is current.
- `workspace_list` returns the deterministic global catalog.
- `workspace_inspect` returns one Workspace and the resolution state of every
  member.

Create, open, and update results own copied descriptors and member diagnostics
until `workspace_command_batch_close` releases them.

## Startup selection

The startup screen includes `Open Workspace`. Activating it opens the shared
candidate navigator. Each row shows the Workspace name and Project count.
Typing filters the list, the arrow keys change the current candidate, `Enter`
opens it, and the ordinary component-close command cancels navigation.
Successful selections contribute to bounded global Workspace recency, which
is stored and ranked independently from Project recency.

Successful opening publishes the stored root order and shows the first
Project. When an active document belongs to another member root, Project-scoped
consumers switch to the most specific enclosing Project root. This rule keeps
nested Project roots deterministic.

## Failure behavior

Workspace opening is all-or-nothing:

- missing, unavailable, conflicting, or stale members remain visible with
  copied diagnostics and do not rewrite the durable record;
- modified buffers require explicit resolution before a different root set can
  replace the current composition;
- stale Workspace or root generations are rejected;
- duplicate Workspace identities, names, Project identities, and member roots
  are rejected before publication; and
- cancellation releases the prepared composition without changing active
  roots.

Project trust remains Project-scoped. A Workspace never grants trust and does
not enable Project-local configuration, tools, language services, or
extensions for an untrusted member.

## Bounds

The checked Workspace model admits at most 256 Workspaces per catalog and 256
Projects per Workspace. Factory defaults admit 32 Workspaces and 32 Projects
per Workspace. Candidate presentation, copied bridge records, text, temporary
storage, and session roots remain subject to their respective checked limits.
