<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why the UI Foundation Publishes Complete Logical Generations

Odra already has stable semantic owners for text, buffers, candidates,
projects, keymaps, search, prompts, and pane layouts. A shared UI layer must not
replace those owners or let a renderer mutate them. It instead needs one
frontend-independent presentation boundary that can represent their current
state consistently and can reject an incomplete update before users see it.

## Logical surfaces are not physical surfaces

A logical `Surface` says that one view is renderable, visible, focusable, and
associated with input and keymap context. It does not allocate terminal cells,
create a native window, or own a renderer buffer. The renderer receives an
immutable snapshot and owns all physical output.

This distinction keeps terminal mechanics out of semantic presentation. It
also allows a later frontend to lower the same logical generation when its
declared capability profile is compatible, without moving model ownership into
that frontend.

## Projection separates models from presentation

Models remain under their existing subsystem owners. A projection identifies
one exact model generation and accounts for the copied data needed by a view.
Views then describe text, list, or input presentation without holding mutation
authority over the model.

List selection makes this separation explicit. A Buffer Menu selection can be
part of model state, while a navigation cursor can remain view-local. The UI
record states which owner applies instead of inferring ownership from renderer
behavior.

## Complete proposals prevent mixed generations

Publishing surfaces, focus, status, and styles one record at a time would let a
renderer observe combinations that never formed a valid UI. The registry
therefore prepares one private generation, validates its complete topology and
cross-references, and then replaces the root in one publication step.

```text
current root
    -> begin checked proposal
    -> populate private records
    -> select root and focus
    -> validate complete generation
    -> publish atomically
    -> copy compatible renderer snapshot
```

A stale expected root, invalid cross-reference, exceeded bound, incompatible
renderer, or allocation fault leaves the current root intact. An aborted
proposal releases only unpublished storage. The same preservation rule applies
when a snapshot allocation fails partway through its independent copies.

## Delivered list consumers share one presentation contract

Startup, the Buffer Menu, Project inventory, ambiguous directory resolution,
keymap inspection, and all four candidate sources are production `ListView`
consumers. Each publishes a focusable `Surface` containing copied item text,
semantic action references or passive presentation rows, current-item and
viewport state, and optional save or kill marks. The generic renderer lowers
only list roles: normal row, current row, save mark, and kill mark. It has no
feature-specific branch for any of these workflows.

Startup centers a passive terminal mark above its three existing actions:
create a buffer, open a local file, and open a directory. Its workflow owns
view-local selection while no buffer graph exists and keeps selection on those
three actions. Activating a row dispatches the existing command and transitions
to that command's prompt or editing state.

The Buffer Menu copies the editor session's active-then-MRU descriptors. The
editor session remains authoritative for entries, labels, activity, modified
state, and lifecycle. The inventory workflow owns its current entry, semantic
save and kill marks, return target, and partial-execution progress. `ListView`
owns only the checked presentation copy. Marked execution accepts copied
`Entry_Handle` and operation pairs, so it does not depend on a component
generation or renderer state.

Both workflows publish complete root generations on open, navigation, mark
change, refresh, and resize. Stale handles or generations reject; allocation,
item, text, geometry, and mark limits reject before publication; a failed
replacement preserves the previous complete root. Closing the workflow
releases the snapshot and registry storage and returns focus through the
recorded semantic target.

Project inventory retains the active `Project_Descriptor` and copied
`Membership_Descriptor` batch as its semantic source. Its list projection
shows registration state, directory count, normalized paths, trust, and
availability. Refresh follows membership identity across a new Project
publication instead of treating row position as identity. The ambiguous
directory workflow retains its copied registered-Project candidates and uses
the same list primitive with a distinct semantic mode.

Keymap inspection retains the complete copied `Inspection_Result` and
`Command_Catalog`. Formatting a list row does not replace binding, remap, map,
snapshot, rejection, profile, availability, protection, or provenance records.
The workflow releases both retained owners on close and returns through the
captured primary-view target.

Candidate presentation composes a model-owned-selection `ListView`, an `Input`
projection of the candidate session's query generation, and one root-edge
`StatusRegion`. The command, session-buffer, Project-buffer, and Project-file
adapters provide different semantic rows and annotations, but presentation
selects no source-specific primitive or renderer branch. The candidate session
remains the only owner of query text, matching, ranking, stable selection,
recency, and checked actions.

The input surface captures focus while the candidate root is active. Its
cursor and horizontal viewport are derived from the complete UTF-8 query; the
root-edge label carries source, scope, and selected/result counts. A rejected
turn projects the bounded diagnostic as rejected input without replacing the
retained candidate generation. Acceptance or cancellation closes the session,
releases capture, and restores the checked semantic return target.

