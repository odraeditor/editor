<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Contextual Keymap Reference

This reference describes the layered keymap, programmable Racket profile,
copied native boundary, transactional activation, and runtime contextual-map
contracts. The factory terminal profile keeps its existing visible bindings.

## Identities and generations

Every durable or runtime-scoped value is checked independently.

| Value | Identity | Revision or generation |
| --- | --- | --- |
| Command registry | `Registry_Generation` | One immutable registry generation |
| Interaction profile | `Profile_ID` | `Profile_Revision` |
| Keymap | `Map_ID` | `Map_Revision` |
| Interaction context | `Context_ID` | `Context_Generation` |
| Context owner | `Owner_ID` | `Owner_Generation` |
| Compiled snapshot | `Snapshot_Generation` | Bound to registry, profile, and context identities |

Map identity is independent of declaration order, module load order, compiled
array position, and snapshot allocation. A contextual map is active only when
its complete checked context and owner handles match the active context.

## Precedence classes

Active maps resolve from highest to lowest precedence:

1. `Protected_Recovery`
2. `Transient_Interaction`
3. `Component_Tool`
4. `Buffer_Local`
5. `Language_Context`
6. `Project`
7. `User_Global`
8. `Profile_Base`
9. `Factory_Fallback`

Source and precedence are separate metadata. A user-authored language map is
still a language-context map; it does not become globally stronger merely
because its provider is user configuration.

Maps in the same class use descending declared priority and stable map
identity. `Before` and `After` constraints refine that order. Unknown targets,
cross-class constraints, cycles, and colliding equal-priority maps without an
explicit relation reject candidate compilation. Module load order is never a
tiebreaker.

## Binding operations

`Layered_Binding_Definition` stores a complete `Key_Sequence`, a semantic
command name, an operation, and source provenance.

| Operation | Meaning |
| --- | --- |
| `Bind` | Add a previously absent sequence to the derived map. |
| `Replace` | Replace an entry already declared in the same derived map. |
| `Unbind` | Remove an entry already declared in the same derived map. |
| `Mask` | Claim the sequence without a command and block lower maps. |

An ordinary duplicate is rejected. A replacement or unbind without an
existing entry is rejected. After derivation, one map cannot contain an exact
binding that is also a strict prefix of another sequence.

`Command_Remap_Definition` redirects a semantic command identity. The
highest-precedence active remap for the resolved command wins; the remap does
not encode or search for another physical key sequence.

## Resolution

`profile_snapshot_compile` performs the complete candidate operation:

1. validate registry, profile, context, owner, map, provenance, and policy;
2. account for copied definition bytes and selected capacities;
3. order maps and reject invalid constraints;
4. derive each map's bindings and compile command identities;
5. validate same-map prefixes, same-class conflicts, remaps, and protected
   overlap;
6. retain one private immutable candidate; and
7. replace the active snapshot only after every check succeeds.

Resolution examines active maps in precedence order. The first map that
defines the accumulated sequence as exact, prefix, or mask owns the result.
A higher prefix therefore produces pending input even when a lower map has an
exact command for the same strokes. Lower definitions remain retained for
later inspection work.

Text commits remain separate from logical key strokes. When no active keymap
claims the input, the checked native text fallback preserves the direct
profile's current insertion behavior.

## Protected recovery map

The Odin-owned `protected-recovery` map has identity
`0xffff_ffff_ffff_fffe@1`, uses `Protected_Recovery` precedence, and contains
exactly these accepted entries:

| Sequence | Command | Reason |
| --- | --- | --- |
| `C-g` | `keyboard-quit` | Cancel active interaction or recover from pending input and active selection. |
| `M-x` | `execute-extended-command` | Preserve access to registered interactive commands and active bindings. |

The compiler inserts this map independently of ordinary profile maps. Any
ordinary definition or contextual interception that would shadow, mask, or
reinterpret either sequence fails with `Protected_Binding`. A frontend whose
declared logical-input capabilities cannot produce either sequence fails with
`Unsupported_Protected_Input`.

