<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Work in the Modal Profile

This chapter activates `modal`, completes one ordinary editing workflow, uses
the integrated terminal without losing child input, and returns safely to
`direct`.

## Before You Begin

If you enter this chapter directly, first complete
[Prepare the User Guide Exercises](../getting-started/prepare-exercises.md) and
[Use Commands and Interactions](../getting-started/commands-and-interactions.md).
Reset the chapter-owned configuration examples:

```sh
"$HOME/odra-guide/kit/bin/odra-guide" reset configuration-examples
```

The keys below are factory bindings. Personal maps and active components can
change the effective route; use `describe-key` and `describe-keymap-state` to
inspect the current result.

## Make Modal the Startup Profile

Create `~/odra-guide/config/odra/init.rkt` with this complete configuration:

```racket
#lang racket/base

(require odra/keymaps)

(provide odra-interaction-profile)

(define odra-interaction-profile
  (factory-modal-interaction-profile))
```

Launch the tutorial note:

```sh
odra "$HOME/odra-guide/work/dirs/notes/review.md"
```

The Status Bar shows `NORMAL`, and the text cursor is a block. A configuration
failure preserves the last confirmed profile generation. Without this
selection, a clean installation still starts in `direct`.

For a session-only change, run `M-x select-interaction-profile`, select
`modal`, and press Enter. Confirmation starts Normal without rewriting
`init.rkt`. Select `direct` through the same command when you want to return.

## Move, Insert, and Replace Text

Normal does not insert unmatched printable input. Move with `h`, `j`, `k`, and
`l`; use `0` and `$` for line boundaries, `w`, `b`, and `e` for words, and
`gg` or `G` for the buffer boundaries. Arrow, Home, End, Page Up, and Page Down
remain available through their canonical movement commands.

Press `i`. The Status Bar changes to `INSERT`, the cursor becomes a bar, and
ordinary text edits the active buffer. Backspace and Delete invoke the same
canonical deletion commands used by Direct. Press `Escape` or `C-[` to return
to Normal. The other factory entry keys are:

| Key | Result |
| --- | --- |
| `a` | Move after the current grapheme and enter Insert. |
| `I`, `A` | Enter Insert at the first non-whitespace or line-end boundary. |
| `o`, `O` | Create a line below or above and enter Insert there. |
| `R` | Enter Replace at point. |

Insert retains compatible Direct editing bindings. For example, `C-w` keeps
`kill-region`, `C-y` keeps `yank`, and `C-r` keeps backward search. Modal
conventions do not replace those delivered Direct meanings while Insert owns
input.

Press `R` in Normal to enter Replace. The Status Bar changes to `REPLACE`, and
supporting frontends use an underline cursor. Type over existing text to
replace complete graphemes. Input at the end of the line inserts before the
line break, so replacement never consumes the following line. Press `Escape`
or `C-[` to return to Normal; ordinary undo and redo reverse and restore the
replacement transactions.

## Use Counts, Search, and Operators

In Normal, type `3w` to move by three word starts. Digits `1` through `9`
start a bounded count; `0` is a digit only after a count has started and is
otherwise line-start movement. An overflow or an incompatible counted command
is rejected before movement or mutation.

Press `/`, enter a literal search pattern, and press Enter. Use `n` and `N` to
repeat the confirmed canonical search forward or backward. `?` begins the
same search workflow in the opposite direction.

Operators resolve one checked target before changing text:

| Input | Result |
| --- | --- |
| `d{movement}`, `c{movement}`, `y{movement}` | Delete, change, or copy one movement range. |
| `dd`, `cc`, `yy` | Apply the operator to complete logical lines. |
| `>`, `<` with a target | Indent or outdent intersecting logical lines. |
| `x`, `X` | Delete the next or previous complete grapheme. |
| `r<char>` | Replace one complete grapheme and remain Normal. |
| `p`, `P` | Paste shared retained text after or before point. |
| `.` | Repeat the latest admitted semantic change at the current point. |
| `u`, `C-r` | Invoke canonical undo or redo. |

Counts compose with operators and movements. Modal delete, change, copy, and
paste share Odra's ordinary history, kill ring, clipboard adapter, and named
text slots; there is no second modal buffer or unnamed register.

To try semantic repetition, press `i`, type `reviewed`, and return to Normal
with `Escape`. Move to another insertion point and press `.`. Odra resolves the
recorded Insert entry at the new point and commits the retained text as one
history unit. Press `u` to reverse only that repeated change and `C-r` to
restore it.

