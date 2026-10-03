<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Frontend-Independent Editor Views

Odra separates what the user is looking at from the terminal currently used to
show it. The separation is not preparation for a hypothetical GUI alone; it
keeps canonical text, interaction state, layout decisions, and physical I/O
independently checkable today.

## The pipeline

The visible path flows through explicit values and owners:

```text
Buffer --effective point and selection--> Editor view
   |                                  |
   `----------- current text ----------+-- stored point and viewport
                               |
                               v
                    bounded display projection
                               |
                               v
                    immutable display snapshot
                               |
                               v
                  terminal renderer --> terminal surface
```

Input travels in the opposite direction without reversing ownership:

```text
terminal bytes
-> bounded normalized event
-> navigation calculation or canonical buffer splice
-> updated editor-view state
-> new projection and presentation
```

The terminal reports an arrow key; it does not decide what a Unicode movement
means. The display package calculates a grapheme-aware target. The selected
view records the resulting stored point and scrolling state while the buffer
records the effective point. Buffer text changes only when an insertion reaches
the canonical splice path.

## Why point is split between buffer and view

Two people can look at the same text at different positions, or one person can
open two panes on the same buffer. Storing the cursor or scroll origin in the
buffer would make those observations interfere.

The buffer therefore keeps the effective point, optional retained mark, and
region activation. Each view keeps a stored-point anchor and viewport origin.
When focus changes, the outgoing effective point is saved into its view and the
incoming stored point becomes effective. Buffer publication transforms all of
these anchors with the edit, so every view remains meaningful at the new
revision without duplicating selection truth.

The desired display column is also view state. When vertical movement passes
through a short line, the actual cursor must stop at a valid grapheme boundary,
but the remembered target column remains available for the next longer line.

## Why layout returns a snapshot

Projection depends on more than text: it also needs a particular view state,
geometry, tab policy, display profile, and Unicode version. Bundling those
inputs into the snapshot identity makes stale presentation detectable.

The snapshot is immutable after publication. A shared UI text projection binds
its exact buffer revision, view generation, viewport, geometry, and profile to
one logical surface; the terminal validates that binding before lowering a
complete frame. Canonical text therefore cannot change behind a borrowed
pointer, and any changed input makes the previous projection incompatible.

This model also makes resize straightforward. Physical geometry changes, the
logical view stays intact, projection produces a new compatible snapshot, and
the terminal renderer performs a bounded full redraw.

## Why terminal cells are not editor state

Terminal cells are one frontend's coordinate system. A graphical frontend may
need pixels, shaping runs, fonts, bidirectional layout, or accessibility
metadata instead. Making cells canonical would force every future frontend to
pretend that its world is a terminal grid.

Odra instead gives the terminal an explicit display profile. The current
profile resolves Unicode graphemes, cell widths, replacement behavior, and tab
stops deterministically. The buffer still contains only canonical UTF-8, and
the view stores a display-column offset rather than ANSI sequences or terminal
handles.

## Bounded work before convenience

The first view does not soft-wrap. One logical line becomes one display row,
and horizontal movement reveals clipped content by changing the view's
display-column offset. This keeps source traversal, mappings, renderer damage,
and cursor behavior explicit while the ownership model is established.

Soft wrapping remains necessary for an ergonomic editor, but it changes the
meaning of vertical movement, viewport origins, row mappings, and invalidation.
Adding it later as a deliberate layout policy is safer than hiding those
decisions in the first terminal renderer.

The same discipline applies to input. Normalized events resolve through named
commands and the Racket-defined direct keymap. Physical terminal bytes do not
select editor operations directly.

## Where Racket fits

Racket remains the programmable control layer, but it is not called per byte,
grapheme, display run, row, or cell. Those are hot data paths with Odin-owned
state and explicit bounds. Future Racket commands can request coarse editor
operations through checked capabilities; the resulting canonical mutation and
view projection still follow the same ownership rules.

This preserves the useful Lisp property—programmable editor behavior—without
making garbage-collected extension objects responsible for canonical text or
terminal correctness.

See the [Editor View and Display Reference](../../reference/editor-view/index.md)
and [Selection Reference](../../reference/selection/index.md) for the exact
current contracts and
[Run the Terminal View](../../how-to/run-terminal-view/index.md) for direct
observation.
