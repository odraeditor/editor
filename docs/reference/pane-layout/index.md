<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Pane Layout Reference

The `layout` package owns one bounded, frontend-independent binary pane tree.
It coordinates checked pane identity, retained and additional editor views,
pane-local buffer histories, display policy, integer geometry, focus order,
structural transformations, programmable observation, and teardown. The terminal
package projects complete snapshots, and the command and hosting packages expose
checked native and Racket transformations. The layout does not own buffers or
retain a hidden tree for maximize restoration.

## Entities and ownership

| Entity | Contract |
| --- | --- |
| Layout registry | Owns one live tree, geometry snapshot, focus state, pane MRU, display policy, pane dedication, accounting, and layout generation. |
| Partition | Has exactly two ordered children, an above/below or left/right arrangement, and two exact positive integer weights. |
| Pane | Is one leaf with a checked pane identity, one editor-view handle, one buffer identity, one bounded buffer history, dedication, pane geometry, and an MRU rank. |
| Retained primary view | Remains owned by its editor session when its pane closes or another pane is kept. |
| Additional view | Is created by split, owned by the layout while visible, and released by close, keep-only, or layout teardown. |
| Buffer | Owns canonical text, effective point, mark, and region activation. The editor session owns its graph; coordinated layout kill may detach that graph only after every visible occurrence has a fallback. |

`Registry`, `Layout_Handle`, and `Pane_Handle` contain no borrowed tree or view
pointers. A layout handle contains owner, layout, and layout-generation
identity. A pane handle additionally contains pane identity, slot, and slot
generation. Every state-changing materialization or transformation advances
the layout generation, so earlier handles reject as stale.

## Lifecycle and inspection

| Operation | Result |
| --- | --- |
| `registry_init` | Creates one materialized root pane from an existing live view. |
| `registry_handle` | Copies the exact current layout handle. |
| `registry_snapshot` | Copies the complete tree in spatial preorder with dedication, geometry, focus, and MRU rank. |
| `registry_stats` | Copies node, pane, partition, dedication, storage, and geometry-work accounting. |
| `registry_close` | Releases every visible additional view and the registry allocation. Retained primary views and buffers survive. |

Snapshots are fixed-size caller values. They contain no native pointers or
borrowed registry collections.

## Pane buffer history

Each pane retains a duplicate-free, most-recent-first history of live buffer
contexts. One `Pane_Buffer_State` copies the checked session entry and buffer
identity together with stored point, viewport start, horizontal display
column, and desired display column. A split copies the complete source history
by value; later changes in either pane are independent.

The layout also retains a separate duplicate-free top-level buffer recency
list. This list is not the editor-session MRU and does not contain pane-local
redisplay state. It provides a deterministic fallback only after a pane has no
usable local-history entry.

| Operation | History behavior |
| --- | --- |
| `registry_pane_history_record` | Moves one checked buffer context to the pane-history head and updates top-level recency. |
| `registry_pane_history_snapshot` | Copies one exact pane history and its generation. |
| `registry_pane_history_previous` | Returns the most recent entry other than one excluded buffer. |
| `registry_buffer_list_snapshot` | Copies the independent top-level recency list and generation. |
| `registry_pane_history_purge` | Removes one undisplayed buffer from every pane history and the top-level list. |

Revisiting a retained buffer restores its pane-local presentation state after
positions are normalized against the buffer's current revision and text
extent. Canonical text, effective point, mark, and region remain buffer-owned.

## Buffer replacement and kill

`registry_replace_pane_buffer` rebinds one checked pane to one live
editor-session entry. It stores the outgoing presentation, restores retained
incoming presentation when available, uses the retained primary view when the
incoming buffer is otherwise undisplayed, and creates an additional view when
another pane already shows that buffer. Replacing with the pane's current
entry succeeds without changing the layout generation unless hard dedication
rejects the replacement before buffer or view inspection.

`registry_kill_buffer` first assesses dirty and transient state, then replaces
every visible occurrence before detaching the session graph. Each affected
pane selects its first valid fallback in this order:

1. that pane's local history;
2. the layout top-level buffer list; and
3. an explicit factory fallback supplied by the application.

The killed entry is excluded from every choice and purged from all histories.
If editing has begun and no ordinary fallback exists, the application admits
the unassociated `*scratch*` buffer and retries it as the factory fallback.
Pathless startup remains a distinct pre-editing list root with zero buffers.

Dirty buffers still require explicit discard or successful save authority.
Busy view state, stale identities, unavailable fallback, preparation failure,
or delegated session/view failure preserves the published layout and live
buffer graph. Additional views are prepared or rebound before publication and
obsolete additional views are released after the complete replacement commits.

