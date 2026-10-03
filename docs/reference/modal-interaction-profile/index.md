<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Modal Interaction Profile Reference

The `modal` interaction profile is a session-global stateful keyboard profile.
The factory catalog contains `direct` and `modal`; `direct` remains the factory
selection when personal configuration does not choose another profile.

The current delivery provides Normal, Insert, Replace, Visual Character, and
Visual Line; the core navigation and search grammar; bounded operators and text
transfer; direct-binding continuity in Insert and Replace; canonical command
entry; semantic last-change repetition; and pane, buffer, component, and
integrated-terminal interaction.

## Selection

`select-interaction-profile` opens a session candidate list through `M-x`.
Selecting a row and pressing `Enter` confirms the change. The command has no
factory key binding and does not write `init.rkt`.

The selector validates the exact catalog generation, snapshot generation,
profile identifier, and profile revision before publication. A successful
selection cancels pending key sequences and activates the selected profile's
initial state. A stale, malformed, unavailable, or failed candidate leaves the
previous profile and state active.

The factory initial states are:

| Profile | Initial state |
| --- | --- |
| `direct` | `direct-editing` |
| `modal` | Normal |

## Persistent startup selection

Personal configuration can select `modal` without replacing the factory
catalog:

```racket
#lang racket/base

(require odra/keymaps)

(provide odra-interaction-profile)

(define odra-interaction-profile
  (factory-modal-interaction-profile))
```

The configuration loader evaluates this definition as part of the existing
atomic personal-configuration generation. A rejected generation preserves the
previous confirmed profile catalog.

## Normal navigation and state entry

Normal rejects unmatched text input. Its navigation bindings are:

| Input | Command | Result |
| --- | --- | --- |
| `h`, Left | `cursor-previous-grapheme` | Move to the previous grapheme boundary. |
| `l`, Right | `cursor-next-grapheme` | Move to the next grapheme boundary. |
| `j`, Down | `cursor-next-line` | Move to the next logical line while preserving desired display column. |
| `k`, Up | `cursor-previous-line` | Move to the previous logical line while preserving desired display column. |
| `0`, Home | `cursor-line-start` | Move to the logical line start. |
| `$`, End | `cursor-line-end` | Move to the logical line end. |
| `^` | `cursor-line-first-non-whitespace` | Move to the first non-whitespace grapheme. |
| `w` | `cursor-next-word-start` | Move to the next canonical word start. |
| `b` | `cursor-previous-word` | Move to the previous canonical word start. |
| `e` | `cursor-word-end` | Move to the current or next canonical word end. |
| `gg` | `cursor-buffer-start` | Move to the active buffer start. |
| `G` | `cursor-buffer-end` | Move to the active buffer end. |
| Page Up, Page Down | `scroll-previous-page`, `scroll-next-page` | Move by one canonical viewport page. |
| `f<char>`, `F<char>` | character-target movement | Find the next or previous matching character on the logical line. |
| `t<char>`, `T<char>` | character-target movement | Stop adjacent to the next or previous matching character. |
| `;`, `,` | repeated character-target movement | Repeat the latest admitted character target in the same or opposite direction. |
| `/`, `?` | `isearch-forward`, `isearch-backward` | Begin a canonical literal search prompt. |
| `n`, `N` | search occurrence movement | Repeat the latest confirmed canonical search in the same or opposite direction. |
| `i` | `modal-enter-insert` | Enter Insert at point. |
| `a` | `modal-enter-insert-after` | Move after the current grapheme when possible, then enter Insert. |
| `I` | `modal-enter-insert-line-first` | Move to the first non-whitespace boundary and enter Insert. |
| `A` | `modal-enter-insert-line-end` | Move to the logical line end and enter Insert. |
| `R` | `modal-enter-replace` | Enter Replace at point. |
| `.` | `modal-repeat-last-change` | Repeat the latest admitted semantic change at the current point. |
| `o` | `modal-open-line-below` | Insert one logical line below and enter Insert there. |
| `O` | `modal-open-line-above` | Insert one logical line above and enter Insert there. |
| `v` | `modal-enter-visual-character` | Select the current grapheme and enter Visual Character. |
| `V` | `modal-enter-visual-line` | Select the complete current logical line and enter Visual Line. |
| `C-v` | `modal-enter-visual-block` | Start a logical rectangular selection and enter Visual Block. |

