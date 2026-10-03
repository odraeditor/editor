<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Programmable Command Reference

This reference describes the named-command registry, Racket-defined keymap,
normalized input, text-transfer, search, and buffer-session facades, dispatch
results, and terminal-visible bindings. Declaration-level Odin comments and
Racket contracts remain authoritative.

## Responsibility map

| Package | Responsibility |
| --- | --- |
| `terminal_frontend` | Decode physical bytes into normalized `interaction.Input` values. |
| `interaction` | Own command, profile, map, context, and owner identities; compile immutable layered snapshots; retain bounded pending input; and resolve commands. |
| `command` | Execute admitted native and Racket commands and expose checked buffer-session composition without duplicating native indexes. |
| `hosting` | Root Racket procedures and copy bounded keymap and command values across the native boundary. |
| `odra` | Own bounded prompts, resolve the active checked entry for each turn and frame, decide redraw or exit, and order shutdown. |

The terminal package does not name editor operations. Racket does not own the
active snapshot, pending sequence, buffer, view, or canonical publication.

## Normalized terminal input

`terminal_frontend.Decoder` retains at most eight physical bytes. A successful
decode returns one `interaction.Input`; its optional text borrows decoder
storage until the next decoder operation.

| Physical input | Logical input |
| --- | --- |
| Printable UTF-8 scalar | `Key` with `Unicode_Scalar` and the same committed text. |
| Left, Right, Up, Down | Corresponding logical special key. |
| Home variants | `Home`. |
| End variants | `End`. |
| Backspace `0x08` or `0x7f` | `Backspace`. |
| `CSI 3~` | `Delete`. |
| Carriage return or line feed | `Enter`. |
| `Control-G` or `Control-X` | Unicode scalar with the `Control` modifier. |
| `Control-/` or `Control-_` byte `0x1f` | Canonical `Control-/`; both physical forms are indistinguishable in the terminal protocol. |

Malformed, incomplete, oversized, unknown, or unsupported physical input does
not enter resolution and does not clear an existing pending command sequence.

## Command registry

The factory registry contains 129 commands: 101 native commands, 21 native
contextual commands, six Racket-backed inspection commands, and one Racket
editing command.

| Command | Implementation | Confirmed effect |
| --- | --- | --- |
| `cursor-previous-grapheme`, `cursor-next-grapheme` | Native | Move the view cursor by one complete grapheme. |
| `cursor-previous-line`, `cursor-next-line` | Native | Move by logical line while preserving the desired column. |
| `cursor-line-start`, `cursor-line-end` | Native | Move to a logical line boundary. |
| `insert-text` | Native | Publish one insertion using resolved committed text. |
| `delete-previous-grapheme`, `delete-next-grapheme` | Native | Delete to the prior logical indentation boundary for leading Backspace, or publish complete-grapheme deletion elsewhere. |
| `insert-line-break` | Native | Insert one canonical line feed. |
| `undo`, `redo` | Native | Traverse the preferred reversible history branch. |
| `save-associated-document` | Native | Save the current target or request a path for an unassociated buffer. |
| `set-mark-command`, `deactivate-mark`, `exchange-point-and-mark` | Native | Change the active buffer's mark and region state through its selected view. |
| `select-word`, `select-paragraph`, `select-buffer`, `select-definition`, `structural-select` | Native | Select one semantic text unit through the active view. |
| `pop-selection-location` | Native | Restore the newest available retained selection or location. |
| `save-location`, `list-locations`, `visit-location` | Native | Persist, inspect, or visit named document locations. |
| `store-number`, `increment-number`, `store-text`, `store-region-text`, `store-position`, `insert-slot` | Native | Manage bounded persistent typed values and insert retained text. |
| `store-layout`, `restore-layout` | Native | Persist or restore portable pane-layout intent. |
| `copy-region`, `kill-region`, `delete-region` | Native | Retain or delete the active ordered region. |
| `yank`, `yank-pop` | Native | Insert retained text or rotate the immediately preceding yank. |
| `indent-lines`, `outdent-lines` | Native | Atomically shift every logical line intersecting an explicit or active range. |
| `normalize-indentation-to-tabs`, `normalize-indentation-to-spaces` | Native | Atomically convert leading indentation on the current or selected lines while preserving interior whitespace. |
| `find-file` | Native | Request a bounded path prompt, then open or select one canonical local target. |
| `switch-to-buffer` | Native | Open bounded session-buffer candidate navigation, then activate a checked row or create one valid unmatched name. |
| `kill-buffer` | Native | Request an exact label, then close clean work or obtain explicit save or discard authority for modified work. |
| `list-buffers` | Native | Present the checked active-then-MRU buffer inventory list. |
| `describe-language-state` | Native | Present copied language association, provider, revision, parser, syntax, renderer, usage, pending-work, and rejection state for the active buffer. |
| `reload-interaction-profile` | Native | Validate and atomically activate the staged interaction profile. |
| `execute-extended-command` | Native | Present checked interactive command navigation. |
| `keyboard-quit` | Native | Clear pending input or deactivate the active region. |
| `isearch-forward`, `isearch-backward` | Native | Start, update, repeat, or reverse bounded incremental literal search. |
| `isearch-forward-regexp`, `isearch-backward-regexp` | Native | Start, update, repeat, or reverse bounded incremental regexp search. |
| `query-replace`, `query-replace-regexp` | Native | Coordinate progressive replacement over one revisioned scope. |
| `replace-string`, `replace-regexp` | Native | Publish one admitted replacement batch atomically. |
| `request-editor-exit` | Native | Request a checked clean or unsaved exit transition. |
| `describe-key`, `where-is`, `describe-bindings`, `describe-keymap`, `describe-keymap-conflicts`, `describe-keymap-state` | Racket | Select one checked keymap inspection projection. |
| `uppercase-current-line` | Racket | Uppercase one bounded logical line and publish at most one splice. |