## Pane dedication

Dedication is persistent pane state independent from the displayed buffer. It
has three strengths:

| State | Automatic reuse | Ordinary explicit replacement |
| --- | --- | --- |
| `None` | Eligible when every other policy condition passes. | Allowed. |
| `Soft` | Excluded. | Allowed; the pane remains soft dedicated. |
| `Hard` | Excluded. | Rejected atomically with `Dedication_Conflict`. |

`registry_pane_dedication_inspect` copies the current pane handle and
dedication. `registry_pane_dedication_set` accepts `None`, `Soft`, or `Hard`
against one current checked pane. A changed value advances layout generation
because both the observable snapshot and display eligibility changed. Setting
the current value is a no-op and retains the generation. `Invalid_Dedication`
rejects any other encoded value.

Splitting preserves the original pane's dedication and creates an ordinary
`None` pane. Dedication otherwise follows pane identity across buffer and
geometry changes. Snapshot node descriptors expose the state, while
`Registry_Stats.soft_dedicated_panes` and
`Registry_Stats.hard_dedicated_panes` report exact live counts.

Automatic display may split a dedicated active pane, but it never selects a
soft or hard pane for same-buffer, least-recent, or most-recent reuse. Explicit
replacement and automatic destination selection therefore remain separate:
soft dedication restricts policy selection, while hard dedication also
protects the pane from ordinary replacement.

When a killed buffer is displayed in dedicated panes, every affected soft or
hard pane closes if another pane survives. Removal uses the ordinary parent
collapse, geometry rematerialization, and MRU focus rules. Removed additional
views are released after publication. If all panes are dedicated and display
the killed buffer, the active pane is retained as the final pane, its
dedication clears to `None`, and it receives the admitted local, top-level, or
factory fallback. This final-pane exception preserves the invariant that an
editing session always has a visible buffer.

Dedication operations retain the normal wrong-owner, stale-layout,
stale-pane, generation, preparation-memory, topology, view, and session
diagnostics. `Failure_Context.dedication` identifies the requested invalid
state or the hard state that caused `Dedication_Conflict`. Rejection preserves
pane, buffer, view, history, focus, dedication, and layout state.

## Other-pane display policy

Other-pane display separates destination selection from focus. One
`Display_Request` copies the exact live entry and buffer, current layout,
active pane, and other-pane intent. The active pane is never eligible. A
`Display_Policy_Proposal` then copies the current policy generation, mandatory
eligibility flags including dedicated-pane exclusion, ordered actions, and
split thresholds. No proposal contains native pointers or mutable node or view
references.

The factory policy evaluates these actions in order:

1. `Reuse_Same_Buffer` selects a non-active pane already showing the requested
   buffer.
2. `Split_Below` creates an above/below partition when the active pane reaches
   the height threshold and the resulting shape satisfies layout minima.
3. `Split_Right` creates a left/right partition when the active pane reaches
   the width threshold and the resulting shape satisfies layout minima.
4. `Reuse_Least_Recent` selects the eligible non-active pane at the tail of
   pane MRU.

The factory height threshold is 12 rows and the width threshold is 40 columns.
They are automatic-display heuristics, not operating minima. Explicit
`split-pane-below` and `split-pane-right` commands ignore them. Custom policy
may reorder any unique sequence of up to 32 actions and may also use
`Reuse_Most_Recent`.

`registry_display_policy_replace` accepts one complete valid policy only when
its expected policy generation is current, then publishes a new policy
generation. `registry_display_buffer` revalidates the request, layout, policy,
buffer, active-pane exclusion, and action sequence before replacing or
creating a destination. Its result reports the chosen pane and action but does
not focus that pane. Selecting commands compose a subsequent ordinary focus
transaction; display-only commands retain the original focus.

If no action can reuse an eligible pane or create an admissible split,
`No_Other_Pane` rejects without changing layout, buffers, histories, or focus.
Invalid or stale requests and policies reject as `Invalid_Display_Request`,
`Stale_Display_Request`, `Invalid_Display_Policy`, `Stale_Display_Policy`,
`Display_Action_Limit`, or `Invalid_Display_Action`.

The Racket facade exposes `display-policy-inspect`, `display-policy-replace`,
`reload-display-policy!`, and `reset-display-policy!`. A fixed-width 35-field
record crosses hosting: action count, 32 action slots, and two thresholds. A
checked bridge capability is owner-thread, registry, layout, and generation
bound; it copies the candidate back to Odin for complete validation and atomic
publication. At most eight display-policy capabilities may be live. Racket
exceptions, malformed records, wrong results, stale generations, and
reentrant or wrong-thread use preserve the current native policy.