Protection applies only to the two complete normalized sequences. It does not
protect aliases; in particular, `C-x C-c` is configurable.

## Runtime contextual maps

`Context_Map_Stack` owns the runtime overlays used by prompts, shared UI lists,
and candidate roots.
It is initialized against one exact command-registry generation and retains at
most eight simultaneously active maps with at most 128 bindings in each map.
Contextual maps are compiled into fixed native storage when activated; normal
input resolution does not call Racket or allocate.

Every activation defines a map identity, owner identity, precedence, priority,
bindings, unmatched-input policy, and optional text fallback. The stack
publishes a `Context_Map_Handle` containing the exact map identity, context
generation, owner generation, and slot. Reusing an active identity or owner is
rejected.

Active contextual maps resolve before the immutable global profile snapshot.
The current application owners are:

| Owner | Precedence | Unmatched input | Semantic actions |
| --- | --- | --- | --- |
| Text-entry prompt | `Transient_Interaction` | `Text_Input` | insert text, delete previous, accept, cancel |
| Incremental search | `Transient_Interaction` | `Text_Input` | insert, delete, accept, cancel, repeat forward or backward |
| Query-replacement response | `Transient_Interaction` | `Reject` | replace, skip, replace remainder, replace and exit, quit, cancel |
| Fixed-choice prompt | `Transient_Interaction` | `Reject` | bounded choices and cancel |
| Startup list | `Component_Tool` | `Fallthrough` | previous row, next row, activate current |
| Buffer Menu list | `Component_Tool` | `Reject` | movement, activation, save or kill mark, unmark, execute, close |
| Project list | `Component_Tool` | `Reject` | movement, activation or inspection, close |
| Buffer navigator | `Component_Tool` | `Text_Input` | query text, delete previous scalar, movement, activation or creation, close |
| Project buffer navigator | `Component_Tool` | `Text_Input` | query text, delete previous scalar, movement, activation, close |
| Command navigator | `Component_Tool` | `Text_Input` | query text, delete previous scalar, movement, activation, close |
| Keymap inspection | `Component_Tool` | `Reject` | movement, close, reopen command navigation |

`Transient_Interaction` precedes `Component_Tool`, so a prompt opened from a
list root owns the next turn while the list map remains active beneath it. Once
the prompt ends, list routing resumes without reconstructing the global
profile. `Component_Tool` is the retained precedence name for these contextual
maps; it no longer denotes a component presentation registry.

`context_map_end` records `Completed`, `Cancelled`, or `Invalidated`, removes
the exact owner generation, and clears contextual and base pending sequences.
`context_map_owner_invalidate` performs the same checked cleanup through an
owner handle. A stale handle cannot end or alter a successor that reused its
slot. Closing the stack releases its fixed storage after all application
owners have been invalidated.

## Racket profile API

`src/command/keymaps.rkt` owns immutable Racket values for strokes, sequences,
provenance, bindings, remaps, ordering constraints, maps, and profiles.

The checked operation constructors are `keymap-bind`, `keymap-replace`,
`keymap-unbind`, `keymap-mask`, `keymap-remap`, `keymap-before`, and
`keymap-after`. `compose-interaction-profile` flattens module contributions in
declared order. `stage-interaction-profile!` replaces only the Racket-owned
candidate; it cannot mutate the active native snapshot.

`interaction-profile-candidate` returns the staged value or constructs the
factory direct profile. `clear-staged-interaction-profile!` removes the staged
value. This state is process-local and has no persistence contract.

## Copied profile schema

Schema version `1` is one little-endian batch containing these regions in
order:

| Region | Record width | Selected count bound |
| --- | ---: | ---: |
| Header | 136 bytes | 1 |
| Map | 200 bytes | 128 |
| Binding operation | 88 bytes | 16,384 total; 4,096 per map |
| Semantic remap | 80 bytes | 16,384 |
| Ordering constraint | 16 bytes | 8,192 total; 64 per map |
| Normalized stroke | 24 bytes | 262,144 before the combined byte gate |
| UTF-8 text | Variable | Subject to the combined byte gate |