Digits `1` through `9` start a bounded positive decimal count. Additional
digits extend the count through checked arithmetic. `0` is part of an active
count and otherwise remains line-start movement. A count applies to the next
admitted movement, including page, character-target, and confirmed-search
movement. Overflow or a count before a command that does not admit counts is
rejected before movement.

Replace admits the same compatible Direct bindings as Insert. Committed text
replaces the corresponding complete graphemes on the current logical line;
after the line-end boundary it inserts without consuming the line break.
`Escape` or `C-[` returns to Normal. Replacement uses ordinary transactions,
so undo and redo retain their canonical behavior.

Character targets are one Unicode scalar and never cross a logical line.
Missing targets are no-ops. Their repeat state retains the exact profile,
state, interaction context, view generation, buffer identity, and buffer
revision; a stale request is rejected and cleared without partial movement.

`/` and `?` use the ordinary incremental-search prompt, history, policy,
revision checks, empty-match handling, cancellation, and resource bounds.
Accepting that prompt records only its direction and pattern kind in modal
state; the pattern and policy remain in canonical session search history.
`n` and `N` open, execute, accept, and close a canonical search turn without
leaving a second prompt or occurrence model active. A failed counted repeat
aborts the transient search and restores its origin.

## Visual interaction

Visual Character, Visual Line, and Visual Block use the active buffer's one
canonical point and mark. Character and Line materialize a linear region.
Block records a rectangular shape and derives bounded per-line ranges from the
two logical grapheme columns; interaction state does not retain a second text
range.

The Normal movement grammar, counts, character targets, and canonical search
extend the active region in every Visual state. Visual Character includes the
destination grapheme. Visual Line materializes every complete logical line
between the anchor and active end. Visual Block recalculates its per-line
ranges from the moved endpoint. `o` exchanges the active end and anchor through
`exchange-point-and-mark`.

The following state controls are exact:

| Input | Visual Character | Visual Line | Visual Block |
| --- | --- | --- | --- |
| `v` | Deactivate the region and return to Normal. | Convert to Visual Character. | Convert to Visual Character. |
| `V` | Convert to Visual Line. | Deactivate the region and return to Normal. | Convert to Visual Line. |
| `C-v` | Convert to Visual Block. | Convert to Visual Block. | Deactivate the region and return to Normal. |
| `Escape`, `C-[` | Cancel and return to Normal. | Cancel and return to Normal. | Cancel and return to Normal. |

`d`, `c`, and `y` apply immediately in every Visual state. Block copy retains
newline-separated line ranges; block delete and change mutate every derived
range through one transaction. `>` and `<`, plus `iw`, `aw`, `ip`, and `ap`,
remain linear Visual operations. Successful delete, copy, indent, and outdent
return to Normal; successful change enters Insert. A different view of the
same buffer can retain the buffer-owned selection; a different buffer cannot
extend it.

## Operators and targets

Normal composes an operator with one target before resolving a canonical
command. No pending operator moves point or changes text.

| Input | Result |
| --- | --- |
| `d{target}` | Retain the target in the shared kill ring, then delete it. |
| `c{target}` | Perform the same retained deletion, then enter Insert. |
| `y{target}` | Copy the target to the shared kill ring without changing text. |
| `>{target}`, `<{target}` | Indent or outdent every intersecting logical line by one active indentation unit. |
| `dd`, `cc`, `yy`, `>>`, `<<` | Apply the operator to complete logical lines. |
| `D`, `C`, `Y` | Delete, change, or copy through the current logical line boundary. |
| `x`, `X` | Delete the next or previous complete grapheme without adding a kill-ring entry. |
| `r<char>` | Replace the next complete grapheme with one admitted text input. |
| `p`, `P` | Insert the newest retained text after or before the current point target. |
| `u`, `C-r` | Invoke canonical undo or redo. |

Operator targets include the Normal movement grammar, arrow and navigation
keys, `iw`, `aw`, `ip`, and `ap`. A count before the operator combines with a
count before its target using checked arithmetic. Compatible standalone
deletion and paste commands also accept counts. Line indentation is one atomic
multi-line edit and one ordinary history unit.