## Geometry

`Geometry_Request` supplies total rows and columns plus top-level reserved rows
and columns. Reservations are removed from the trailing bottom and right edges;
the usable root rectangle begins at row and column zero. The terminal workflow
reserves the final row for global prompts and diagnostics.

Each pane reserves:

- at least one semantic content row;
- exactly one pane-status row; and
- at least one semantic content column.

The default operating minimum is two content rows plus the status row and
eight columns. Above/below children share all columns and require no extra
separator row. Left/right children reserve one separator column between them.

For an available axis `N` and stored positive weights `a:b`, the first child
receives `floor(N * a / (a + b))`. The second receives the remainder. Effective
spans clamp to subtree minima without rewriting the stored weights. All sums,
products, offsets, and conversions use checked integer paths.

`registry_materialize` has two modes:

| Mode | Behavior |
| --- | --- |
| `Operating` | Rejects unless every pane satisfies the configured operating minimum. |
| `External_Shrink` | Publishes operating geometry when possible, semantic geometry when only semantic floors fit, or `Insufficient` with no partial pane geometry. |

The insufficient state retains the complete tree, views, buffers, focus, MRU,
weights, and request. The terminal replaces pane output with one global
diagnostic until the tree fits again.

## Manual resize and balance objectives

`registry_resize_pane` accepts the current active pane, one partition
orientation, and a signed delta of exactly `-1` or `1`. It selects the nearest
ancestor partition with that orientation and moves its divider by exactly one
row or column. It does not fall back to a farther compatible ancestor when the
selected partition cannot move. The two resulting spans become exact positive
weights, preserving the achieved ratio on later geometry materialization.

The resize result copies the current layout and pane handles, partition
identity, orientation, signed delta, and resulting child spans. A resize
rejects atomically when no compatible divider exists, the layout is in
insufficient geometry, or either subtree would fall below its operating
minimum.

`registry_balance_panes` preserves topology and recalculates every partition's
weights to minimize visible row and column imbalance. Its dimension units
prefer subtrees that span a complete axis; materialization then respects
operating minima, separators, checked integer geometry, and deterministic
rounding. The closest valid result is published when exact equality is not
attainable. The result reports the current layout, active pane, and whether
weights changed; an already balanced layout succeeds as a no-op.

`registry_balance_pane_areas` instead minimizes the final outer-cell areas of
all leaf panes. It orders valid complete weight maps by:

1. the sum of absolute pairwise leaf-area differences;
2. the range from the smallest to the largest leaf area; and
3. the lexicographically smallest first-child span vector in spatial
   partition preorder.

The third rule resolves symmetric integer ties consistently. The operation
exhausts admitted integer spans under the geometry-work ceiling, uses checked
wide arithmetic for areas and scores, and either publishes the exact ordered
optimum or rejects without changing topology, weights, focus, or accounting.
Operating minima and left/right separator columns are part of every candidate.
An already optimal layout succeeds as a no-op.

## Terminal projection

`ui.proposal_map_pane_layout` maps one complete immutable layout snapshot into
the shared UI proposal. Every pane becomes a text surface with copied pane
identity, geometry, focus, MRU rank, history generation, and dedication. Every
partition becomes a split node with the delivered orientation, weights, depth,
and separator geometry. The layout registry remains the canonical owner of
topology and pane state; the UI root is a checked presentation projection.

The terminal receives one `UI_Presentation` containing the immutable UI root
and exactly one `Text_Surface_Projection` for every text surface. Each text
projection contains the matching compatible display snapshot and logical view
snapshot. The renderer rejects missing, duplicated, stale, wrong-view,
wrong-buffer, wrong-profile, or geometry-incompatible projections before
allocating a frame.

The full frame contains:

- every pane's content at its absolute content rectangle;
- one reverse-video status row per pane, with `*` identifying the active pane;
- one `│` cell for every row of a left/right separator rectangle;
- no separator row for above/below partitions; and
- the active pane's cursor translated to absolute terminal coordinates.

Each pane status is an attached `StatusRegion` copied into the same UI
generation as its surface. Its one-row geometry comes from the delivered pane
geometry, its compact content reports active pane, buffer selection label,
modification state, and point offset, and its semantic style is
`Status_Normal` or `Status_Active`. Global prompts continue to render in the
reserved final row until their recorded migration slice. Shared list and
candidate roots use the same generic UI renderer outside the editing layout.

## Commands and factory bindings

