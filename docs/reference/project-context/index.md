<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Project Context Reference

A Project is one durable identity for one normalized root Dir. Its local
record is authoritative; global discovery is an index, not a second identity
source.

## Scope and ownership

`src/project` owns checked Project identities, one-root records, discovery,
promotion, trust, file enumeration, candidate state, and migration. The editor
session owns the active Dir or Project projections and applies Project scope to
buffers without transferring buffer or document ownership.

An ordinary Dir has no Project capabilities. Opening it does not create local
metadata, grant trust, or start Project-rooted services.

## Identity and storage

The canonical Project record is:

```text
<project-dir>/.odra/project.rkt
```

It contains one opaque identity, one generation, one display name, the exact
normalized root, and one `trusted` or `untrusted` state. The record is created
only by explicit promotion or admitted legacy migration.

The global discovery record is:

```text
$XDG_CONFIG_HOME/odra/projects/<project-id>.rkt
```

It copies the identity, expected local generation, and last known root. A
discovery record establishes Project scope only when the matching local record
loads and validates.

`Open Project` lists these validated discovery references through the shared
candidate navigator. Rows are filtered by Project name, identity, or root.
Missing, malformed, root-mismatched, and generation-stale references are
omitted without changing either the global reference or local metadata.
Successful selection contributes to bounded global Project recency.

## Root resolution

Opening a root first admits it as a Dir. If the exact root contains a valid
local Project record whose stored root matches, Odra publishes a Project
projection instead. Invalid, missing, stale, or root-mismatched metadata does
not become Project authority.

A Project owns exactly one root. Ordered groups of one or more Projects are
represented by a Workspace, not by adding roots to a Project.

## Commands

| Command | Contract |
| --- | --- |
| `open-directory` | Opens one selected Dir as a Maksym buffer without changing Project identity. |
| `project-promote` | Creates local Project identity for the active ordinary Dir. |
| `describe-project` | Reports the active Project identity and one-root state. |
| `project-find-file` | Selects one regular file below the active Project root. |
| `project-switch-buffer` | Selects one live buffer owned by the active Project. |
| `project-save-buffers` | Saves modified file-backed Project buffers. |
| `project-close-buffers` | Closes Project buffers through ordinary dirty-state protection. |
| `project-refresh` | Reconciles the active Project root observation. |
| `project-search-text` | Searches literal text across the active Project and presents common read-only results. |
| `project-search-text-regexp` | Searches a regular expression across the active Project. |
| `project-search-repeat` | Repeats the last Project query against the current exact Project generation. |
| `project-command-menu` | Presents the active Project command collection. |
| `describe-project-bindings` | Inspects effective and reserved Project bindings. |

Project-only commands return a Project-scope failure in an ordinary Dir.

## Trust

Promotion creates an untrusted Project. Trust is exact to the one local
Project identity and root generation. Only a trusted Project may admit its
local configuration, tools, language services, or extensions.

Workspace activation preserves each member Project's trust independently. A
Workspace cannot grant or combine trust.

## Candidate and buffer scope

Project file candidates enumerate only the active normalized root. Candidate
identity is generation-bound and stale activation is rejected. A live buffer
is Project-owned when its associated path is contained by that root;
pathless or outside buffers remain external.

Project-wide save and close operations act only on Project-owned buffers.
Dirty-buffer protection and document publication remain owned by the editor
session.

Project text search reads admitted regular files without opening each file as
an editor buffer. Hidden, ignored, binary, include, and exclude policy is
explicit. Results retain checked source fingerprints and use the shared result
surface, refresh behavior, active location source, and return-location history.
Refreshing or replacing the active Project invalidates its prior search
authority.

## Limits and failures

Paths, names, identities, candidates, copied diagnostics, catalog entries,
record bytes, and session roots are bounded by their checked policies.
Publication is atomic and generation-checked. Missing roots, invalid local
records, stale discovery, unsafe permissions, symbolic links, and filesystem
failures preserve the last valid active state.

## Focused validation

```sh
make project-promotion-test
make workspace-composition-acceptance
make project-workspace-migration-acceptance
```
