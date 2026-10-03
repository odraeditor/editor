<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Candidate Session Reference

The candidate-session kernel in `src/interaction` admits one complete copied
source, filters and ranks it through a bounded query, preserves selection by
stable identity, and releases every retained resource on close. It is
source-neutral: command, buffer, document, and Project adapters remain outside
the kernel.

The terminal integrates command, complete-session buffer, active-Project
buffer, and active-Project file sources through one shared candidate UI root.
File-backed buffers use durable document identity; Project files use their
canonical normalized paths.

When navigation starts from an editor view, the shared root composes a bounded
panel below the displaced pane status. The query occupies the first panel row
and candidates grow downward while every pane retains at least one content row
and its status row. Command rows reserve aligned name, optional binding, and
description columns. Provider and availability annotations remain part of the
checked source contract but are not rendered in command rows.

## Identity and source contract

`Candidate_Identity` is an opaque source-owned tuple of `kind`, `primary`, and
`secondary`. `kind` and at least one numeric component must be nonzero. An
identity is stable only within its source scope and is never reconstructed
from a label.

One `Candidate_Source_Definition` supplies:

- a closed source kind;
- scope identity and generation;
- a strictly increasing source generation; and
- the complete descriptor set for that generation.

Every descriptor has a unique identity, nonempty UTF-8 label, checked action,
availability, optional searchable fields, optional presentation annotations,
and process-local recency. Actions contain copied owner identities and
generations, not procedures or borrowed owner pointers.

Source admission copies labels, searchable fields, and annotation text. The
caller may release or reuse its definition storage after initialization or
refresh returns.

## Query and matching

A query is valid UTF-8 split on Unicode whitespace. Empty components are
discarded. Every remaining component must match, but component order does not
constrain where text appears in a descriptor.

Matching is case-insensitive. The canonical label is always searchable;
source-declared searchable fields participate without changing the displayed
label. Each component has two interpretations:

1. literal substring matching; and
2. an expression admitted by the existing bounded regular-expression policy.

An invalid or inadmissible expression remains an ordinary literal component.
A literal match wins before expression matching is attempted.

The resulting match classes, from strongest to weakest, are:

1. the complete canonical label equals the complete query;
2. every component begins at a label prefix or documented boundary;
3. another label or searchable-field literal match;
4. an expression-only match; and
5. an empty-query match.

Documented label boundaries are the start of the label, Unicode whitespace,
and `-`, `_`, `/`, `.`, or `:`.

## Ranking and selection

Rows are sorted deterministically by:

1. match class for a nonempty query;
2. descending successful-use recency;
3. case-folded canonical label; and
4. stable identity.

Source enumeration order is not a tie-breaker. A successful action may be
recorded only through `candidate_session_record_success`; failed or cancelled
actions do not change recency. Recency is renormalized before unsigned
overflow while preserving the prior total order.

For a registered active Project, the source adapter seeds this recency field
from the Project candidate-usage record before the session copies and ranks the
source. Command names, canonical file-backed document paths, and canonical
Project-file paths are separate durable identity categories. The common
session still treats the resulting number as advisory ordering input; it does
not own persistence or make a durable key actionable.

The selected row is stored as a stable identity across query replacement and
complete source refresh. If that identity is absent from the new projection,
the first ranked row is selected. An empty projection has no selection.
Movement is clamped to the first and last row and rejects zero movement.

## Lifecycle and generations

The lifecycle operations are:

| Operation | Contract |
| --- | --- |
| `candidate_session_init` | Validate and copy one complete source and initial query before publishing generation 1. |
| `candidate_session_view` | Borrow one immutable normalized view until the next operation on the session. |
| `candidate_session_set_query` | Build a complete replacement projection and publish it atomically. |
| `candidate_session_move` | Move the selected row within the current projection. |
| `candidate_session_refresh` | Validate and copy one newer complete source generation, preserving selection by identity. |
| `candidate_session_record_success` | Prepare and atomically publish the new recency order after an action succeeds. |
| `candidate_session_cancel` | Mark the session cancelled without invoking or recording an action. |
| `candidate_session_close` | Release source copies, expressions, projections, rows, and query storage exactly once. |