The contextual commands implement prompt input, fixed choices, query-replace
responses, and shared-list navigation. They remain registry identities so the
same layered keymap resolver can bind and inspect them, but they are not
independent editing operations.

## Internal command routing

Command names remain the stable public identities used by Racket profiles,
lookup, inspection, diagnostics, and boundary requests. Execution does not
branch on those strings.

Every registered definition also carries a provider-owned `Command_Route`.
The route selects one typed native, contextual, Racket-inspection, or Racket
runtime operation. Before the factory registry becomes visible, activation
checks that each route exists and that its implementation class, invocation
class, text requirement, and declared effects match the provider contract.
Missing routes, duplicate route identities, and incompatible declarations
reject the candidate registry without publishing it.

Native and Racket executors decode only their own route types. Prompt, UI,
search, replacement, transfer, and application lifecycle owners use
the same typed routes or the typed `Native_Completion` result. Programmable
facades may still accept a public command name, but they resolve it once through
the registry and admit the resulting typed route before execution.

## Built-in keymap

Racket returns one complete typed interaction-profile catalog. Odin copies the
fixed-width records, reconstructs profiles, states, maps, bindings, remaps, and
ordering constraints, validates command names and fallback behavior, then
atomically activates the compiled layered snapshot. `src/command/builtins.rkt`
owns the shipped definitions, `src/command/keymap-model.rkt` owns the typed
Racket model, and `src/command/keymaps.rkt` owns candidate staging and factory
catalog composition.

