<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Reversible History Is Separate from Transactions

A transaction answers one question: can this complete proposed edit become
visible atomically? History answers a different question: which committed
states remain reachable, and how can the editor return to them safely?

Keeping these responsibilities separate prevents transaction lifecycle code
from becoming a general tree, retention, and navigation subsystem. It also
prevents history from gaining an independent way to mutate canonical text.

## The reservation closes a dangerous gap

A post-commit observer is too late to create the required undo record. If its
allocation failed, the editor would already contain text that could not be
reversed.

Odra reserves history during transaction validation:

```text
private edit
    |
    v
normalized forward and inverse payload
    |
    v
complete history reservation ----failure----> abort private edit
    |
    v
transaction Ready
    |
    v
publish rope root
    |
    v
attach already allocated history node
    |
    v
deliver observers
```

After publication begins, attaching the reserved node does not allocate or
call an extension. Canonical text and its immediate record therefore become
visible as one invariant even though the transaction and history packages own
different state.

## Why undo and redo are new transactions

A history node represents text, not permission to replace the editor's current
revision number with an old one. Reusing historical revisions would make
positions, anchors, views, proposals, and external observations appear current
when they are stale.

Undo instead computes the inverse transition retained by the active node and
submits it through the existing transaction path. Redo submits the chosen
child's forward transition. Both validate current buffer identity and revision,
prepare a private rope, and publish one fresh monotonically increasing
revision.

The history move is reserved before this navigation transaction begins and is
finalized only after the exact text transition publishes. Failure leaves both
the active node and canonical text unchanged.

## Why alternate futures remain

Linear undo stacks usually discard redo entries when the user edits after an
undo. That makes a previously valid state disappear because of a later choice.

Odra stores parent and child relations instead. Editing from an earlier node
adds a sibling and marks it preferred for ordinary redo. The old sibling stays
retained until bounded policy removes it. This creates enough structure for a
branch chooser without making a visual history browser part of the engine
contract.

The preferred child records ordinary intent rather than storage order. Undoing
from a child makes that child preferred. A new edit from the same parent makes
the new child preferred.

## Why branch inspection is a copied neighborhood

Extensions need enough information to present choices, but exposing native
nodes would let storage lifetimes escape the Odin owner. Inspection therefore
copies the active node, its nearby relations, and a bounded prefix of immediate
children. Opaque identities can be returned in a later request; pointers and
payload storage cannot.

Result and traversal ceilings are separate declarations of cost. A caller may
ask for fewer displayed children than the policy permits, and the engine still
has an explicit bound on the work used to find them. A truncated result is
truthful data, not an implicit request to continue walking the tree.

Selecting a distant retained node computes one complete path through the
lowest common ancestor. The engine first prepares every inverse and forward
edit, then publishes the path as one fresh transaction. Preferred edges are
updated only after publication, so a failed branch recovery leaves the old
text and navigation intent intact.

## Why selective undo creates compensation

Moving the active pointer to an old node would discard all later work.
Selective undo has a different meaning: preserve later independent edits while
reversing one admitted earlier unit. The engine transforms the target inverse
through later changes and rejects any overlap it cannot prove safe.

When the proof succeeds, the inverse is not treated as special hidden state.
It becomes one ordinary `selective-undo` transaction and one ordinary history
child. This keeps a simple invariant: every visible text change has an
immediate reversible record, including a selective reversal itself.

Stable anchors narrow the requested region without transferring anchor
ownership into history. The command layer resolves them against the current
editor revision, then supplies plain checked coordinates. This preserves the
editor's ownership of live positions and the history engine's ownership of
dependency analysis.

## Why history retains changes, not canonical ownership

The persistent rope already shares immutable storage efficiently, but making
history own canonical roots would blur the editor boundary. The first history
engine instead owns normalized forward and inverse edit payloads. Navigation
uses those payloads to prepare another transaction.

This has three useful properties:

1. The editor remains the only owner of the current root.
2. Selective undo can later analyze explicit changes rather than infer them
   from complete snapshots.
3. A future durable format can describe semantic transitions without exposing
   rope node layout as a storage contract.

Root sharing remains a possible measured optimization. It is not required for
correctness and does not change ownership authority.

## Why a multibuffer unit has one explicit link

Several edits occurring near each other in time do not prove shared intent.
Odra links history only when one explicit multibuffer transaction declares the
complete participant set and one undo identity. This keeps independent edits
independent even when they are published in adjacent command turns.

The link does not replace per-buffer history. Each buffer still owns its node,
record, payload, revision agreement, and branch position. One immutable shared
relation identifies the corresponding nodes and their deterministic order.
The first ordered store owns the link allocation, while coordinated teardown
releases it only after every participant node is detached.

This split avoids two bad ownership choices: copying the full participant set
into every node would grow quadratically, while letting a transaction retain
the link would outlive the transaction allocator contract. A single history-
owned link keeps storage linear and preserves one authority for topology.

## Why linked navigation prepares every buffer first

Moving one history pointer before another buffer is ready would create a state
that never existed canonically. Linked undo, redo, branch selection, and
selective undo therefore validate the complete live store set, active nodes,
revisions, generations, payloads, and resource bounds before any editor root
is installed.

The prepared edits then use the same no-fail multibuffer publication boundary
as ordinary workspace edits. Only after every editor root is canonical does
history move every active node. A missing participant, divergent active node,
dependency conflict, cancellation, or allocation failure leaves all buffers
and all histories unchanged.

Selective undo follows the same rule but creates a new linked compensation.
Each buffer proves its target inverse against later work independently; all
proofs must succeed before the compensating multibuffer transaction can enter
`Ready`. The compensation is therefore atomic and itself reversible.

Pruning uses the same completeness principle. Independent pruning skips linked
nodes. Coordinated pruning removes a relation only when every participant is
an eligible inactive leaf outside its protected recent window.

## Why no-op publication still matters

A transaction with no normalized text change creates no undo node. The editor
can still publish a fresh revision for its working root. History therefore
reserves a revision-only update so its current revision remains synchronized
without inventing a user-visible edit.

This distinction also supports the rule that cursor, scrolling, focus, and
presentation changes do not create history nodes.

## Why pruning is conservative first

Deleting part of an undo unit or losing its inverse text would convert a real
transition into a false empty change. Pruning therefore operates on complete
nodes and their complete records.

The first slice removes bounded old inactive leaves. It never removes the
root, active state, active ancestry, or protected recent window. If a new
record cannot fit, admission fails before text publication instead of pruning
speculatively and then reporting a failed edit with changed topology.

Later policy replacement can widen this strategy only by preparing and proving
the complete pruning result before a new policy generation becomes
authoritative.

## Why Racket remains outside canonical ownership

Racket configures policy and requests bounded history operations, but it does
not own nodes, links, payloads, or publication. It receives copied projections
and returns checked intent across the native boundary.

This keeps the Racket facade cohesive: it can describe intent and inspect
results without becoming a second history implementation or a second
multibuffer publication coordinator.

The exact declarations, defaults, failures, and measurements are in
[Reversible Editing History Reference](../../reference/reversible-editing-history/index.md).