Every mutating request carries the exact session identity and generation it
observed. A successful change advances the generation. A mismatched request
is stale and cannot affect the live state. A refresh also requires a newer
source generation for the same source kind and scope identity.

Initialization, query replacement, refresh, and recency publication prepare
new owned state before replacing the visible generation. Validation,
allocation, expression, or work failure leaves the prior published state
unchanged.

## Ownership and accounting

The session owns copied descriptor text, compiled admitted components,
filtered projections, normalized rows, and process-local recency. A
`Candidate_View` borrows that state only until the next session operation.
Rows borrow labels and annotations owned by the session.

`Candidate_Accounting` reports retained logical resources for the current
generation:

- candidate count;
- canonical-label bytes;
- searchable-field bytes;
- annotation bytes;
- durable-key bytes;
- query bytes and component count; and
- filtered projection count.

Temporary splitting, matching, sorting, and renormalization storage is bounded
per operation and retained for no longer than that operation.

## Project candidate-usage history

One local Project may have one editor-managed private record at
`$XDG_STATE_HOME/odra/projects/<project-id>/candidate-usage.rkt`. When
`XDG_STATE_HOME` is absent on Linux, the base is `$HOME/.local/state/odra/`.
macOS and Windows use the platform state root documented in the
[Configuration System Reference](../configuration-system/index.md). An
ordinary Dir and a session without an active Project use process-local recency
only and do not create this file. Records from one Project are never consulted
for another Project.

The constrained module has this canonical shape:

```racket
#lang racket/base

(provide candidate-usage)

(define candidate-usage
  '((format-version . 1)
    (project-id . "example-project")
    (generation . 4)
    (next-sequence . 18)
    (entries
      ((category . command)
       (key . "project-find-file")
       (sequence . 17)))))
```

Only the exact `provide` and quoted definition forms are admitted. The loader
does not evaluate arbitrary module forms. It validates the format, Project
identity, generation, next sequence, closed category set, canonical path keys,
command-name keys, unique category/key pairs, entry count, and complete module
size as one unit. A rejected or unsupported record contributes no partial
ordering.

Eligible successful actions update exactly one of these identities:

| Category | Durable key |
| --- | --- |
| `command` | Exact registered command name. |
| `document` | Canonical normalized path of a file-backed buffer. |
| `project-file` | Canonical normalized path selected from the active Project file source. |

Synthetic buffer creation, non-file-backed buffers, unavailable rows, stale
actions, failed actions, and cancellation do not produce a durable event. A
successful action is never reversed when later persistence fails.

Odin owns the indexed lookup, retention, logical sequence, one dirty
generation, and success decision. It flushes after 16 eligible successful
events, when the active Project changes, and during orderly editor shutdown.
One failed flush may be retried once. Each publication increments the persisted
generation exactly once; a stale expected generation is rejected.

Racket renders entries in descending sequence order with category and key
tie-breakers, writes an owner-only staging file, synchronizes it, reloads it
through the constrained parser, atomically replaces the target, and
synchronizes the containing directory. A failure before replacement preserves
the earlier record. A failure after replacement is recovered by validating the
visible target and is reported as recovered or durability-uncertain evidence.

The history policy is bounded as follows:

| Resource | Limit |
| --- | ---: |
| Entries per local Project | 1,024 |
| One stable key | 4,096 bytes |
| Complete module or copied hosting batch | 8 MiB |
| Logical sequence | 9,223,372,036,854,775,807 |
| Dirty generations | 1 |
| Successful events before action flush | 16 |
| Retry after a failed flush | 1 |
| Racket callbacks per load or publication | 8 |

When the entry bound is reached, the least-recent identity is replaced.
Sequence exhaustion renormalizes retained entries while preserving total
order. Missing, malformed, oversized, permission-unsafe, stale, unwritable,
or unavailable state disables durable publication for that loaded Project
generation but leaves candidate navigation and process-local ranking usable.
State directories use owner-only permissions and remain outside Project
catalog records and workspace content.

## Factory limits

