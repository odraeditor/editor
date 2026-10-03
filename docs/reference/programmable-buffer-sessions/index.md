<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Programmable Buffer Session Reference

The programmable buffer-session boundary lets Racket inspect and compose one
live editor session through copied values and checked lifecycle requests. Odin
remains the only owner of session indexes, canonical buffers, histories,
documents, primary views, UI workflows, and publication.

## Responsibility map

| Package | Responsibility |
| --- | --- |
| `editor_session` | Own the live registry, complete entry graphs, MRU order, aggregate accounting, visible target, detachment, and cleanup. |
| `command` | Construct immutable authority, validate every supplied generation, decode requests, and delegate admitted operations to their native owners. |
| `bridge` | Define pointer-free record layouts, operation identifiers, and aggregate byte limits. |
| `hosting` and `adapter.c` | Bind the buffer facade to the shared scoped transport, reject identity, thread, extent, and reentrancy violations, contain exceptions, and clear callback storage before return. |
| `command/buffers.rkt` | Present contracted Racket values and compose semantic buffer operations during one dynamic extent. |
| `ui` | Own copied list roots, surfaces, item projections, styles, focus, generations, and bounds. |
| `odra` | Own Buffer Menu selection, semantic marks, return behavior, prompts, terminal presentation, and process exit. |

## Dynamic extent

`call-with-buffer-session` accepts an active transport generation, a positive
opaque token supplied by the native host, and one callback. It constructs a
`buffer-session` value that is valid only while that callback is running on
its owning Racket thread.

The session retains a copied scope and an opaque control object. It does not
retain a native pointer. Use after return, continuation escape, or transfer to
another Racket thread raises an exception before a native operation is
accepted. Forced Racket collection does not change the lifetime of the native
session.

## Copied value shapes

| Value | Copied contents |
| --- | --- |
| `buffer-scope` | Editor-session identity, immutable access set, session and registry generations, and the exact visible entry, primary view, or UI-root owner, model, and generation. |
| `buffer-handle` | Session identity and generation, registry generation, entry identity, slot, and slot generation. |
| `buffer-descriptor` | Complete handle, buffer and history identities, primary-view identity, optional document identity, copied label, association, persistence, operation, active and modified flags, and activation sequence. |
| `buffer-usage` | Exact live counts plus canonical text, label, view, history, registry, capability, prepared-operation, and detached-cleanup accounting. |
| `buffer-outcome` | Refreshed scope, operation completion, affected identities, save publication, close state, marked-operation counts, decision or failed entry, and remaining live counts. |
| `buffer-mark` | Exact entry handle plus the semantic `save` or `kill` operation. |
| `buffer-mark-decision` | Checked entry handle, `save`, `discard`, or `cancel`, and an optional copied first-save path. |
| `buffer-session-failure` | Copied native failure code and optional `limit` and `actual` values. |

`buffers.rkt` exports predicates and semantic accessors for copied scope,
handle, descriptor, usage, outcome, mark, decision, and failure values.
Descriptor labels are immutable byte strings. No accessor exposes the
raw transport record, registry storage, or canonical text.

## Racket procedures

| Procedure | Contract |
| --- | --- |
| `buffer-session-scope` | Return the current copied authority and visible-target scope. |
| `buffer-session-usage` | Return exact aggregate accounting or a checked failure. |
| `buffer-session-descriptors` | Return one bounded active-then-MRU descriptor list. Optional `#:count` and `#:label-bytes` arguments may narrow the copy budget. |
| `buffer-session-descriptor` | Inspect one exact checked handle and copy its complete descriptor. |
| `buffer-session-create!` | Create and activate one named unassociated buffer. |
| `buffer-session-open!` | Open one admitted local path or activate its existing normalized-path owner. |
| `buffer-session-activate!` | Activate one exact live entry generation. |
| `buffer-session-save!` | Save an associated entry or perform first save with `#:path`. |
| `buffer-session-kill!` | Close one exact entry; `#:discard? #t` supplies explicit modified-text discard authority. |
| `buffer-session-execute-marks!` | Execute one nonempty bounded list of copied `buffer-mark` values with copied dirty-entry decisions. |

Create, open, activate, save, kill, and marked execution replace the session's
local copied scope only after Odin returns a successful outcome. A later call
therefore presents the refreshed visible-target generation. Reusing an older
scope is rejected as stale.

## Native capability authority

`Buffer_Session_Access` grants usage inspection, descriptor inspection,
creation, open, activation, save, kill, and marked execution independently.
Every operation reconstructs the current native scope and then compares the
editor identity, access set, session handle, registry generation, and visible
target with the copied request.

Entry operations additionally validate the complete `Entry_Handle`. Marked
execution validates every copied semantic mark, rejects duplicate or stale
entry handles, and then delegates to the existing truthful-save and
all-or-nothing kill workflow. It does not borrow list or renderer state.

## Record layout and limits

All native-boundary scalars use fixed pointer-free records.

| Record | Width |
| --- | ---: |
| Scope | 144 bytes |
| Usage | 248 bytes |
| Descriptor header | 160 bytes |
| Descriptor | 168 bytes |
| Request header | 272 bytes |
| Semantic mark | 56 bytes |
| Marked decision | 72 bytes |
| Outcome | 328 bytes |

| Copied resource | Default boundary limit |
| --- | ---: |
| Descriptors per response | 256 |
| Aggregate descriptor labels or marked paths | 4 MiB |
| One name or local path request | 4,096 bytes |
| Semantic marks per request | 128 |
| Marked decisions per request | 128 |
| Concurrent hosted buffer-session turns | 1 |

The editor-session policy may reject an operation below these transport
ceilings. Batch-size helpers validate aggregate widths before native or Racket
allocation. Inventory and marked execution cross in bounded batches rather
than one call per buffer, text byte, or display cell.

## Failure behavior

Native capability rejection distinguishes invalid context, missing permission,
changed authority, wrong editor or session, stale registry or visible target,
wrong entry, invalid semantic mark sets, missing descriptors, and
temporary-memory limits.
The underlying editor-session, document, view, history, and interaction failure
contexts remain authoritative for their operations.

Malformed records, oversized requests, wrong-thread use, reentrancy, escaped
capabilities, Racket exceptions, cancellation, and invalid result envelopes are
contained before another turn begins. A native failure is returned as
`buffer-session-failure`; a local contract or lifetime violation raises a
Racket exception that the hosting layer converts to a structured host failure.

Every failure before publication preserves canonical state. A successfully
completed save remains an external fact even if a later independently admitted
operation fails.

## Validation

```sh
raco test src/hosting/buffer-session-bridge.rkt src/command/buffers.rkt
make native-command-test
make buffer-session-command-benchmark
make buffer-session-acceptance
make verify
```

See [Editor Session Reference](../editor-session/index.md) for registry and
lifecycle contracts and [Racket Runtime Boundary Reference](../racket-runtime-boundary/index.md)
for hosting-wide rules.
