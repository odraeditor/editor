<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Theme System Reference

The `theme` package owns complete frontend-independent style definitions,
provider and definition generations, one session-wide selection, maintained
factory fallback, color-minimal safe baseline, resource accounting, and exact
cleanup.

This reference describes the native registry, the copied Racket capability,
and application presentation through the active session selection.

## Ownership

```text
semantic UI.Style_Role
          |
          v
immutable theme Definition
          |
          v
one session Selection
          |
          v
logical UI publication -> terminal profile lowering
```

`theme` imports the semantic style vocabulary from `ui`. The UI package does
not import theme provider lifecycle, choose a theme, or interpret theme
identity. Syntax providers continue to publish semantic roles only. The
terminal remains the sole owner of true-color, indexed, basic, and monochrome
lowering.

`Registry` is a non-copyable owner. `Provider_Handle` and `Definition_Handle`
contain registry, provider, definition, and exact generation identity without
native pointers. `Definition_View` borrows immutable copied styles only until
the next registry mutation.

## Session ownership and resolution

One application `Command_Context` owns one factory-initialized `Registry` for
the complete editor session. Initialization selects `Wrocław Night`; orderly
command-context teardown closes the registry after the last use. Theme state is
not global, buffer-owned, pane-owned, or persisted between sessions.

Every application UI proposal resolves exactly one complete theme definition
before adding content and decorations. Resolution reads the pending transition
target when a transition is being presented and otherwise reads the registry's
active definition. The resolver validates that the definition contains each of
the 32 current roles exactly once before copying the styles into the proposal.
Missing, duplicate, or unknown roles reject the proposal without publishing a
partial style set.

Application routes do not assemble independent style tables. Startup, editor
views, buffer and project inventories, candidate and keymap surfaces, and
language-state surfaces all use the same session resolver. Calls without a
command context use the maintained factory fallback definition so recovery
presentation never depends on an unowned registry.

The terminal renderer applies the resolved `Text_Normal` style before clearing
the frame, so its background covers the complete canvas rather than only cells
containing text. Surfaces without `Text_Normal` fall back through their normal
list, status, or diagnostic style. Row erasure occurs after the row style is
active, preserving the same guarantee for lists and prompts.

## Factory identities

The maintained family follows one daylight order. The safe baseline is
separate from that four-theme family.

| Order | Identity | Display name | Profile | Background |
| ---: | --- | --- | --- | --- |
| 1 | `wroclaw-sunrise` | `Wrocław Sunrise` | muted solarized light | `#B0DEF3` |
| 2 | `wroclaw-morning` | `Wrocław Morning` | bright clear light | `#F7FDFD` |
| 3 | `wroclaw-sunset` | `Wrocław Sunset` | warm golden-hour light | `#F3EBDD` |
| 4 | `wroclaw-night` | `Wrocław Night` | deep navy-black dark | `#1A1B26` |
| - | `terminal-default` | `Terminal Default` | terminal defaults and attributes | inherited |

`Wrocław Night` is the startup selection and maintained failure fallback.
`Terminal Default` is selected when the theme capability is explicitly
disabled. Runtime selection is session-wide and is not persisted by this MVP.

The Wrocław palettes are the accepted initial approximation derived from the
reference photographs. Later palette refinement may change maintained color
values without changing these public identities or native contracts.

## Maintained palette data

Factory definitions use the following exact semantic palette tokens. Every
colored foreground/background pair meets the maintained 4.5:1 contrast
threshold. Selection foreground uses the theme background token.

| Theme | Foreground | Muted | Red | Green | Yellow | Blue | Magenta | Cyan | Selection background |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Sunrise | `#1A202C` | `#525A5E` | `#7C544B` | `#1E4051` | `#65433A` | `#3C5985` | `#465E8B` | `#2C6080` | `#1E4051` |
| Morning | `#1A1F25` | `#68706F` | `#814022` | `#53591E` | `#6C5811` | `#335AA7` | `#4C5C92` | `#3074A9` | `#2B3C67` |
| Sunset | `#11130E` | `#6A6866` | `#83440A` | `#47280C` | `#6C4901` | `#374670` | `#574380` | `#6C5E97` | `#493E61` |
| Night | `#D6D6B3` | `#848587` | `#B47745` | `#B2A44B` | `#BFBB40` | `#5981E3` | `#78A0FA` | `#51B6F5` | `#D5924F` |

The same token-to-role mapping applies to all four colored definitions:

| Roles | Foreground token | Background token | Attributes |
| --- | --- | --- | --- |
| `Text_Normal`, `List_Normal`, `Syntax_Operator`, `Syntax_Variable` | Foreground | Background | none |
| `Text_Region` | Background | Selection background | bold |
| `List_Current` | Background | Selection background | none |
| `Text_Search_Current` | Background | Selection background | bold, underline |
| `List_Emphasis` | Cyan | Background | bold |
| `List_Mark_Save` | Green | Background | bold |
| `List_Mark_Kill` | Red | Background | bold |
| `Status_Normal`, `Syntax_Punctuation` | Muted | Background | none |
| `Status_Active` | Background | Selection background | bold |
| `Diagnostic_Normal`, `Syntax_Attribute`, `Syntax_Boolean`, `Syntax_Number` | Yellow | Background | none |
| `Diagnostic_Rejected` | Red | Background | bold, underline |
| `Syntax_Comment` | Muted | Background | dim |
| `Syntax_Constant`, `Syntax_Function_Builtin`, `Syntax_Type` | Cyan | Background | none |
| `Syntax_Constructor`, `Syntax_Function` | Blue | Background | none |
| `Syntax_Keyword` | Magenta | Background | bold |
| `Syntax_Label`, `Syntax_Variable_Parameter` | Red | Background | none |
| `Syntax_String` | Green | Background | none |

`Terminal Default` leaves every foreground and background absent. It preserves
distinction through reverse on region and current-list roles, reverse plus
underline on the current search role, reverse on active status, bold or
underline on list marks, bold on list emphasis, bold plus underline on rejected
diagnostics, dim on comments, and bold on keywords.

## Definition contract

One `Definition_Proposal` borrows:

- one lowercase ASCII machine identity using letters, digits, and internal
  hyphens;
- one UTF-8 display name;
- one UTF-8 provider name;
- one UTF-8 provenance description; and
- exactly one valid `ui.Style_Definition` for every current `Style_Role`.

The current vocabulary contains 27 valid roles. Unknown roles, duplicate
roles, missing roles, noncanonical optional colors, invalid text, oversize
fields, insufficient monochrome distinctions, proposal overflow, duplicate
identities, and retained-data overflow reject the complete proposal.

A confirmed definition is immutable. Replacement copies one complete new
generation, validates it against the exact current selection, and publishes
the new definition handle only after every check passes. Factory definitions
cannot be replaced through the admitted-provider operation.

## Registry lifecycle

`theme_registry_init_factory` copies the factory provider, four Wrocław
definitions, and safe baseline into one registry allocation. It selects
`Wrocław Night` as both active definition and fallback.

| Operation | Contract |
| --- | --- |
| `theme_registry_propose` | Copies one complete inactive Racket-source definition against an exact registry generation. A new provider name creates one confirmed admitted provider. |
| `theme_registry_confirm` | Advances one exact proposed definition to a new confirmed generation. |
| `theme_registry_select` | Selects one exact confirmed generation against the complete expected `Selection`. |
| `theme_registry_replace` | Validates, confirms, and selects one complete new generation atomically. |
| `theme_registry_restore` | Selects the maintained `Wrocław Night` fallback. |
| `theme_registry_select_baseline` | Selects `Terminal Default` without removing required roles. |
| `theme_registry_fail_provider` | Releases that provider's definitions and restores fallback when it was active. |
| `theme_registry_close_provider` | Restores fallback first when needed, then releases admitted provider state. |
| `theme_registry_close` | Releases the registry allocation and invalidates every handle exactly once. |

Registry and selection generations are nonzero monotonic `u64` values.
Exhaustion rejects rather than wrapping. Rejected operations preserve the
active handle, both generations, occupancy, and retained-byte accounting.

## Atomic application publication

Application selection changes use one pending transition containing the exact
expected `Selection`, resolved target definition, current UI root, and complete
renderer profile. Select, restore, safe-baseline, and active-provider failure
transitions follow the same order:

1. validate the exact current selection and confirmed target;
2. retain the current root and renderer profile as transition preconditions;
3. build and present one complete UI generation with the target definition;
4. commit the native registry mutation only after presentation succeeds; and
5. clear the pending transition.

The native active selection therefore remains unchanged while the candidate
frame is prepared and written. A stale selection, changed UI root, changed
renderer profile, invalid target, generation exhaustion, proposal failure, or
terminal presentation failure aborts the transition. After a failed candidate
presentation or failed registry commit, the application republishes the prior
active definition. No successful theme change can expose a new native
selection with an old frame or a new frame assembled from a partial definition.

## Interactive commands

`select-theme` is a canonical native command available through `M-x` without
an initial direct-profile binding. It builds one shared candidate session from
every confirmed factory or admitted definition. Candidate rows contain the
display name, stable identity, provider, and active, fallback, baseline, or
available state. Filtering searches the display name, identity, and provider.

