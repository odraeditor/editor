<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Incremental Analysis and Rewrite Reference

Jan maintains one retained Tree-sitter parser and one confirmed concrete tree
per `Jan_Structural_Owner`. Candidate work stays private until the complete
typed analysis, configuration-sensitive attributes, recovery records, semantic
indexes, resource accounting, and exact scope have all passed validation.

## Analysis Entry Points

| Procedure | Contract |
| --- | --- |
| `jan_structural_owner_publish_initial` | Publish the first complete analysis for an owner. A second initial publication rejects as stale. |
| `jan_structural_owner_analyze_incremental` | Apply one exact `transaction.Commit_Event` to a copy of the confirmed tree and publish only the validated result revision. |
| `jan_structural_owner_analyze_incremental_configured` | Use the same incremental path with one explicitly confirmed Jan configuration. |
| `jan_structural_owner_refresh` | Perform a full current-source parse for a strictly newer analysis generation, including grammar or configuration invalidation. |
| `jan_structural_owner_inspect` | Return copied last-confirmed scope, root, recovery summary, limits, usage, and latest rejection without parsing. |

The incremental path requires the event buffer and base revision to match the
confirmed scope. Its result revision must match the candidate scope, and the
analysis generation must advance. Document, language, provider, selection,
parser, grammar, configuration, and baseline identities remain exact for an
ordinary incremental update.

Each normalized splice is checked against both source versions. Removed bytes
must match the base, replacement bytes must match the result, ranges must be
ordered and non-overlapping, and the final byte count must reconstruct the
result. Tree-sitter edits are applied to `ts_tree_copy`; the confirmed tree is
untouched until the candidate projection succeeds.

## Atomic Confirmation

Initial, incremental, and refresh candidates publish one complete owner state:

1. retained concrete tree;
2. document and source revision;
3. language, provider, and selection generations;
4. parser and grammar generations;
5. baseline and configuration identity;
6. analysis generation;
7. copied root and recovery summary; and
8. resource usage and limits.

A cancelled, malformed, stale, invalid, over-limit, timed-out, provider, or
allocation failure deletes the candidate and records the rejection. Inspection
continues to return the previous confirmed scope with `Incomplete` status when
the caller presents a newer scope. That retained result is diagnostic only; its
scope mismatch prevents it from authorizing a rewrite.

## Rewrite Planning

`jan_rewrite_plan_prepare` accepts an exact current `Jan_Structural_Analysis`,
its canonical source bytes, a nonzero rewrite generation, and one or more
`Jan_Rewrite_Request` values. Each request either names a node whose range is
exactly equal to the request range or leaves the node identity empty for unique
exact-range resolution. Missing or ambiguous ownership rejects the plan.

The planner removes the common UTF-8-safe prefix and suffix between each owned
source range and its replacement. It then sorts the remaining edits and rejects
overlap or ambiguous equal starts. No-op replacements are rejected. Replacement
bytes are copied into one bounded plan-owned arena; `Jan_Rewrite_Edit` values
address that arena by offset and length.

`Jan_Rewrite_Plan_Descriptor` reports the exact analysis scope, rewrite
generation, splice count, copied replacement bytes, and metadata bytes. The
selected Jan rewrite-splice and aggregate-byte limits are checked before plan
publication.

## Transaction Adaptation

`jan_rewrite_plan_transaction_batch` exposes the checked plan as borrowed
ordinary `transaction.Base_Splice` values. This path supports normal
transaction validation, history attachment, atomic commit, undo, and redo.

`jan_rewrite_plan_admit` is the optimistic proposal adapter. It verifies that
the live buffer still has the plan buffer identity and source revision, then
uses `transaction.proposal_admit`. Transaction rejection returns a Jan stale or
invalid-rewrite failure before canonical publication.

The plan must remain alive through admission because transaction inputs borrow
its copied replacement text. `jan_rewrite_plan_close` releases the batch, arena,
and descriptors exactly once after the transaction has copied or consumed the
proposal.

## Focused Validation

Run:

```sh
make jan-document-language-focused-test
```

The focused language tests compare generated incremental edit sequences with
fresh full analyses, exercise malformed recovery and generation invalidation,
check cancellation, stale, time, allocation, splice, byte, and cleanup limits,
and publish representative heading, property, list, table, and inline rewrites
through ordinary reversible transactions.