Every fixed record is pointer-free. Variable strings use checked offsets and
lengths into the final text region. Map records identify contiguous binding,
remap, and ordering ranges; binding records identify contiguous stroke ranges.
The complete batch, including fixed records and text, is limited to 8 MiB.
Individual maxima therefore cannot necessarily be combined.

`keymap_profile_records_validate` checks schema, exact copied width, counts,
ranges, UTF-8, identities, enum domains, provenance, sequence bounds, unique
map identities, ordering targets, and contextual owner shape before native
adaptation.

## Runtime activation

`runtime_load_keymap_profile` performs one bounded Racket call and retains the
result only in private candidate storage. The adapter contains Racket
exceptions, wrong envelopes, oversized batches, unsupported schema versions,
wrong-thread calls, reentrant calls, and allocation failures.

`racket_profile_reload` adapts the validated candidate and calls
`profile_activation_replace`. A successful replacement advances the snapshot
generation, retires the previous compiled owner, and clears generation-bound
pending input. A stale revision or any copy, validation, command, ordering,
policy, or allocation failure preserves the prior generation.

`reload-interaction-profile` is registered as an interactive native command
but intentionally has no factory binding. It is discoverable through `M-x`
and reloads only the current process session; configuration discovery and
persistence remain outside this capability.

## Interactive command catalog

`command_catalog_build` copies one immutable view of every registered
interactive command from an exact command-registry generation and active
resolution snapshot. Noninteractive text fallbacks and contextual helper
commands are excluded.

Each `Command_Catalog_Entry` contains:

| Field | Contract |
| --- | --- |
| `metadata.handle` | Exact checked command identity for one registry generation. |
| `metadata.name` | Stable UTF-8 semantic name, at most 96 bytes. |
| `metadata.description` | UTF-8 description, at most 256 bytes. |
| `metadata.implementation` | `Native` or `Racket`; no implementation pointer is exposed. |
| `metadata.requirements` | Any of active buffer, associated document, and active region. |
| `metadata.effects` | Declared buffer, view, and lifecycle effects. |
| `metadata.provenance` | Provider, source, and optional declaration location. |
| `availability` | `Available` or `Unavailable` for the captured editor context. |
| `unavailable_reason` | Bounded explanation when a requirement is absent. |
| `bindings` | Every complete active effective normalized sequence for the command. |

Catalog storage owns copied metadata, provenance, entries, and sequences until
`command_catalog_close`. It remains valid after the source registry or
snapshot closes, but its identities do not become valid for a replacement
generation.

## Command navigator

The factory profile binds `M-x` to `execute-extended-command`. The command
builds one copied catalog from the current primary view, adapts it into a
`Commands` candidate source, and admits that complete generation to the common
candidate session. The terminal projects the normalized candidate view through
the shared candidate `ListView`, `Input`, and root-edge `StatusRegion`; none is
a second filter, query, selection, or dispatch owner.

The bottom label has this logical form:

```text
Commands [active editor context] 1/42 M-x query
```

It identifies the source and captured editor scope, reports selected and
visible-result counts, and presents the session-owned editable query. Rows are
vertical and the list highlight mirrors the selected candidate identity.
`C-n` or `Down` moves to the next candidate, `C-p` or `Up` moves to the
previous candidate, `Backspace` or `DEL` removes one complete UTF-8 scalar,
`Enter` activates the current row, and `C-g` cancels and closes the session.
Printable input is resolved through the named `component-query-text` command.

Matching is case-insensitive over the canonical command name and copied
description. Whitespace separates bounded components and every component must
match. Literal matching is always admitted; a valid bounded expression may
produce a pattern match, while invalid expression syntax remains literal
input. Exact labels and boundary matches rank ahead of other literal and
pattern-only results.

One projected row has this logical form:

```text
command-name  [M-x, C-x C-c]  [provider]  available  Description.
```