| Resource | Factory limit |
| --- | ---: |
| Candidates in one complete source | 4,096 |
| Copied source text | 32 MiB |
| One canonical label | 4 KiB |
| Searchable fields per candidate | 4 |
| Annotations per candidate | 4 |
| Query text | 4 KiB |
| Query components | 8 |
| One expression-aware component | 4 KiB |
| Visible rows | 4,096 |
| Temporary operation storage | 16 MiB |
| Complete refreshes per input turn | 1 |
| Ordinary 256-candidate peak memory | 16 MiB |
| Demanding 4,096-candidate peak memory | 128 MiB |

The selected ordinary 256-candidate latency gate is 5 ms. The selected
demanding 4,096-candidate gate is 100 ms. Resource admission rejects overflow;
it never silently truncates a source, query, component set, or visible result.

## Failures

Failures distinguish invalid configuration, closed or stale sessions, invalid
or stale sources, invalid or duplicate identities, malformed UTF-8, each
resource limit, temporary and persistent allocation exhaustion, invalid
movement, absent selection, and cancellation.

Where applicable, `Candidate_Failure` reports the session and source
generations, candidate identity, admitted limit, and observed value. A failure
does not make a stale identity actionable and does not publish partial state.
Recoverable source, query, movement, refresh, history, and presentation
failures are copied into the bounded terminal diagnostic buffer. While a
candidate root remains visible, its `Input` surface projects that diagnostic
with the rejected style for the failed turn instead of allowing an internal
failure to terminate the editor. The next input clears the transient message
and continues from the retained candidate generation.

## Extension boundary

A source adapter may enumerate owner state and map it into complete candidate
definitions. It retains ownership of source enumeration, availability checks,
and eventual action invocation. The kernel owns only copied discovery state
and opaque action data.

The factory command adapter maps a copied
interactive command catalog to canonical command-name labels; binding,
provider, availability, and description annotations; stable checked command
identities; and `Invoke_Command` actions. The terminal projects its
`Candidate_View` through the shared candidate root, while the command registry
and keymap snapshot remain the invocation authorities.

The buffer adapter maps complete `session_descriptors` snapshots to canonical
labels, document-path, modified-state, and backing annotations, checked object
graph actions, and optional durable document keys. General navigation may add
one synthetic creation candidate for a valid unmatched query. Project buffer
navigation joins the same complete session snapshot to one checked Project
classification and admits only `Project_Owned` rows; it never creates buffers.

The Project-file adapter maps one complete bounded enumeration generation to
relative canonical labels, canonical-path searchable fields, optional member
directory annotations for equal relative labels, `Open_Document` actions, and
durable `Project_File` keys. Its runtime action retains the exact Project and
file-enumeration generations. Refresh reconciles the Project, enumerates and
adapts a complete replacement privately, then calls `candidate_session_refresh`.
Overflow, stale scope, filesystem failure, and allocation failure preserve the
prior source and UI root.

Presentation consumes `Candidate_View`; it does not rerank rows or infer
identity from text. Invocation resolves the selected action against the
current canonical owner generation before execution. Filesystem access,
Racket calls, terminal decoding, and durable Project history load or
publication are outside a candidate-session input turn. The factory owns
source construction, ranking, navigation, and presentation. Public replacement
hooks remain outside the delivered boundary; extensions contribute named
commands through bounded registration rather than installing a parallel
matcher or dispatcher.

The shared root projects the session-owned selection into a `ListView`, the
session-owned query generation into an `Input`, and source, scope, and counts
into one root-edge `StatusRegion`. The input surface captures focus and records
the checked primary-view return target. Presentation generations, viewports,
and copied row annotations are UI state; query mutation, matching, selection,
history, availability, and actions remain candidate or source-owner state.

The earlier component presentation registry, candidate adapters, snapshots,
visible target, and full-frame renderer were removed after all four sources
migrated. Contextual precedence and command routes retain their existing
`Component_Tool` and `component-*` names only as keymap vocabulary.

See [Why Candidate Navigation Uses a Source-Neutral Session](../../explanation/candidate-session-ownership/index.md)
for the ownership rationale.

Run the complete validation procedure in
[Validate Candidate Navigation](../../how-to/validate-candidate-navigation/).
