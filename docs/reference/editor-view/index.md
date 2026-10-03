<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Editor View and Display Reference

This reference describes the current public contracts that connect canonical
buffer text to the interactive terminal proof. Declaration-level source
comments remain authoritative.

## Responsibility map

| Package | Owns | Does not own |
| --- | --- | --- |
| `editor` | Canonical UTF-8 text, revisions, effective point, optional mark, region activation, persistent anchors, atomic splices | Viewport geometry or terminal state |
| `view` | Checked view identity, stored point, desired column, viewport origin, horizontal offset, resolved display policy | Canonical text, mark, activation, or physical rows |
| `display` | Unicode profile, navigation calculation, bounded projection, immutable snapshots, source/display mappings, optional checkpoints | Buffer mutation or terminal I/O |
| `ui` | Checked `Text_View` projections, logical surfaces, composition, status regions, semantic styles, and immutable UI roots | Canonical text, editor-view mutation, pane mutation, or terminal output |
| `terminal_frontend` | POSIX terminal session, normalized input, generic UI-root lowering, ANSI encoding, writes, flush, restoration | Logical cursor or canonical text |
| `odra` | Application assembly, editor-session composition, event loop, interaction routing | Reusable editor or frontend contracts |

## Editor-view lifecycle

`view.Registry` owns at most `MAX_VIEWS`, currently 1,152: 1,024 retained
primary records plus 128 additional records. A `View_Handle` is
checked by registry identity, view identity, slot, and generation; it is not a
raw pointer.

`view.create` creates the buffer's unique retained primary record.
`view.clone_additional` copies one source view's stored point, desired column,
viewport, and display policy into a bounded additional record. Both operations
create persistent anchors for stored point and viewport origin before
publication. Mark and activation remain in the buffer.
`view.close` releases all view-owned anchors and invalidates the supplied
handle; it never closes the buffer or clears its selection.
`view.registry_close` accepts only an empty registry.

`view.Snapshot` is an immutable logical value containing:

- exact buffer and view identity and generation;
- the current buffer revision;
- stored point and buffer effective point;
- buffer-owned optional mark and region activation;
- desired display column;
- viewport origin and horizontal display-column offset;
- resolved tab width and display-profile identity.

`view.move_point` changes point position, desired column, and one declared
region outcome as a single transition. Ordinary command movement uses
`Point_Movement_Region_Action.Preserve`, so an active region remains active.
`set_mark`, `set_region_active`, `exchange_point_and_mark`, and `clear_mark`
provide checked transitions over buffer-owned selection. `store_effective_point`
and `restore_stored_point` are the native synchronization primitives used by
the atomic pane-focus transaction.

Creation rejects duplicate primary records and retained or additional capacity
overflow before publication. Wrong-registry, stale-handle, anchor-allocation,
active-preparation, and generation failures preserve existing buffer and view
state.

## Navigation

`display.navigation_target` calculates a target without mutating the view or
buffer. Its `Navigation_Kind` values are:

| Kind | Behavior |
| --- | --- |
| `Previous_Grapheme` | Move to the preceding extended-grapheme boundary, crossing a line ending when possible. |
| `Next_Grapheme` | Move to the following extended-grapheme boundary, crossing to the next line when possible. |
| `Previous_Line` | Choose the nearest grapheme boundary on the preceding logical line. |
| `Next_Line` | Choose the nearest grapheme boundary on the following logical line. |
| `Line_Start` | Move to the current logical line start. |
| `Line_End` | Move to the current logical content end, before its line ending. |

Horizontal movement returns the actual target display column. Vertical
movement preserves `Snapshot.desired_display_column`, including while passing
through a shorter line. Navigation examines at most the 64 KiB operating
source allowance for one logical line and returns `Source_Byte_Limit` when the
line exceeds it.

## Projection

`display.project` consumes one checked set of inputs:

```text
buffer + view snapshot + viewport constraints + display profile + limits
-> immutable display snapshot or explicit failure
```

The initial model maps one logical line to one display row. It horizontally
clips complete graphemes and does not soft-wrap. Each row refers to compact
UTF-8 runs and boundary maps rather than owning one heavyweight value per
terminal cell.

A display snapshot is compatible only when all of these still match:

- buffer identity and revision;
- view identity, generation, and state generation;
- display-profile and Unicode version identity;
- viewport constraints and resolved tab width.

