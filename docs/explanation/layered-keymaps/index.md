<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Keymaps Are Layered

A single table can answer which command one key sequence invokes, but it
cannot explain why that answer changes inside a prompt, language buffer,
Project, or future editing state. Odra represents those concerns as named
maps inside one global interaction profile instead of repeatedly rebuilding
one anonymous flat table.

## Semantic commands remain the stable center

Physical input is not an editor operation. Frontends normalize physical
events, keymaps associate sequences with semantic command identities, and the
command registry checks which native or Racket implementation may execute.

This separation lets a command keep the same meaning while profiles and
contexts change its physical bindings. It also lets command navigation invoke
the same checked identity without pretending to press a key.

## Context is activation, not another profile

Odra has one active interaction profile for the editor session. A language
buffer, prompt, tool, or Project does not silently select a different global
profile. It activates checked maps inside that profile.

Keeping those concepts separate matters for future modal editing. The global
profile may establish a modal grammar while buffer and transient contexts
continue to contribute language and workflow maps through the same resolver.
Modal behavior does not require a parallel dispatch system.

## Explicit precedence prevents accidental policy

Import order and package initialization order are poor user-interface policy:
they are difficult to inspect, unstable under refactoring, and unrelated to
the user's current context.

Precedence classes state the intended relationship directly. A transient
prompt outranks a buffer-local or language map; a language map outranks
Project and global fallback maps. Maps in one class must use declared
priority and ordering constraints. Ambiguous equal-priority collisions and
cycles fail before activation.

This produces a deterministic answer and enough retained evidence to explain
that answer later.

## Recovery is protected policy, not hidden input handling

A programmable system needs a reachable way to cancel transient interaction
and discover registered commands even when user or package maps are invalid.
Encoding those keys as frontend conditionals would create a second invisible
dispatcher and make the effective policy impossible to inspect.

Odra instead represents recovery as an ordinary compiled map at the highest
declared precedence, with two exceptional policy rules: its catalog is fixed
and lower maps may not shadow, replace, mask, or reinterpret its sequences.
The protected entries still resolve to normal registered commands and retain
map identity, provenance, and reasons. The frontend must prove it can emit the
normalized logical strokes before the profile becomes active.

Keeping the catalog to `C-g` and `M-x` preserves recovery while leaving every
other sequence, including conventional exit aliases, under the programmable
profile. Expanding the catalog is a policy change because each additional
entry reduces the configuration space.

## Prefixes participate in precedence

Multi-stroke input cannot be resolved by checking exact bindings alone. A
higher-precedence map may own a strict prefix while a lower map owns the same
strokes as an exact command. Executing the lower command would make the higher
sequence unreachable.

Odra therefore asks each active map, in precedence order, whether the current
sequence is exact, a prefix, or masked. The first map that answers owns the
turn. A prefix becomes pending input; a mask blocks fallback; an exact binding
produces a checked command.

## Masks and remaps solve different problems

A mask says that a physical sequence must not fall through to a lower map. It
does not need a replacement command.

A remap says that a semantic command should mean another registered command
inside the active policy. It targets command identity rather than duplicating
every physical sequence that might invoke that command. Bind, replace, unbind,
mask, and remap remain distinct operations so inspection can report the real
reason for the effective behavior.

## Compilation keeps the typing path native

Racket is the programmable authoring layer, but canonical input state and
command admission remain native responsibilities. A complete candidate is
copied, validated, ordered, and compiled before publication. Ordinary exact
and prefix lookup then uses immutable Odin-owned storage without entering
Racket or allocating on each key.

Runtime changes use the same candidate boundary. A failed allocation, stale
owner, invalid command, ordering cycle, or policy conflict destroys only the
candidate. The last confirmed snapshot continues to resolve input.

## Configuration is staged before it becomes behavior

Racket can freely compose profiles and map contributions because those values
remain candidate configuration. Staging a Racket value is not activation and
cannot alter canonical input state.

Reload crosses one versioned copied boundary. Odin validates the complete
shape, adapts only private storage, compiles a new immutable snapshot, and then
publishes it as one generation. This makes runtime configurability compatible
with deterministic lookup: ordinary input never consults mutable Racket state.

