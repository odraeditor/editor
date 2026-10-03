<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Interaction Compatibility Reference

Odra's Direct profile uses familiar bindings when the corresponding operation
is meaningful in the terminal editor. The compatibility fixture at
`tests/interaction_compatibility/cases.tsv` pins 190 reviewed Core, Maksym,
Darek, Jan Babel, Ksawery, and Roman behavior cases. Each row records its
identity, applicability, expected Odra command and binding, behavior
classification, evidence, and review state.

`make interaction-compatibility-focused-test` checks the fixture shape and counts,
Direct-profile register bindings, unbound exclusions, and the dangerous
Ksawery Status conflicts. It does not build or link the editor.

## Shared Command Foundations

The Direct profile accepts bounded universal and numeric prefix arguments.
`C-u` starts with 4 and repeated `C-u` multiplies the value by 4. `M-0`
through `M-9` start a numeric argument, subsequent digits extend it, and
`M--` starts a negative argument. `C-g` or `Esc` cancels retained prefix state.
The argument belongs to the next resolved command, including a command chosen
through `M-x`. Switching away from Direct clears it. Modal counts remain owned
by the modal profile.

Command implementations can resolve a current word, logical line, paragraph,
active region, or complete buffer without requiring the user to select the
exact range first. Definition, Jan entry, and Roman node targets use a supplied
owner generation and reject stale context. An explicit current range takes
precedence when a command already owns one.

## Contextual Help

The Direct profile provides these familiar help bindings:

| Binding | Command | Result |
| --- | --- | --- |
| `C-h b` | `describe-bindings` | List active bindings in resolution order. |
| `C-h k` | `describe-key` | Capture a key sequence and explain its effective and alternate definitions. |
| `C-h w` | `where-is` | Find active bindings and command-entry surfaces for a registered command. |
| `C-h m` | `describe-keymap-state` | Describe the active profile and state plus the loaded profile catalog. |

Inspection output retains the map, profile, surface, provider or package,
binding disposition, command identity, availability, and declared command
effects. The same canonical inspection commands remain available through
`M-x`; the bindings do not create a separate help registry.

## Applicability and Exclusions

The fixture contains 178 applicable cases and 12 terminal exclusions. An
excluded case remains visible in the ledger instead of disappearing from the
denominator. Frame-only and graphical text-scaling operations are excluded
because the terminal UI has no equivalent frame or graphical scaling object.

All 178 applicable cases resolve through an exact binding, one declared
composition, or one normalized alias. Their behavior classifications are 95
matches, 12 behavior matches, 66 explicit adaptations, and 5 partial matches.
No applicable row is unclassified or mapped to an unrelated command.

## Final Ledger Results

| Scope | Cases | Applicable | Binding result | Behavior result |
| --- | ---: | ---: | --- | --- |
| Core | 108 | 97 | 95 exact, 1 composition, 1 normalized alias | 58 match, 12 behavior match, 22 adapted, 5 partial |
| Maksym | 26 | 25 | 25 exact | 18 match, 7 adapted |
| Darek | 5 | 5 | 5 exact | 1 match, 4 adapted |
| Jan Babel | 26 | 26 | 26 exact | 11 match, 15 adapted |
| Ksawery | 19 | 19 | 19 exact | 1 match, 18 adapted |
| Roman | 6 | 6 | 6 exact | 6 match |

The 12 exclusions remain explicit rows: 11 Core operations depend on graphical
frames or visual text scaling, and one Maksym operation targets another
graphical frame. Package-family assessments remain separate from this ledger.
Darek's broader 45-family assessment, for example, retains five explicit
reference-only boundaries and four partial relationships outside the supplied
row corpus. This avoids turning different denominators into one compatibility
percentage.

The ledger is the reproducible closure boundary. Broader package reports can
describe absent optional features, but they cannot reduce a confirmed binding
or change its command identity without updating the versioned row and checker.

Exact binding, alternate binding, behavior match, partial match, and missing
behavior are separate classifications. A familiar key is safe only when it
invokes the corresponding semantic command in the matching context.

## Conflict Policy

- A familiar key must not invoke an unrelated or more destructive operation.
- Module-local bindings apply only while that module owns the active surface.
- Relocation keeps the existing command available while freeing the familiar
  key for its conventional family.
- Command names remain available through `M-x` when no safe TUI binding is
  assigned.
- Direct and modal profiles share command identities but own separate maps.

## Roman Entry Map

Roman contributes its familiar map only while the package is enabled and a
Jan document is active:

| Binding | Command |
| --- | --- |
| `C-c n l` | `roman-relations-open` |
| `C-c n f` | `roman-node-find` |
| `C-c n g` | `roman-graph` |
| `C-c n i` | `roman-node-insert` |
| `C-c n c` | `roman-capture` |
| `C-c n j` | `roman-daily-capture` |

Direct and Modal maps use the same command identities. Package replacement,
disablement, and removal withdraw the maps with the corresponding contribution
generation.

## Register Migration

| Previous Direct binding | Current access | Reason |
| --- | --- | --- |
| `C-x r s` for prompted text | `M-x store-text` | `C-x r s` now stores the active region. |
| `C-x r SPC` for region text | `C-x r s` | The familiar register binding stores the region. |
| `C-x r j` for storing a position | `C-x r SPC` | Space stores the current point in a position slot. |
| `C-x r f` for layout restoration | `C-x r j` or `M-x restore-layout` | `C-x r f` is a frame command and is excluded in the TUI. |

`C-x r j` opens the typed-slot selector. A position visits its file and point;
a layout restores its compatible pane topology. Text and integer slots remain
visible for discovery but report that they cannot be visited. `C-x r i`
continues to insert text slots, and `C-x r w` continues to store layouts.

## Ksawery Safety Migration

Ksawery uses `d`, `r`, `m`, `M`, `C`, `i`, `I`, `o`, `O`, `T`, `w`, `W`,
`>`, `z`, `Z`, `l`, and `B` for their
familiar Status families. Those keys do not invoke the previous unrelated
actions. Existing operations remain explicitly available:

| Operation | Current Ksawery key |
| --- | --- |
| Refresh | `g` |
| Mark, unmark, clear | `*`, `-`, `0` |
| Discard selected path | `k` |
| Fetch selected remote | `&` |
| Skip active rebase step | `;` |
| Inspect the active sequence | `M-x ksawery-sequence` |

Discard retains its exact confirmation and stale-generation checks after the
binding relocation.

The delivered inspection sequences are `z z` for Stash, `Z Z` for Worktree,
`l r` for Reflog, and `B b` for Blame. `z l` and `Z l` are equivalent list
entries inside their respective families.

The advanced familiar families prepare reviewed operations rather than hiding
raw Git effects: `C` clones, `i` opens ignore policy, `I` initializes, `o`
manages submodules, `O` manages subtrees, `T` manages notes, `w` applies
patches, `W` creates patch output, and `>` manages sparse checkout. Gitignore
files are edited as ordinary Odra resources. The other families reuse
Ksawery's bounded argument editor, exact confirmation, Process ownership,
cancellation, and repository refresh.
