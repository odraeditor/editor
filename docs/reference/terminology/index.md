<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Editor Core Terminology

## Buffer

The editor-owned object containing canonical text, identity, revision, limits,
and committed records.

## Editor session

The Odin-owned coordinator for live buffer graphs, checked identities,
selection indexes, aggregate policy, activation order, visible-target identity,
detachment, and cleanup.

## Project

One durable identity for one normalized root Dir. Its canonical record is
local to that Dir. A Project is not inferred from version-control metadata and
does not own the files, buffers, documents, histories, or views below its root.

## Project projection

One checked session relationship between a local Project generation and its
normalized root. The checked Project handle, rather than the path alone,
authorizes generation-sensitive operations.

## Project snapshot

One immutable, complete publication of Project identity, name, root, trust, and
generation. Replacement prepares a new snapshot privately and publishes it
atomically.

## Workspace

One durable ordered composition of at least one Project reference.
A Workspace restores roots together but owns no Project identity, trust,
configuration, buffers, documents, histories, or views.

## Project layer

The contextual keymap precedence class between buffer-local and global fallback
maps. It names where Project-scoped bindings participate; it does not itself
define or activate those bindings.

## Document

The optional association between one live buffer and one external target. It
owns normalized path identity, persistence state, observations, and safe I/O;
it does not own canonical text.

## Primary view

The retained logical presentation state used when one buffer is presented. It
owns stored point, desired column, viewport, resolved display policy, and
view-local transient state. Its buffer owns effective point, mark, and region
activation.

## Selection label

The complete bounded UTF-8 value used to select one live entry: an explicit
name for an unassociated buffer or its complete normalized path when
associated. A checked entry handle, not the label, authorizes mutation.

## Canonical state

The buffer root and revision visible to normal editor operations. Prepared
state is not canonical until atomic publication completes.

## Revision

A monotonically increasing version of one buffer. A successful splice advances
it exactly once. Positions from older revisions are stale.

## Position

A `(buffer identity, revision, byte offset)` tuple. The offset addresses UTF-8
bytes rather than characters and must lie on a code-point boundary.

## Splice

One replacement of the half-open range `[start, end)` with UTF-8 text. Insertion
uses an empty range; deletion uses an empty replacement.

## Validation

The non-mutating phase that checks identity, revision, range, UTF-8, size,
memory, and work bounds.

## Reservation

The calculated result size and resource budget attached to a validated splice.
Preparation must remain inside it.

## Preparation

The fallible phase that allocates a candidate rope and owned result records
without changing canonical state.

## Publication

The short phase that swaps the canonical root and advances the revision. No
expected failure, allocation, callback, or cancellation check belongs inside it.

## Rope

A tree representation of text. Leaves contain bounded UTF-8 byte chunks;
internal nodes contain children and cached summaries.

## Root

An opaque retained handle identifying one immutable rope version and its store.

## Leaf and chunk

A leaf is the terminal rope node. Its chunk owns the bounded byte payload.

## Internal node

A structural node that groups children and summarizes the bytes and line feeds
below it.

## Persistent structure

An immutable structure in which an edit creates a new version while the old
version remains valid. Versions may share unchanged nodes.

## Structural sharing

Reuse of immutable nodes by multiple roots. Sharing reduces copying but makes
reference ownership and reclamation explicit.

## Change set

The committed description of what range changed and what replacement was
published.

## Undo record

The removed and inserted text required to describe the inverse edit.

## Ownership

The obligation to keep a resource alive and release it exactly once. Handles,
text views, and allocators have different owners and lifetimes.

## Reclamation

Recovery of nodes that no retained root can reach. Normal release performs
bounded work; final store release drains the remaining queue.

## Racket runtime

The single embedded Racket CS instance owned and started by Odin. It is
process-long and cannot restart after failure or shutdown.

## Native boundary

The narrow C-compatible interface between Odin and Racket CS. It transfers
checked scalar values, copied bytes, result envelopes, and diagnostics.

## Capability

An opaque non-pointer token that authorizes one class of operation on an
Odin-owned resource. A buffer capability names a registry, slot, and generation.

## Generation

A counter advanced when a capability slot is reused. A token with an earlier
generation is stale even when its slot number now contains another resource.

## Registry

The Odin-owned bounded table that maps opaque capabilities to checked native
buffer references. Racket never receives the table or its pointers.

## Command turn

One bounded sequence in which Racket requests copied input, computes a result,
and returns at most one proposed splice before Odin validation and publication.

## Exception barrier

The Racket wrapper and native validation that convert an ordinary Racket
exception into a structured Odin failure before control returns to editor code.

## Result envelope

A fixed-shape Racket list carrying success, checked values, copied bytes, and a
bounded diagnostic. The native adapter validates every element.
