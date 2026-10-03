<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Ownership and Lifetimes

Persistent ropes avoid copying unchanged text by sharing immutable nodes. That
optimization is safe only when every handle, byte view, and allocator has an
explicit lifetime.

## Interaction workflow ownership

The process-level input router resolves a command and delegates each
multi-turn interaction to one responsibility-owned workflow. Search and query
replacement share a search owner; open, save, kill, and exit coordination use
a document owner; marked Buffer Menu operations use an inventory owner;
clipboard import, export, yank state, and kill continuity use a clipboard
owner; UI workflows and prompts each own their checked contextual state.

These owners retain only the state required across input turns. The router
borrows canonical editor, session, registry, allocator, and frontend resources
for the current operation. It does not duplicate canonical text or transfer
ownership through a prompt or UI root.

Every retained workflow has an explicit reset boundary:

| End condition | State released or invalidated |
| --- | --- |
| Prompt completion or cancellation | Prompt storage and map, search transient state, document prompt state, inspection input |
| Marked operation completion or cancellation | Copied mark batch, decisions, pending entry, temporary path |
| UI-workflow completion or invalidation | UI root, context map, inspection input, command catalog, candidate session |
| Coordinator shutdown | All workflow state, after contextual maps are ended |

This partition keeps lifecycle cleanup deterministic and prevents the
process-level coordinator from becoming shared mutable storage for unrelated
features.

## Buffer ownership

The caller provides storage for `editor.Buffer` and initializes it once. A live
buffer owns its internal state, canonical root, and most recent committed change
and undo records. `editor.buffer_close` releases that state and invalidates the
handle.

The persistent allocator supplied at initialization must remain usable until
`buffer_close` returns. Temporary allocators are borrowed only for the operation
that receives them.

## Root ownership

A valid `text.Root` is a retained handle. `root_build`, `root_retain`, and
`root_prepare_splice` each return one independently owned reference on success.
Every such handle must eventually be passed by pointer to `root_release` exactly
once. Release invalidates the caller's handle before reclamation proceeds.

Several roots may point at the same immutable node. Reference counts keep that
node alive until no root can reach it.

## Prepared-splice ownership

A valid `editor.Prepared_Splice` owns an unpublished root plus candidate change
and undo text. It also reserves the buffer's single preparation slot. Aborting
the preparation releases all of those resources and leaves canonical state
unchanged. The internal publication path instead transfers the candidate root
and records into the buffer before consuming the handle.

## Borrowed text views

Not every Odin `string` owns its bytes.

| View | Owner | Valid until |
| --- | --- | --- |
| `Splice.replacement` | Caller | Validation and preparation finish |
| Candidate change and undo text | Prepared splice | Abort or publication consumes the preparation |
| Committed change and undo text | Buffer | Next successful splice or `buffer_close` |
| Inspection destination | Caller | Determined entirely by the caller |

Inspection copies bytes into caller-owned storage specifically to avoid lending
a view into rope chunks whose retention would otherwise become ambiguous.

## Bounded reclamation

Releasing a root may make a subtree unreachable. Normal release processes only
the configured number of nodes and queues the rest, preventing one edit from
performing unbounded cleanup. `root_maintain` advances that queue explicitly.
When the final store handle disappears, release drains all remaining nodes and
then frees the store.

This division makes two guarantees compatible: individual operations have
bounded routine work, and final ownership still ends with complete cleanup.
