<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Compatibility Inspection Reference

Compatibility inspection returns one bounded immutable `Inspection_Result`.
The result owns its records, strings, and shared selectors until
`inspection_result_close`; it does not borrow catalog, snapshot, registry, or
Racket storage.

## Queries

| Query kind | User command | Result |
| --- | --- | --- |
| `Sequence` | `describe-key` | Effective, shadowed, masked, or inactive binding records for one normalized sequence. |
| `Command` | `where-is` | Binding and remap records for one canonical command plus every active command-entry surface. |
| `Map` | `describe-keymap` | One map and its binding and remap records. |
| `Active_Maps` | Extension API | Active maps, or retained inactive maps when explicitly requested. |
| `Bindings` | `describe-bindings` | The bounded binding and remap projection. |
| `Snapshot` | Extension API | Registry, snapshot, profile, context, pending-input, usage, and catalog/state identities. |
| `Compatibility` | `describe-keymap-state` | Snapshot, catalog, active and inactive profile/state definitions, and surfaces. |
| `Latest_Rejection` | `describe-keymap-conflicts` | The latest rejected candidate context, when present. |

Invalid names, identifiers, sequences, or query kinds reject before result
allocation.

## Record kinds

| Record | Compatibility fields |
| --- | --- |
| `Binding` | Sequence, effective and original command, map, precedence, operation, protection, catalog, owning profile, active state, scope, selectors, effect admission, and provenance. |
| `Remap` | Original and target command, map, catalog, active selection, disposition, and provenance. |
| `Map` | Identity, owner, precedence, priority, active disposition, catalog selection, protection, and provenance. |
| `Snapshot` | Registry and snapshot generations, context, catalog generation, active profile/state, pending sequence, and usage. |
| `Catalog` | Catalog generation and active profile/state identities. |
| `Profile` | Identity, bounded name, catalog generation, and active or inactive disposition. |
| `State` | Owning profile, identity, bounded name, text-input policy, admitted effects, active or inactive disposition, and provenance. |
| `Surface` | Identity, bounded name, command when queried, state admission, availability, and provenance. |
| `Rejection` | Failure code plus catalog, profile, state, scope, selector, surface, command, map, owner, generation, and resource fields available from the rejected candidate. |

`effects_admitted` is derived from the same active-state rule used by key,
text, command-navigation, and direct invocation paths. It does not authorize
execution by itself.

## Binding scopes and selectors

`Protected_Recovery`, `Shared_Continuity`, and `Profile_Specific` remain
distinct in copied records. Shared records own a copied selector list; each
selector contains one profile identifier and one state identifier. No record
retains a slice into the live catalog.

## Racket composition

`src/command/keymap-inspection.rkt` exposes guarded request, record, and result
structures with the same query kinds and compatibility fields. Constructors
copy strings, effect lists, selectors, and record lists. They cannot call the
resolver or retain native pointers.

## Limits and failures

One result contains at most 128 records. A complete compatibility projection
that exceeds this bound fails with `Inspection_Limit`; it is never truncated.
Allocation failure releases every partially copied record, selector, and text
arena and preserves the active catalog and snapshot.

The compatibility resource policy remains:

| Resource | Maximum |
| --- | ---: |
| Profiles | 32 |
| States per profile | 16 |
| Total states | 512 |
| Selectors per shared binding | 64 |
| Total selectors | 65,536 |
| Command-entry surfaces | 8 |
| Inspection records per result | 128 |

Run `make profile-compatibility-resource-study` for capacity, latency,
accounting, teardown, and cleanup evidence.
