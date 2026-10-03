<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Project and Workspace Migration Reference

Legacy migration converts the former global multi-dir Project catalog into
local one-root Projects and global Workspaces. It is explicit, bounded,
source-preserving, and journaled.

## Inputs and targets

The default read-only input root is `$HOME/.odra/`:

```text
$HOME/.odra/
|-- projects/<legacy-project-id>.rkt
`-- state/
```

Targets use the current lifecycle layout:

```text
<project-dir>/.odra/project.rkt

$XDG_CONFIG_HOME/odra/
|-- projects/<project-id>.rkt
|-- workspaces/<workspace-id>.rkt
|-- migration.rkt
`-- state/
```

When `XDG_CONFIG_HOME` is absent, the target global root is
`$HOME/.config/odra/`.

## Mapping

A valid legacy Project with one Dir becomes one local Project record and one
global discovery reference. Its identity, display name, and representable
trust state are preserved.

A valid legacy Project with several distinct Dirs becomes one local Project
per Dir plus one Workspace with the legacy identity, display name, and root
order. A member Dir shared by several legacy records resolves to one validated
target Project instead of being promoted repeatedly.

Confirmed candidate history moves to the global `state/` root with its entries
preserved and a new target generation. Rejected or unavailable state remains
visible in the plan and is not published.

## Planning and publication

`legacy-migration-plan-compose` reads a copied legacy inventory and current
target catalogs. It produces deterministic Project, Workspace, candidate
state, source, rejection, and expected journal-generation records without
writing.

`legacy-migration-execute` publishes one admitted source at a time:

1. persist the source as `planned` in `migration.rkt`;
2. transition it to `staged`;
3. publish and reload every target record;
4. transition it to `published`; and
5. preserve all journal entries whose source is absent from the current
   inventory.

If publication fails, records created only by that attempt are rolled back.
Pre-existing exact targets are retained. A later plan classifies valid
completed targets as `already-published` and incomplete journal entries as
`retry`.

## Rejections and failures

Planning separates invalid inventory, unavailable roots, target identity or
root conflicts, invalid journals, and conflicting Workspaces. Rejected sources
remain input for a later run.

Execution separates journal, Project, discovery, Workspace, candidate-state,
rollback, and unresolved-publication failures. The failure record states
whether no target, a partial target, a complete target, or an uncertain target
may be visible.

Neither planning nor execution deletes or rewrites legacy source records.

## Command contract

`scripts/migrate-project-workspaces.rkt` previews by default and requires
`--apply` for publication. `--legacy-root` and `--configuration-root` replace
the defaults for isolated operation.

Exit statuses are:

| Status | Meaning |
| ---: | --- |
| `0` | Every admitted source is complete and no source is rejected. |
| `1` | At least one execution failure occurred. |
| `2` | At least one source remains rejected and retryable. |