You can also repeat deletion, change, replacement, indentation, paste, and
named-slot insertion. Operator movements and named slots are resolved from the
current context. If the command catalog or modal profile has changed, or the
current target is unavailable, Odra reports the rejection without changing
the buffer. Run `M-x describe-modal-repeat` to inspect the bounded record
without displaying its retained text.

## Select with Visual States

Press `v` for Visual Character, `V` for Visual Line, or `C-v` for Visual Block.
The Status Bar shows `VISUAL`, `VISUAL LINE`, or `VISUAL BLOCK`. Movement
extends the active buffer's canonical selection. Character and Line use a
linear region; Block derives one logical grapheme-column range per intersected
line. Use `o` to exchange its active end and anchor.

Apply `d`, `c`, or `y` to any Visual selection. Rectangular copy joins the
selected line ranges with newlines; rectangular delete and change edit all
ranges as one undoable transaction. `>` and `<` apply to Character and Line
selections. Delete, copy, indent, and outdent return to Normal; change enters
Insert. `Escape` or `C-[` cancels Visual interaction and returns to Normal.

## Invoke Commands and Use Editor Contexts

Press `:` in Normal or any Visual state, type a canonical command name such
as `save-associated-document`, and press Enter. `:` and protected `M-x` use
the same command catalog and command identities; shorthand aliases such as
`:w` are not added.

Use the Normal pane prefix to work across views:

| Input | Result |
| --- | --- |
| `C-w h`, `C-w j`, `C-w k`, `C-w l` | Focus an adjacent pane. |
| `C-w s`, `C-w v` | Split below or to the right. |
| `C-w c`, `C-w o`, `C-w =` | Close, keep only, or balance panes. |

The ordinary buffer candidates, prompts, completion, Darek, Maksym, Ksawery,
search, diagnostics, and result surfaces keep their local input maps while
active. Closing them restores the compatible modal state. Switching to a
different buffer ends a Visual selection because a selection cannot span
buffers.

## Work in the Integrated Terminal

Run `M-x terminal-new`. A focused live terminal keeps its terminal-input
context, so ordinary keys go to the child even when the Status Bar says
`NORMAL` or `INSERT`. In particular, ordinary `Escape` is encoded for the
child; it does not leave Insert or change editor state.

Press `C-\ C-n` to enter modal terminal copy mode. The child keeps running,
and retained terminal text accepts `h`, `j`, `k`, `l`, `0`, `$`, arrows, Home,
End, Page Up, and Page Down. Use `C-SPC` to set the mark and `M-w` to copy.

Press Enter to finish copy mode and return to live input in Normal. Press `i`
instead to finish copy mode, enter Insert, and return to live child input.
Live input uses the child-owned terminal cursor; copy mode uses a non-blinking
block cursor at the retained-text point.

`M-x` and `C-g` remain protected editor recovery routes. Run
`M-x terminal-send-next-key`, or use its factory `C-q` binding, to forward one
otherwise intercepted terminal key. The `direct` profile retains its existing
terminal bindings and pass-through behavior.

## Inspect and Recover

Run `M-x describe-keymap-state` to inspect the selected profile, state,
pending modal composition, and active contextual owner. Use `describe-key` for
one physical sequence and `where-is` for the active bindings of one canonical
command.

Press `C-g` to cancel a pending count, operator, character target, command
entry, prompt, or candidate interaction. A stale view, buffer, state, terminal,
or configuration candidate is rejected without partial mutation; the last
confirmed profile and recovery commands remain available.

Recorded macros, external editor configuration, and external editor plugins
remain outside the current modal profile.

## Verify the Result

You have completed this chapter when startup shows Normal; Insert edits and
returns with `Escape`; counts, search, one operator, and one Visual selection
work; `C-v` creates a rectangular Visual Block selection; `:` invokes a
canonical command; pane and buffer contexts restore modal input; terminal
`Escape` reaches the child; `C-\ C-n` enters copy navigation; `i` returns that
terminal to live input in Insert; and `.` repeats a change as one undoable unit.

For the exact factory grammar, state, resource, inspection, and exclusion
contracts, read the
[Modal Interaction Profile Reference](../../../reference/modal-interaction-profile/index.md).
For terminal troubleshooting, read
[Troubleshoot the Integrated Terminal](../../../how-to/troubleshoot-integrated-terminal/index.md).

---

[Previous: Modal Interaction](index.md) ·
[User Guide](../index.md)
