<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Trace a Multibuffer Edit Proposal

This code-reading path follows one two-buffer proposal from confirmed snapshots
to one shared commit. The relevant implementation is in `src/transaction`.

## 1. Start from confirmed buffers

Assume buffers 7 and 9 are both at revision 3. Ordinary readers can inspect
their canonical text. No private transaction state exists yet.

## 2. Capture the producer's assumptions

The producer creates one `Proposal_Snapshot` for each buffer. Every snapshot
contains the live buffer handle, `Buffer_ID`, and revision 3. It also creates
one `Proposal_Edit` per snapshot. Each edit carries an ordered base-relative
batch whose positions also belong to revision 3.

The snapshot list and edit list together form an `Edit_Proposal`. Their input
order is not publication order.

## 3. Admit the complete proposal

`proposal_admit` checks that the two lists describe the same unique participant
set. It verifies that both live buffers still have revision 3. A mismatch
returns `Stale_Revision` before any private state opens.

The coordinator sorts the set by buffer identity: buffer 7, then buffer 9. It
opens one private working revision for each and applies both batches. If the
second batch fails, the first private result is discarded too.

## 4. Validate without publication

Each private revision is normalized and reconstructed against its confirmed
base. Publication records are allocated and reserved for both buffers. The
root reaches `Ready` only after every participant passes.

At this point ordinary readers still observe revision 3 in both buffers.

## 5. Publish one logical result

`multibuffer_commit` enters the non-cancelable publication section. It installs
buffer 7 and buffer 9 in deterministic order without calling Racket, observers,
allocators, or external I/O. The exclusive editor turn prevents another reader
from observing the internal installation sequence.

The returned `Multibuffer_Commit_Event` contains:

1. One `Transaction_ID`.
2. One linked `Undo_Unit_ID`.
3. Producer origin and command metadata.
4. Ordered `Buffer_Commit_Result` entries for buffers 7 and 9.
5. One normalized changeset per buffer.

Both buffers now expose revision 4.

## 6. Observe after commit

The shared observer receives the complete event only after the root is
`Committed`. `multibuffer_event_for_buffer` can select buffer 9 while retaining
the shared transaction and undo identities. Observer failure is recorded but
does not undo revision 4.

## 7. Release borrowed results

The event and normalized splice slices borrow transaction-owned storage.
`multibuffer_close` releases that storage. The canonical buffer revisions and
their editor-owned records remain valid.

Continue with
[Atomic Edit Transaction Reference](../../reference/atomic-edit-transactions/index.md)
for exact declarations and [Why Commands Publish Through Transactions](../../explanation/atomic-edit-transactions/index.md)
for the design rationale.

