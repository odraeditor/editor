<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Roman Remains an Optional Package

Roman is a product composed from Odra capabilities, not a second knowledge
subsystem embedded in editor core. This boundary lets users install, update,
disable, replace, or omit linked-knowledge behavior while core continues to
own text, views, transactions, Projects, Jan semantics, and package isolation.

## Canonical Source and Derived State

The default brain keeps Jan documents canonical because they remain readable,
editable, versionable, and recoverable without Roman. Roman's SQLite database
accelerates identity, relation, query, and graph workflows. Treating that
database as a rebuildable projection prevents an index failure from becoming
document loss or a second conflicting source of truth.

Managed provider spaces have a different ownership class: their records may
be canonical package data. Roman therefore identifies every space, consumer,
grant, schema, generation, and storage owner explicitly instead of pretending
that all knowledge is document-backed.

## The Generic Native Boundary

Roman needs Jan meaning but does not own Jan parsing. Odra exposes one generic
bounded analysis operation through the package command context. It returns
copied nodes, attributes, recoveries, and index facts for exact bytes. No parser
pointers, editor internals, or private Jan modules cross the boundary.

This split keeps native parsing and source fidelity in Jan while allowing a
verified Racket package to define product policy. Another package can consume
the same generic analysis surface without acquiring Roman concepts.

## Authority Follows the Resource

The package artifact grants no runtime trust by itself. Curation identifies
reviewed immutable bytes; installation verifies them; enablement grants the
requested authorities; and each command still receives a bounded context.

Roman reads the explicitly configured personal brain and writes captures below
that root. The editing Project does not select or replace the brain. Odra
supplies generic named package resources; it does not know Roman's brain model.
Roman edits open text only through checked transactions and stores derived
state only below its package data root. Its `external-process` grant admits one
semantic Graphviz rendering request with fixed arguments, destinations,
deadline, and output limits. General shell execution, network access,
foreign-library access, environment access, and private-module access remain
outside its authority.

## One Package, Many Modules

Roman is larger than a single entrypoint file. The generic package runtime
materializes every declared module from content-addressed verified artifacts,
then resolves only package-relative imports plus a narrow admitted Racket
library set. The entrypoint registers contributions; specialized modules own
corpus discovery, storage, indexing, interaction, relations, workflows,
providers, portability, and recovery.

This is still one activation unit. Odra validates the complete manifest and
command set before atomically publishing a contribution generation. Partial
module loading cannot expose a partial command catalog.

## Disablement Is Not Deletion

Disabling Roman removes its commands and contextual keymaps, then retires its
runtime generation. It
does not delete brain documents or package data. Removal and cleanup follow
generic package reachability, while destructive managed-data decisions remain
explicit Roman operations. This distinction makes experimentation reversible
and prevents package lifecycle commands from becoming hidden data-erasure
authority.

The exact public behavior is in the
[Roman Linked Knowledge Reference](../../reference/roman/index.md).