| Input | Command |
| --- | --- |
| Arrows, Home, End | Corresponding cursor command. |
| Backspace | `delete-previous-grapheme`. |
| Delete | `delete-next-grapheme`. |
| Enter | `insert-line-break`. |
| `Control-S`, `Control-R` | Forward and backward literal incremental search. |
| `Control-Meta-S`, `Control-Meta-R` | Forward and backward regexp incremental search. |
| `Meta-%`, `Control-Meta-%` | Literal and regexp query replacement. |
| `Control-Space` | `set-mark-command`. |
| `Control-G` | `keyboard-quit`. |
| `Control-W`, `Meta-W` | `kill-region`, `copy-region`. |
| `Control-Y`, `Meta-Y` | `yank`, `yank-pop`. |
| `Control-X`, then `Control-X` | `exchange-point-and-mark`. |
| `Meta-@`, `Meta-H`, `Control-X` then `h`, `Control-Meta-H` | Select a word, paragraph, buffer, or current definition. |
| `Control-U`, then `Control-Space` | `pop-selection-location`. |
| `Control-X`, then `r`, then `m`, `l`, or `b` | Save, list, or visit persistent named locations. |
| `Control-X`, then `r`, then `n`, `+`, `s`, `Space`, `j`, or `i` | Store, update, insert, or visit persistent typed named slots. |
| `Control-X`, then `r`, then `w` | Store a portable pane layout; `Control-X r j` restores it through the typed-slot visitor. |
| `Control-/`, `Control-_`, or `Control-X`, then `u` | `undo`. |
| `Control-X`, then `Control-S` | `save-associated-document`. |
| `Control-X`, then `Control-F` | `find-file`. |
| `Control-X`, then `b` | `switch-to-buffer`. |
| `Control-X`, then `k` | `kill-buffer`. |
| `Control-X`, then `Control-B` | `list-buffers`. |
| `Control-X`, then `Control-C` | `request-editor-exit`. |
| Unclaimed printable UTF-8 | `insert-text`. |

These are demonstration bindings, not a compatibility profile.

The factory keymap obtains its six active search entries from
`search-factory-bindings`. `search-reserved-bindings` separately exposes the
unassigned `M-s` family for future symbol, word, occurrence, and highlight
commands; reservations are not active bindings.

## Programmable text transfer

`src/command/transfer.rkt` exposes one cohesive `racket/base` facade for modes,
hooks, and later user commands. `call-with-text-transfer` receives the active
transport generation and an opaque positive token, then creates a session
valid only for the callback's dynamic extent.

| Procedure | Result |
| --- | --- |
| `text-transfer-region` | Immutable copied point, optional mark, activation, and ordered region bounds. |
| `text-transfer-ring` | Immutable newest-to-oldest entry metadata, limited to 256 entries. |
| `text-transfer-entry-text` | Authorized immutable UTF-8 bytes for one retained entry, limited to 12 MiB. |
| `text-transfer-command!` | Completion code from one admitted stable semantic command. |

The admitted command names are `set-mark-command`, `deactivate-mark`,
`exchange-point-and-mark`, `copy-region`, `kill-region`, `delete-region`,
`yank`, and `yank-pop`. The facade invokes the existing registry identities;
it does not define parallel commands or bypass ordinary transaction, history,
view, and ring validation.

Each copied value carries the exact editor session, authority set, view,
view-state generation, buffer and revision, ring and generation, and command
registry generation captured by Odin. A successful command refreshes that
scope before another operation can proceed.

## Programmable search and replacement

`src/command/search.rkt` exposes copied pattern, replacement, scope, policy,
session, occurrence, capture, progress, usage, command, and result values under
one `call-with-search` dynamic extent. Racket composes stable semantic names;
Odin continues to own matching, live view sessions, canonical text,
transactions, history, and publication.

The facade admits the eight search and replacement names listed in the command
registry. It validates UTF-8 and local value shape before crossing the boundary.
The native callback then validates complete identity, generations, permissions,
policy relationships, resource ceilings, and command-specific semantics.

`reload-search-policy!` replaces the Racket transformation used to derive the
default for later programmable invocations. `make-search-command` may instead
carry one explicit copied policy. Neither path changes a live terminal search
retroactively or grants a raw buffer mutation primitive.

See the [Search and Replacement Reference](../search-and-replacement/index.md)
for exact values and limits and
[Configure Programmable Search Policy](../../how-to/configure-search/index.md)
for the live configuration procedure.

## Programmable buffer sessions

`src/command/buffers.rkt` exposes one contracted facade for the five factory
buffer command names: `find-file`, `switch-to-buffer`, `kill-buffer`,
`list-buffers`, and `save-associated-document`. `call-with-buffer-session`
creates one thread-bound dynamic session over a copied scope.

