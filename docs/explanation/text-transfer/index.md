<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Text Transfer Uses an Internal Kill Ring

Odra treats text transfer as an editor-state concern rather than as a thin
alias for the system clipboard. The internal ring makes copy, kill, yank, undo,
and rotation deterministic even when no graphical session, clipboard program,
or local presentation machine is available.

## Transfer and deletion are different intentions

Copy retains text without changing the buffer. Kill retains the same complete
text and removes it through history. Delete removes text without retaining it.
Keeping these commands distinct makes their effects visible in command
metadata and prevents deletion from silently overwriting useful retained text.

The system clipboard is an interoperability adapter. It can fail or be absent
without weakening the internal semantics.

## The presentation environment owns the physical clipboard

The process editing text and the machine displaying its terminal may be
different. A remote Odra process cannot treat a display server or clipboard
utility on its own host as equivalent to the clipboard beside the user.

Odra therefore places physical transport in the frontend. The current Herdr
path sends one bounded OSC 52 frame through terminal output to the outer
client. It does not move physical clipboard state into the editor core and
does not pretend that a write-only path can read.

## External transfer follows canonical completion

Copy first retains one immutable internal entry. Kill first coordinates ring,
text, view, and history publication. Only then may the frontend export the
exact retained value. This ordering means an external failure can be reported
without inventing rollback for a command that already succeeded internally.

Yank reverses the direction: a read-capable frontend may provide one copied
external value before the ordinary internal yank begins. Change tokens and
content comparison suppress self-export and repeated values. Any admitted
external text becomes an ordinary bounded ring entry; the physical clipboard
itself never becomes a canonical dependency of undo, redo, or later yanks.

## Capability absence is normal

Read and write are independent because terminal paths are asymmetric. The
supported Herdr path can forward clipboard writes but cannot answer clipboard
queries. Nested multiplexers and generic SSH terminals are left unavailable
until their framing, passthrough, security, and presentation behavior are
admitted from evidence.

This conservative negotiation keeps the full internal workflow usable in
headless, remote, unsupported, and failing environments while allowing a
frontend with stronger capabilities to replace the adapter later.

## Reservation makes kill atomic

Kill changes two durable structures: the session ring and a buffer with its
logical view and history. Publishing the deletion before knowing that the ring
can retain the complete text would lose the transfer value. Publishing the
ring first while the text transaction could still fail would expose a copy
that the user did not successfully kill.

Odra resolves this by preparing both sides completely. The ring owns a copied
candidate and an eviction plan; the transaction owns private text, view, and
history results. Only after both validate does the command enter an
allocation-free publication phase.

## Coalescence follows meaning, not time

Consecutive kills often express one larger removal. Forward deletion extends
the retained text at its end, while backward deletion extends it at its
beginning. This ordering cannot be recovered from timestamps alone.

Semantic sequence, event, buffer, direction, and source-position metadata make
the relationship explicit. An intervening command breaks the sequence even if
it executes immediately; a delayed command can remain compatible only when the
command coordinator still identifies the same uninterrupted semantic chain.

## Complete eviction preserves text meaning

The ring is bounded by both entry count and retained bytes. Evicting only whole
oldest entries preserves each retained value as valid UTF-8 and makes ordering
predictable. Oversized input is rejected before eviction so an impossible new
entry cannot destroy usable older entries.

## Rotation is transient text context

Yank rotation is not general ring navigation. It means “replace the text
inserted by the immediately preceding yank with the next retained value.” The
editor therefore records the exact view, revision, inserted range, ring
generation, and entry identity.

This context expires on any intervening command or state change. The strict
lifetime prevents a later `yank-pop` from replacing unrelated text and avoids
persistent hidden selection state. Rotation changes the buffer through a new
reversible transaction but leaves shared ring ordering stable.

## Odin owns state while the keymap remains programmable

Odin owns immutable entries, limits, reservation, publication, buffer state,
view context, and history because these are canonical resource-sensitive
paths. The factory bindings still originate in the Racket-defined keymap.
Later programmable transfer capabilities can invoke and inspect these checked
operations without duplicating or taking ownership of the ring.

The [Text Transfer Reference](../../reference/text-transfer/index.md) states
the exact commands, limits, and failures. [Copy, Kill, Yank, and Rotate
Text](../../tutorials/text-transfer/index.md) walks through the terminal flow.
The [System Clipboard How-to](../../how-to/use-system-clipboard/index.md)
describes the supported physical export path.
