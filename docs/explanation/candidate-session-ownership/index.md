<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Candidate Navigation Uses a Source-Neutral Session

Command names, open buffers, documents, and Project files come from different
owners, but interactive navigation applies the same short-lived work to each:
copy one observation, filter it as the query changes, rank the result, retain a
stable selection, and either cancel or hand one checked action back to its
owner. Odra keeps that shared work in one source-neutral candidate session
instead of embedding a separate matcher in every command.

## Discovery is not canonical ownership

A candidate row is a disposable discovery projection. It is not a command
registry entry, buffer handle, document association, or filesystem object.
The source adapter therefore copies an opaque stable identity and checked
action data into the session while the canonical subsystem retains authority
over the real object.

This boundary prevents labels from becoming identities. Equal command names,
paths, or display text can remain distinct when their source-owned identity is
distinct. It also prevents a borrowed pointer from surviving a registry,
session, or Project generation change.

## Complete snapshots make replacement atomic

The session admits a complete source generation. A refresh prepares and
validates a complete replacement, filters it with the current query, finds the
prior selected identity, and only then publishes the new generation. A failed
copy or stale refresh leaves the existing source and selection visible.

The same discipline applies to query changes and recency updates. Matching,
sorting, and row construction happen before the current projection is
released. Allocation failure therefore has one clear result: the requested
turn is rejected and the previous generation remains usable.

## Stable identity separates selection from row position

Filtering and recency routinely change row order. Keeping only a numeric row
index would move selection to an unrelated action after a query edit or source
refresh. The kernel instead remembers the selected candidate identity and
locates that identity in the new projection. Row position is only a view of
the current ordering.

Activation still revalidates the action against its canonical owner. Stable
candidate identity preserves intent across projections; it does not override
an unavailable command, detached buffer, stale document, or changed Project.

## One matcher keeps ordering explainable

Literal matching is always available and has priority over expression-only
matching. Exact labels and boundary matches rank above other literal matches,
then successful-use recency, folded label, and identity resolve remaining
ties. This ordering is shared by every future source and does not depend on
enumeration order or frontend behavior.

Invalid expressions fall back to literal interpretation because candidate
navigation is an incremental discovery interaction, not an expression editor.
The fallback retains useful text without weakening the bounded expression
policy.

## The input turn remains narrow

The kernel performs copied in-memory work only. It does not scan a directory,
call Racket, decode terminal bytes, persist history, or invoke the selected
action. Source adapters perform enumeration before admission; presentation
renders the normalized view; the canonical owner checks and invokes an action
after selection.

Keeping those boundaries outside the input turn makes latency and failure
accounting local. Candidate count, copied text, query size, components,
expression size, visible rows, temporary storage, and refresh work all have
explicit ceilings. Hitting a ceiling is an observable rejection rather than a
partial list.

## Durable history remains advisory evidence

Successful-use ordering crosses sessions only for a local Project, but
that does not move ranking ownership into persistence. Odin decides whether a
checked command, file-backed buffer, or Project-file action succeeded and
updates the in-memory sequence. Racket handles only the constrained private
record load and atomic publication outside the candidate input turn.

This split matters when storage is missing, corrupt, stale, unsafe, or
unwritable. The candidate session can still use its current in-memory recency,
the successful action remains successful, and no partial persisted record
becomes ranking evidence. A rejected load also disables publication for that
loaded Project generation, so navigation does not overwrite evidence it could
not validate.

Project identity is the privacy and isolation boundary. Records live under the
global Odra state root rather than inside a Project Dir, and an ordinary Dir
or a session without a Project never receives a durable record. Command,
document, and Project-file keys use separate categories so equal text cannot
silently merge unrelated identities.

## Cleanup follows one owner

The session owns every copied label, field, annotation, expression, projection,
and row. Views borrow those values only until the next operation. Closing the
session releases the complete graph regardless of whether the interaction was
accepted, cancelled, refreshed, or rejected during a later turn.

This single owner is also the extension point. Command, session-buffer,
Project-buffer, and Project-file navigation now use source adapters and checked
action resolution without duplicating the candidate lifecycle or moving
authority into the terminal. The Project-file adapter demonstrates why label
and identity stay separate: two member directories may publish the same
relative label while their canonical paths and checked actions remain distinct.

All four adapters now share one presentation root as well as one semantic
session. A `ListView` copies rows and the model-owned current selection, an
`Input` copies the session query generation, and a root-edge `StatusRegion`
copies source, scope, and count context. This composition remains source-neutral:
the UI formats supplied annotations but does not know how to enumerate, rank,
persist, or invoke any source.

Input focus is captured by the shared root and released through the checked
primary-view return target. A failed query or presentation turn can show a
bounded rejected diagnostic while retaining the prior candidate generation.
There is no second query owner, selection cursor, focus owner, or recovery
state in the renderer.

The earlier Racket command-navigation composition facade was retired only
after reference-model, native, Racket, restart, fault, and PTY parity passed.
Programmability remains at command registration and keymap composition; the
common Odin session is now the only filtering, ranking, selection, and
candidate-dispatch path for the factory sources.

The later UI migration retired the component registry, candidate presentation
adapters, component snapshots and visible target, and the full-frame component
renderer after the last candidate consumer moved to the shared root. Legacy
`Component_Tool` precedence and `component-*` route names remain only as
contextual interaction vocabulary.

The [Candidate Session Reference](../../reference/candidate-session/index.md)
states the exact matching, ranking, lifecycle, limits, accounting, and failure
contracts.
