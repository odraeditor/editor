<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Project Promotion Reference

## Command

`project-promote` is a named lifecycle command available through `Meta-X`. It
requires one exact ordinary Dir root. Its text prompt proposes the Dir basename
as an editable Project name.

Success creates one local Project with generation `1`, untrusted state, and an
exact normalized root. It publishes the matching global discovery reference,
then atomically replaces the session's Dir projection with the Project
projection. It does not change documents, buffers, views, or text.

## Abandonment decisions

The terminal offers promotion before an ordinary Dir is replaced or abandoned
during exit. It does not offer the decision for file closure, buffer or pane
switching, movement within a Dir, an existing Project, or a suppressed Dir.

| Decision | Persistent effect | Pending action |
| --- | --- | --- |
| Promote | Local Project and global discovery reference | Continues after durable publication and session conversion |
| No | None | Continues |
| Cancel | None | Cancels |
| Disable | Exact global Dir suppression | Continues after durable publication |

Exit performs modified-buffer protection before preparing Dir abandonment.
Preparations retain the exact root handle, root-set generation, normalized
path, and pending action. Admission rejects a changed root set or mismatched
Project conversion.

## Suppression state

The global `promotion-suppressions.rkt` record stores a generation and a
bounded ordered set of normalized absolute Dir paths. Inspect, add, and remove
operations are idempotent for an unchanged exact path. A successful mutation
increments the record generation once.

Suppression lookup occurs before each eligible abandonment decision. Moving or
renaming a Dir changes its path identity. Removing its exact global entry makes
the Dir eligible again. Suppression never creates Project identity or local
`.odra/` metadata.

## Publication and recovery

Local Project metadata is canonical. Global discovery is rebuildable. A
promotion publishes local metadata first and publishes discovery only after
the local record reloads exactly. A local-only result is reconciled
deterministically by publishing the matching discovery reference.

Prepublication failure preserves the ordinary Dir and removes a newly created
empty `.odra/` dir. Existing `.odra/` content without one valid matching
Project record is a conflict and is not overwritten. Visible but uncertain
durability stops the pending abandonment action until later reconciliation.

New Projects remain untrusted. Promotion does not admit executable
configuration, tools, processes, language services, extensions, commands, or
keymaps.

## Focused validation

```sh
make project-promotion-test
make native-command-test
```

The focused suite covers local and discovery round trips, duplicates,
conflicts, trust, stale generations, suppression restart and removal,
publication faults, cancellation, every terminal decision, and terminal
restoration.
