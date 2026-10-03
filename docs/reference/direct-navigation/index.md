<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Direct Navigation Reference

The factory direct profile exposes these semantic commands in an ordinary
editable view.

| Binding | Command | Behavior |
| --- | --- | --- |
| `C-f`, `Right` | `cursor-next-grapheme` | Move forward by one complete grapheme. |
| `C-b`, `Left` | `cursor-previous-grapheme` | Move backward by one complete grapheme. |
| `C-n`, `Down` | `cursor-next-line` | Move to the next logical line. |
| `C-p`, `Up` | `cursor-previous-line` | Move to the previous logical line. |
| `C-a`, `Home` | `cursor-line-start` | Move to the current logical-line start. |
| `C-e`, `End` | `cursor-line-end` | Move to the current logical-line end. |
| `M-m` | `cursor-line-first-non-whitespace` | Move to the first non-whitespace grapheme on the current line. |
| `M-f`, `M-Right`, `C-Right`, `C-Down` | `cursor-next-word` | Move to the next direct-profile word boundary. |
| `M-b`, `M-Left`, `C-Left`, `C-Up` | `cursor-previous-word` | Move to the previous direct-profile word boundary. |
| `M-<` | `cursor-buffer-start` | Move to the start of the active buffer. |
| `M->` | `cursor-buffer-end` | Move to the end of the active buffer. |
| `M-g g` | `goto-line` | Prompt for a one-based logical line number. |
| `M-g c` | `goto-char` | Prompt for a one-based grapheme position. |
| `Tab` | `insert-indentation` | Insert one resolved indentation unit at point. |
| `Backspace` | `delete-previous-grapheme` | Delete to the previous logical indentation boundary in leading whitespace, or delete one preceding grapheme elsewhere. |
| `Insert` | `toggle-overwrite-mode` | Toggle active-view overwrite input. |
| `Delete` | `delete-next-grapheme` | Delete the complete grapheme after point. |
| `Prior` | `scroll-previous-page` | Move to the preceding viewport page. |
| `Next` | `scroll-next-page` | Move to the following viewport page. |

## Movement

Grapheme movement uses the active Unicode display profile. At either buffer
boundary, movement in the unavailable direction is a no-op. Logical-line
movement retains the desired display column; a shorter destination line uses
its end without discarding that desired column.

The direct word policy treats Unicode letters, digits, and `_` as word
graphemes. It is deterministic for plain text and does not require language
analysis. A later language capability may refine word behavior without
renaming these commands or changing their direct-profile bindings.

`M-m` moves to the logical-line end when no non-whitespace grapheme exists.

`goto-line` and `goto-char` accept positive decimal targets. Targets beyond the
available text clamp to the last line or buffer end. Character targets count
complete graphemes, so they never place point inside a combining sequence.

## Indentation, overwrite, and paging

`insert-indentation` publishes one ordinary atomic text edit using the active
view's resolved representation and logical width. The factory unit is four
spaces. Repeated `Tab` input is eligible for ordinary typing-group undo, while
a movement or other semantic boundary starts a new group.

Within leading indentation, Backspace removes whitespace to the preceding
logical indentation boundary. A partial unit returns to its nearest boundary;
outside leading indentation, the command removes exactly one complete
grapheme. `normalize-indentation-to-tabs` and
`normalize-indentation-to-spaces` convert only leading indentation on the
current or selected lines. Each normalization is one atomic undo unit and
leaves interior spaces unchanged.

Overwrite state is local to a view. Enabling it does not mutate buffer text,
the active profile, the command registry, or the keymap. A subsequent text
input replaces exactly the next complete grapheme and publishes through the
ordinary transaction and history path. Input at buffer end remains insertion.

`Prior` and `Next` use the active viewport height and retain one logical line
of context when possible. At the first or last reachable page, the matching
command is a no-op. Paging changes view state only and does not create history.

## Context and profile boundaries

The bindings belong to the direct profile, not to terminal decoding alone. A
transient prompt, search, candidate list, or other input-owning context may
bind the same physical key for its documented local behavior. Closing that
context restores direct-profile resolution without changing the direct command
definitions.

These bindings are continuity candidates for a future modal profile. They are
not global reservations: a future profile selects their availability through
the interaction-profile compatibility contract while retaining the same
semantic command identities.

## Validation

```sh
make native-command-test
make terminal-presentation-test
```

The native checks cover Unicode boundaries, desired columns, history, view
ownership, and contextual resolution. The terminal acceptance scenario covers
physical key decoding, ordinary edits, command-list ownership, paging, and
terminal restoration.
