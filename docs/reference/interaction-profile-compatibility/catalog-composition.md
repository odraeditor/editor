<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Profile Catalog Composition

This reference describes the Racket definitions and copied native records used
to transport complete interaction profile catalogs. The transport is the first
atomic candidate boundary before native validation, ownership, and activation.

## Factory Catalog

`factory-interaction-profile-catalog` returns one immutable catalog for the
requested command-registry generation. The shipped catalog contains:

1. Catalog generation equal to the requested registry generation.
2. One `direct` profile with identity `1:1`.
3. One `direct-editing` state with identity `1:1`.
4. The current factory and project maps.
5. One `extended-command` surface with identity `1:1`.
6. Active profile `1` and active state `1`.

The factory profile keeps every ordinary binding `profile-specific`. Protected
`C-g` and `M-x` recovery bindings remain native factory policy and are not
redeclared by the Racket catalog.

## Racket Definitions

`src/command/keymaps.rkt` exports transparent guarded records for:

| Record | Purpose |
| --- | --- |
| `odra-interaction-profile-catalog` | Complete generation, profiles, active selection, and command-entry surfaces. |
| `odra-interaction-profile` | Profile identity, states, initial state, maps, and text fallback. |
| `odra-interaction-state` | State identity, text-input admission, admitted command effects, and provenance. |
| `odra-binding` | Operation, sequence, command, scope, selectors, provenance, and protection reason. |
| `odra-profile-state-selector` | One exact shared-continuity target. |
| `odra-command-entry-surface` | One canonical-name command-entry presentation. |

`compose-interaction-profile-catalog` validates the bounded catalog shape.
`stage-interaction-profile-catalog!` replaces only the Racket-owned candidate
used by the next transfer. `clear-staged-interaction-profile!` restores lazy
factory composition.

Existing `keymap-bind`, `keymap-replace`, `keymap-unbind`, and `keymap-mask`
construct profile-specific definitions. `keymap-share` converts one binding to
shared continuity and requires one through 64 explicit selectors.

The compatibility API exposes no modal grammar, state-transition language, or
alternate command names.

## Copied Record Order

`runtime-keymap-profile-batch` serializes one self-describing batch in this
order:

1. Catalog header.
2. Profile records.
3. State records.
4. Map records.
5. Scoped binding records.
6. Profile/state selector records.
7. Command-entry surface records.
8. Remap records.
9. Ordering records.
10. Normalized stroke records.
11. Shared UTF-8 text payload.

Every range is contiguous and expressed as a record index and count. Text is
expressed as byte offsets and byte counts into the final payload. Records use
fixed-width integer fields and contain no pointers.

The current schema version is `2`. `src/bridge/native_contract_schema.odin` is
the native authority for every width and quota, and
`src/command/native-contracts.rkt` rejects drift during runtime startup.

## Selected Quotas

| Resource | Maximum |
| --- | ---: |
| Profiles | 32 |
| States | 512 |
| Maps | 4,096 |
| Scoped bindings | 65,536 |
| Shared selectors | 65,536 |
| Command-entry surfaces | 8 |
| Remaps | 65,536 |
| Ordering constraints | 262,144 |
| Flattened strokes | 1,048,576 |
| Text payload | 32 MiB |
| Complete copied batch | 32 MiB |

Per-profile and per-definition native limits still apply. A profile has at
most 16 states and 128 maps, a map has at most 4,096 bindings and 64 ordering
constraints, a shared binding has at most 64 selectors, and a sequence has at
most 16 strokes. The complete 32 MiB batch limit can reject a combination even
when every individual count remains below its maximum.

## Validation

The native bridge rejects a batch before adaptation unless all of these hold:

1. Schema version, record width, counts, and exact total bytes agree.
2. Registry, catalog, active profile, and active state identities are non-zero.
3. Profile state and map ranges are contiguous and complete.
4. Active and initial state selections belong to the named profile.
5. Profile, state, map, and surface identities are unique in their required
   scope.
6. Map child ranges, binding stroke ranges, and binding selector ranges are
   contiguous and complete.
7. Shared selectors resolve to declared profile/state pairs.
8. Scopes, effects, operations, normalized strokes, UTF-8 text, provenance,
   and protection reasons are structurally valid.
9. All per-record and aggregate quotas are satisfied.

Malformed, oversized, truncated, unsupported, stale-registry, invalid-active-
state, exception, reentrant, wrong-thread, and allocation-fault candidates are
rejected without returning partial definitions.

## Ownership and Lifetime

The Racket byte string is copied into caller-provided native storage by the C
adapter. Hosting parses borrowed record slices over that private storage, then
allocates native profile, state, map, binding, selector, surface, remap, and
ordering arrays.

`keymap_profile_candidate_catalog_definition` borrows the complete adapted
catalog. The runtime reload path uses this complete view and copies it into an
independent `Profile_Catalog`; it does not retain the hosting candidate or its
selected-profile compatibility view. Neither hosting view outlives its
candidate.

`keymap_profile_candidate_close` releases every adapted array and the copied
batch. Rejection releases partial adaptation before returning. Closing an
already closed candidate is safe and exposes no further borrowed view.

## Current Runtime Boundary

The command reload path passes the complete borrowed transport definition to
native catalog validation. Activation owns a separate immutable copy, selects
the declared profile and state, projects applicable shared contributions, and
publishes one compiled snapshot transactionally. Inactive profile-specific
bindings cannot resolve input or replace the selected text fallback.

See [Catalog Activation and State Admission](activation-and-state-admission.md)
for the live ownership and command-admission contracts and
[Compatibility Inspection](inspection.md) for the copied runtime projection.