Accepting a candidate checks the captured registry generation, selection
generation, and immutable definition handle before beginning the atomic
application transition. `Control-G` cancels without mutation. A stale or
unavailable candidate remains contained and preserves the prior selection.

`describe-theme` is a canonical native command that copies registry,
selection, active definition, fallback, baseline, provider, usage, limits,
latest rejection, and every active style into a read-only shared list. Summary
rows identify the current lifecycle state and renderer profile. Per-role rows
report frontend-independent colors and attributes plus the exact value lowered
for the active renderer capability. Up and Down navigate; `q` or `Control-G`
returns to the primary view.

## Inspection and accounting

`theme_registry_selection` copies the exact registry ID, registry generation,
selection generation, disposition, active definition, fallback, and baseline.
`theme_registry_provider` copies one provider descriptor.
`theme_registry_definition` and `theme_registry_definition_by_name` return a
descriptor plus a borrowed immutable style slice.

`theme_registry_inspect` copies selection, limits, current usage, and the
latest rejected operation. Usage reports live providers, live definition
generations, logical retained definition bytes, copied inspection bytes, peak
preparation bytes, hosted operations, and hosted turns. Factory and admitted
definitions use the same logical byte formula: copied identity, display name,
provider name, provenance, and style records.

## Resource limits

| Resource | Limit |
| --- | ---: |
| Live providers | 64 |
| Live definition generations | 64 |
| Theme identity | 96 bytes |
| Display name | 96 bytes |
| Provider name | 96 bytes |
| Provenance | 256 bytes |
| Styles in one definition | every current valid role, at most 64 |
| Aggregate retained definition data | 1 MiB |
| Complete proposal | 64 KiB |
| Operations in one hosted turn | 64 |
| Complete copied inspection | 1 MiB |
| One preparation operation | 8 MiB |
| Diagnostic text | 4 KiB |
| Concurrent hosted turns | 1 |

Callers may lower limits while preserving the compiled relationships. They
cannot raise a limit beyond its compiled ceiling.

## Failures and preservation

`Failure` contains operation, stable code, provider and definition handles,
and optional limit and actual values. Codes distinguish invalid, closed,
wrong-registry, stale, duplicate, incomplete, unconfirmed, immutable,
over-limit, exhausted-generation, allocation, and busy conditions.
`failure_code_diagnostic` maps every code to deterministic English text.

Validation and capacity failures occur before mutation. Provider failure and
teardown remove only the owned admitted definitions. Registry close releases
the single registry allocation; no theme owns a UI root, terminal state, or
document resource.

Application failures preserve the same boundary. Theme access reports the
exact theme operation and stable failure code. UI preparation reports stale
roots, incompatible renderer profiles, invalid definitions, limits, and
allocation failures through its own failure record. Physical write and flush
failures remain terminal failures. A failed admitted provider that was active
is presented through the maintained factory fallback before that fallback is
committed as the native selection.

## Precedence and renderer degradation

Theme resolution changes style definitions, not decoration ordering. Terminal
presentation continues to apply current search, active region, syntax, and
`Text_Normal` in that fixed precedence. Each winning semantic role obtains its
complete style from the one resolved theme definition.

Ksawery uses the same semantic presentation path for Status, History, revision
inspection, ranges, commit composition, amend confirmation, Refs, Process
inspection, push confirmation, local branch or tag confirmation, Sequence,
Conflict, merge and rebase confirmation, ordered-revision confirmation, manual
bisect confirmation, and conflict-resolution confirmation.
Repository identity, headings, primary subjects, secondary metadata, graph
structure, working-tree layers, current `HEAD`, local and remote-tracking
branches, tags, remotes, tracking relationships, confirmation warnings,
selection, marks, and operation outcomes remain separate logical meanings
before the renderer lowers them. A theme can change their presentation but
cannot change repository identity, authorize a Git operation, or make a
history rewrite or remote publication safe.

Compact active-process progress uses `Status_Active`. A successful terminal
outcome uses `Status_Normal`, cancellation uses `Diagnostic_Normal`, and failed,
timed-out, or indeterminate outcomes use `Diagnostic_Rejected`. Process detail
continues to use ordinary selection, operation, and failure semantics; theme
color never changes cancellation availability or outcome classification.

Contributed Ksawery Status sections use the same `normal`, `muted`, `identity`,
`active`, `success`, `warning`, `alert`, and `information` semantic vocabulary
as native presentation. Repository annotations may additionally declare
`none`, `hint`, `information`, `warning`, or `error` severity. Odra maps these
values to maintained theme roles only after validating the complete provider
and observation generation.

