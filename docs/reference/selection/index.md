<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Selection Reference

This reference defines the current point, mark, region, command, display, and
history contracts.

## Logical state

Each live buffer owns:

- one effective point, represented by a persistent right-affinity anchor;
- zero or one retained mark, represented by a persistent left-affinity buffer
  anchor;
- one region-activation flag independent from endpoint equality;
- one selection shape, either linear or rectangular, with logical grapheme
  columns as the current rectangle policy.

Each live `view` owns one independently transformed stored-point anchor plus
desired display column and viewport state. Simultaneous views of one buffer
share mark and activation but retain different stored points and viewports.

The linear region is the ordered half-open interval between point and mark.
Direction is retained by endpoint identity: point may be before or after mark.
An active empty linear region is valid. A rectangle treats both endpoint
columns as included, so equal endpoints select the current grapheme column on
one line. A region cannot be active without mark.

`view.Snapshot` reports the view's stored `point_position`, the buffer's
`effective_point_position`, shared `mark`, and shared `region_active` at one
checked revision. Closing a view releases its stored point and viewport; it
does not release buffer point or mark.

## View operations

| Operation | Result |
| --- | --- |
| `set_point` | Moves point without changing mark or activation. |
| `move_point` with `Preserve` | Moves point and desired column while retaining activation. |
| `set_mark` | Creates or moves mark and optionally activates the region. |
| `set_region_active` | Changes activation without moving or releasing mark; deactivation resets the shape to linear. |
| `set_selection_shape` | Changes an active canonical region between linear and rectangular projection. |
| `exchange_point_and_mark` | Swaps endpoints and activates the region. |
| `clear_mark` | Releases mark and deactivates the region. |

Logical text-edit publication can preserve, deactivate, or activate a region
and can preserve, remove, or restore mark at a checked result position. The
complete result publishes with canonical text without an expected-failure
boundary after publication begins.

## Semantic commands and direct bindings

| Command | Direct binding | Behavior |
| --- | --- | --- |
| `set-mark-command` | `C-SPC`; terminal `C-@` is the same physical byte | Set mark at point and activate the region. |
| `exchange-point-and-mark` | `C-x C-x` | Swap endpoints and activate the region. |
| `keyboard-quit` | `C-g` | Clear pending key input or deactivate the active region while retaining mark. |
| `deactivate-mark` | Unbound | Deactivate the region while retaining mark. |
| `select-word` | `M-@` | Select the direct-profile word at point. |
| `select-paragraph` | `M-h` | Select the logical paragraph at point. |
| `select-buffer` | `C-x h` | Select the complete active buffer. |
| `select-rectangle` | Unbound | Project the active region as a logical grapheme rectangle. |
| `copy-rectangle` | Unbound | Copy its per-line ranges as newline-separated retained text. |
| `kill-rectangle` | Unbound | Remove and retain all per-line ranges in one transaction. |
| `replace-rectangle-text` | Unbound | Replace all per-line ranges with one entered value in one transaction. |
| `select-definition` | `C-M-h` | Select the current language definition containing point. |
| `structural-select` | `C-M-SPC` | Select the enclosing named structural unit. |
| `pop-selection-location` | `C-u C-SPC` | Restore the newest available retained selection or location. |

Ordinary movement preserves an active region. Ordinary self-insertion occurs
at point, never replaces the region implicitly, and deactivates it after a
successful commit. View-only commands do not create history nodes.

The terminal decoder normalizes bytes `0x01` through `0x1a` into logical
Control-modified scalar keys. Byte `0x00`, produced by `C-SPC` or `C-@`, is
normalized as `Control-Space`.

## Persistent named state

Named locations and slots are stored under the global configuration state
root and survive editor restarts. Names are bounded and unique within the
shared persistent collection. Reusing a name with the same kind replaces its
value atomically; changing its kind requires explicit confirmation.

Storage prompts qualify names by value type. Commands that retrieve an
integer, text, layout, or named location use the shared fuzzy candidate list.
Type-specific commands restrict it to compatible values. `visit-slot` lists
all typed slots so it can visit a stored position or restore a stored layout;
selecting text or integer state reports that the type is not visitable. Text
and integer slots include a bounded preview derived from their already loaded
value; layouts remain name-only.

