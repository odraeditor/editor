<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Search State Is Separate from Editor Text

Incremental search changes what the user is looking at, not the document being
edited. Odra therefore keeps matching, interaction state, display projection,
and canonical text under separate owners. A failed query can change a prompt
and still guarantee that the rope and edit history remain untouched.

## The engine reads immutable revisions

The `search` package receives a checked immutable buffer snapshot, a copied
query or replacement template, a revisioned scope, and explicit resource
policy. It traverses rope windows directly instead of flattening the complete
buffer into a contiguous string. Literal search uses bounded overlap.
Regular-expression search copies
one bounded window plus its admitted maximum match span because the standard
matcher requires contiguous input. Both strategies recognize cross-leaf
matches without creating a permanent whole-buffer copy.

The engine returns copied byte ranges carrying buffer identity and revision.
It does not own a buffer, point, viewport, frontend, or history node. This
makes a result useful to views and later programmable callers without exposing
rope storage or borrowing bytes across package lifetimes.

## The view owns the interaction lifetime

A live view owns the active session because origin, direction, current match,
viewport restoration, and failed-suffix recovery are view-local concerns. Two
views over one buffer may search independently without making either session
canonical editor state.

On the first published turn, the view captures effective point and viewport as
persistent origin anchors. A successful result moves buffer effective point and
the initiating view's stored point to the directional match edge. A failed
result replaces the query and status but retains the last successful result and
point. Acceptance releases the origin anchors and keeps point; abortion
resolves them, restores buffer effective point plus view stored point and
viewport, and then releases them.

Search movement does not create edit history. History records reversible text
publication, while an active search is disposable interaction state.

## Command coordination preserves the boundary

The `command` package captures the live scope and revision, admits each query,
runs one bounded engine turn, prepares point visibility, and publishes a
complete view transition. It validates display policy before session
publication so an expected presentation failure cannot leave a half-confirmed
command result.

`interaction` owns normalized inputs and the bounded query prompt. The Racket
factory keymap declares `C-s`, `C-r`, `C-M-s`, `C-M-r`, `M-%`, and `C-M-%`
against named commands, but Racket does not reproduce rope traversal or own
occurrence state. This preserves a narrow programmable control layer around
one Odin-owned matching implementation.

The same boundary supports higher-level composition without expanding
ownership. Racket receives immutable copies of the current scope, complete
policy, session text, nearby occurrences, captures, progress, and usage. It may
derive a new complete policy and invoke an admitted semantic command with
copied pattern, replacement, direction, and scope values. Odin revalidates
every identity, generation, bound, and policy relationship before executing
the existing command path.

The opaque context exists only during one synchronous dynamic extent. Escaping
it, resuming an escaped continuation, entering on the wrong owner thread, or
reentering the native callback is rejected. Copied Racket values may outlive
the call because they contain no native pointer or borrowed rope storage.

The regular-expression adapter also owns two details that cannot be delegated
blindly to the standard iterator. It preserves declared capture numbers when
optional groups do not participate, and it advances empty matches by Unicode
scalar boundaries. These are editor occurrence contracts rather than terminal
or extension behavior.

## Replacement remains private until the complete batch is valid

Replacement expansion belongs beside matching because captures, case policy,
UTF-8 boundaries, and source revision must agree before text can be trusted.
The search layer therefore produces owned occurrence-specific expansions; it
does not mutate the buffer or publish history.

The command layer collects those expansions as base-relative splices. It
filters literal overlap deterministically, accounts for every copied and
expanded byte, and revalidates the immutable source revision after enumeration.
Only then does it hand one non-overlapping batch to the transaction layer.

This separation prevents an early replacement from changing the meaning or
coordinates of a later match. It also gives cancellation, resource exhaustion,
allocator failure, stale state, and history admission one shared outcome: the
candidate batch is released and canonical text is unchanged.

## One publication is one history event

Atomic replacement publishes one normalized changeset and reserves one
independent history unit. The buffer revision advances once regardless of the
number of matches, and undo or redo traverses the whole replacement as one
event. A no-match result skips both revision publication and history.

The logical view participates in the same transaction. Point is mapped through
the final batch, the active region is deactivated, and display observes only
the committed revision. A frontend never has to render a partially replaced
document or infer which subset belongs to the undo unit.

## Display maps ranges; the terminal only styles them

The `display` package maps revisioned occurrence endpoints through Unicode
layout, clipping, scrolling, and resize. The UI root copies that exact search
observation into its text projection and composes the search input and status
as separate logical surfaces. The terminal renderer consumes the immutable
root and styles the current visible range. Current-search style overrides an
active region only where their ranges overlap; it does not erase the remainder
of the region. The renderer cannot infer a canonical match from terminal cells,
and another frontend can render the same snapshot without changing engine or
view semantics.

## Pending and failure are truthful states

A large traversal stops after its admitted scan window and publishes explicit
progress. `Pending` means more of the same scope remains; `Wrapped` means the
next turn starts at the opposite boundary. Neither is reported as no match.

Allocator failure, cancellation, stale revision, malformed input, and work
limits reject the candidate turn before it replaces the visible session.
Deterministic close paths keep copied queries, results, occurrences, temporary
windows, and view anchors from leaking across interactions.

The [Search and Replacement Reference](../../reference/search-and-replacement/index.md)
states the exact commands, states, limits, and cleanup rules. The
[incremental-search tutorial](../../tutorials/search-and-replacement/index.md)
walks through the visible behavior.