| Command | Binding | Behavior |
| --- | --- | --- |
| `split-pane-below` | `C-x 2` | Split the active pane into ordered above/below children. |
| `split-pane-right` | `C-x 3` | Split the active pane into ordered left/right children. |
| `close-pane` | `C-x 0` | Close the active non-final pane. |
| `keep-only-pane` | `C-x 1` | Remove every pane except the active pane. |
| `focus-next-pane` | `C-x o` | Focus the next pane in spatial preorder, with wrap. |
| `enlarge-pane-vertically` | `C-x ^` | Enlarge the active pane by one row at its nearest above/below divider. |
| `enlarge-pane-horizontally` | `C-x }` | Enlarge the active pane by one column at its nearest left/right divider. |
| `shrink-pane-horizontally` | `C-x {` | Shrink the active pane by one column at its nearest left/right divider. |
| `balance-panes` | `C-x +` | Balance visible pane dimensions without changing topology. |
| `balance-pane-areas` | None; use `M-x` | Balance final pane areas without changing topology. |
| `find-file-other-pane` | `C-x 4 f` | Open or reuse a local file buffer in another pane and focus it. |
| `switch-to-buffer-other-pane` | `C-x 4 b` | Show a live or newly named buffer in another pane and focus it. |
| `display-buffer-other-pane` | `C-x 4 C-o` | Show a selected buffer in another pane without changing focus. |

The first pane command creates the presentation layout around the active
primary view. Native command dispatch revalidates the active pane's exact view
before applying a transformation. `balance-pane-areas` is public and
discoverable through `M-x`, but intentionally has no factory binding.

## Insufficient-geometry recovery

External resize uses `External_Shrink`. When the resulting state is
`Insufficient`, the input layer admits only external resize, `close-pane`,
`keep-only-pane`, and `request-editor-exit`. All other completed commands are
rejected without changing buffers, focus, MRU, or topology. A successful resize
or tree reduction rematerializes the complete layout and resumes ordinary
rendering.

## Transformations

| Operation | Structural and focus behavior |
| --- | --- |
| `registry_split_below` | Replaces the active leaf with an above/below partition. The original pane is first and the copied pane is second. |
| `registry_split_right` | Replaces the active leaf with a left/right partition. The original pane is first and the copied pane is second. |
| `registry_focus` | Stores the outgoing buffer effective point, restores the incoming pane stored point, then publishes active pane and MRU head. |
| `registry_resize_pane` | Moves the active pane's nearest compatible divider by one signed cell and persists the resulting exact span ratio. |
| `registry_balance_panes` | Recalculates partition weights for deterministic visible dimension balance while preserving topology. |
| `registry_balance_pane_areas` | Selects the exact bounded optimum for final leaf-area balance while preserving topology. |
| `registry_close_pane` | Rejects the final pane; otherwise removes the active leaf and its parent, promotes the sibling, and focuses the surviving MRU head. |
| `registry_keep_only` | Removes every pane except the active leaf and expands that leaf over the complete usable area. |

New partitions start with weights `1:1`. Split clones the source view into an
independent additional view, preserves buffer text, mark, activation, focus,
and existing MRU ranks, and appends the new pane as least recent. Explicit
split admission always requires operating geometry.

Focus uses `view.transfer_focus`. If incoming point publication fails, the
outgoing stored-point move is rolled back before the failure returns. Mark and
region activation are not transferred or copied.

Close and keep-only retain primary views and release removed additional views.
Neither operation keeps a restorable layout.

## Checked programmable capability

`Layout_Capability_Scope` is the complete pointer-free authority for one host
turn. It copies the permitted operation set, exact layout handle, and current
pane handle. Validation distinguishes invalid context, permission denial, wrong
authority, wrong layout or pane, and stale layout or pane generations before
calling the layout registry.

The Racket facade in `src/hosting/layout-bridge.rkt` exposes these operations:

| Procedure | Result |
| --- | --- |
| `layout-inspect` | Copies the current complete `layout-snapshot`. |
| `layout-split-below`, `layout-split-right` | Request a checked split of one copied pane handle. |
| `layout-focus`, `layout-close`, `layout-keep-only` | Request the corresponding checked pane transformation. |
| `layout-resize` | Moves one compatible divider by a signed single-cell delta. |
| `layout-balance-dimensions`, `layout-balance-areas` | Request one topology-preserving balance objective. |
| `layout-dedication`, `layout-set-dedication` | Inspect or replace one pane's dedication. |

`call-with-layout-control` confines the opaque native capability to one dynamic
Racket extent. The control rejects after escape, from another thread, during
reentrant use, or after native revocation. A successful mutation returns a
`layout-outcome` with the refreshed scope; later operations in the same turn
must use that new generation.

