<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Programmable Structural Commands Reference

The programmable structural boundary exposes Odin syntax navigation,
expanding selection, and indentation to Racket through copied records and one
synchronous scoped capability. Odin remains the only owner of buffers, views,
transactions, history, retained source snapshots, parsers, trees, nodes, and
Tree-sitter cursors.

## Command Registry

The canonical native command names are:

| Command | Effect set | Semantic result |
| --- | --- | --- |
| `structural-forward` | View | Move to the end of the next named node. |
| `structural-backward` | View | Move to the start of the previous named node. |
| `structural-up` | View | Move to the start of the enclosing named node. |
| `structural-down` | View | Move to the start of the first named child. |
| `structural-select` | View | Select or expand to one enclosing named node. |
| `structural-indent` | Buffer, View, Text Mutation | Publish one grammar-owned indentation transaction. |

All six names resolve through the ordinary command registry and delegate to
the semantic structural editor owner. The factory direct profile, `M-x`, and
Racket composition invoke these same identities; application coordination
supplies one exact active analysis scope for every route.

## Dynamic Extent and Authority

`call-with-structural-commands` receives the current hosted generation, an
opaque positive token, and one callback. The callback receives a
`structural-command-control` that is valid only for that synchronous turn on
the owning Racket thread.

The immutable access set grants inspection and each of the six operations
independently. Every call validates editor-session identity, authority,
capability generation, command-registry generation, view identity and state,
buffer revision, canonical selection generation, and the complete retained
analysis scope before semantic execution.

Use after return, continuation escape, cross-thread transfer, or reentrant
entry is rejected before semantic execution. Forced Racket collection does
not change the capability lifetime. The adapter clears callback and
caller-owned storage before returning to Odin.

## Racket Procedures

| Procedure | Result |
| --- | --- |
| `structural-current-scope` | Current copied `structural-scope` or `structural-failure`. |
| `structural-inspect` | Copied `structural-inspection` or `structural-failure`; it triggers no analysis. |
| `structural-forward` | Refreshed `structural-outcome` or `structural-failure`. |
| `structural-backward` | Refreshed `structural-outcome` or `structural-failure`. |
| `structural-up` | Refreshed `structural-outcome` or `structural-failure`. |
| `structural-down` | Refreshed `structural-outcome` or `structural-failure`. |
| `structural-select` | Refreshed `structural-outcome` or `structural-failure`. |
| `structural-indent` | Refreshed `structural-outcome` or `structural-failure`. |

Each semantic procedure first obtains copied inspection, derives the exact
point or ordered active region, sends one generated fixed-width request, and
replaces its local scope only after a successful native outcome.

## Copied Values

| Value | Copied contents |
| --- | --- |
| `structural-scope` | Schema, access, editor session, view, buffer, revision, selection, language, provider, parser, tree, registry, and capability generations. |
| `structural-request` | Exact scope, operation, point, ordered range, and region-presence flag. |
| `structural-target` | Exact scope, presence, named-node range, bounded kind text, and depth. |
| `structural-plan` | Exact scope, selected line range, copied edits when present, and usage. |
| `structural-outcome` | Refreshed scope, operation, completion, point, mark, region state, transaction identity, undo identity, and usage. |
| `structural-inspection` | Current scope plus the last copied target, plan summary, outcome, usage, and diagnostic. |
| `structural-failure` | Stable native failure code and optional `limit` and `actual` values. |

Inspection retains only copied last-operation state. Indentation edit text is
not retained after publication, so later inspection reports the plan range
and line or byte usage with an empty edit list. The transaction and history
owners retain their ordinary canonical results.

## Record Layout and Limits

All native-boundary scalars use little-endian fixed pointer-free records.

| Record | Width |
| --- | ---: |
| Scope | 160 bytes |
| Request | 200 bytes |
| Target header | 208 bytes |
| Indentation plan header | 224 bytes |
| Indentation edit | 32 bytes |
| Usage | 40 bytes |
| Outcome | 264 bytes |
| Diagnostic header | 112 bytes |

| Copied resource | Limit |
| --- | ---: |
| Target kind text | 96 bytes |
| Indentation edits | 16,384 |
| Diagnostic text | 4 KiB |
| Complete inspection | 1 MiB |
| Concurrent hosted structural turns | 1 |

Aggregate-width helpers validate target text, edit arrays, diagnostics, and
complete inspection size before native or Racket allocation. Generated
requests have one exact width and boolean encoding.

## Outcomes and Staleness

Movement and selection refresh view and selection generations without changing
the buffer revision. Indentation publishes one ordinary transaction and
returns the new editor revision while retaining the analysis identity that
produced the plan. That analysis is stale after publication; another
structural operation rejects until the application coordinator supplies a
refreshed retained tree.

Boundary no-ops are successful outcomes. A successful result contains no
native pointer and retains no transaction after the callback returns.

## Failure Containment

Native rejection distinguishes invalid context, missing permission, changed
authority, wrong editor session or view, stale view state, buffer, revision,
selection, analysis, command registry, and capability generation. Subordinate
editor, view, language, transaction, and history failures remain available in
the native failure context.

Malformed records, invalid booleans, oversized copies, wrong-thread use,
reentrancy, escaped capabilities, Racket exceptions, cancellation, allocation
failure, stale scope, syntax containment, and resource limits preserve
canonical state. Bounded diagnostic text is copied into structural inspection;
no runtime-owned diagnostic view is retained.

## Validation

Run the focused gates from the repository root:

```sh
raco test src/command/structural.rkt src/hosting/structural-bridge.rkt
odin test src/bridge -vet -warnings-as-errors
make native-command-test
make hosting-test
```

Coverage includes schema and widths, aggregate accounting, generated requests,
all six native/Racket parity cases, refreshed outcomes, authority and stale
generation rejection, malformed and oversized records, cancellation, owner
thread, reentrancy, forced collection, continuation escape, exception
containment, allocation failure in the semantic owner, deterministic cleanup,
and runtime reuse after rejection.

See the [Structural Editor Operations Reference](../structural-editor-operations/)
for canonical editor and transaction behavior and the
[Racket Runtime Boundary Reference](../racket-runtime-boundary/) for the shared
host lifecycle. Use
[Use and Validate Structured Syntax](../../how-to/use-structured-syntax/) for
focused native, Racket, and PTY commands.
