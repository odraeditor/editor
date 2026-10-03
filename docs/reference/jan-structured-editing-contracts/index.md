<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Structured Editing Contracts Reference

Jan Structured Editing is the Stage 2 native domain over the accepted Jan
Document Language analysis. This reference describes the base contracts:
resource policy, exact operation scope, view-local hidden ranges, deterministic
visibility transitions, failures, ownership, and focused validation. Concrete
outline behavior is documented in the
[Jan Outline Editing Reference](../jan-outline-editing/).

The application publishes the complete Stage 2 command catalog through one
native coordination layer. See
[Jan Structured Editing Commands and Configuration](../jan-structured-editing-commands/).

## Package boundary

`src/jan_editing` consumes copied Stage 1 analysis and generic view contracts.
It does not parse source, retain Tree-sitter values, own canonical text, publish
transactions directly, or import `src/odra`.

`src/view` owns generic hidden ranges because folding is presentation state for
one view. It does not know Jan headings, sparse predicates, document syntax, or
command identities.

Both packages are statically compiled. No dynamic library or plugin boundary is
introduced.

## Exact scope

`jan_editing.Scope` binds one request to:

- a complete `language.Jan_Analysis_Scope`;
- one checked `view.View_Handle` generation;
- the exact view-state and visibility generations; and
- confirmed Stage 2 configuration and provider generations.

Any mismatch is stale. A stale prepared transition remains inspectable and
releasable but cannot change view state.

`jan_editing.Target` adds a target kind, copied Jan node identity, and exact
source range. Document and region targets may be range-owned without one node;
all other target families require a nonzero copied node identity.

## View-local hidden ranges

`view.Hidden_Range` contains current-revision half-open editor positions.
`view.visibility_replace` validates the complete candidate, sorts it, merges
overlapping or adjacent ranges, creates persistent anchors, and replaces the
previous generation only after the candidate is ready.

Start anchors use right affinity and end anchors use left affinity. Text
inserted exactly outside a hidden boundary therefore remains visible. Edits
before a range move both anchors automatically. Deleting the complete range
collapses its anchors; the next checked visibility operation removes the empty
range and advances the visibility generation.

The public operations are:

| Operation | Result |
| --- | --- |
| `view.visibility_replace` | Atomically installs one normalized generation |
| `view.visibility_clear` | Releases all ranges, or returns unchanged when already empty |
| `view.visibility_copy_ranges` | Copies current ranges into caller-owned bounded storage |
| `view.visibility_position_is_hidden` | Tests one exact current position |
| `view.visibility_reveal_position` | Removes a containing hidden range before movement or editing |
| `view.visibility_reveal_range` | Removes every range intersecting an admitted source operation |

Cloned views start with no hidden ranges. Each view can then derive independent
visibility over the shared buffer and analysis. Rebinding or closing a view
releases all range anchors and retained storage.

## Deterministic cycles

The local cycle is closed and ordered:

```text
Heading_Only -> Direct_Children -> Complete_Subtree -> Heading_Only
```

The global cycle is also closed and ordered:

```text
Overview -> Contents -> Show_All -> Overview
```

`jan_editing.visibility_transition_prepare` copies the proposed hidden ranges
and records the prior and next state. Publication rechecks analysis revision,
view generation, view-state generation, and visibility generation before
calling the generic view owner. Successful publication consumes the prepared
transition. Rejection requires an explicit close.

## Stage 2 availability

The package defines exactly five operational factory-native families:

- visibility;
- structural editing;
- list editing;
- table editing; and
- contextual editing.

The application publishes these five records as operational factory-native
capabilities. Later-stage task, property, time, computation, external-resource,
and extension families remain unavailable with their owning stages preserved.

## Resource limits

| Resource | Limit |
| --- | ---: |
| Hidden ranges per view | 16,384 |
| Sparse matches | 16,384 |
| Semantic targets per command | 4,096 |
| Table cells per operation | 65,536 |
| Rewrite splices | 16,384 |
| Completion candidates | 512 |
| Copied completion text | 256 KiB |
| Templates | 256 |
| Completion sources | 256 |
| Copied configuration | 1 MiB |
| Active previews per view | 8 |
| One preview result | 8 MiB |
| Process-wide preview cache | 64 MiB |
| Entries between cancellation checks | 4,096 |

The stricter Stage 1 rewrite or transaction limit always wins.

## Failures and cleanup

Invalid scope, target, visibility state, stale generation, limits,
cancellation, allocation failure, view failure, and unavailable capability are
explicit outcomes. Failure publishes no partial hidden-range generation.

View range storage contributes to `view.Registry_Stats.storage_bytes`.
Allocation-fault tests cover both transition allocations and view replacement;
tracked teardown proves that views, anchors, transition copies, buffers, and
registries retain no storage after close.

## Focused validation

Use:

```sh
make jan-structured-editing-focused-test
```

The target runs the independent Racket model and resource study plus strict
tests for `src/view` and `src/jan_editing`. It does not import or build
`src/odra`.