## Semantic prompts remain interaction state

Moving a prompt into the UI root does not make the UI registry the owner of a
save path, exit decision, Project operation, or keymap query. Those meanings
remain in `interaction.Prompt` and the workflow that initiated it. The UI
generation is a checked observation: value, cursor, choices, validation, and
geometry copied from one exact semantic generation.

This separation matters most for fixed choices. A displayed alternative is
not interpreted as a command by the renderer. The semantic prompt copies each
bounded visible name together with its existing named command, and the `Input`
projection carries a generation-checked action reference. The command layer
resolves that reference against the still-active prompt owner before invoking
the choice. Reordering, stale presentation, or duplicate display text cannot
retarget the decision.

The same complete-publication rule governs geometry. Activating a transient
prompt reduces the base content by one row, composes a root-edge input and
status row, publishes them together, and captures focus only afterward. Closing
the prompt releases capture and the next root restores the row. A resize never
mixes the old pane tree with new prompt geometry; insufficient height rejects,
while a long label is clipped at a complete Unicode grapheme so the input keeps
one usable cell.

Keeping `interaction.Prompt` after this migration is deliberate rather than a
second presentation system. It is the bounded semantic state machine for text
entry and decisions. Search and query replacement reuse its bounded text-entry
state while their search and replacement sessions remain authoritative for
direction, matches, progress, counts, and completion. Diagnostics and passive
status add no semantic owner at all: they copy existing bounded feedback into a
root-edge status region.

The direct terminal overlay is removed because every remaining consumer now
has a complete root representation. This also makes style precedence explicit
in the logical generation: current search wins only on cells where it overlaps
an active region, list marks survive current-row styling, and diagnostic or
status roles reach the renderer without feature-specific branches.

## Generations make stale use explicit

Handles carry registry, object, root-generation, slot, and slot-generation
identity. A later publication does not silently reinterpret a handle from an
older root. Snapshot requests also name the exact expected root and renderer
profile.

This is stricter than relying on allocation addresses. Released storage may be
reused, but a stale logical identity still rejects. The renderer can therefore
finish or discard a copied snapshot without borrowing the mutable registry.

## Focus capture is a logical transaction

Transient input must temporarily own focus and then return it safely. Capture
records the current surface as a checked return target. Release restores it
when it remains valid; otherwise the current generation supplies a safe
focusable fallback.

The renderer does not decide this policy from cursor position. It only lowers
the published focus record, keeping keyboard context and visual focus in one
logical generation.

## Bounds are part of the contract

The resource ceilings come from a separate representation study rather than
from the convenient size of an implementation container. The study exercises
ordinary, demanding, and stress profiles, compares lookup and snapshot
representations, proves explicit rejection, and verifies zero retained bytes
after cleanup.

The production registry uses fixed-capacity generation storage and direct
checked resolution. Snapshot size, projection content, compact regions,
temporary work, and future event work remain separately bounded so one large
category cannot hide inside an aggregate allocation.

## The foundation stays consumer-driven

Slice 1 deliberately changed no visible production consumer. Slice 2 moves the
existing ordinary editor text, pane splits, pane status, region, and current
search highlight through shared UI roots while leaving buffer, view, search,
and layout ownership unchanged. The superseded single-view and layout-specific
terminal entry points are removed once those consumers use the generic root.
Slice 3 moves Startup and the Buffer Menu through shared list roots and removes
their feature-specific component and renderer paths. Slice 4 does the same for
Project inventory, ambiguous directory resolution, and keymap inspection.
Slice 5 moves all candidate sources through one composed root and removes the
component registry, adapters, snapshots, visible target, and full-frame
renderer after their final consumer migrates. Slice 6 moves every non-search
prompt through checked input, root-edge status, and focus contracts while
retaining semantic prompt ownership. Slice 7 moves search, query replacement,
diagnostics, and passive status through the same root contract and removes the
final direct prompt renderer after parity evidence.
Slice 8 exposes the seven migrated current-consumer roles through copied,
session-scoped Racket capabilities while native built-ins remain confirmed
fallbacks and semantic, publication, layout, focus, and renderer authority
remain in Odin.
Slice 9 reconciles diagnostics, makes resource and acceptance evidence
reproducible through named repository gates, verifies every current consumer
against source, and prevents the superseded presentation entry points from
returning.

The foundation does not pre-implement trees, tables, panels, popups, images,
retained notifications, or progress displays. Those shapes remain excluded
until an actual Odra consumer establishes their behavior and evidence.
