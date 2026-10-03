<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why the Editor Session Coordinates Complete Buffer Graphs

A buffer is not the whole editable experience. Showing and safely retaining
one text also requires history, optional persistence state, and a logical
view. Treating those objects as unrelated application variables works for one
startup document, but it cannot preserve identity and cleanup invariants once
several buffers remain live.

The editor session exists to own those relationships without taking over each
object's internal responsibility.

## Coordination is different from implementation

The session answers cross-object questions:

- Which buffer identities are live?
- Which document target belongs to which buffer?
- Which primary view should be visible?
- Which entry was activated most recently?
- Can a complete new graph fit inside aggregate policy?
- Can every observer stop reaching a graph before cleanup begins?

It does not answer how a rope applies a splice, how history retains a branch,
how a document saves a file, or how a view moves point. Those operations stay
with `editor`, `history`, `document`, and `view`.

This makes `editor_session` a lifecycle coordinator rather than a container
for unrelated editor functions.

## A label cannot be an identity

Names and paths can change meaning. A name may later be renamed; a filesystem
path can be associated after the buffer already exists. Neither value can
prove that an earlier command still addresses the same live object.

An `Entry_Handle` therefore combines session, registry, entry, slot, and slot
generation. The selection label remains complete human-facing metadata. The
normalized path remains a uniqueness index. Mutation uses the checked handle.

When a detached slot is reused, its generation advances. The old handle then
fails even if the slot number and new label happen to look familiar.

## The owner must stay at one address

A logical view retains a native reference to its editor buffer wrapper. Moving
that wrapper after view creation would leave the view pointing at an obsolete
address even though the buffer's internal state still existed.

Preparation therefore allocates one stable `Entry_Owner` first. Buffer,
history, and document wrappers transfer into that owner, and the primary view
is created against the stable buffer address. Publication moves only the owner
pointer into the registry slot. Detachment moves the same pointer into cleanup
state. The responsibility-owned wrapper never moves during its live graph.

## Reservation prevents partial graphs

Publishing a buffer before its history, document, view, labels, or index
entries are ready would expose a state that ordinary commands cannot use or
close safely.

The session uses the same prepare-then-publish discipline as the editor core:

```text
caller-owned live objects
          |
          v
validate identities and association
          |
          v
reserve slot, generation, indexes, MRU, and aggregate usage
          |
          v
allocate stable owner and create primary view
          |
          v
complete private graph -----failure-----> release or retain caller ownership
          |
          v
allocation-free publication
          |
          v
live indexed entry and visible primary view
```

Concurrent private preparations reserve their labels, paths, slots, document
capacity, and aggregate bytes before either graph becomes live. This prevents
two successful preparations from discovering the same uniqueness violation
only during publication.

## MRU order is session state

Effective point, mark, and region activation belong to the buffer. Stored point,
viewport, and search state belong to the primary view. The decision about which
primary view is current belongs to the session.

MRU order records activation intent, not storage order. Publishing or
activating an entry links it at the front. Reactivating the current entry is a
successful no-op. When the visible entry disappears, the surviving MRU head
is the deterministic successor.

An intrusive doubly linked order makes activation constant work and avoids
moving a growing array on each switch. The entry slots and selection indexes
remain separate structures with one validated graph invariant.

## One retained primary view preserves interaction context

Switching text without retaining its view would reset stored point, desired
column, and viewport on every activation. The buffer retains effective point,
mark, and region activation; the view retains only presentation-specific state
so later simultaneous views can remain independent.

Each live entry therefore owns one primary view. Inactive entries keep that
view and their independent history. Activation changes only the session's
visible target and MRU order. The application borrows the newly visible graph
for the next command or frame; it does not cache the startup pointers as the
editor target.

Search, query replacement, and command preparation belong to the outgoing
view. They must reach an accepted, canceled, or rejected terminal state before
activation. Rejecting a switch is safer than allowing transient state to act
on a different buffer.

## UI roots are interaction state, not text state

A startup surface and a Buffer Menu need selection, rows, geometry, and local
keys, but neither one is canonical editable text. Creating synthetic buffers
for them would attach history, document, and primary-view resources to data
whose purpose is navigation.

The visible target therefore selects one of two ownership paths:

```text
Editor session visible target
|-- primary view ------> checked entry graph ------> editable text
`-- UI root -----------> UI registry --------------> bounded views and marks
```

The session stores only copied UI owner, model, and generation identity. The UI
registry owns the published root, copied view projections, focus, and geometry;
semantic workflows retain selection or marks when those values are not
view-local. Display receives an immutable checked snapshot, and the terminal
receives only that snapshot.

Pathless startup can consequently hold zero live buffer graphs. Create and Open
leave the startup root through the same session commands used during ordinary
editing. Once editing begins, application policy keeps editing state distinct:
killing the final ordinary buffer admits an unassociated `*scratch*` graph
instead of returning to Startup.

The Buffer Menu follows the same separation. It copies active-then-MRU
descriptors with complete labels instead of borrowing registry collections.
Refresh replaces the complete bounded row set and preserves selection or marks
only for exact entry handles that still exist. Generation checks prevent a
delayed key from acting on a row that now names a different live entry.

## Complete paths make file selection unambiguous

Short display names are convenient until two live files share a basename.
Using the complete normalized path as the file-backed selection label makes
exact switching deterministic without inventing suffixes or consulting a
second disambiguation table.

The normalized-path index also gives `find-file` one canonical reuse decision.
Relative and absolute spellings that normalize to the same target activate
the existing entry without rereading the file. Unassociated buffers use their
explicit unique names because no filesystem identity exists for them.

## Detachment and destruction are separate boundaries

Once cleanup starts, no new observer may acquire the graph. Removing one
index at a time while the graph is still discoverable would create aliases to
partially closed state.

Detachment therefore removes label lookup, path lookup, MRU membership,
visibility, and the live slot together. Allocation for copied post-close
metadata finishes before that mutation. The detached graph is unreachable but
still owned.

Cleanup then follows reverse dependency order:

1. Close the primary view and its buffer anchors.
2. Close document operations and target state.
3. Close history and retained records.
4. Close canonical buffer storage.
5. Release copied labels, paths, and detached-owner storage.

A busy subsystem can stop this sequence while the detached owner remains
available for retry. The session never makes a partly released graph live
again.

## Dirty authority belongs before detachment

Modified text cannot be discovered only after lookup and visibility have been
removed. The session therefore assesses one exact entry generation while the
complete graph is still live. It checks transient view and history ownership,
derives modified state from canonical and saved revisions, and returns a
copied label with the required decision.

No prompt owns native lifecycle state. Racket names `kill-buffer` and binds
`C-x k`; the Odin command and application layers resolve that intent, present
the bounded interaction, and submit explicit preserve or discard authority to
the session. Canonical buffers, saved revisions, handles, MRU order, and graph
destruction remain Odin-owned.

Process exit applies the same assessment to a copied MRU sequence. Decisions
finish before graph detachment begins, so cancellation cannot leave a partly
destroyed session. Filesystem saves are intentionally different: each
successful save is externally visible immediately and remains true even when
a later buffer cancels exit.

## Marked operations separate truthful effects from atomic detachment

Marked saves and marked kills cannot share one rollback rule. A successful
filesystem save is an external fact; pretending to undo it after a later save
failure would make the editor's report false. Buffer detachment, by contrast,
can remain all-or-nothing until every dirty decision is known.

```text
checked inventory model generation and marked entry set
                         |
                         v
               revalidate every handle
                         |
            +------------+------------+
            |                         |
            v                         v
      save marks in order       assess all kill marks
            |                         |
   report completed/pending      collect Save/Discard/Cancel
                                      |
                           complete required saves
                                      |
                           reserve all detach records
                                      |
                           no-fail set detachment
```

Cancellation or a required-save failure therefore kills no buffer. Earlier
successful saves remain published and are removed from the pending marked set.
Once every kill decision is admitted, allocation cannot interrupt the registry
mutation halfway through the set.

## Detached bytes remain charged

Removing an entry from the live count does not free its rope, history, labels,
or paths. If the session immediately forgot those bytes, another admission
could exceed the intended aggregate budget while cleanup was still pending.

The accounting model therefore separates live counts from retained charges.
Preparation charges bytes before publication. Detachment reduces live counts
but retains byte charges. Final detached release subtracts them.

Creation and open reserve the complete graph before publication. Ordinary
commands reconcile text and history sizes for the exact active entry after
each completed turn. A future transaction that intentionally changes several
buffers must reserve their aggregate growth before canonical publication.

## Checked native access is transitional infrastructure

Existing native command APIs accept responsibility-owned buffer, history,
document, and view objects. Rewriting all of those packages into the session
would destroy their boundaries.

`Entry_Access` instead acts as a generation-checked native capability. Each
borrow revalidates the live entry and lends its objects only for the immediate
native operation. The application retains no registry collection or slot
address.

This access is not the programmable boundary. Racket receives copied bounded
descriptors and checked requests through a separate command facade; it never
receives native object pointers or cleanup ownership.

## Programmability mirrors authority without moving ownership

A programmable layer needs enough information to rank buffers, choose an
action, and compose several operations. Giving it registry storage would also
give it accidental authority over identity, aggregate admission, and cleanup.
Giving it only command names would prevent useful inspection and composition.

The buffer-session facade therefore copies the session scope, descriptors,
usage, and outcomes while preserving checked native handles. Racket can choose
which operation to request, but Odin reconstructs current authority and
generations before every inspection or publication.

```text
Odin-owned session registry
          |
          v
copied scope + bounded descriptors
          |
          v
Racket composition during one dynamic extent
          |
          v
checked request + copied expected generations
          |
          v
native revalidation and responsibility-owned publication
```

The dynamic extent prevents a Racket session object from becoming a second
lifecycle owner. Thread transfer, continuation escape, reentrancy, malformed
records, quota excess, cancellation, and stale scopes are rejected before a
later turn begins. Successful mutations return a refreshed copied scope; no
Racket finalizer controls native lifetime.

Batch enumeration is equally important. Crossing once per buffer would make
programmable ranking depend on foreign-call count and would expose a registry
that changes between individual reads. One bounded copied batch instead gives
Racket a coherent snapshot while native generation checks still protect the
action selected from it.

## Ownership arrived before visible multiplicity

The first session slice changed ownership while preserving one visible startup
entry. The next slice added complete graph admission, exact selection, and
per-turn active-entry routing. This staging kept the existing editor packages
authoritative while making multiplicity visible only after the registry could
preserve identity, state, and cleanup invariants.

Checked dirty kill, protected multi-buffer exit, pathless startup, the
post-startup scratch invariant, the marked Buffer Menu, and programmable
enumeration now build on the same measured registry without inventing another
partial notion of a live buffer.

The exact declarations, limits, failure codes, and validation commands are in
the [Editor Session Reference](../../reference/editor-session/index.md).

The copied Racket surface is in the
[Programmable Buffer Session Reference](../../reference/programmable-buffer-sessions/index.md).