Range-oriented delete and change use `kill-region`; copy uses `copy-region`.
They therefore share kill-ring coalescence and optional clipboard export with
Direct. Paste performs the ordinary clipboard import check before canonical
yank. Small `x` and `X` deletion deliberately does not update retained text.

## Repeat the last change

`.` repeats one retained semantic change. Odra records the resolved command or
operator, movement target, count, inserted text, selection shape, and named
text-slot identity that define the change. It never records or replays raw key
events.

Insert and Replace sessions retain at most 1,024 bytes of committed text.
Repeating `i`, `a`, `I`, `A`, `o`, `O`, or `R` resolves the recorded entry
semantics at the current point and publishes one ordinary transaction. A count
before `.` replaces the retained count for the replay. Operator targets are
resolved again from the current point; named text is read again from the named
slot before mutation.

The record is scoped to the command-registry and modal-profile generations
that admitted it. Missing, oversized, stale, incompatible, or unavailable
records are rejected before buffer mutation. A successful repeat is one
canonical history unit, so ordinary undo and redo reverse and restore it.
Direct interaction does not capture or dispatch modal repeat state.

`M-x describe-modal-repeat` reports the retained operation, semantic target,
count, text size, selection shape, named-slot identity, and owning generations.
It does not expose retained text content.

## Named text slots

`"<name>` selects one existing named slot for the immediately following
compatible delete, change, copy, or paste. The name is copied into bounded
pending interaction state and is visible through ordinary interaction
inspection.

Named delete, change, and copy store the exact resolved range in the selected
text slot. Named `p` and `P` insert the selected text slot before or after the
current point target without changing the unnamed kill ring. Counts repeat a
named paste only within the named-text size limit.

A missing or oversized text slot rejects the complete operation. Selecting a
slot of another kind opens the existing replacement confirmation; cancellation
preserves both the stored value and buffer. Confirmation is bound to the
observed slot generation and immutable buffer range, so a changed slot,
profile, view, buffer, or revision rejects the deferred operation.

## Insert continuity

Insert admits ordinary text input through the canonical `insert-text` command.
It also projects the complete delivered Direct factory and project binding
tables into the Insert state with their original precedence. This includes
ordinary movement, selection, retained text, undo, search, completion, file,
buffer, pane, project, and lifecycle bindings.

Direct bindings win when a familiar modal Insert convention conflicts with an
existing command. In particular:

| Input | Insert command |
| --- | --- |
| `C-w` | `kill-region` |
| `M-w` | `copy-region` |
| `C-y` | `yank` |
| `M-y` | `yank-pop` |
| `C-r` | `isearch-backward` |
| Backspace | `delete-previous-grapheme` |
| Delete | `delete-next-grapheme` |
| `Escape`, `C-[` | `modal-enter-normal` |

State transitions do not create history nodes. `a`, `I`, and `A` retain their
canonical movement behavior, while `o` and `O` create one ordinary reversible
line insertion before entering Insert.

## Command entry

Normal, Visual Character, and Visual Line bind `:` to the same
`execute-extended-command` command used by protected `M-x`. Both surfaces read
the shared immutable command catalog and expose the same canonical command
names, descriptions, availability, provenance, completion, history, argument
contracts, and checked dispatch. Modal command entry has no aliases or trailing
command syntax: `:save-associated-document` and
`M-x save-associated-document` select one command identity, while `:w` is not
defined implicitly.

Cancelling `:` restores its source state and selection. Successful dispatch
returns a non-Normal source state to Normal unless the selected command opens a
stronger prompt or component-owned context. Generation, view, and buffer
changes reject stale command entry without partial dispatch.

## Panes and buffers

Normal and all Visual states provide the following pane prefix:

| Input | Command |
| --- | --- |
| `C-w h`, `C-w j`, `C-w k`, `C-w l` | Focus the adjacent pane left, down, up, or right. |
| `C-w s`, `C-w v` | Split the active pane below or to the right. |
| `C-w c` | Close the active pane. |
| `C-w o` | Keep only the active pane. |
| `C-w =` | Balance pane sizes. |

Directional focus selects the nearest pane whose geometry overlaps on the
orthogonal axis. A missing adjacent pane is a no-op. The compatible Direct
buffer and pane commands remain available with their canonical bindings and
candidate workflows; the modal profile does not create a separate buffer list
or layout model.