The facade can inspect exact aggregate usage, enumerate one bounded copied
descriptor batch, inspect a checked handle, and request create, open,
activation, save, kill, or generation-bound marked execution. Successful
mutations refresh the local copied scope. Odin revalidates the complete scope
and owns every registry lookup, canonical object, filesystem effect, and
lifecycle publication.

See the [Programmable Buffer Session Reference](../programmable-buffer-sessions/index.md)
for value shapes, accessors, quotas, outcomes, and failure behavior.

## Programmable Ksawery providers

The public `odra/commands` module re-exports the complete personal Ksawery
facade. A configuration generation exports `odra-ksawery-contributor` and,
when it contributes command families, `odra-ksawery-command-families`.

| Public group | Constructors and access |
| --- | --- |
| Contributor | `make-ksawery-extension-limits`, `make-ksawery-contribution`, `make-ksawery-contributor`, compatibility predicates, and copied data inspection. |
| Status | `make-ksawery-status-metadata`, `make-ksawery-status-command-reference`, `make-ksawery-status-item`, `make-ksawery-status-section`, and proposal composition. |
| Annotation | `make-ksawery-annotation-target`, `make-ksawery-annotation-command-reference`, `make-ksawery-annotation`, and proposal composition. |
| Command family | Choice, argument, action, family, boolean, choice-value, text, target, and opaque constructors; copied command-context accessors; checked action or external-operation requests; explicit rejection and cancellation. |
| External operation | Built-in Git or configured absolute executable constructors, verifier and limit constructors, and `make-ksawery-operation-plan`. |
| Conflict assistance | Provider construction, copied observation, target, and side accessors, guidance, editor, external-tool, decline, and diagnostic response constructors. |

Identities match
`^[a-z][a-z0-9]*(?:[./-][a-z0-9]+)*$`, are at most 96 UTF-8 bytes, and
remain stable within their owner. Public labels are at most 128 UTF-8 bytes.
Contributor, family, provider, plan, observation, target, selection, and
capability generations are independent and must match the active native scope.

Contribution kinds are `command`, `keymap`, `status-section`, `annotation`,
`command-family`, `external-operation`, `conflict-assistance`, and
`provider-role`. Observation families are `status`, `history`, `refs`,
`sequence`, `conflict`, and `process`. Requested authorities are `inspect`,
`present`, `invoke-declared-command`, `request-core-action`,
`submit-external-operation`, and `assist-conflict`. Construction rejects an
authority, observation, provider role, semantic target, action, or response
that is not declared by the same contributor generation.

Status styles are `normal`, `muted`, `identity`, `active`, `success`,
`warning`, `alert`, and `information`. Annotation target families are `path`,
`diff-unit`, `revision`, `revision-range`, `ref`, `remote`, `conflict`,
`sequence`, and `process`; severities are `none`, `hint`, `information`,
`warning`, and `error`. Both surfaces retain explicit text and truncation state
independently from color.

Command arguments are `boolean`, `closed-choice`, `text`, `selection`, `ref`,
`revision`, `revision-range`, or `opaque`. A `request-core-action` must name one
closed core operation, be mutating, and require confirmation. A
`submit-external-operation` must require confirmation and provide one
two-argument procedure that returns a declared plan. The stable command name is
`<contributor>/<family>/<action>` and enters the existing registry; there is no
second Ksawery command catalog.

External plans classify effects as `read-only`, `repository-mutating`, or
`externally-mutating`; use `suppressed` or `bounded-public` diagnostics; and
verify `none`, `observation-available`, `target-present`, `target-absent`, or
`operation-state`. Plans are inert values. Odin revalidates their complete
identity and owns the repository directory, fixed environment, closed input,
child process, limits, cancellation, refresh, Process record, and result.

Conflict providers declare any supported subset of `text`, `binary`, `rename`,
`delete`, `type-change`, `submodule`, `missing-stage`, `truncated`, and
`unsupported`, plus `present-guidance`, `open-editor`, or
`submit-external-tool`. A response may decline, present copied guidance, open
the ordinary editor workflow, or propose one already admitted external plan.
It cannot resolve the index or control a sequence.