| Command | Direct binding | Behavior |
| --- | --- | --- |
| `save-location` | `C-x r m` | Store point, mark, and region state for the active document under a name. |
| `list-locations` | `C-x r l` | List the available named locations. |
| `visit-location` | `C-x r b` | Select and visit a named location. |
| `store-number` | `C-x r n` | Store one signed integer under a name. |
| `increment-number` | `C-x r +` | Add a checked signed increment to one integer slot. |
| `store-text` | `M-x store-text` | Store entered UTF-8 text under a name. |
| `store-region-text` | `C-x r s` | Store the active nonempty region as text, then deactivate it while retaining mark. |
| `store-position` | `C-x r SPC` | Store the active document and point as a position slot. |
| `insert-slot` | `C-x r i` | Insert a selected text slot through the reversible editing path. |
| `store-layout` | `C-x r w` | Store the portable pane tree, document targets, selection, and dedication. |
| `visit-slot` | `C-x r j` | Visit a stored position or restore the compatible portion of a stored pane layout. |
| `restore-layout` | `M-x restore-layout` | Restore a stored pane layout through the layout-only selector. |

Locations and positions require regular local-file targets. Visiting a
missing target or invalid position leaves the current editor location intact.
Integer overflow leaves the stored value unchanged. Layout snapshots exclude
terminal geometry and native resources; restoration may collapse a subtree
that the current terminal cannot display, and reports that partial result.

## Display and terminal presentation

`display.Region_Map` records ordered canonical byte bounds and the visible
display positions of either endpoint. Projection derives those bounds from
point and mark before layout; it never reconstructs them from cells. A
rectangular region additionally derives one bounded half-open range per
logical line from the anchor and point grapheme columns. Short lines clamp to
their text, and terminal cell geometry does not redefine the rectangle.

Only an active non-empty region is highlighted. The renderer clips the region
at visible grapheme boundaries and applies the active theme's `Text_Region`
foreground, background, and attributes. Colored factory themes use their
selection background; `Terminal Default` uses reverse video. Inactive and
empty regions produce no highlight. Tabs, wide graphemes,
combining sequences, emoji clusters, vertical clipping, and horizontal
scrolling preserve canonical region bounds.

The UI text projection copies the exact selection generation and assigns the
visible nonempty region the semantic `Text_Region` role. The terminal validates
that role against the matching logical and display snapshots, clips it at
visible grapheme boundaries, and lowers it as part of the complete UI frame.
A change in activation, generation, or visible endpoints therefore requires a
new compatible UI root even when the UTF-8 row bytes are unchanged.

## Selection layers

Editor selection is semantic buffer state. Keyboard and pointer selection use
the active buffer's effective point, mark, and activation. A primary-button
press over represented text places point and deactivates the active region
while retaining mark. A primary-button drag assigns the origin to mark, moves
point through represented text boundaries, and leaves the resulting ordinary
linear region active on release. These transitions create no text-history
node.

Pointer selection cannot span panes or buffers. It begins only on represented
text, clamps to the visible projection of its originating pane, and derives
copied content from the canonical buffer range. Gutters, Status Bars,
separators, borders, popup content, padding, and neighboring panels therefore
cannot become part of the selected value. Stale geometry, invalid mapping,
capture cancellation, or resource limits preserve the last confirmed
selection state and end the transient capture.

Terminal-emulator selection is external geometric state over rendered cells.
It can cross pane boundaries and include cells from different buffers or
separators. Odra does not receive that range as editor selection and cannot
constrain it semantically. It remains distinct from Odra's pointer selection.

The first pointer delivery excludes drag autoscroll, rectangular and multiple
selection gestures, semantic double and triple click, ordinary editor wheel
scrolling, and secondary-button contextual commands. `C-SPC` plus ordinary
movement is the keyboard equivalent for linear selection; `select-rectangle`
converts an active keyboard region, and the semantic selection commands listed
above remain available for larger units.

## History restoration

Each tracked logical edit may retain, for both its before and after boundary:

- point byte offset and desired display column;
- whether mark exists and its byte offset when present;
- region activation;
- selection shape and rectangle column policy.

Undo restores the first record's before context; redo restores the last
record's after context. The initiating live view is preferred. If it no longer
exists, the invoking view for the same buffer receives the context. Other
views retain their stored points and viewports while their anchors transform
through the text publication. All views observe the restored buffer mark and
activation.

Restoring a missing mark reserves its anchor before the history transaction
begins. Failure, cancellation, stale identity, or allocation rejection releases
the reservation and changes neither canonical text nor logical view state.

## Relevant limits and failures

Mark and view creation are subject to buffer anchor limits. The registry admits
1,024 retained primary and 128 additional view records. View operations reject
stale handles, wrong buffers, active preparations, state-generation exhaustion,
duplicate primary creation, invalid configuration, and attempts to activate
without mark. Projection
rejects stale or incompatible snapshots and applies the documented display
source, mapping, and storage limits.

Use `odin doc src/view -in-source-order`,
`odin doc src/display -in-source-order`, and
`odin doc src/command -in-source-order` for generated declaration reference.
