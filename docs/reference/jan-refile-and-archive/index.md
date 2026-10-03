<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Refile and Archive Reference

Jan refile and archive workflows move or copy complete heading subtrees through
exact Jan analysis scopes. They retain canonical document bytes as the only
editable source and expose every multi-resource outcome that may require
recovery.

## Candidate selection

One refile candidate identifies a provider-owned resource, exact planning
scope, exact heading target, structural level, Project and Workspace identity,
path, recent-use rank, and configured-predicate result.

Candidate filtering can compose:

- minimum and maximum destination level;
- one exact file resource;
- one Project or Workspace identity;
- a path prefix;
- a bounded recent-use rank; and
- a configured predicate that has already been admitted by its owner.

Filtering preserves candidate order. Malformed candidates reject the complete
selection, and an undersized output rejects with exact limit accounting instead
of truncating silently. One selection admits at most 16,384 candidates.

## Same-document refile and copy

A request carries distinct exact source and destination headings, their common
analysis scope, one resource identity, the destination level, and a nonzero
rewrite generation. The source and destination ranges must not overlap.

The planner copies the complete source subtree, adjusts every heading level
relative to the selected destination, and appends it beneath that destination.
A move also deletes the exact source subtree; a copy preserves it. Both changes
are one `language.Jan_Rewrite_Plan`, so validation or publication failure leaves
the document unchanged.

## Cross-document publication

Cross-document requests bind different provider-owned resources and different
exact analysis scopes. Plan preparation validates both source snapshots before
retaining either mutation. An open-buffer operation locks both buffers,
revalidates both revisions, applies the destination and optional source batches
privately, and validates one `transaction.Multibuffer_Transaction` before its
caller may commit.

For a copy, the source still participates in the checked transaction even
though it receives no edit. For a move, destination insertion and source
removal publish as one commit. A stale source or destination rejects the whole
operation.

Closed-resource publication uses an explicit durable state record:

| State | Meaning |
| --- | --- |
| `Prepared` | No resource change is recorded. |
| `Destination_Committed` | The destination contains the subtree; the source still does too. |
| `Recovery_Required` | Source removal or cancellation failed after destination publication. |
| `Completed` | Copy publication finished, or move publication and source removal both finished. |
| `Failed` | Destination publication failed; the source remains authoritative. |
| `Cancelled` | Cancellation occurred before any publication. |
| `Rolled_Back` | Recovery removed the destination copy and retained the source. |

The record includes schema, operation, mode, both resource identities and
revisions, payload byte count, payload fingerprint, and the two committed-state
flags. Recovery must explicitly finish source removal or roll back the
destination. A destination-first interruption may temporarily duplicate a
subtree, but it cannot hide that duplicate or silently lose the source.

## Internal archive

Internal archive adds the compatible `ARCHIVE` tag to the exact heading line.
Restore removes that tag. The whole subtree remains in its original document,
and the checked rewrite changes no unrelated source bytes.

Archived-content projection is explicit: ordinary searches and agendas omit
archived content, while an include-archived request admits it. This helper is a
domain contract; agenda integration remains owned by the agenda slices.

## External archive and restore

External archive is a cross-document move whose destination payload contains
an ordinary property drawer immediately below the archived heading:

```org
:PROPERTIES:
:JAN_ARCHIVE_SOURCE_PROVIDER: 7
:JAN_ARCHIVE_SOURCE: notes/projects.jan
:JAN_ARCHIVE_NODE: 42
:JAN_ARCHIVE_PARENT: 7
:JAN_ARCHIVE_REVISION: 11
:JAN_ARCHIVE_POSITION: 3
:END:
```

These properties preserve the resource, node, parent, revision, and sibling
position required to visit the origin or propose restoration. Restore accepts
only the exact expected metadata, removes it from the payload, and uses the same
checked cross-document move protocol. The destination still requires a current
explicit structural target; origin metadata never authorizes a stale mutation.

Archive files, tags, and origin properties remain normal inspectable Jan/Org
source. They are not hidden database state.

## Failure and cancellation

- Cancellation before publication changes no source.
- Same-document failures abandon one rewrite plan.
- Open-buffer cross-document failures abandon one private transaction.
- External publication after destination commit reports one committed resource
  and enters recovery-required state.
- Stale scopes, malformed resources, overlapping targets, invalid levels,
  allocation failure, and fixed-limit overflow reject without publication.
- Plan close releases both source and destination rewrite storage exactly once.

## Current delivery boundary

`src/jan_planning` supplies candidate, rewrite, transaction-admission,
publication-recovery, internal-archive, external-archive, restore, visit, and
visibility contracts. Public `jan-refile`, `jan-copy-subtree`,
`jan-archive-subtree`, and `jan-toggle-archive` command registration remains in
the Planning closure slice. Linked application and terminal acceptance remain
in the final Jan delivery closure slice.
