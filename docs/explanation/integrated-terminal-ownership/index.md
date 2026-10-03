<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Integrated Terminals Separate Process, State, and Presentation

An integrated terminal combines three lifetimes that must not collapse into
one owner. The interactive-session layer owns the child, process group, PTY,
queues, signals, exit collection, and cleanup. The terminal-session layer owns
the pinned emulator handle, parsed state, scrollback, semantic events, images,
and copied projections. Editor buffers and panes own identity and presentation,
not the process.

This separation allows one terminal buffer to appear in several panes while
there remains exactly one child process. Hiding or replacing a pane does not
terminate the session, and closing the final retained terminal buffer can
coordinate cleanup without making the physical TUI renderer a process owner.

The emulator boundary uses the complete `libghostty-vt` state machine because
Odra needs VT parsing, mode-aware input encoding, scrollback, render state,
semantic markers, effects, and Kitty image metadata. Upstream pointers and
enums stop at the repository-owned C adapter. Odin receives generation-checked
handles and bounded copied values.

Racket remains the programmable control plane. It observes immutable bounded
events and requests checked mutations on the owner thread. PTY and parser
callbacks never enter Racket synchronously, so slow or failed automation cannot
stall native I/O or reenter emulator state.
