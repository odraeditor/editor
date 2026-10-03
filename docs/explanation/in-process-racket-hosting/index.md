<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Odin Hosts Racket

Odra combines two languages because they solve different problems. Odin owns
the editor's canonical, performance-sensitive data plane. Racket supplies a
programmable control plane for commands, keymaps, policy, configuration, and
composed providers. The boundary is useful only while those roles remain
explicit.

## The delivered shape

```text
One Odin process
  |
  +-- Odin: canonical editor state, active registries, resources, validation,
  |         transaction publication, rendering, and runtime lifecycle
  |
  +-- C adapter: Racket CS embedding, exact procedure roots, value conversion,
  |               callback containment, and exception barriers
  |
  `-- Racket: command and keymap definitions, configuration, policy,
              concern facades, provider composition, and operational records
```

Odin starts the executable and embeds Racket CS. Racket returns complete copied
candidates and performs bounded command turns. Odin validates those values and
atomically activates or publishes native state. Neither side maintains a
parallel canonical editor.

This shape now supports more than the initial uppercase-line proof. The rooted
Racket boundary supplies a command catalog, typed interaction profiles,
configuration observations, history and display policy, programmable command
facades, Project and Workspace operations, named state, candidate history, UI
roles, themes, structural operations, and language-service definitions.

## Why programmability is not native ownership

Racket is well suited to text transformation, policy, orchestration, and
composition. A command can inspect bounded copied text, compute a result with
ordinary Racket code, and request a checked native operation. That flexibility
does not require access to rope nodes, renderer storage, process handles, or
publication roots.

The direction is deliberately asymmetric:

1. Odin lends a checked capability for one dynamic extent.
2. Racket receives copied observations and composes a semantic result.
3. The result crosses the adapter as a bounded record.
4. Odin validates identity, generation, authority, resources, and current
   state.
5. Odin alone commits the new canonical generation.

A Racket exception, malformed result, stale capability, or resource failure
therefore cannot partially publish editor state.

## Why commands and keymaps originate in Racket

Command and keymap authoring benefits from symbolic data, composition, and
small declarative definitions. Racket owns the shipped programmable command
catalog and typed interaction-profile candidates. Odin owns the admitted
command registry, keymap resolver, active profile, input state, and execution
route.

This separation gives native and programmable implementations the same
semantic identities. Keymaps name commands rather than procedure addresses or
native entrypoints. Replacing an implementation does not require a parallel
command system or unrelated binding changes.

Registration is explicit. Loading a Racket module does not silently mutate an
active registry. Startup asks Racket for complete catalogs and profiles, then
Odin validates and activates them atomically.

## Why built-ins may use native mechanisms

User extensions provide Racket modules; they do not modify the compiled Odin
core. A built-in provider has a natural implementation advantage when a
capability participates in hot editing or rendering paths, owns operating
system resources, or must remain available when configuration fails.

That advantage is not a reason to move policy indiscriminately into Odin. Odra
uses three placement shapes:

- Racket for policy, orchestration, bounded text work, and extension behavior;
- Odin for canonical state, native resources, deterministic publication, and
  measured hot paths; and
- a composed provider when Racket should retain policy while Odin supplies one
  bounded mechanism.

Built-in and extension providers still occupy the same semantic role when the
role is replaceable. A native implementation does not require a second full
Racket implementation merely for symmetry.

## Why capabilities are integers

A raw pointer would make lifetime and reuse errors indistinguishable from valid
access. It could also expose native storage across a moving-GC boundary.

A capability token instead names a registry, slot, and generation. Odin
resolves it for every operation. Releasing and reusing a slot changes the
generation, so an old token cannot silently resolve to a later resource. The
token reveals nothing about a buffer address or internal storage layout.

The shared scoped transport additionally checks capability kind, opaque domain
token, owner thread, active generation, reentrancy, and dynamic extent before a
concern callback sees input.

## Why crossings are coarse and bounded

The original text-transform proof used two explicit Racket calls: one to
request a bounded range and one to return a proposed replacement. That proof
established the enduring rule, not the final feature set.

Current concern facades use copied fixed records and bounded trailing data.
They do not call Racket per character, syntax cell, or rendered terminal cell.
All foreign execution finishes before native publication starts. This keeps
allocation, latency, failures, and retained storage measurable without
removing Racket from semantic command composition.

## Why a C adapter exists

Odin calls C-compatible functions, while Racket CS exposes a C embedding API
and uses C macros and headers for low-level value operations. The adapter boots
Racket, instantiates one explicit boundary module, roots an exact procedure
table, converts fixed values, installs one scoped callback, contains Racket
exceptions, and copies results.

The adapter contains no editor policy. It does not define commands, choose
keymaps, own operational records, or publish editor state. Keeping it narrow
limits the code that must reason about both Odin ABI rules and Racket GC rules.

## Why Racket is not the top-level process

The rejected hosting candidate ran Racket first and loaded Odin as a shared
library. It passed correctness and provisional performance gates, and its
scalar crossing was faster. It was not selected because it reversed the
accepted ownership model:

- Racket would own top-level startup and shutdown;
- Odin readiness would depend on Racket-controlled bootstrap;
- native cleanup would depend more on custodian and library-unload behavior;
  and
- the programmable layer could outlive or prematurely release editor
  resources.

Lower scalar latency did not outweigh those lifecycle costs. The selected
direction keeps startup, failure, and shutdown under the same native owner as
canonical editor state.

## Why operational records are Racket modules

Project discovery, Workspace composition, saved locations and slots,
candidate usage, and migration journals use constrained Racket records. The
format does not turn them into executable user configuration. Domain modules
decode only admitted data shapes and own their semantics, validation, paths,
and recovery policy.

Shared storage modules provide deterministic record encoding, generation and
catalog mechanics, and one durable staged-publication primitive. They do not
become a second domain owner. The `.odra/` record in a Project remains local
identity; user-level state under the configuration root supports discovery and
cross-Project features without scanning the filesystem.

## Why shutdown rejects retained capabilities

Racket may retain an opaque scalar wrapper, but that wrapper does not own the
native resource. Odin must release capabilities explicitly.

If shutdown accepted live capabilities, cleanup would have to guess whether to
invalidate, leak, or silently release native references. Coordinated shutdown
instead fails while capabilities remain live. The caller releases them, then
shutdown retries in a defined order. Racket garbage-collection timing is never
a native lifecycle contract.

## What the measurements mean

The original reference measurement placed an ordinary command turn well below
the provisional 10 ms p95 gate while leaving zero tracked native temporary
bytes. Forced full Racket collection raised latency into tens of milliseconds
but retained deterministic results and zero tracked native bytes after
cleanup.

Those measurements justify coarse crossings and explicit ownership. They do
not justify moving every command into Odin. Native placement requires a
concrete lifecycle, ownership, startup, safety, or measured performance reason.

## Current extension boundary

The architecture now has deliberate seams for programmable commands, typed
keymaps, configuration, and composed providers. Personal `init.rkt` loading
currently validates and transfers a bounded module proposal; it does not yet
constitute a general package, hook, mode, or REPL system. Those extension
surfaces require their own stable contracts before activation.

For exact module ownership, initialization, declarations, and failure mapping,
see the
[`Racket Runtime Boundary Reference`](../../reference/racket-runtime-boundary/index.md).
Provider placement follows the
[`Native and Programmable Provider Pattern`](../../../ops/default/spec/stable/native-and-programmable-provider-pattern.md).