Provider labels, detail, severity, explicit truncation text, and stable
ordering remain available without color. Extensions cannot supply terminal
colors, attributes, cells, row coordinates, or renderer callbacks; cannot
hide or reorder core Status groups; and cannot alter core selection or action
availability through style. Empty, stale, disabled, rejected, or failed
provider output is omitted while the built-in semantic presentation remains
active.

The terminal remains the only component that lowers logical colors. One theme
definition is presented through the immutable renderer profile as true color,
indexed 256 color, basic 16 color, or monochrome. Indexed profiles choose the
nearest supported palette entry deterministically. Monochrome omits colors but
retains abstract attributes, so every maintained definition preserves the
required non-color distinctions. Theme selection never changes the renderer
profile and a profile mismatch during a pending transition rejects the
transition instead of changing degradation policy mid-frame.

## Programmable capability

`call-with-theme-control` lends one opaque `theme-control` value to one
synchronous Racket turn. The value is valid only on the owner thread and only
within that call's dynamic extent. Calls are non-reentrant. The adapter clears
the callback, token, caller storage, and locked Racket procedure references
before returning after success, rejection, escape, or exception.

The Racket facade exposes immutable copied values for colors, styles, provider
and definition handles, scopes, usage, limits, providers, definitions,
diagnostics, snapshots, proposals, outcomes, and failures. It exposes these
operations:

| Procedure | Native operation | Required access |
| --- | --- | --- |
| `theme-current-scope` | copy the exact current scope | scope bootstrap |
| `theme-inspect` | inspect the complete registry | inspect |
| `theme-inspect-definition` | inspect one exact definition generation | inspect |
| `theme-propose` | admit one inactive complete definition | propose |
| `theme-confirm` | confirm one proposed definition generation | confirm |
| `theme-select` | select one confirmed definition generation | select |
| `theme-replace` | replace and select one immutable generation | replace |
| `theme-restore` | select the maintained fallback | restore |
| `theme-select-baseline` | select the color-minimal safe definition | select baseline |
| `theme-teardown` | release one admitted provider and its definitions | teardown |

Every operation after scope bootstrap returns the refreshed registry and
selection scope. Requests carry the exact expected registry, selection,
provider, and definition generations. Stale or wrong-registry requests reject
without mutation. Proposal text and styles are copied before native validation;
inspection and outcome data are copied before control returns to Racket.

### Copied record widths

| Record | Bytes |
| --- | ---: |
| Scope | 144 |
| Usage | 56 |
| Limits | 112 |
| Snapshot header | 360 |
| Provider | 64 |
| Definition | 112 |
| Style | 80 |
| Proposal header | 264 |
| Outcome | 264 |
| Diagnostic | 96 |

The startup schema publishes every width, operation, access code, enum value,
semantic style role, attribute bit, resource ceiling, and stable failure code.
Racket refuses startup when any generated schema value differs from the native
manifest.

### Containment and recovery

One turn admits at most 64 operations, one 64 KiB proposal, one 1 MiB copied
inspection, and one concurrent hosted call. Invalid record widths, malformed
UTF-8, invalid enums, incomplete style maps, stale scopes, and over-limit
requests are contained at the boundary. A Racket exception after selecting an
admitted provider marks that provider failed, removes its definitions, and
restores `Wrocław Night`. Explicit restore, safe-baseline selection, and
provider teardown return complete refreshed outcomes.

No Racket value owns a native pointer, registry allocation, UI root, renderer,
terminal resource, or application selection. Racket operations use the exact
scoped theme capability and its native registry contracts. The application
does not yet expose those operations through a user-facing theme workflow;
application-facing selection enters through the pending atomic transition
boundary described above.

## Validation

Use the focused native gates while changing this contract:

```sh
make theme-reference-test
make theme-equivalence-test
odin test src/theme -vet -warnings-as-errors
odin test src/ui -vet -warnings-as-errors
raco test src/hosting/theme-bridge.rkt
make hosting-test
make terminal-presentation-test
make docs-check
```

`tests/theme_reference` is an independent lifecycle and resource model.
`tests/theme_equivalence` compares its factory, proposal, confirmation,
selection, replacement, restoration, and baseline transitions with the
production registry. Package tests generate role-completeness checks and cover
contrast, duplicate and invalid data, limits, fallback, allocation failure,
accounting, stable diagnostics, and teardown. Hosting and command tests cover
generated proposals, every programmable lifecycle operation, stale and
malformed requests, operation limits, owner-thread enforcement, reentrancy,
dynamic-extent escape, exceptions, fallback recovery, allocation faults, and
cleanup.
The application tests cover factory startup ownership, complete role
resolution, pending target presentation, atomic commit, stale selection and UI
state, provider-failure fallback, renderer degradation across every maintained
definition, rollback, and deterministic teardown. The PTY scenarios verify the
selected theme together with search, region, and syntax precedence.
