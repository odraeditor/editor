<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Status Bar Reference

The Status Bar is the pane-local summary attached to the bottom of every
ordinary editing pane. It reports the buffer, position, and available editing
context displayed by that pane. It does not own or mutate the state that it
presents.

## Core Layout

The initial factory layout keeps pane-local file and position fields on the
left and broader context on the right, separated by flexible space:

```text
704 src/odra/ main.odin 418:17 23%       W:editor P:odra UTF-8 LF Odin LS 1E 2W
```

The left group contains:

- a retained alert marker when the pane needs attention;
- an exceptional buffer-state marker when needed;
- the exact buffer size in bytes;
- the Project-relative directory context when available;
- the user-facing buffer name;
- the one-based logical line and display column as `line:column`; and
- `Top`, `Bot`, or the position percentage.

The right group contains:

- active Workspace and Project names when the pane belongs to them; and
- document encoding and line-ending policy when selected; and
- language, language-service health, and current error and warning totals when
  those owners publish current observations.

The visible document identity is a filename, not an absolute path. Its
Project-relative directory is a separate themeable segment and ends in `/`.
Non-document buffers retain their ordinary user-facing names. Documents
without active Project context omit the directory segment.

Unavailable context is absent. The Status Bar does not invent Workspace,
Project, language-service, remote, version-control, client, or frontend state.

## Context Forms

| Context | Full form | Compact form |
| --- | --- | --- |
| document encoding | `UTF-8 LF` | `U8` |
| soft-dedicated pane | `Soft` | `S` |
| hard-dedicated pane | `Hard` | `H` |
| Workspace | `W:editor` | `W` |
| Project | `P:odra` | `P` |
| editing context | `Odin LS 1E 2W` | `Odin` |

An alert uses `i`, `!`, or `!!` according to severity. Its complete bounded
diagnostic remains inspection metadata instead of expanding the row. Failed or
stopped language-service state is explicit in the editing-context segment.

## Buffer-State Markers

| Marker | Writable | Modified |
| --- | --- | --- |
| absent | yes | no |
| `**` | yes | yes |
| `%%` | no | no |
| `%*` | no | yes |

Write policy and modification state are independent. Clean writable buffers
do not spend space on a redundant marker. A visible marker never clears
modified state or changes write policy.

## Narrow Panes

The Status Bar always targets the exact width of its pane. When space becomes
limited, it applies a deterministic order:

1. use admitted compact forms;
2. omit optional low-priority segments;
3. truncate the buffer label at a grapheme boundary and append `…`; and
4. preserve retained alerts, required state, identity, and compact position
   information.

Composition measures terminal cells with the editor's Unicode profile. It does
not split a grapheme or infer width from UTF-8 byte length.

## Presentation

The complete row uses the active or inactive Status Bar role from the selected
editor theme. Active rows apply separate semantic roles to safety state, buffer
identity, position, alerts, Workspace, Project, and editing context instead of
reversing the complete row. Inactive rows remain deliberately muted. Every
shipped theme maps those meanings, and the color-minimal terminal baseline
retains distinctions through restrained attributes. The factory presentation
is visually distinct from ordinary text and aligned without decorative
terminal-specific markup.

A dedicated separator row places subtle visual space between pane content and
the Status Bar text. Its line uses the base Status Bar theme color uniformly,
so semantic segment colors do not leak into the separator.

Segment meaning is independent of concrete colors. Theme and extension layers
may refine or replace presentation while preserving checked UI and resource
contracts.

## Interaction

The Status Bar exposes its segment model through ordinary registered commands:

| Command | Behavior |
| --- | --- |
| `status-bar-inspect` | List every visible segment and its bounded inspection value. |
| `status-bar-actions` | List only visible segments with an available primary action. |
| `status-bar-activate-segment` | Select and invoke one visible primary action. |

All three commands are available through `M-x`. Their candidate surface uses
the active pane's exact Status Bar generation. Typing filters the list, the
arrow keys move the selection, `RET` accepts it, and `C-g` cancels and restores
editing. A candidate from an older UI or command-registry generation is
rejected instead of invoking a different command.

Factory actions reuse existing command owners. Buffer identity opens buffer
navigation, Project context opens the Project command surface, and language
context opens language inspection. Current language diagnostics provide the
applicable diagnostic action. A visible segment without an admitted existing
command remains inspectable but is not presented as actionable.

## Personal Configuration

`init.rkt` may export one complete `odra-status-bar-configuration` hash. The
admitted keys and values are:

| Key | Admitted values |
| --- | --- |
| `position` | `line-column-percentage`, `line-column`, `byte-offset` |
| `visible` | A unique list drawn from `encoding`, `pane-state`, `workspace`, `project`, and `editing-context` |
| `compact` | `automatic`, `prefer-compact`, `essential-only` |

Omitted keys retain their factory values. `essential-only` removes every
optional segment. `prefer-compact` starts optional segments in their admitted
compact forms. Configuration changes presentation policy only; they do not
edit Status Bar text, expose native state, or transfer ownership of a segment.

The boundary copies only the three encoded policy values. An invalid value,
duplicate visibility entry, evaluation failure, timeout, or oversized result
rejects the personal configuration and preserves the complete factory policy.

## Programmable Segments

The Racket facade separates declarative segment construction from lifecycle
authority:

| Procedure | Contract |
| --- | --- |
| `status-bar-segment` | Construct one bounded semantic segment definition. |
| `status-bar-provider` | Group one non-empty, identity-unique segment list under one package owner. |
| `status-bar-register` | Publish one new provider generation. |
| `status-bar-replace` | Atomically replace one exact provider generation. |
| `status-bar-remove` | Remove one exact provider and all its segments. |
| `status-bar-teardown` | Remove all Status Bar state owned by a closing provider. |
| `status-bar-inspect` | Return one copied registry snapshot with limits, usage, providers, segments, and the latest diagnostic. |

A segment chooses `left` or `right`, stable order and priority, full and
compact text, omission or truncation policy, one admitted semantic style, and
optional registered primary and secondary command identities. Programmable
styles are `ordinary`, `context`, `editing-context`, and `disabled`.

Factory identities are reserved. Provider and segment identities are bounded
machine names. Text is copied UTF-8 and rejects controls and terminal escape
sequences. Actions name commands already admitted by the command registry;
they cannot carry procedures or native handles.

Registration, replacement, removal, and teardown are explicit scoped
operations. A stale provider generation, invalid scope, duplicate identity,
over-budget proposal, unregistered command, or allocation failure rejects the
complete operation and preserves the last valid registry generation. Native
pane composition copies confirmed definitions and performs no Racket callback.

## Ownership and Limits

The Status Bar receives copied observations for one exact generation. A view
is immutable after composition and owns its rendered text, segment ranges, and
inspection text until it is closed.

The initial limits admit at most:

- 32 segment definitions;
- 32 programmable providers;
- 16 programmable segments per provider and 20 across all providers;
- 4 KiB for any segment text value;
- 16 KiB of composed text;
- 64 semantic style spans; and
- 8 MiB of aggregate programmable registry content; and
- 1,024 bounded composition work units.

Invalid generations, duplicate segment identities, invalid UTF-8, control
characters, over-limit input, insufficient width, allocation failure, and
double close are explicit failures.
