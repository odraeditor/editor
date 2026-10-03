<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Agenda Queries Reference

Jan agenda queries operate over one immutable, revision-bound index generation.
`src/jan_planning` copies admitted discovery results and query facts; it does
not scan filesystem roots, fetch providers, own canonical document text, or
edit source entries through cached rows.

## Source discovery and indexing

One source set preserves configured order across file, bounded directory,
Project, Workspace, and provider sources. Every discovery result identifies:

- the configured source and source kind;
- a provider-owned resource identity;
- confirmed, stale, unavailable, or failed state;
- document revision or durable provider version;
- Jan baseline identity;
- configuration and provider generations;
- admitted discovery depth and document limit; and
- copied entry candidates only when the source is confirmed.

Root admission is explicit. A directory result cannot use an unadmitted root,
exceed depth 64, or exceed its configured document limit. One index generation
accepts at most 1,024 source documents, 65,536 entries, 16 MiB of copied text,
and 64 MiB of derived state.

Stale, unavailable, and failed sources remain first-class source records with
zero indexed entries. They are never converted into a successful empty source.
Confirmed source rows retain source order, exact semantic targets where one
exists, and their source revision or durable version. Typed diary, calendar,
anniversary, reminder, and extension rows use the same result contract without
inventing document targets.

## Indexed entry facts

An indexed entry can expose:

- category, heading path, task state, completion, priority, and archive state;
- tags and exact properties;
- schedule, deadline, timestamp, time of day, and warning state;
- Project identity and stuck-project state;
- clock and effort totals;
- column and plain-text projections;
- block and custom-query identities; and
- provider kind and bounded annotation.

The index owns copies of every string, tag, and property until close. Callers
borrow records only for that lifetime. Canonical document bytes and provider
payloads remain with their existing owners.

## Query families

One exact index generation supports:

- daily and weekly time spans;
- unfinished tasks and exact task-state selection;
- tag, property, and postfix Boolean combined predicates;
- plain-text and compatible regular-expression search;
- Project and stuck-Project views;
- clock, effort, and column views;
- block and configured custom views; and
- diary, calendar, anniversary, reminder, and extension-provider views.

Combined predicates support task, tag, property, text, timestamp, Project,
stuck-project, clock, effort, and entry-kind operands with `not`, `and`, and
`or`. Malformed postfix expressions reject the query instead of producing a
misleading empty result. Saved or configured callers retain their query
dialect and configuration generation in the request.

Archived rows are excluded unless explicitly included. Additional exact tag,
property, and computed Boolean filters apply before sorting and result limits.

## Sorting and presentation

Sort precedence accepts up to eight unique keys chosen from category, time,
priority, deadline, schedule, task state, source order, heading path, clock,
and effort. The implementation uses stable merge ordering; equal rows fall
back to configured source order and original entry order.

Views can group by category, Project, source, day, or task state. Prefixes can
show category, task state, priority, time, or heading path. Time-grid flags are
set only for rows with a known time of day. Group and prefix buffers report
their own presentation truncation rather than retaining unbounded text.

The result descriptor distinguishes returned rows from total matched rows. A
result limit sets `truncated` while retaining the full match count. It reports
indexed and scanned sources plus stale, unavailable, and failed counts;
`complete` is false whenever source health or truncation prevents a complete
answer.

## Cache invalidation

Acceleration is valid only when index generation, configuration generation,
source-set identity, and nonzero query identity still match. Any generation
change invalidates the cache key. Cached rows are operational data and never a
replacement source of truth.

## Failure and cleanup

- Cancellation rejects before publishing an index or result.
- Duplicate source resources, malformed source bounds, stale confirmed
  generations, invalid targets, malformed predicates, and invalid regular
  expressions reject explicitly.
- Source, entry, copied-text, and derived-state limits report exact ceilings
  and observed values.
- Allocation failure releases partially built index or query state.
- Closing an index releases sources, entries, tags, properties, and copied
  text; closing a result releases its sorted row state.

## Integration boundary

This package supplies discovery-result admission, immutable indexes, native and
provider query semantics, filters, sorting, grouping, presentation metadata,
inspection counts, and cache invalidation. The
[Jan Planning and Agenda Operations Reference](../jan-planning-and-agenda-operations/index.md)
defines navigation, source reveal, checked remote edits, bulk operations,
commands, refresh, and export handoff. Linked editor and terminal acceptance
remains reserved for the final Jan product closure slice.