`display.snapshot_view` borrows immutable arrays until
`display.snapshot_close` consumes their owner. A stale or incompatible
snapshot must not be rendered as current state.

## Initial display profile

`display.terminal_unicode17_profile` selects deterministic Unicode 17.0.0
segmentation and terminal-width behavior:

- ambiguous-width text occupies one cell;
- recognized emoji presentation and ZWJ sequences occupy two cells;
- unsupported presentation uses a one-cell replacement;
- tabs remain canonical `\t` bytes and expand to the next resolved tab stop;
- the default resolved tab width is four cells.

The profile is an explicit input. Replacing Unicode data does not require a
different projection representation.

## Terminal input

`terminal_frontend.Decoder` retains at most
`MAX_INPUT_SEQUENCE_BYTES`, currently eight bytes. `decoder_push` consumes one
byte and produces at most one normalized `interaction.Input` value.

| Physical input | Normalized input |
| --- | --- |
| Left, Right, Up, Down | Corresponding logical special key. |
| Home or `CSI 1~` / `CSI 7~` | `Home`. |
| End or `CSI 4~` / `CSI 8~` | `End`. |
| Backspace `0x08` or `0x7f` | `Backspace`. |
| `CSI 3~` | `Delete`. |
| Carriage return or line feed | `Enter`. |
| Printable ASCII or one complete UTF-8 scalar | `Unicode_Scalar` key with committed text. |
| Required control bytes | Unicode scalar key with the `Control` modifier. |

The direct profile maps byte `0x00`, emitted by terminal `C-SPC` and `C-@`, to
logical `Control-Space`. Control bytes `0x01` through `0x1a` map to their
corresponding Control-modified scalar keys.

`Decode_Status` distinguishes `Event`, `Pending`, `Incomplete`, `Malformed`,
`Oversized`, `Unknown`, and `Unsupported`. Only `Event` enters interaction
routing. Every other result leaves canonical text unchanged. Decoding performs
no allocation, and it does not select a command or process exit action.

## Terminal session and renderer

`session_acquire` owns raw-mode changes, the previous `SIGWINCH` action, and
the initial terminal geometry. `session_restore` consumes that ownership,
restores the exact saved terminal attributes and signal action, resets styling,
and makes the physical cursor visible.

`proposal_project_editor_text_view` copies one exact `view.Snapshot` into a
logical `Text_View`. The projection preserves view and buffer generations,
point, mark, region activation, viewport, display policy, presentation
ownership, and the current search match. A single-view presentation places
that view in one surface; a pane presentation maps every delivered pane into
one surface under the shared UI root.

`renderer_present_ui` accepts one compatible immutable UI snapshot plus one
`Text_Surface_Projection` for every text surface. Each projection binds the
surface to the exact compatible display and logical view snapshots used for
its text. The terminal validates the complete root, geometry, identities,
generations, semantic region and search state, and renderer profile before it
allocates and writes one bounded full frame. The renderer retains no logical
view state or physical-row cache between presentations.

An active non-empty `display.Region_Map` is rendered with reverse video. The
UI text projection and display snapshot retain the semantic selection and
visible region offsets, so activation or endpoint changes produce a new
validated full frame even when their UTF-8 bytes are equal.

## Operating limits

| Resource | Initial operating limit |
| --- | ---: |
| Viewport width | 240 cells |
| Viewport height | 80 rows |
| Displayed product | 19,200 cells |
| Source work per projection or navigation line | 64 KiB |
| Retained derived display storage | 2 MiB per view |
| Compact runs | 4,096 per snapshot |
| Boundary mappings | 65,536 per snapshot |
| Long-line checkpoints | 4,096 per view |
| Encoded terminal output | 2 MiB per write request |
| Pending terminal input sequence | 8 bytes |

Expected limit, allocation, stale-state, compatibility, terminal, and I/O
failures are returned as package-specific failure values. Allocation failure
does not publish a partial splice, snapshot, view transition, UI root, or
terminal frame.

## Generated declaration reference

Render the public Odin documentation from the repository root with:

```sh
odin doc src/view -in-source-order
odin doc src/display -in-source-order
odin doc src/terminal -in-source-order
odin doc src/odra -in-source-order
```

Run `make docs-check` to generate all package reference files, require public
source comments, and validate Markdown links.

For the design rationale, see
[Frontend-Independent Editor Views](../../explanation/frontend-independent-view/index.md)
and [Why Selection Uses Point, Mark, and Region](../../explanation/selection/index.md).
