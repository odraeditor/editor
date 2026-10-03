<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Catalog Activation and State Admission

This reference describes how Odra turns one copied profile catalog into the
active runtime profile, state, keymap snapshot, and command-admission policy.
The shipped catalog still contains only the direct profile.

## Publication Transaction

`profile_activation_replace_catalog` performs one prepare, validate, compile,
and publish transaction:

1. Reject a zero, stale, or non-increasing catalog generation.
2. Validate the complete borrowed catalog against structural limits and the
   active command registry.
3. Copy every retained definition and string into one private
   `Profile_Catalog` owner.
4. Resolve the declared active profile and state from that owned catalog.
5. Project only the bindings applicable to that selection.
6. Compile the projected profile into a private resolution candidate.
7. Publish the new snapshot, catalog, profile, and state together.
8. Clear pending input only after successful publication.
9. Retire the previous snapshot and catalog deterministically.

Failure before publication closes every private candidate and preserves the
confirmed catalog, profile, state, snapshot, pending-input state, views, and
canonical editor state.

## Owned Catalog

`Profile_Catalog` owns copied arrays for profiles, states, maps, scoped
bindings, selectors, surfaces, remaps, and ordering constraints. One text arena
owns all retained names, command identifiers, protection reasons, and
provenance strings.

`profile_catalog_usage` reports borrowed definition bytes, retained owner
bytes, counts, and candidate peak bytes. `profile_catalog_close` releases the
complete owner exactly once. Allocation failures during construction release
all partially allocated storage.

## Active Selection and Isolation

Exactly one profile and one state are active. Profile-specific bindings from
inactive profiles are retained for later selection but never enter the active
snapshot. The selected profile supplies its maps, remaps, ordering, and text
fallback.

A shared-continuity contribution enters the selected snapshot only when it
names the active profile and state. A contribution stored with another profile
can be projected through the corresponding selected map identity. The
candidate rejects atomically when any declared target does not exist or does
not admit the command effects.

Protected `C-g` and `M-x` bindings remain native factory policy. External
catalog definitions cannot declare or overlap protected recovery bindings.

## State-Aware Command Admission

Every registered command declares its complete effect set. Commands that can
change canonical text additionally declare `Text_Mutation`. This includes text
insertion and deletion, line breaks, replacement, undo and redo, region
deletion, kill, yank, yank replacement, and the programmable line transform.

`profile_activation_command_admit` resolves command metadata from the checked
registry and compares it with the active state. A command rejects with
`Command_Effect_Rejected` when:

1. Its invocation requires ordinary text input and the state does not admit
   text input.
2. Any declared command effect is absent from the state's admitted effects.

The same check runs after key resolution, after text fallback resolution, when
command navigation dispatches a selected command, and for direct invocation.
Command navigation keeps rejected commands visible but marks them unavailable
with an active-state reason.

## Direct Compatibility

The factory catalog activates profile `direct` at revision `1` and state
`direct-editing` at revision `1`. That state admits ordinary text input and all
currently delivered command effects. Existing key bindings, text fallback,
transient interactions, command names, editing behavior, and terminal flows
therefore remain unchanged.

Synthetic profiles and non-editing states are test fixtures only. They verify
inactive isolation, explicit shared projection, navigation admission, text
mutation rejection, rollback, capacity, latency, accounting, and cleanup.

## Extended-Command Surface

The active catalog contains surface `extended-command` with identity `1:1`.
The delivered `M-x` navigator resolves that checked surface before building its
command catalog and retains the surface identity with the navigation
projection. It continues to use canonical registered command names.

No second command registry, command alias catalog, `:` surface, modal
transition, or modal binding grammar is included.

## Failures

Expected activation failures include:

1. Invalid or stale catalog, profile, state, map, command, or generation.
2. Unknown text fallback or registered binding command.
3. Invalid scope, selector, ordering, remap, or protected overlap.
4. A shared command effect rejected by any selected target state.
5. Catalog, definition, snapshot, or allocation limits.
6. A command effect rejected by the active state at dispatch time.

Failure contexts retain catalog generation, snapshot generation, profile,
state, command, binding scope, selector index, map identity, and resource
bounds where applicable.