A switch to another buffer ends Visual selection and enters Normal before the
destination buffer receives modal input. A different view of the same buffer
may retain its canonical buffer-owned selection. Display-only operations in
another pane preserve focus and do not transfer Visual ownership.

## Contextual components

Prompt, candidate, search, completion, file-management, repository, diagnostic,
result, help, and other component maps retain their documented precedence and
plain-key bindings. Context activation suspends ordinary modal grammar without
replacing the selected profile or compatible persistent state. It cancels an
incompatible pending count, operator, character target, or named-slot prefix;
the command-navigation component alone retains the exact pending `:` request
until cancellation or checked command dispatch.

Closing a component restores the compatible underlying modal state. A plain
key owned locally by a component does not become a global Normal binding.
Protected `C-g` and `M-x`, stale-generation rejection, and contextual-map
inspection retain their canonical behavior.

## Integrated terminal

A focused live terminal retains its terminal-input context. Unclaimed input,
including ordinary `Escape`, is encoded for the child and does not transition
the persistent modal state. Protected `M-x` and `C-g` remain editor-owned.

The modal live-terminal map adds `C-\ C-n` for `terminal-copy-mode` without
changing the Direct terminal map. Copy mode transitions the modal profile to
Normal and owns retained-text input with these additions:

| Input | Command or result |
| --- | --- |
| `h`, `j`, `k`, `l` | Move left, down, up, or right through retained terminal text. |
| `0`, `$` | Move to the retained row's beginning or end. |
| Enter | Run `terminal-copy-mode-done` and restore live input in Normal. |
| `i` | Finish copy mode, enter Insert, and restore live input. |

Arrow, Home, End, Page Up, Page Down, `C-SPC`, `M-w`, and `C-c C-r` retain
their documented terminal copy-mode meanings. Copy mode never pauses,
duplicates, or restarts the child. `terminal-send-next-key`, bound to `C-q` in
the terminal context, forwards one otherwise intercepted key without weakening
protected recovery.

Live terminal presentation uses the child-owned cursor style, visibility, and
blinking state. Modal terminal copy mode uses a non-blinking block cursor at
the retained-text point.

## Inspection

Interaction inspection reports the selected profile and state, applicable map
and binding scopes, shared contributions, effective command-entry surface,
pending modal composition, conflicts, alternatives, and latest rejection.
Visual inspection additionally copies its kind, anchor, active endpoint, and
source profile, context, view, buffer, and generation identities. Context-map
inspection reports the active component owner and effective local bindings.
Inspection results are immutable snapshots and remain independent of later
state changes until explicitly closed.

## Presentation

The existing Status Bar editing-context segment displays `NORMAL`, `INSERT`,
`REPLACE`, `VISUAL`, `VISUAL LINE`, or `VISUAL BLOCK` while `modal` is active.
The segment is required for modal sessions and degrades to `N`, `I`, `R`, or
`V` before lower-priority optional segments are omitted.

Editable text views publish frontend-independent cursor intent. Normal and all
Visual states use a block cursor, Insert uses a bar cursor, and Replace
uses an underline where the frontend supports it. Integrated terminal views
retain their child-owned cursor shape and blinking state.

## Ownership and failure behavior

Racket owns declarative profile definitions. `src/interaction` owns copied
catalogs, state identity, checked state transitions, pending modal state,
compiled snapshots, rejection context, and cleanup. `src/odra` coordinates
candidate confirmation and active-view presentation. Frontends only render
the copied state and cursor intent.

Profile selection and state transition compile a complete private candidate
before publication. Allocation failure, count overflow, missing or stale
targets, invalid state, or incompatible command admission preserves the
previous published snapshot and does not mutate text. Pending counts,
operators, character targets, and named-slot prefixes are included in
interaction inspection and are cleared by cancellation, profile replacement,
incompatible context takeover, or stale view and buffer identity.

Recorded macros, delimiter and quoted-text objects, syntax-specific objects,
and modal-only register storage are not part of this delivery.

## Validation

```sh
make profile-compatibility-resource-study
make modal-interaction-acceptance
```

The focused acceptance covers factory and personal selection, all six checked
states, modal movement, Visual range materialization, Insert continuity,
search, operator and transfer composition, candidate confirmation, stale and
allocation failure, Status Bar fallback, cursor lowering, direct-profile
parity, PTY behavior, and cleanup.
