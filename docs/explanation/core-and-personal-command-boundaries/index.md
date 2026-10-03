<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Core and Personal Command Boundaries

Odra gives factory commands and personal commands access to the same editor
concepts without granting them identical authority. Both can participate in
named command routing, inspect admitted text, publish edits through
transactions, and produce one logical undo unit. They differ in how code
enters the process, which resources it may consume, and which state it may
own.

This separation is an execution-boundary decision rather than a judgment about
Racket as a text-processing language.

## Different provenance requires different policy

Factory code ships with the editor, passes repository validation, and may use
private native or Racket modules. Personal code is selected from the user's
configuration and can be replaced while the editor is running. Its behavior
therefore passes through a narrower control plane with explicit admission,
resource containment, generation replacement, rollback, and recovery.

| Concern | Factory implementation | Personal implementation |
| --- | --- | --- |
| Code loading | Built and validated with the editor | Evaluated as a replaceable configuration generation |
| Racket modules | Normal internal compilation and module resolution | Isolated embedded authoring namespace |
| Resource policy | Subsystem-specific native and hosting bounds | Dedicated personal-command deadline, memory, text, splice, and diagnostic profile |
| Editor state | Private subsystem APIs where ownership permits | Copied values and opaque public capabilities |
| Replacement | Editor build or provider lifecycle | Atomic live reload with rejected-generation rollback |
| Failure recovery | Subsystem-specific fallback | Last confirmed generation plus factory command recovery |

The personal profile does not constrain factory commands. Internal Racket
modules can use the normal language surface, while personal modules use the
currently verified embedded authoring surface documented in the
[Personal Commands Reference](../../reference/personal-commands/).

## Text budgets bound a turn, not the buffer

The personal text ceilings bound copied inspection and transaction work for one
command turn. They do not define the maximum document or buffer size. Ordinary
source files fit comfortably inside the current profile; large logs, generated
files, minified assets, and complete-buffer rewrites can make the distinction
visible.

The native editor and transaction layers retain larger independent ceilings.
The personal profile is intentionally more conservative because dynamically
loaded code shares the editor process. Increasing that profile, introducing
multiple profiles, or adding incremental processing are separate policy
choices. Each choice trades larger workloads against memory use, rollback
retention, latency, and responsiveness.

## A synchronous deadline protects interaction

One personal command executes synchronously under a bounded elapsed deadline.
This is suitable for interactive text transformations, where a delay near the
deadline is already noticeable. Heavy analysis, external processes, or large
inputs may call for asynchronous work rather than a substantially longer
blocking turn.

An asynchronous model would need explicit cancellation, progress, stale
revision handling, result publication, cleanup, and shutdown semantics. Raising
the synchronous deadline and introducing asynchronous tasks are therefore
different decisions.

## Transactions are a shared guarantee

Opaque positions, ranges, and transactions are not restrictions placed only on
personal code. They preserve revision identity, atomic publication, rollback,
and coherent undo throughout the editor.

The public API can become more convenient without removing those guarantees.
Insert, delete, range transformation, line iteration, and incremental reading
helpers can often be implemented as Racket procedures over the existing
context. Such helpers would make common commands direct to author while still
publishing through the same private transaction.

An operation needs a wider bridge only when the current context cannot express
the required authority or native data. Convenience and authority expansion
should not be treated as the same change.

## Canonical editor state remains native-owned

Non-destructive annotations, presentation overlays, semantic properties, and
syntax metadata interact with revisions, anchors, views, themes, rendering,
undo, persistence, and provider lifecycle. Racket can describe or compose
these concepts, but a durable or visible instance requires an Odin-owned model
and a checked bridge.

The core can currently implement specialized behavior directly, as selection,
syntax presentation, diagnostics, and search results already do. That does not
yet imply one generic annotation system suitable for extensions. A common
model would need to distinguish at least:

- buffer-owned semantic state from view-local presentation;
- anchored metadata from disposable projections;
- provider lifecycle from document lifecycle;
- theme roles from hard-coded rendering;
- transient state from undoable or persistent state.

Simulating these capabilities by inserting ordinary document text would break
the ownership model and produce incorrect save and undo behavior.

## Language power and editor authority are separate

Racket remains capable of substantial Unicode text processing through ordinary
procedures, higher-order composition, regular expressions, data structures,
and recursion. The currently verified personal-module syntax and the public
editor API determine which of those programs can be loaded and which editor
effects they may request.

The useful comparisons are therefore separate:

1. what a Racket program can compute;
2. what the embedded authoring namespace can load;
3. what the public command context can inspect or mutate;
4. what canonical state Odin currently models.

Expanding one layer does not automatically expand the others.

## Evolution remains evidence-driven

Backlog research records possible changes to text budgets, scheduling,
transformation conveniences, embedded authoring, and annotations. Those
investigations may recommend preserving the current behavior, refining public
Racket APIs, extending the bridge, adding Odin-owned state, or promoting a
larger change into a specification and sliced delivery.

The current contracts remain authoritative until such a change is explicitly
accepted. See [Why Odin Hosts Racket](../in-process-racket-hosting/),
[Why Commands Publish Through Transactions](../atomic-edit-transactions/), and
the [Racket Runtime Boundary Reference](../../reference/racket-runtime-boundary/)
for the surrounding ownership and lifecycle model.