The mixed-language records have fixed widths: 64 bytes for scope, 192 bytes for
the snapshot header, 376 bytes per node, 144 bytes for a request, and 224 bytes
for an outcome. At most 255 node records cross one snapshot call. Racket values
contain no native pointers or borrowed collections.

## Hooks and deferred mutations

`registry_hook_register` retains one checked `Hook_Handle` and callback;
`registry_hook_release` consumes that exact identity. The command owner uses
`racket_layout_hook_register` and `racket_layout_hook_release` to bind the same
native lifecycle to an embedded Racket callback.

After a mutation publishes, every live hook in the notification round receives
the same immutable copied snapshot. Inspection remains synchronous. A structural
request from a callback is copied with `registry_defer_request` into the bounded
FIFO and cannot mutate the registry reentrantly.

After notification completes, deferred requests run as ordinary transactions
in sequence order. Each request revalidates its expected layout and pane against
the then-current generation. An earlier accepted request can therefore make a
later request stale. The stale request is recorded and skipped without rolling
back the earlier publication.

Callback exceptions and false callback results do not roll back the committed
generation. The registry records `Callback_Failure`; the Racket owner preserves
the contained hosting or `Racket_Exception` context. `registry_hook_stats` and
`registry_hook_failures` copy notification, callback, queue, and last-failure
evidence without exposing retained callback storage.

## Atomicity and failures

Structural operations copy the bounded registry into private prepared state,
apply the complete transformation, materialize geometry, validate topology and
MRU, and reserve or validate view resources before publication. An expected
failure before publication preserves the prior layout generation and snapshot.

`Failure_Code` distinguishes registry and owner identity, stale layout and
pane handles, invalid dedication and dedication conflict, topology and parent
defects, invalid weights or geometry, absence of a compatible divider, pane
and depth ceilings, snapshot and prepared-memory bounds, geometry-work limits,
operating minima, semantic insufficiency, final-pane rejection, generation
exhaustion, checked integer overflow, persistent allocation, invalid or
displayed buffer state, history limits, busy state, absent fallback, and
delegated view or session failure.
`Failure_Context` copies the operation, current layout, requested pane, bound
and actual values, hook or deferred sequence when applicable, and any underlying
view or editor-session failure. Command containment additionally preserves the
layout failure, capability failure, host failure, and bounded Racket diagnostic
needed to distinguish an interactive rejection from a fatal invariant defect.

## Selected limits

| Resource | Default ceiling |
| --- | ---: |
| Live panes | 128 |
| Partitions | 127 |
| Total nodes | 255 |
| Partition depth | 32 |
| Snapshot nodes | 255 |
| Snapshot bytes | 1 MiB |
| Prepared transaction bytes | 4 MiB |
| Geometry work | 1,048,576 units |
| Pane-local history entries | 64 per pane |
| Pane-local history storage | 64 KiB per pane |
| Aggregate pane-history storage | 8 MiB per layout |
| Top-level buffer recency entries | 1,024 |
| Display-policy actions | 32 |
| Live display-policy capabilities | 8 |
| Registered layout hooks | 64 |
| Deferred layout requests | 256 |
| Bounded diagnostic text | 4 KiB |

The selected resource study reaches 128 panes and 255 nodes at depth 7. On the
reference environment, the registry retained 1,974,720 bytes, the snapshot
value was 69,472 bytes, and complete geometry consumed 1,020 work units. The
area oracle used 234 candidate units for the ordinary three-pane profile,
10,416 for an adversarial four-pane tree, and 398,664 for the demanding
five-pane profile. A generated 16-pane minimum-geometry tree completed
production area balance with 139 reported geometry-work units under the
25-millisecond demanding latency gate.

## Validation

```sh
odin test tests/layout_reference -vet -warnings-as-errors
odin test tests/pane_buffer_reference -vet -warnings-as-errors
odin test src/layout -vet -warnings-as-errors
make native-command-test
make layout-acceptance-runtime
make layout-acceptance
make docs-check
make verify
```

See [Why Pane Layout Is a Native Transaction Kernel](../../explanation/pane-layout-kernel/index.md)
for the ownership and publication rationale, and
[Manage Pane Layouts](../../how-to/manage-pane-layouts/index.md) for the command
workflow. See [Configure Other-Pane Display Policy](../../how-to/configure-pane-display-policy/index.md)
for checked destination configuration,
[Why Programmable Pane Layouts Use Copied Authority](../../explanation/programmable-pane-layouts/index.md)
for the capability and hook architecture, and
[Validate Pane Layouts](../../how-to/validate-pane-layouts/index.md) for the
focused and integrated evidence procedure.
