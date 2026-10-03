<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Selection Uses Point, Mark, and Region

Selection is not stored as an independent range. Each buffer retains effective
point and mark and derives one ordered region from them. Each view separately
retains a stored point for focus and redisplay. This keeps
movement direction, editing position, and selected bounds coherent without a
second range that could drift out of sync.

## Point is the active endpoint

Point is where movement acts and ordinary insertion occurs. Mark is a retained
reference position. Moving point therefore changes both the insertion position
and, when the region is active, one endpoint of the selected interval.

The ordered interval uses the lesser and greater positions, so exchanging point
and mark preserves the selected text while reversing direction. Commands that
care about direction can still observe which endpoint is point.

## Retention and activation are separate

Cancelling a selection should remove the immediate visual emphasis without
destroying useful positional context. Odra therefore treats mark existence and
region activation as separate state.

This separation also makes an active empty region well-defined: both endpoints
may coincide while activation remains true. Transfer commands can reject the
empty interval explicitly without pretending that mark is absent.

## Anchors keep regions coherent through edits

Effective point and mark are persistent anchors owned by the buffer. Every view
of that buffer observes the same mark and activation, while its stored point
and viewport remain independent. Canonical text publication transforms the
buffer selection and all stored view points using declared affinity and
deletion behavior.

Ordinary insertion deliberately does not replace an active region. It inserts
at point and deactivates afterward. Commands that later delete, kill, or replace
a region will name that intent and publish their complete text and logical-view
result through the transaction boundary.

## Display state remains derived

The display layer receives canonical endpoints at a checked revision, orders
them, and maps visible boundaries through Unicode-aware layout. Terminal cells
are not used to reconstruct the logical region. This matters when tabs expand,
graphemes occupy two cells, combining sequences share one cell, or either
endpoint lies outside the viewport.

The terminal renderer applies presentation styling only after projection. A
future graphical frontend can render the same region with different visual
mechanics without changing point, mark, or canonical text.

## Pointer selection reuses the same region

A pointer gesture resolves visible cells into canonical text boundaries, then
changes the same point, mark, and activation state as keyboard selection. It
does not retain a geometric rectangle from the terminal. This keeps copying
independent from line numbers, gutters, pane separators, Status Bars, and
other interface text that happened to lie along the physical drag path.

The transient capture belongs only to routing the gesture until release or
cancellation. It is bounded and cannot become a second persistent selection
owner. If geometry changes, the target closes, input is malformed, or a work
limit is reached, capture ends while the last confirmed semantic state remains
authoritative. A frontend without pointer reporting simply continues through
the existing keyboard path.

## History records command boundaries

Movement and endpoint exchange are view-only transitions and do not create text
history. A text command, however, records the complete point, optional mark,
and activation context on both sides of its commit. Undo and redo can therefore
restore what the user was interacting with, not merely a byte offset.

The [Selection Reference](../../reference/selection/index.md) states the exact
operations and bindings. [Select Text with Point and Mark](../../tutorials/selection/index.md)
walks through the visible terminal behavior.