An interactive command with no effective active sequence shows `unbound`. A
command whose context requirements are not satisfied shows `unavailable`
followed by its reason. Sequence notation preserves every normalized stroke;
supported modifier prefixes are `C-`, `M-`, `A-`, and `s-`, multi-stroke
sequences use spaces, and special keys use names such as `RET`, `DEL`, `HOME`,
and `LEFT`.

Selection retains the candidate-session generation, stable source identity,
checked action, command-registry generation, and keymap snapshot generation.
Before execution, the coordinator checks the current registry and profile
generation, reconstructs the exact command handle from the closed action, and
rechecks catalog availability. Available selection restores its primary-view
return target and enters the same ordinary native or Racket dispatch path used
by key resolution. It cannot invoke an arbitrary Racket helper. Process-local
recency is recorded only after that dispatch succeeds; stale, unavailable,
failed, and cancelled interactions do not update it.

The command adapter admits at most the command-catalog ceiling of 2,048
interactive commands. The common session additionally enforces a 4 KiB query,
eight query components, a 4 KiB pattern component, 4,096 visible rows, 32 MiB
of copied source text, and 16 MiB of temporary turn storage. It rejects rather
than truncates. Reaching the query ceiling reports `Command query limit
reached`; a changed interaction profile reports `Interaction profile changed;
reopen M-x`; and an unavailable command reports its copied requirement reason.
Other lifecycle, allocation, malformed-text, and source failures retain their
typed `Candidate_Failure` classification.

The current command source is factory-owned. Extension code may contribute an
interactive command only through bounded command registration; it cannot
install a replacement candidate provider, ranking policy, navigation policy,
or presentation. Durable Project-scoped recency remains outside this slice.

The earlier Racket command-candidate composition facade has been retired.
Programmable code contributes commands through bounded command registration;
Odin then adapts the checked registry and keymap snapshot into the common
candidate-session contract. Filtering, ranking, movement, and dispatch have no
per-source parallel implementation.

## Keymap inspection

Profile, map, binding, remap, and ordering definitions preserve bounded
provider, source, and optional declaration-location metadata. The compiled
snapshot retains map and binding provenance together with the effective map
order and shadowed definitions.

`keymap_inspect` copies one bounded immutable result from the active registry,
profile activation, pending sequence, and query. The caller owns the result
until `inspection_result_close`. Closing or replacing the source snapshot does
not invalidate copied record text.

`Inspection_Query_Kind` supports:

| Kind | Selector | Records |
| --- | --- | --- |
| `Sequence` | Complete normalized sequence | Effective winner and retained shadowed, masked, or inactive alternatives. |
| `Command` | Registered command name | Binding and remap records for the command. |
| `Map` | Positive `Map_ID` | Map metadata followed by its binding and remap records. |
| `Active_Maps` | None | Maps in resolution order. |
| `Bindings` | None | Active binding records in resolution order. |
| `Snapshot` | None | Active identities, pending sequence, and exact usage. |
| `Latest_Rejection` | None | The most recent failed activation context, if present. |

Every `Inspection_Record` identifies its kind and disposition, normalized
sequence, command and remap identities, map identity and name, owner,
precedence, priority, active state, binding operation, provenance, protection
state and reason, or rejection context as applicable. Dispositions are
`Effective`, `Shadowed`, `Masked`, `Inactive`, and `Rejected`.

The registered Racket inspection commands are:

| Command | Query |
| --- | --- |
| `describe-key` | Capture one complete sequence and explain its resolution. |
| `where-is` | Prompt for a registered command and list its active bindings. |
| `describe-bindings` | List every active binding. |
| `describe-keymap` | Prompt for one positive map identifier. |
| `describe-keymap-conflicts` | Show the latest rejected candidate. |
| `describe-keymap-state` | Show active identities, pending input, usage, and rejection state. |

The terminal presents results in a read-only shared `ListView` root. The
workflow retains the complete copied `Inspection_Result` and `Command_Catalog`;
rows format rather than replace sequence, binding, remap, conflict, rejection,
snapshot, map, profile, provenance, availability, and protection records.
`Up` and `Down` move the current row; `q` and `C-g` close it; `M-x` returns to
the captured primary view and reopens command navigation.

