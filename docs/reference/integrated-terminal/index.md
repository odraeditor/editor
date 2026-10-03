<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Integrated Terminal Reference

An integrated terminal is a retained terminal-backed buffer associated with
one independent local PTY process and terminal-emulator state. Ordinary panes
may present the same session more than once without duplicating the process.

## Commands

The lifecycle commands are `terminal-open`, `terminal-new`,
`terminal-open-here`, `terminal-open-project`, `terminal-open-other-pane`,
`terminal-toggle`, `terminal-list`, `terminal-rename`, and
`terminal-terminate`. `terminal-clear` clears through terminal input;
`terminal-clear-scrollback` drops retained history.

`shell-command` (`M-!`) presents one task-backed command result.
`async-shell-command` (`M-&`) retains the result without replacing the active
view. `compile` retains the accepted command, and `recompile` executes it
again. A completed compilation result binds `g` to `recompile`. All four use
the existing nonblocking process and terminal owners.

Interaction commands include `terminal-copy-mode`, prompt and result movement,
`terminal-open-link`, `terminal-send-next-key`, and the `terminal-send-*`
family for Return, Tab, Escape, navigation, editing keys, and Space. Commands
are discoverable through `M-x` and are available only in compatible contexts.

## Pane Placement

`terminal-open`, `terminal-new`, `terminal-open-here`, and
`terminal-open-project` show the session in a pane below the active editing
pane. Later calls reuse that lower pane; creating another session does not
stop the previously retained shell. `terminal-open` reuses the live default
session for the active scope.

`terminal-toggle` hides or shows this lower pane and remembers its height.
Hiding leaves the shell running and returns focus to the editing pane. The
terminal participates in ordinary pane cycling with `C-x o`. When its shell
exits, the lower pane closes and focus returns to editing; a scratch buffer
is created if no text buffer remains.

`terminal-open-other-pane` retains the ordinary other-pane display policy.
Explicit buffer selection can still place a retained terminal in the selected
pane. The lower-pane default does not change `shell-command` result placement
or the hidden presentation used by `async-shell-command`.

## Contextual Keys

Live terminal input binds Return, Tab, Backspace, Delete, arrows, Page Up, and
Page Down to mode-aware terminal input. `C-y` yanks, `M-y` rotates the yank,
`C-l` clears through terminal input, and `C-q` forwards the next normalized key.
The `C-c` prefix provides `C-t` for copy mode, `C-n` and `C-p` for prompt
movement, and `C-l` for clearing scrollback.

Copy mode uses ordinary movement, `C-Space` to set the mark, `M-w` to copy,
Return to finish, and `C-c C-r` to reset the retained cursor point. The active
context map determines whether a key edits retained selection state or reaches
the child process.

## Pointer Routing

A primary-button press on an unfocused terminal focuses the pane and is
consumed locally. Once focused, a terminal without active child mouse
reporting treats a primary-button drag as local retained-text selection and
enters copy mode for that gesture. The resulting text uses the same copy-mode
point, mark, region, viewport, and `M-w` copy path as keyboard interaction.

When the child has requested mouse reporting, admitted press, release, drag,
modifier, and existing wheel events are encoded for the child. Holding Shift
retains local Odra selection ownership. Pointer routing validates the current
pane, session, geometry, and child state before either local publication or
child forwarding; an invalid or closed target cannot leak the event into an
editor buffer or another terminal.

Pointer capability is optional. Without it, `C-x o` changes pane focus and
`terminal-copy-mode` with `C-SPC`, movement, and `M-w` provides the complete
local selection path. Cleanup, frontend loss, and repeated restoration clear
pointer capture and restore terminal mouse modes without retaining an input
owner.

## Racket API

`src/command/terminal.rkt` exports immutable session, provenance, exit,
snapshot, key, subscription, event, and observation structures. The public
operations are `terminal-sessions`, `terminal-session-state`,
`terminal-visible-text`, `terminal-scrollback`, `terminal-send-text!`,
`terminal-send-key!`, `terminal-terminate!`, `terminal-subscribe!`, and
`terminal-unsubscribe!`, plus Return, Tab, and Escape conveniences.

All operations require the owner-thread terminal context and exact
generation-checked session references. Text input is limited to 4 KiB,
snapshots to 4 MiB, and copied metadata to 16 KiB. Subscription definitions
select session references and event kinds, may opt into raw output explicitly,
and carry bounded batch, time, and temporary-memory values.

## Context and Lifetime

The default session is Workspace-scoped when a Workspace is active and uses an
instance-global fallback otherwise. Hidden sessions keep running. Terminal
activity, titles, working-context reports, bells, progress, and images never
change pane placement or focus. Closing a pane detaches a view; terminating the
process and closing the retained terminal buffer are separate operations.

## Effects and Security

Titles and working-context reports are copied UTF-8 metadata, not commands or
filesystem authority. Clipboard reads and writes requested by the child are
denied. Desktop notifications and unknown sequences remain inert with bounded
diagnostics. Hyperlinks require explicit activation. External file, temporary
file, and shared-memory image media are disabled.

Kitty image payloads use an 8 MiB encoded operating bound, 16 MiB decoded
per-image bound, eight-placement ceiling, and 32 MiB active storage bound.
The terminal frontend renders one compact anchored placeholder when it cannot
render decoded pixels; it does not allocate another requested rectangle.

## Selected Limits

The operating session target is eight and the immutable ceiling is 32.
Terminal geometry is capped at 2,048 columns, 1,024 rows, and 1,048,576 cells.
Output work is limited to 256 KiB or 4 ms per turn. Scrollback defaults to
32 MiB and 100,000 rows, with ceilings of 64 MiB and 250,000 rows. Ordinary
terminal state targets 64 MiB and cannot exceed 128 MiB. One copied metadata
value cannot exceed 16 KiB.

Racket event queues default to 1,024 entries and 1 MiB per session. Delivery
batches, subscriber time, temporary memory, aggregate queues, and subscriber
counts have independent ceilings. Overflow is explicit and never transfers
native process or emulator ownership to Racket.
