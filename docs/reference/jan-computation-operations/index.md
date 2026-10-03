<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Computation Operations Reference

Jan computation exposes one public command family over checked Computable
Documents contracts. Commands identify requested work; they do not bypass the
transaction, process, resource, policy, or adapter owners that perform effects.

## Public commands

| Area | Commands |
| --- | --- |
| Tables | `jan-table-recalculate`, `jan-table-recalculate-all`, `jan-table-debug-formula`, `jan-table-plot` |
| Execution | `jan-execute`, `jan-execute-subtree`, `jan-execute-buffer`, `jan-call`, `jan-execute-batch` |
| Results | `jan-result-remove`, `jan-result-inspect` |
| Source | `jan-edit-source`, `jan-return-from-source`, `jan-tangle`, `jan-tangle-file`, `jan-noweb-inspect`, `jan-library-load` |
| Sessions | `jan-session-list`, `jan-session-inspect`, `jan-session-close` |
| Cache | `jan-cache-inspect`, `jan-cache-evict`, `jan-cache-clear` |
| Inspection | `jan-computation-status` |

Commands that can replace document-owned results or source declare buffer,
view, lifecycle, and text-mutation effects. Inspection and external-resource
lifecycle commands declare view and lifecycle effects. Global batch execution
has no active-document requirement but still declares possible document
mutation. Every route is native, stable, and distinct from the earlier Jan
language, structured-editing, and planning catalogs.

## Batch admission and execution order

An admitted batch has a nonzero identity, an `atomic` or `best-effort` mode,
and concurrency between one and the child-process ceiling. Each target must
carry:

- an exact document and source position;
- a valid semantic target tied to that position;
- an explicit invocation with an `allow` authority decision;
- policy and adapter generations equal to the computation scope; and
- one selected adapter or a complete cache hit.

Targets are copied and sorted by document, source position, and operation
identity. Duplicate operations reject the entire plan. Opening, parsing,
rendering, indexing, saving, or exporting a document never creates an admitted
batch.

Every outcome must identify the corresponding ordered target and stay within
per-target and aggregate output limits. Completed and cache-hit targets count
as successful. Rejected, unattempted, and cancelled targets remain separately
attributed. An atomic batch publishes zero targets when any target is not
successful; best-effort mode publishes only successful targets.

## Capability availability

| Capability | Required operational owners |
| --- | --- |
| Formulas, text plots, results, cache, source editing, noweb | confirmed Jan language analysis |
| Graphical plots | Jan language analysis and graphical adapter |
| Execution, sessions, batch | Jan language analysis, execution adapter, and process owner |
| Tangling | Jan language analysis and resource owner |

Unavailable optional owners leave their dependent capability unavailable and
do not narrow unrelated capabilities. Available factory-adapter capabilities
report the exact adapter generation used by requests.

## Bridge records

Native contract schema version 25 adds the `jan-computation` concern. Fixed,
pointer-free records cover computation scope, commands, batch targets, batch
headers, target outcomes, capability availability, and failures. Schema entries
also publish the stable executable-target, output, retained-output, and cache
limits plus the formula-to-inspection operation and formula-to-batch capability
ranges.

The bridge validates record widths, enum ranges, nonzero identities, exact
generations, complete batch accounting, atomic publication semantics, and
adapter-generation attribution before a value crosses the Racket boundary.

## Failures and no-effect guarantees

Malformed, stale, unauthorized, conflicting, over-limit, cancelled, incomplete,
or unavailable work returns an attributable failure. Failure does not execute
another language adapter, publish partial atomic results, overwrite source,
write a tangle target, retain partial output, or activate a session. Cache
maintenance cannot delete document-owned results.

## Focused validation

Use:

```sh
make jan-computation-focused-test
```

The target checks independent Racket models, configuration, resource profiles,
byte-identical `.org` and `.jan` fixtures, and strict `src/jan_computation`
tests. Bridge and command packages are checked separately. The focused path
does not build or run the complete editor.
