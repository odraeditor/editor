<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Named Commands Sit Between Input and Editing

Physical input, user intent, and editor mutation are different concerns. Odra
keeps them separate so a terminal byte sequence is not permanently coupled to
one buffer operation and programmable behavior does not gain ownership of
canonical state.

## The control flow

```text
terminal bytes
  -> normalized logical input
  -> Odin-owned compiled keymap
  -> checked command handle
  -> native or Racket implementation
  -> confirmed completion
  -> redraw, no-op, or orderly exit
```

The terminal decoder knows that `CSI D` means a logical Left key. It does not
know that Left currently invokes `cursor-previous-grapheme`. The keymap makes
that decision, and the command implementation owns the checked behavior.

## Why Racket defines the map but Odin resolves it

Keymaps are programmable policy, so Racket is the natural authoring layer.
Calling Racket for every key would put garbage collection and foreign-runtime
latency on the ordinary typing path. It would also make pending prefix state
depend on dynamic objects outside the native owner.

Odra instead asks Racket for one bounded immutable factory definition during
startup. The adapter copies it into fixed records, and Odin validates and
compiles a private snapshot. The native resolver also admits multiple named
maps in one checked profile. Later resolution is allocation-free,
generation-checked, and requires no foreign call.

## Why commands have names

A stable semantic name lets bindings change without changing behavior. The
same command can later be invoked by another keymap, an interactive command
palette, a macro, or Racket composition without teaching those callers how the
buffer algorithm works.

Names also make implementation ownership explicit. Most initial commands are
native because they manipulate cursor, view, or canonical text directly. The
uppercase example is Racket-owned because it demonstrates programmable text
computation through the supported boundary.

## Why Racket still cannot edit the rope

Programmability does not require sharing internal storage. The uppercase
command receives a checked copy of one logical line and returns a proposed
replacement. Odin validates identity, revision, range, size, and UTF-8 before
publishing through the same atomic splice path used by native editing.

This preserves one authority for canonical state while allowing Racket to
express the interesting transformation.

## Prefixes and cancellation

The active snapshot owns the meaning of multi-stroke sequences. `Control-X`
begins a prefix because the current factory map contains longer bindings. The
native pending state is bounded to 16 strokes and tied to the exact snapshot
generation; the current Racket factory transfer remains limited to four
strokes until programmable profile activation widens that boundary.

`Control-G` is a declared cancellation command, not a hard-coded decoder
escape. It is recognized before extending an ordinary prefix. An invalid
continuation clears the prefix and is discarded instead of being replayed as
fresh text, keeping resolution deterministic.

## Exit is a command, not a byte

The decoder no longer treats `Control-Q` or any other byte as process
termination. The active map binds `Control-X`, then `Control-C` to
`request-editor-exit`. The command returns an explicit lifecycle completion;
the coordinator leaves the loop and restores terminal state in owner-defined
order.

This makes exit rebindable without giving a command permission to terminate
the process or bypass cleanup.

For exact bindings and limits, see the
[Programmable Command Reference](../../reference/programmable-commands/index.md).
For contextual precedence, masks, remaps, and candidate replacement, see
[Why Keymaps Are Layered](../layered-keymaps/index.md).