All synchronous provider calls use one non-reentrant bounded turn. Importing or
constructing a value has no native effect. A complete valid generation is
copied and activated atomically; rejection retains the previous generation.
Refresh, replacement, disablement, failure, and teardown revoke stale routes,
projections, capabilities, and Racket roots without changing canonical Git
state.

See the [Ksawery Reference](../ksawery/index.md) for visible keys, lifecycle,
resource ceilings, Process integration, and fallback, and
[Extend Ksawery from Personal Configuration](../../tutorials/user-guide/customization/extend-ksawery.md)
for one complete executable authoring workflow.

## Resolution rules

- An exact binding produces one checked command handle.
- A strict prefix stores at most 16 strokes in native pending state. The
  current factory-map transfer remains limited to four strokes per sequence.
- `Control-G` is admitted before ordinary prefix extension and clears pending
  state.
- An invalid continuation clears pending state and discards that continuation.
- An unclaimed printable scalar uses the native text fallback only when no
  prefix was already pending.
- Registry and snapshot generations must match exactly.

Resolution performs no Racket call. Native movement, insertion, deletion,
line break, cancellation, and exit also avoid Racket.

## Dispatch outcomes

| Completion | Coordinator action |
| --- | --- |
| `No_Op` | Preserve revision and do not redraw. |
| `View_Changed` | Render the confirmed view. |
| `Buffer_Committed` | Render the new canonical revision. |
| `Pending_Input_Cancelled` | Preserve the current display. |
| `Document_Saved` | Report the exact published revision and durability state. |
| `Document_Target_Required` | Enter the bounded `Save as:` interaction. |
| `Find_File_Requested` | Enter the bounded `Find file:` interaction. |
| `Switch_To_Buffer_Requested` | Enter the bounded `Switch to buffer:` interaction. |
| `Kill_Buffer_Requested` | Enter the bounded `Kill buffer:` interaction with the current complete label prefilled. |
| `List_Buffers_Requested` | Present the bounded Buffer Menu list and retain its checked return target. |
| `Exit_Requested` | Inspect all live buffers and either exit or enter the bounded Save, Discard, Cancel sequence. |

The Racket uppercase turn copies at most 4 KiB, validates echoed identity,
range, size, and UTF-8, and completes all foreign execution before the sole
possible canonical splice.

## Resource limits

| Resource | Limit |
| --- | ---: |
| Registered commands | 2,048 |
| Command name | 96 UTF-8 bytes |
| Maps per layered profile | 128 |
| Active maps per context | 16 |
| Bindings per layered map | 4,096 |
| Total layered bindings | 16,384 |
| Strokes per layered sequence | 16 |
| Copied layered definitions | 8 MiB |
| Retained layered snapshot | 32 MiB |
| Factory transfer bindings | 1,024 |
| Factory transfer strokes per sequence | 4 |
| Normalized text payload | 4 KiB |
| Racket input and replacement | 4 KiB each |
| Transfer ring metadata | 256 entries per call |
| Transfer entry text | 12 MiB per call |
| Transfer command name | 96 UTF-8 bytes |
| Search command name | 96 UTF-8 bytes |
| Search pattern or replacement request | 64 KiB each |
| Copied search occurrences | 256 per inspection |
| Copied search captures | 2,816 per inspection |
| Copied search session text | 192 KiB per inspection |
| Copied buffer descriptors | 256 per call |
| Copied buffer labels or marked paths | 4 MiB per call |
| Buffer create or open request text | 4 KiB per call |
| Buffer marked decisions | 128 per call |
| Concurrent command turns | 1 |
| Canonical splices per command | 1 |

## Validation commands

```sh
make terminal-test
make terminal-presentation-test
make terminal-benchmark
make hosting-evidence
make search-command-benchmark
make buffer-session-command-benchmark
make buffer-session-acceptance
make verify
```

See [Why Named Commands Sit Between Input and Editing](../../explanation/programmable-command-routing/index.md)
for the command-routing rationale and the
[Contextual Keymap Reference](../contextual-keymaps/index.md) for the layered
resolver contract.
