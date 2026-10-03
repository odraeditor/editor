<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Pane Layout Is a Native Transaction Kernel

Multiple visible panes combine topology, geometry, focus, per-pane
presentation state, and resource lifetime. Treating those as terminal drawing
details would make correctness depend on incidental render order. Odra instead
keeps one frontend-independent native kernel that publishes complete pane
states for any later frontend to project.

## The tree is semantic state

A binary tree records the durable relationship users manipulate: one pane was
split into an ordered pair, with an exact proportion. It does not record the
current terminal widths as canonical state. Geometry is derived recursively
from the tree, weights, current usable rectangle, and declared minima.

This separation matters during resize. A temporary narrow terminal can force
clamped or insufficient geometry without damaging proportions or deleting
panes. When space returns, the same tree and weights materialize again.

## Integer geometry is part of correctness

Terminal cells are discrete, so floating-point ratios would introduce
platform-dependent rounding and cumulative drift. Exact positive integer
weights plus floor-and-remainder division produce deterministic spans. Clamping
changes only the current spans. The weights remain stable and continue to
describe intent.

The status row belongs to each pane. It therefore also acts as the boundary
between above/below children. A left/right relationship has no equivalent
owned column, so its partition reserves one explicit separator column.

Operating and semantic minima answer different questions. Operating minima
admit deliberate editor actions such as split. Semantic minima decide whether
an externally resized frontend can still project every pane. Below the
semantic floor, the honest state is one insufficient-layout diagnostic, not a
partially valid substitute tree.

## Two balance objectives answer different questions

Equal dimensions and equal areas are not the same goal in a nested tree.
Dimension balance assigns row and column units through the topology and favors
subtrees that span a complete orthogonal axis. This makes `balance-panes`
useful when the visible shape of rows and columns matters.

Area balance evaluates the final height multiplied by width of every leaf.
`balance-pane-areas` can therefore give a full-width pane less height so that
its area approaches the areas of narrower panes elsewhere in the tree. It does
not replace or reset the topology; it changes only partition proportions.

Discrete cells, minima, and separator columns mean several weight maps can
have the same best area score. Odra resolves those ties by area range and then
spatial first-child spans. The native kernel searches only within its explicit
work ceiling and publishes nothing if it cannot complete the exact bounded
decision. That tradeoff keeps the result deterministic without turning an
interactive layout command into unbounded optimization.

## Focus crosses two ownership domains

The buffer owns the effective point because editing, mark, and activation are
canonical buffer behavior. Each view owns a stored point because two panes can
show the same buffer at different locations.

Focus therefore has an ordered transaction:

```text
outgoing effective point
-> outgoing stored point
-> incoming stored point
-> incoming effective point
-> active pane and MRU publication
```

The order is significant when both panes show the same buffer. The outgoing
point must be saved before the incoming point changes the shared effective
point. The view layer rolls back the first move if the second cannot publish,
so a failed focus attempt changes neither point nor layout focus.

## Spatial order and MRU answer different questions

Tree preorder expresses spatial reading order. Pane MRU expresses interaction
history. Split preserves the active pane and every existing MRU relationship;
the new pane starts least recent. Explicit focus moves its target to MRU head.
Closing the active pane promotes its structural sibling but focuses the
surviving MRU head, which can be elsewhere in the tree.

Keeping only the active pane is a structural reduction, not a hidden maximize
stack. Removed nodes and additional views are released. Retained primary views
stay with the editor session, and buffers stay alive under their existing
owners.

## Buffer history belongs to each pane

An editor-session MRU answers which buffer graph was activated recently. It
cannot answer which buffer a particular pane showed before replacement or how
that pane presented the buffer. Odra therefore retains a separate bounded
history in each pane. Each entry combines checked buffer identity with point
and viewport state, while canonical text and selection remain buffer-owned.

Splitting copies the current history instead of sharing it. The two panes can
then visit different buffers and accumulate different redisplay paths without
introducing mutable aliases. A separate top-level buffer list supplies a
layout-wide fallback but intentionally carries no redisplay state.

Replacement chooses the retained primary view when a buffer is not displayed
elsewhere and an additional view when it is. This preserves the session's
single primary-view ownership while allowing several panes to show one buffer
at independent locations.

## Kill is a layout and session transaction

Closing a buffer graph before replacing every visible occurrence would leave
panes pointing at released views. Replacing panes one at a time without prior
admission would expose a mixed layout if a later fallback or allocation failed.
The kill coordinator therefore resolves all affected panes first, preferring
each pane's own history and then the layout-wide buffer list. The killed buffer
is never an eligible fallback.

Only after all views and presentation states are prepared does the coordinator
publish the complete layout, purge the killed buffer from every history,
detach its editor-session graph, activate the resulting active pane, and clean
the detached resources. An expected failure before publication preserves the
old layout and graph.

The `*scratch*` fallback belongs to application policy, not the layout kernel.
Pathless startup legitimately contains no buffer because editing has not
started. Once a user has entered editing, killing the final editing buffer
creates one admitted unassociated scratch graph so every pane continues to
name live editable state.

## Publication follows validation

Every structural operation first resolves exact owner, layout, pane, slot, and
view generations. It then copies the bounded registry into private state,
builds the proposed topology, materializes complete geometry, validates tree
parentage, depth, focus, MRU, counts, and resource ceilings, and prepares view
effects. Only the complete result replaces the published registry generation.

This arrangement gives the terminal and command layers a narrow contract:
consume one immutable snapshot or report one bounded failure. They do not
repair trees, guess focus, recalculate ownership, or expose internal node
storage.

## Recovery preserves meaning

External resize is not an editor command and cannot be rejected merely because
the old operating geometry no longer fits. The layout therefore degrades from
operating geometry to semantic geometry, then to one explicit insufficient
state while retaining the full logical tree.

The terminal does not draw a partial tree in that final state. It presents one
global diagnostic, and the input layer narrows authority to resize, close,
keep-only, and exit. This avoids editing against invisible panes or publishing
focus changes that the user cannot observe. Once a complete semantic geometry
exists again, the same tree resumes ordinary projection.

The global prompt row is reserved outside pane geometry. Pane status rows remain
pane-owned, so transient prompts never overwrite the status of the bottom pane.

## Why the kernel is native

Racket policy chooses display destinations and composes checked layout
operations, but it does not own mutable nodes or native views. Native ownership
keeps pointer lifetime, allocator use, checked generations, geometry work, and
cleanup under one bounded system. Programmable policy can inspect copied
snapshots, observe committed generations, and request semantic operations while
the kernel remains the authority that validates and publishes them.

See [Pane Layout Reference](../../reference/pane-layout/index.md) for the API,
limits, failure taxonomy, and validation commands. See
[Why Programmable Pane Layouts Use Copied Authority](../programmable-pane-layouts/index.md)
for capability, hook, and deferred-publication rationale.