The distinction also gives failure a precise boundary. A Racket exception,
malformed record, stale profile revision, unknown command, allocation failure,
or policy conflict is a rejected candidate rather than a partially installed
configuration. Pending multi-stroke input is cleared only after publication,
so failed reload cannot disturb the current interaction.

Runtime staging is intentionally separate from persistence. A future
configuration loader can produce the same Racket profile values without
changing snapshot ownership or activation semantics.

## Short-lived interaction grammar belongs to its owner

A prompt or UI workflow is not merely a rendering condition around a global
keymap. It has a bounded grammar and a lifecycle. Treating those keys as local
application branches would create a second dispatch system that profile
configuration, future modal editing, and inspection could not explain.

Odra therefore gives each active prompt or UI workflow a native contextual map.
The startup list falls through to global commands because it deliberately
coexists with ordinary editor sequences. Fixed-choice prompts and the Buffer
Menu reject unrelated input because their interaction state admits only a
small response vocabulary. Text-entry prompts use committed text as a semantic
fallback while retaining explicit bindings for acceptance, deletion, and
cancellation.

The owner generation is as important as precedence. A pending multi-stroke
sequence is meaningful only while the same prompt or workflow generation is
alive. Completion, cancellation, invalidation, or replacement clears that
pending state. If storage is reused for a later interaction, the stale handle
cannot affect the new owner.

Transient maps outrank list-tool maps, so a prompt can temporarily take input
while its underlying UI workflow stays alive. When the prompt ends, the
workflow continues through the same semantic resolver. This nesting avoids
rebuilding the programmable profile and avoids hiding raw input rules inside
the application coordinator. The precedence enum remains named
`Component_Tool` for compatibility, but no component presentation owner
remains.

## Provenance is part of behavior

Layered resolution without attribution would merely move hard-to-find
conflicts into a more elaborate data structure. The compiled model retains
stable profile and map identities, precedence, priority, source metadata,
binding operations, remaps, and lower alternatives.

That retained information supports questions such as which map won,
which binding it shadowed, why a sequence is masked, and which source declared
the effective command. Inspection is therefore a consumer of the resolver
model, not a separate reconstruction from mutable configuration.

Inspection copies a bounded result from one immutable snapshot. This makes an
explanation stable after the live profile changes and avoids retaining native
resolver storage across Racket or frontend work. A query that would exceed the
configured alternative limit fails explicitly instead of presenting a
plausible but incomplete answer.

The visible inspection list is only a projection. Winner selection,
shadow classification, protection, pending state, generations, and rejection
context come from the same native model that handles input. Racket can compose
the copied records, and another frontend can render them differently, without
acquiring canonical input state or redefining precedence.

## Command navigation is registry navigation

An extensible runtime can contain many Racket procedures that are helpers,
constructors, adapters, or internal implementation details. Treating every
callable procedure as an editor command would erase admission contracts and
make discovery depend on language internals.

Odra therefore navigates the checked command registry. A definition opts into
interactive discovery and declares its requirements, effects, provider,
description, and provenance. The catalog can list native and Racket commands
uniformly without exposing either an Odin procedure address or a Racket
closure. Selection produces a checked command identity and returns to the
ordinary dispatcher.

Availability belongs in the catalog because discovery and execution have
different jobs. A region command remains worth discovering when no region is
active, but executing it must still fail admission. Showing the missing
requirement teaches the command model without weakening the invariant.

Complete active binding sequences are reinforcement rather than identity. A
reader can learn `C-x C-c` or recognize that a useful command is currently
unbound, while the navigator remains correct after remaps and profile changes.
The displayed notation is derived from normalized strokes; it is never
replayed to execute the selection.

The navigator itself is another lifetime-owned workflow. Its candidate session
owns bounded query and selection state, its contextual map owns movement and
text-entry routing, and `C-g` retires those owners before restoring the primary
view. Registry and snapshot generations prevent a catalog captured before
profile replacement from authorizing a later invocation.

See the [Contextual Keymap Reference](../../reference/contextual-keymaps/index.md)
for exact contracts, limits, failures, and validation commands, and
[Configure a Runtime Keymap Profile](../../how-to/configure-keymaps/index.md)
for the construction workflow.
