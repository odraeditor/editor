<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Programmable Gutters Publish Immutable Generations

Programmable gutters need extension flexibility without placing Racket in the
row-rendering path or giving personal code ownership of editor presentation.
Odra therefore separates declarative contribution from native composition.

## Racket Defines Meaning

Personal Racket configuration describes one provider, its lane, its complete
logical-line marker generation, semantic styles, bounded representations, and
registered command actions. These are stable editor concepts rather than
terminal cells or renderer instructions.

The boundary copies and validates the complete proposal. Racket receives no
native pointers, mutable marker records, pane internals, or renderer state.

## Odin Owns Admission and Presentation

The native Gutter registry prepares and confirms a candidate before replacing
the active generation. It checks identity, generation, resource bounds,
attachment, semantic roles, and command authority. A rejection preserves the
last valid generation.

Factory and programmable markers then enter one deterministic composition
path. Side, lane order, priority, provider order, and provider-scoped marker
identity determine presentation. Theme and frontend capability select the
physical representation without changing marker meaning.

## Rendering Does Not Reenter Racket

One frame borrows one immutable provider snapshot for the complete render
turn. Cursor movement, scrolling, pane composition, and individual row
projection do not invoke Racket callbacks. Replacement and teardown wait until
that borrow has drained, so native code never observes released provider
storage.

This keeps the visible hot path bounded while leaving provider authoring and
generation construction in Racket. Command actions follow the same boundary:
a marker stores an admitted command identity, and invocation returns to the
ordinary command dispatcher instead of calling a marker-owned procedure.

## Detail Presentation Retains the Same Ownership

Marker inspection copies one bounded current marker into a shared anchored
popup generation. The popup owns placement, overlap, theme roles, and
dismissal; the Gutter provider remains the semantic owner of the marker and
its action. Repeated inspection replaces the presentation generation rather
than creating a second marker registry or a Gutter-specific renderer.

When overlap is unavailable, the same copied detail uses the shared compact
feedback path. This degradation changes presentation only; it does not move
provider logic into the renderer or call Racket during a frame.

## One Provider Is a Deliberate Initial Bound

The initial public boundary admits one personal provider with one lane and 256
markers. The limit is sufficient for a dense terminal viewport and keeps
replacement, rollback, memory accounting, and teardown explicit. It does not
create a separate extension renderer or imply that factory providers receive
the same limit.

See the [Gutter Reference](../../reference/gutter/index.md) for the exact API
and [Configure and Reload a Programmable Gutter](../../how-to/configure-programmable-gutter/index.md)
for the operational workflow.
