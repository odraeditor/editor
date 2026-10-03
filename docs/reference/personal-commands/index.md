<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Personal Commands Reference

Personal commands are named Racket procedures selected explicitly by personal
configuration and admitted into the same command registry, command navigator,
keymap resolver, transaction system, and inspection surfaces as factory
commands.

## Public modules

Personal configuration imports only these logical modules:

| Module | Responsibility |
| --- | --- |
| `odra/commands` | Command definitions, execution limits, context inspection, text edits, cancellation, and explicit rejection. |
| `odra/keymaps` | Typed key sequences, bindings, maps, profiles, and provenance. |

Hosting modules, native contracts, registries, and bridge procedures are not
public configuration APIs.

## Embedded authoring compatibility

The currently verified embedded authoring surface includes core forms such as
`define`, `lambda`, `if`, and `let`; ordinary `racket/base` procedures; module
composition through `require` and `provide`; and the public Odra APIs.

Macros that require additional transformer-phase modules are not yet a
guaranteed part of that surface. In particular, `for/list` currently causes a
namespace rejection in a modular personal configuration, while the equivalent
runtime composition with `map` is accepted. Treat other non-core macros as
unverified rather than inherently unsupported.

This is an embedded module-loading limitation, not a command admission or
resource policy. A candidate rejected for this reason leaves the last confirmed
generation active. Use `reload-personal-commands` after replacing the affected
form with core syntax, runtime procedures, or explicit recursion.

## Command definition

`make-command` accepts a lowercase hyphenated symbol or string and a procedure
of exactly one argument. It returns an immutable command definition; it does
not register the command.

```racket
(make-command
 'uppercase-line
 uppercase-line
 #:description "Uppercase the current line."
 #:interactive? #t
 #:requirements '(active-buffer)
 #:effects '(buffer view text-mutation)
 #:source "modules/text-commands.rkt"
 #:location "")
```

The procedure receives one opaque command context. Definitions may require an
active buffer, document, or region. The initial effect set admits buffer and
view access plus text mutation. A definition cannot replace a factory command
or claim an unsupported effect.

`odra-personal-commands` is the sole command contribution exported by personal
configuration. Its value is a proper list of definitions. Loading a module or
constructing a definition does not activate it unless `init.rkt` exports that
list.

## Command context

| Procedure | Result |
| --- | --- |
| `command-context-point` | Opaque point for the current revision. |
| `command-context-active-region` | Opaque ordered region or `#f`. |
| `command-context-current-line` | Opaque current logical line range. |
| `command-context-buffer-range` | Opaque complete-buffer range. |
| `command-context-word-at-point` | Current bounded lexical token or `#f`. |
| `command-context-jan-value-at-point` | Current Jan metadata, link, citation, URL, or lexical value range. |
| `command-context-resolve-value` | Region, value-at-point, then caller-supplied interactive input resolution. |
| `command-context-read` | Immutable Racket string copied from one admitted range. |
| `command-context-replace!` | One transaction-backed range replacement. |
| `make-text-edit` | One copied replacement proposal for a batch. |
| `command-context-replace-batch!` | One sorted, non-overlapping replacement batch. |
| `command-context-cancelled?` | Current cooperative cancellation state. |
| `command-context-abort!` | Abort the private transaction. |

Contexts, positions, ranges, and edits are bound to one owner thread, one
revision, and one dynamic command turn. They become unusable after the turn,
after mutation makes copied text stale, or after a generation replacement.

`command-context-resolve-value` returns a copied contextual value with its
`region`, `point`, or `interactive` source. A source-backed value retains its
exact revision-bound range. The optional `#:at-point` procedure selects the
language resolver; Jan commands use `command-context-jan-value-at-point`.
`#:interactive-value` accepts input already collected by an editor-owned
interaction and is used only when neither a region nor a value at point is
available. The default maximum value size is 4 KiB.

`void`, `command-reject`, a bounded command candidate result, and a direct
navigation result are valid command results. `make-command-candidate` copies
one semantic label, searchable fields, document path, exact byte range, and
source revision.
`make-command-candidate-result` groups up to 256 uniquely identified candidates
with an initial query. Odra presents that result through its ordinary candidate
session; filtering, movement, activation, and cancellation remain editor-owned.
Candidate actions may navigate, resume with the candidate identity, resume with
one selected value after clearing the initiating region, or resume with the
candidate query as editor-collected interactive input. Every resumption
revalidates the initiating document, revision, point, and region first.

`make-command-navigation-result` returns one semantic label, document path,
exact byte range, and source revision for immediate navigation. Odra opens the
document through its ordinary session workflow without presenting a redundant
one-item selector. The package declares the destination but does not receive
direct editor or session access.

An exception, unsupported result, cancellation, stale value, limit failure, or
explicit abort prevents canonical publication. Candidate activation revalidates
the copied session generation and target range before navigation and does not
mutate the source document.

## Default execution limits

`default-personal-command-limits` contains the measured production profile:

| Resource | Default maximum |
| --- | ---: |
| Elapsed execution | 2,000 ms |
| Racket custodian memory | 128 MiB |
| Copied inspection text | 8 MiB |
| Replacement text | 8 MiB |
| Splices per batch | 4,096 |
| Temporary native transaction memory | 32 MiB |
| Nested editor operations | 8 |
| Diagnostic text | 4 KiB |

`make-personal-command-limits` creates a smaller profile through the
corresponding keyword arguments. `make-command` accepts that profile through
`#:limits`. Personal configuration may reduce a ceiling but cannot exceed a
personal or native maximum.

Every invocation runs under one command-owned custodian and deadline. Threads
created during the admitted turn are closed when the turn completes. Native
transaction limits independently bound retained text, splice count, temporary
memory, and nested operations. This is resource containment for trusted
personal code, not process isolation.

## Registration and activation

Odra evaluates `init.rkt` once per candidate generation. It collects
`odra-personal-commands` and the optional `odra-interaction-profile`, validates
their complete command and binding relationship, reserves native storage, and
publishes both owners atomically.

`reload-personal-commands` repeats that process without restarting the editor.
A successful reload changes additions, removals, implementations, and bindings
together. An empty command export with no personal profile deactivates personal
commands. A rejected candidate leaves the prior confirmed generation active.

Retired procedures remain rooted only while an admitted old turn is still
executing. Old routes and contexts reject later use. Shutdown closes active and
retiring roots, command custodians, and inspection state.

## Inspection and diagnostics

Personal definitions appear in `M-x` with their semantic command name,
description, logical provenance, availability, and effective binding.
`describe-key`, `where-is`, `describe-bindings`,
`describe-keymap-conflicts`, and `describe-keymap-state` inspect the shared
registry and keymap state.

The personal inspection snapshot also retains active and rejected generation
identities, resource use from the last command turn, the latest bounded
rejection, and factory recovery availability. Inspection removes terminal
control content and does not expose absolute home paths.

## Recovery

Startup or reload rejection preserves factory command navigation and protected
cancellation. Fix `init.rkt` or one of its selected modules, then invoke
`reload-personal-commands`. A malformed reload does not require restarting the
editor and does not replace the last confirmed command behavior.