`src/command/keymap-inspection.rkt` defines checked immutable request, record,
and result structures plus the six query constructors and
`compose-keymap-inspection`. Racket receives only copied values and cannot
borrow resolver storage or bypass native command admission.

## Selected limits

The initial layered policy was selected by `make keymap-resource-study`.

| Resource | Selected limit |
| --- | ---: |
| Registered interactive commands | 2,048 |
| Maps per profile | 128 |
| Simultaneously active maps | 16 |
| Bindings per map | 4,096 |
| Total layered bindings | 16,384 |
| Strokes per layered sequence | 16 |
| Ordering constraints per map | 64 |
| Complete copied profile batch | 8 MiB |
| Retained compiled snapshot | 32 MiB |
| Inspection alternatives per query | 64 |
| Navigator query | 96 UTF-8 bytes |
| Navigator rows | 2,048 |
| Navigator retained row text | 4 MiB |
| Inspection presentation rows | 64 |
| Inspection presentation row | 4 KiB |

The resource study exercises an ordinary profile with 16 maps and 1,024
bindings, a demanding profile with 128 maps and 16,384 bindings, and a stress
profile at the investigated maxima. It records exact definition and snapshot
storage, compilation, active-context assembly, exact and prefix lookup,
replacement, generations, shadows, allocator failures, and teardown.
The ordinary and demanding profiles match the independent contiguous
precedence oracle, perform lookup without temporary allocation, and release
all tracked memory. The stress-rejection profile verifies cycle, stale-owner,
allocator-fault, and prior-generation preservation paths.

## Failure behavior

Expected failures include unsupported schemas, malformed or oversized copied
records, Racket exceptions, wrong-thread and reentrant calls, invalid or stale identities, unknown commands,
invalid provenance, map and memory limits, duplicate bindings, invalid
operations, exact-prefix ambiguity, invalid remaps, ordering conflicts or
cycles, protected overlap, and allocation failure.

Contextual activation additionally reports invalid context maps, simultaneous
map or per-map binding limits, same-class ordering conflicts, stale owners,
generation exhaustion, invalid text fallbacks, and rejected contextual input.
Failure to activate a new contextual map does not publish it. Ending or
invalidating an owner clears input pending under that owner generation.

Command navigation additionally rejects invalid or oversized queries, stale
candidate or UI generations, registry or profile replacement, malformed
sequence or row text, unavailable commands, list or text exhaustion, and
allocation failure. A rejected unavailable or stale selection does not enter command
dispatch. Cancellation restores the captured return target and releases the
catalog deterministically.

Inspection additionally rejects invalid selectors, stale registry or snapshot
identity, unknown maps, malformed sequences or names, allocation failure, and
queries whose alternatives exceed the snapshot's configured inspection limit.
It does not truncate excess alternatives. Failed inspection leaves the active
generation and owned resolver storage unchanged; partial copied results are
released before returning. List projection additionally rejects stale or
exhausted model generations, invalid geometry, row-text or item overflow, and
allocation failure without publishing a partial root. Closing releases the
retained result and catalog deterministically.

Candidate construction owns all temporary storage. Any failure releases the
candidate and leaves the previous registry and snapshot generation active.
Closing a candidate releases its copied and adapted arrays. Closing an active
profile releases maps, bindings, remaps, and the snapshot owner before the
command registry may close.

## Validation

```sh
make keymap-resource-study
odin test src/interaction -vet -warnings-as-errors
make hosting-test
make native-command-test
make terminal-presentation-test
make check
make docs-check
```

See [Why Keymaps Are Layered](../../explanation/layered-keymaps/index.md) for
the design rationale and the
[runtime configuration guide](../../how-to/configure-keymaps/index.md) for
profile construction and replacement, and the
[Programmable Command Reference](../programmable-commands/index.md) for the
current terminal-visible factory profile.
