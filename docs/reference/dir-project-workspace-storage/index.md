<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Dir, Project, and Workspace Storage Reference

This reference describes the storage contracts used by the Dir-first session
and Project promotion workflows.

## Ownership

- `src/project` owns checked Dir handles, one-root Project records, global
  Project discovery references, promotion suppressions, migration entries,
  limits, failures, and read-only legacy inventory.
- `src/workspace` owns Workspace identity, ordered Project references,
  cardinality, limits, and record validation.
- Racket owns constrained record decoding, deterministic catalog enumeration,
  private staging, loader validation, atomic replacement, and filesystem
  durability reporting.
- Odin owns canonical runtime identity, generations, resource accounting, and
  later publication into editor sessions.

No record is evaluated as arbitrary configuration code. Target storage uses a
closed declarative datum after the required `#lang odra/config` header.

## Paths

The initial target paths are:

```text
<project-dir>/.odra/project.rkt

$XDG_CONFIG_HOME/odra/
|-- projects/<project-id>.rkt
|-- workspaces/<workspace-id>.rkt
|-- promotion-suppressions.rkt
|-- migration.rkt
`-- state/
```

When `XDG_CONFIG_HOME` is absent, the global root is
`$HOME/.config/odra/`. Callers and tests may supply both inputs explicitly.

The local `.odra/` path is reserved for a Project created through admitted
promotion or migration. Merely loading or inventorying a Dir does not invoke
the writer.

New storage roots use owner-only `0700` permissions. Records and private stage
files use `0600`. Symbolic-link parents or targets and pre-existing paths with
unsafe permissions are rejected.

## Local Project Record

`<project-dir>/.odra/project.rkt` is the canonical one-root Project record.
Format version 2 contains:

- one filename-compatible Project identity;
- one nonzero 64-bit generation;
- one bounded display name;
- the normalized absolute root path; and
- explicit `untrusted` or `trusted` state.

The root must identify the Dir containing the record when later promotion and
migration workflows publish it. The storage loader validates shape and bounds;
the workflow validates that filesystem relationship.

## Global Project Discovery

`projects/<project-id>.rkt` contains the same Project identity, its expected
local generation, and its last known root. Enumeration is immediate, bounded,
and ordered by identity.

A discovery reference is not Project authority. Resolution must load the local
record and confirm its identity and generation. References with duplicate
roots are rejected from the valid catalog and remain inspectable.

## Workspace Record

`workspaces/<workspace-id>.rkt` contains:

- one Workspace identity and generation;
- one bounded display name; and
- between 2 and 256 ordered, distinct Project references.

Each member stores the Project identity, expected local generation, and last
known root. Duplicate member identities are invalid. Workspace catalog entries
with duplicate display names are rejected from the valid catalog.

## Promotion Suppressions

`promotion-suppressions.rkt` stores one record generation and at most 4,096
distinct normalized absolute Dir paths. It contains no Project or Workspace
identity and cannot satisfy either lookup. Inspection is read-only. Exact-path
add and remove operations are idempotent when the requested state already
holds; each actual replacement advances the record generation once.

## Migration Journal

`migration.rkt` stores at most 4,096 source-preserving entries. Each entry has
one legacy source identity, source path, target identity, and one of:

- `planned`;
- `staged`;
- `published`; or
- `rejected`.

The explicit migration workflow uses this journal to distinguish planned,
staged, published, rejected, and retryable source state across restarts.

## Atomic Publication

Every writer:

1. validates the owner-only parent and target;
2. checks that a new record begins at generation 1 or an update increments the
   existing generation exactly once;
3. writes one private sibling stage;
4. flushes and synchronizes the stage;
5. reloads it through the real closed-schema loader;
6. compares the loaded record with the proposal;
7. atomically replaces the target; and
8. synchronizes the parent.

Failure before replacement removes the private stage and reports
`not-published`. Parent synchronization failure reports
`published-durability-uncertain` and leaves the visible validated record for
deterministic reconciliation.

## Legacy Inventory

The inventory loader reads valid records from the current
`~/.odra/projects/` catalog and corresponding `~/.odra/state/` candidate state
into bounded copied proposals. Invalid Project and state records remain
separate rejections.

Inventory performs no target publication and no source mutation. The migration
planner consumes its copied proposals; only the explicit `--apply` command may
publish target state.

## Selected Bounds

| Resource | Default | Maximum |
| --- | ---: | ---: |
| Project discovery records | 128 | 1,024 |
| Workspaces | 32 | 256 |
| Projects per Workspace | 32 | 256 |
| Promotion suppressions | 256 | 4,096 |
| Migration entries | 256 | 4,096 |
| Retained lifecycle record bytes | 8 MiB | 64 MiB |
| One record module | 4 MiB | 4 MiB |

The stress study covers 1,024 Projects, 256 Workspaces with 256 members each,
and 4,096 suppressions. Its tracked retained allocation is approximately 1.32
MiB and cleanup returns to zero.

## Focused Validation

```sh
odin test tests/project_reference -vet -warnings-as-errors
make project-resource-study
odin test src/project -vet -warnings-as-errors
odin test src/workspace -vet -warnings-as-errors
make lifecycle-storage-test
make project-workspace-migration-acceptance
```

These commands validate the independent oracle, resource profiles, native
contracts, real local and global round trips, catalog ordering and conflicts,
legacy source preservation, generation checks, permissions, partial writes,
loader rejection, synchronization faults, atomic publication, and cleanup.
The migration acceptance target additionally verifies single-dir and multi-dir
mapping, overlap, rejection, rollback, idempotent restart, source preservation,
target-root adoption, and terminal reopening of migrated Projects and
Workspaces.
