<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Commands Publish Through Transactions

A text command often changes more than one byte range. It may insert paired
text, update a cursor, invoke another command, or apply a workspace-scale
proposal to several buffers. Publishing each step independently would expose
intermediate states that the user never intended.

Odra therefore separates private construction from canonical publication.

```text
command or proposal
        |
        v
private working revisions ----failure----> discard all private state
        |
        v
complete validation and reservation
        |
        v
brief no-fail publication
        |
        v
one shared committed event ----observer failure----> report separately
```

## One authority, several producers

Native commands, Racket commands, language tools, and future external tools
can describe different operations, but they do not receive different mutation
authority. Every producer reaches the same Odin coordinator. Origin metadata
supports diagnostics and auditing; it does not weaken revision checks,
resource limits, or atomicity.

This keeps Racket useful as a programmable control plane without creating a
second canonical buffer model. Racket can inspect its own private writes and
compose edits, while Odin owns lifecycle, validation, and commit.

## Why private revisions are necessary

A sequential command must sometimes inspect the result of an earlier private
edit. A working revision provides that view while ordinary buffer readers keep
seeing the confirmed revision. The transaction later reduces the private edit
sequence to a normalized base-relative changeset.

Batch edits use a different coordinate contract. Every position refers to the
same confirmed base, so multicursor and tool-produced changes do not shift as
the batch is assembled. Mixing base and working positions is rejected rather
than guessed.

## Why nested commands use savepoints

A nested command is part of its caller's logical action. Giving it independent
commit authority would make outer rollback impossible. A savepoint lets child
success join the root and child failure restore only the child's private work.
An unhandled failure still aborts the complete root.

## Why multibuffer publication is ordered

The coordinator sorts buffers by stable identity before editing. Validation
and publication therefore use one reproducible order regardless of proposal
input order. Every participant becomes ready before publication begins. The
editor then installs prepared revisions during one exclusive turn without
allocation, callbacks, or expected failure.

The result contains one transaction identity and one linked undo identity,
plus one normalized changeset per buffer. A filtered observer view keeps the
shared identity, so downstream consumers do not mistake one workspace edit for
unrelated per-buffer commits.

## Why stale proposals are not repaired automatically

A formatter or language tool computed its result from specific snapshots. A
position that can be relocated does not prove the old semantic result remains
correct. Odra therefore compares every declared revision and returns a
conflict when any participant changed.

Automatic retry would also be unsafe for arbitrary Racket commands because a
command may have produced external or user-visible effects before proposing
text. A producer may recompute explicitly, but transaction admission never
hides that decision.

## Why observer failure cannot roll back

Observers run after canonical publication. At that point the commit is real.
Treating an observer exception as transaction failure would make the reported
state disagree with the editor. Odra instead preserves the commit and reports
observer delivery separately.

The exact declarations, limits, failures, and measurements are in
[Atomic Edit Transaction Reference](../../reference/atomic-edit-transactions/index.md).

