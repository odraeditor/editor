<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Interaction Profile Compatibility Contract Reference

This reference describes the native compatibility contracts introduced before
Odra ships another interaction profile. The contracts let later profiles share
canonical commands without making the current direct profile depend on a modal
grammar.

The current implementation validates, owns, and publishes complete copied
catalogs as the live runtime profile source. The shipped catalog contains the
factory-default `direct` profile and the selectable `modal` profile. See the
[Modal Interaction Profile Reference](../modal-interaction-profile/index.md)
for its delivered lifecycle and current behavior.

See [Profile Catalog Composition](catalog-composition.md) for the declarative
Racket API, copied record schema, quotas, ownership, and failure boundary.
See [Catalog Activation and State Admission](activation-and-state-admission.md)
for runtime publication, selection, command admission, and rollback.
See [Compatibility Inspection](inspection.md) for copied queries and records,
active and inactive definitions, scopes, selectors, admission, surfaces,
rejection, ownership, and bounds.

## Selected Limits

The initial compatibility policy uses these measured maxima:

| Resource | Maximum |
| --- | ---: |
| Profiles per catalog | 32 |
| States per profile | 16 |
| States per catalog | 512 |
| Shared selectors per binding | 64 |
| Shared selectors per catalog | 65,536 |
| Command-entry surfaces | 8 |
| Retained catalog metadata | 32 MiB |

Existing keymap limits continue to bound maps, bindings, sequences, copied
definition text, and compiled snapshots. The compatibility policy does not
widen them.

`make profile-compatibility-resource-study` reproduces the selected-capacity
evidence. It runs ordinary, demanding, stress, and rejection profiles. The
study reports exact persistent storage, peak storage, structural validation,
state admission, teardown, cleanup, and an independent admission-oracle check.

## Identity Types

`Profile_Catalog_Generation` identifies one immutable catalog generation.
Existing `Profile_ID` and `Profile_Revision` values continue to identify an
independent profile definition.

`Interaction_State_ID` and `Interaction_State_Revision` identify one immutable
state policy owned by a profile. A state identity has meaning only with its
owning profile definition.

`Command_Entry_Surface_ID` and `Command_Entry_Surface_Revision` identify one
presentation that invokes canonical registered command names. A surface is not
a command namespace or alternate registry.

All zero identities and revisions are invalid.

## Catalog Definition

`Profile_Catalog_Definition` is a borrowed candidate containing:

1. A non-zero catalog generation.
2. One through 32 complete profile definitions.
3. One active profile identifier.
4. One active state identifier owned by the active profile.
5. One through eight command-entry surface definitions.

Every profile contains one through 16 unique state definitions and names one
initial state. Profile identities are unique within the catalog. State
identities are unique within their owning profile. Surface identities are
unique within the catalog.

The catalog may contain inactive profiles, but only the selected profile and
state participate in resolution. Runtime publication copies every retained
definition before compiling the selected profile.

## Interaction State Policy

`Interaction_State_Definition` contains:

1. A checked state identity.
2. A bounded name.
3. An ordinary-text-input admission flag.
4. A set of admitted command effects.
5. Definition provenance.

`Command_Effect.Text_Mutation` distinguishes direct text mutation from broader
buffer, view, and lifecycle effects. `interaction_state_admits` returns true
only when the state admits every effect declared by a command.

The delivered direct profile uses one `direct-editing` state that admits its
current text and command behavior. Synthetic non-editing states exercise the
contract in tests but are not shipped profiles.

## Binding Scope

`Binding_Scope` has four valid values:

| Scope | Meaning |
| --- | --- |
| `Protected_Recovery` | Factory-owned recovery policy; selectors are forbidden and a protection reason is required. |
| `Shared_Continuity` | Explicit applicability to every named profile and state selector. |
| `Profile_Specific` | Applicability only to the owning profile; selectors are forbidden. |
| `State_Specific` | Applicability only to explicit states owned by the binding profile. |

`Invalid` is the zero value and is rejected by catalog validation.

A `Profile_State_Selector` contains one non-zero profile identifier and one
non-zero state identifier. Every selector on a shared binding must resolve in
the same candidate catalog. Duplicate selectors reject the candidate. One
binding can contain at most 64 selectors, and the catalog can contain at most
65,536 selectors.

Catalog publication validates selector structure, identity, registered command
membership, and effect compatibility across every selected target. One
incompatible target rejects the complete candidate.

## Command-Entry Surfaces

`Command_Entry_Surface_Definition` contains a checked identity, bounded name,
and provenance. The delivered extended-command navigator is the first runtime
consumer and carries surface identity `1:1`. Its existing `M-x` binding and
canonical command registry do not change.

This contract does not add `:` input, aliases, another registry, or another
command language.

## Structural Validation

`profile_catalog_definition_validate` is allocation-free and validates:

1. Policy bounds.
2. Catalog, profile, state, and surface identities.
3. Unique profiles, states, and surfaces.
4. Active and initial selection membership.
5. Binding scopes and selector shapes.
6. Selector target existence and uniqueness.
7. Total state and selector limits.
8. Exact definition-byte accounting against the catalog memory limit.

Success returns `Profile_Compatibility_Usage`. Structural validation reports
profile, state, scoped-binding, selector, and surface counts plus exact
borrowed definition bytes. Runtime ownership additionally reports exact
retained and candidate-peak bytes.

## Failure Codes

The compatibility contract adds failures for:

1. Invalid, stale, oversized, or over-budget catalogs.
2. Invalid, stale, or excessive interaction states.
3. Invalid binding scopes.
4. Invalid, duplicate, excessive, or incompatible shared selectors.
5. Invalid or excessive command-entry surfaces.
6. State-rejected command effects.

`Failure_Context` can identify catalog generation, profile, state, binding
scope, selector index, command-entry surface, applicable limit, and actual
usage. Later activation and inspection slices retain these fields instead of
introducing a second diagnostic envelope.

## Ownership Boundary

Definitions are borrowed only during validation and copying. `Profile_Catalog`
owns every retained profile, state, map, binding, selector, surface, remap,
ordering constraint, and string until `profile_catalog_close`.

Rejected and replaced candidates release all private storage. A borrowed
definition returned by `profile_catalog_definition` remains valid only until
its owning catalog closes.

## Current Integration Boundary

1. Racket composes a catalog containing the direct profile, its
   `direct-editing` state, and the `extended-command` surface.
2. Hosting copies and adapts the complete transport candidate.
3. Interaction validation creates a second native-owned immutable catalog,
   validates all shared targets, and compiles only the selected profile and
   state.
4. Key resolution, text fallback, command navigation, and direct invocation
   use the same active-state admission rule.
5. Failed or stale replacement preserves the active catalog, profile, state,
   snapshot, and pending-input generation rule.
6. Compatibility inspection copies catalog, profile, state, scope, selector,
   admission, surface, provenance, alternative, and rejection records through
   the shared UI pipeline.
7. Existing direct bindings and visible behavior remain unchanged.
8. The delivered modal lifecycle provides confirmed profile selection, Normal
   and Insert, state-specific bindings, Status Bar feedback, cursor intent,
   checked counts, the core Normal movement grammar, line-character targeting,
   canonical search traversal, bounded operators, canonical retained-text
   transfer, named text slots, line indentation, undo, and redo. Visual states,
   `:` input, aliases, `.`, and recorded macros remain outside the delivered
   slices.
