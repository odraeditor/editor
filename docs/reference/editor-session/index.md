<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Editor Session Reference

The `editor_session` package owns bounded session identity, complete live
buffer graphs, aggregate admission, selection indexes, activation order,
visible-target identity, detachment, and cleanup coordination.

## Current delivery boundary

The application runs through one editor-session registry. Pathless startup
presents a non-buffer list root with Create, Open, and Open Directory actions. `find-file` can
open or reuse file-backed entries, and
`switch-to-buffer` presents a filtered candidate session that can activate a
checked live graph or create one unmatched named buffer. Editing, history,
search, save, rendering, and resize behavior resolve the checked active entry
for each turn.

Several entries and primary views can remain live. A pane layout can present
several entries and additional views while the session retains one active
entry. Checked buffer killing, first-save for named unassociated buffers,
protected multi-buffer exit, startup actions, and the Buffer Menu use that same
registry while their list presentation remains UI-owned.

## Complete entry graph

One live entry coordinates objects that keep their established package
responsibilities:

```text
Editor session entry
|-- editor.Buffer ----------> canonical text, revision, point, mark, region
|-- history.Store ----------> reversible states for that buffer
|-- optional document ------> target identity and persistence state
`-- primary view -----------> stored point, viewport, search state
```

`editor_session` owns the graph relationship and lifecycle. It does not absorb
rope storage, history topology, file I/O, logical view behavior, command
policy, or terminal presentation.

## Identity and selection

| Contract | Meaning |
| --- | --- |
| `Session_ID` and `Session_Generation` | Identify one exact live editor session. Zero is invalid. |
| `Registry_Generation` | Identifies one complete registry lifetime inside the session. |
| `Entry_ID` | Identifies one buffer entry for the session lifetime. It is never reused. |
| `Entry_Handle` | Combines session, registry, entry, slot, and slot generation. It is the mutation identity. |
| `Object_Graph_Identity` | Copies the associated buffer, history, optional document, and primary-view identities. |
| Selection label | A unique bounded UTF-8 name for an unassociated entry or its complete normalized path when associated. |
| Normalized-path index | Maps one admitted document target to its single live entry. |

Labels and paths are selection metadata. Reusing a slot advances its
generation, so an earlier handle cannot identify the replacement entry.

## Visible target and activation

`Visible_Target` distinguishes no target, one primary view, and one shared UI
root. A primary-view target contains the checked entry and view handles. A UI target
contains copied owner, model, and generation identity; list rows, marks,
geometry, and return behavior remain under their semantic workflow and UI
owners.

Publishing or activating an entry moves it to the front of an intrusive
doubly linked MRU order and selects its primary view. Reactivating the current
entry succeeds without duplicating the order or advancing its activation
sequence. Detaching the visible entry selects the surviving MRU head; removing
an inactive entry leaves the visible target unchanged.

An inactive primary view retains stored point, desired column, viewport origin,
horizontal column, layout policy, and view-local transient state. Its buffer
retains effective point, mark, and region activation, and its session entry
retains independent history ownership. Activation rejects an outgoing view with
unresolved search, query-replacement, or command-preparation state. The visible
target and MRU order remain unchanged on rejection.

## Startup and Buffer Menu list roots

List roots never enter the buffer, document, history, or view registries. The
startup list has three semantic rows:

| Row | Action |
| --- | --- |
| `Create a new buffer` | Starts the ordinary `switch-to-buffer` prompt; an unmatched valid name admits a complete unassociated graph. |
| `Open File` | Starts the ordinary `find-file` prompt; an indexed normalized path activates its existing graph. |
| `Open directory` | Starts the delivered Project directory-opening workflow. |

The Buffer Menu is rebuilt from a copied `session_descriptors` batch in
active-then-MRU order. Each displayed row has this shape:

```text
<mark> <active><modified><association><operation> <complete selection label>
```

| Field | Values |
| --- | --- |
| Mark | `S` for save, `D` for kill, or blank. |
| Active | `.` for the active entry, otherwise blank. |
| Modified | `*` when canonical revision differs from saved or initial state, otherwise blank. |
| Association | `F` for a file-backed document or `U` for an unassociated buffer. |
| Operation | `!` when the entry is not idle, otherwise blank. |
| Selection label | Complete normalized absolute path for a file-backed entry; complete explicit name for an unassociated entry. |

The highlighted row uses the `List_Current` role. Rows are clipped only at
complete grapheme boundaries. Save and kill prefixes use semantic list-mark
roles. Resize publishes checked list viewport and geometry before the next
projection.

| Local input | Result |
| --- | --- |
| Up, Down | Move the highlighted row within the current bounded inventory. |
| Enter | Activate the highlighted checked entry and leave the list. |
| `s` | Mark the row for save and advance one row when possible. |
| `d`, `k` | Mark the row for kill and advance one row when possible. |
| `u` | Remove the current row's mark. |
| `x` | Copy the exact semantic mark set and execute all marks. |
| `q`, `Control-G` | Cancel local interaction and return to the checked target that opened the menu. |

Opening the menu clears older marks, copies fresh descriptors, and records the
current primary view as its non-nesting return target. Refresh preserves a mark
only while the exact entry handle remains live. Delayed local input against an
older list or model generation is rejected. The generic terminal renderer sees
only list rows, roles, marks, focus, and geometry; it has no Buffer Menu kind.

## Buffer candidate navigation

`switch-to-buffer` copies the complete editor-session descriptor generation
into a `Session_Buffers` candidate source. Canonical labels remain exact
unassociated names or normalized document paths. Rows annotate the document
path or `non-file-backed`, modified state, and backing kind.

Printable input filters the common candidate session. `Control-N` or Down and
`Control-P` or Up move the selection, `Backspace` or `DEL` removes one UTF-8
scalar, Enter activates, and `Control-G` cancels. A valid unmatched nonempty
query adds exactly one visibly annotated `create` row; an exact existing label
removes it. Queries are never interpreted as paths.

Activation rechecks the session, registry, entry slot, buffer, history,
optional document, and primary-view identities against a fresh complete
descriptor batch. A stale or failed action preserves the candidate root
and records no successful-use recency. Cancellation restores the exact primary
view that opened the candidate root.

## Public contract groups

| Area | Declarations | Contract |
| --- | --- | --- |
| Session lifecycle | `Session`, `session_init`, `session_registry_handle`, `session_usage`, `session_visible_target`, `session_close` | Initialization allocates the bounded registry and view owner. Copied inspection exposes identity and accounting without registry storage. Close requires no live, prepared, or detached entries. |
| Checked identity | `Session_Handle`, `Registry_Handle`, `Entry_Handle` and their validation procedures | Handles contain no registry pointer and require nonzero generations. |
| Graph transfer | `Entry_Resources`, `Entry_Prepare_Request`, `Prepared_Entry`, `session_entry_prepare` | Success transfers live buffer, history, and optional document wrappers into a stable private owner. Failure leaves caller ownership unchanged. |
| Publication | `prepared_entry_publish`, `Admission_Result` | The reserved graph, indexes, MRU link, accounting, and visible target become live together without allocation. |
| Abort | `prepared_entry_abort` | Reverse-order cleanup releases the complete unpublished graph and every reservation. |
| High-level admission | `Create_Buffer_Request`, `Open_Path_Request`, `session_create_buffer`, `session_open_path` | Initializes complete responsibility-owned graphs privately, publishes atomically, and reuses an already indexed normalized path. |
| Lookup | `session_find_label`, `session_find_path` | A complete label or normalized path resolves to a checked live entry handle. Missing values are ordinary unsuccessful lookups. |
| Activation | `session_activate`, `Activation_Result` | Visible target and MRU order change together after handle validation. |
| UI visibility | `session_present_ui`, `UI_Target` | Publishes a copied checked UI workflow target without changing MRU activation order. |
| Descriptor copy | `session_descriptors`, `Descriptor_Batch`, `descriptor_batch_close` | Copies bounded active-then-MRU entry state and complete labels without lending registry storage. |
| Close assessment | `session_assess_buffer_close`, `Close_Buffer_Request`, `Close_Authority` | Checks the exact generation, transient ownership, persistence state, and required discard authority without mutating the graph. |
| Checked close | `session_close_buffer`, `Closure_Result` | Detaches and cleans one admitted graph, returns copied label and graph metadata, and selects the MRU successor. |
| Checked close set | `session_close_buffer_set`, `Close_Buffer_Set_Result` | Validates all authorities and allocates every detachment record before one no-fail set mutation. |
| First save | `Associate_Save_Request`, `Associate_Save_Result`, `session_associate_and_save` | Reserves the target identity, publishes the external save, and converts an unassociated entry to a uniquely indexed file-backed entry. |
| Exit enumeration | `session_mru_entries` | Copies all live entry handles in deterministic MRU order into caller-owned bounded storage. |
| Ownership inspection | `session_entry_ownership`, `Ownership_Snapshot` | Returns copied graph identities and reservation values without exposing registry collections. |
| Native access | `Entry_Access`, `session_active_entry_access`, `session_entry_access`, `entry_access_borrow`, `entry_access_reconcile` | Each access is generation checked. Responsibility-owned pointers are borrowed only for the immediate native operation. |
| Detachment | `session_entry_detach`, `Detached_Entry`, `Detachment_Result` | Allocation finishes before the no-fail removal from indexes, order, and visibility. |
| Cleanup | `detached_entry_cleanup`, `detached_entry_release`, `Cleanup_Progress` | Cleanup closes view, document, history, then buffer. Copied metadata remains valid until explicit release. |
| Diagnostics | `Policy`, `Resource_Usage`, `Graph_Reservation`, `Failure_Code`, `Failure_Context` | Results expose copied scalar accounting, violated bounds, and responsibility-owned failure contexts. |

## Resource policy

`DEFAULT_POLICY` contains the measured initial values. `policy_validate`
checks every range and rejects documents, inventory marks, or detach
participants that exceed live-buffer capacity.

| Resource | Default | Validated range |
| --- | ---: | ---: |
| Live buffers | 128 | 16 to 1,024 |
| Live documents | 128 | 16 to 1,024 |
| Aggregate canonical text | 4 GiB | 256 MiB to 16 GiB |
| Unassociated name | 256 bytes | 64 to 4,096 bytes |
| Retained labels and paths | 4 MiB | 64 KiB to 16 MiB |
| Copied descriptor batch | 256 | 16 to 4,096 |
| Inventory marks | 128 | 16 to 1,024 |
| Outstanding capabilities | 2,048 | 32 to 8,192 |
| Prepared operations | 16 | 1 to 64 |
| Detach participants | 128 | 16 to 1,024 |
| Cleanup entries per turn | 64 | 1 to 256 |

Per-buffer editor limits, document limits, history policy, view capacity, and
other subsystem limits remain independently authoritative.

`find-file` prompts accept at most 4,096 UTF-8 bytes, matching the document
path ceiling. `switch-to-buffer` queries accept at most 4,096 UTF-8 bytes;
session policy applies the configured unassociated-name limit to a synthetic
creation candidate. `kill-buffer` accepts one complete selection label up to the same
4,096-byte maximum. Exit enumeration is bounded by the validated maximum of
1,024 live buffers. `list-buffers` copies at most the configured descriptor
batch and retains at most the configured simultaneous inventory marks.

## Preparation and publication

`session_entry_prepare` performs the fallible work:

1. Revalidate the session and request metadata.
2. Reject label or normalized-path collisions.
3. Validate buffer, history, document, revision, and association agreement.
4. Reserve a generation-bearing slot and activation sequence.
5. Check live counts and aggregate text and label budgets.
6. Allocate stable owner, copied metadata, and prepared state.
7. Create the primary view against the owner's stable buffer wrapper.
8. Reserve label and path index entries and charge retained usage.
9. Clear the caller's transferred wrappers.

`prepared_entry_publish` then installs the already complete graph, changes the
reserved slot to live, links it at MRU head, and publishes the visible target.
It performs no allocation or extension callback.

## Accounting

`Resource_Usage` distinguishes live counts from storage that remains charged
during preparation or detached cleanup. Canonical text, history, labels,
paths, view context, and registry storage are charged before publication and
remain charged until their final owner releases them.

Command APIs mutate responsibility-owned objects through a checked
`Entry_Access`. Each input turn borrows the visible entry, routes its buffer,
history, optional document, and primary view through the existing command
owners, and then calls `entry_access_reconcile`. Presentation and resize borrow
the active entry again rather than retaining startup pointers.

Admission reserves aggregate graph growth before publication. Ordinary text
commands currently refresh canonical-text and history charges after their
completed native publication.

## Detachment and cleanup

`session_entry_detach` allocates the `Detached_Entry` owner first. The no-fail
mutation then removes label and path index entries, unlinks MRU state,
invalidates the live handle, selects a successor when needed, and transfers
the stable owner out of the live slot.

Detached bytes remain part of aggregate usage. `detached_entry_cleanup`
releases the primary view, optional document, history store, and buffer in
that order. A responsibility-owned busy failure retains the remaining owner
for retry. `detached_entry_release` finally releases copied selection metadata
and its accounting charge.

## Dirty close and process exit

`session_assess_buffer_close` rejects stale handles and entries whose view,
history, search, replacement, command preparation, or document save remains
busy. For a file-backed entry, modified state compares canonical revision with
the last successfully saved revision. An unassociated entry is modified after
its canonical revision advances from zero.

`session_close_buffer` returns `Discard_Required` without mutation when
modified text lacks `Discard_Modified` authority. Once admitted, detachment,
successor selection, cleanup, and copied completion metadata form one checked
lifecycle. Closing the visible entry selects the MRU head; closing an inactive
entry preserves the visible target. The editor-session primitive returns no
successor when it closes the final entry. Application editing policy admits
`*scratch*` before completing a final ordinary kill, so the terminal remains in
editing state. Pathless startup alone presents the Startup list root
with zero live buffer graphs.

First save reserves the normalized path and complete label accounting before
publishing to the filesystem. Success converts the existing entry to a
file-backed identity without replacing its buffer, view, or history. Failure
leaves the entry live and reports any external publication state truthfully.

Process exit copies the complete MRU handle sequence and assesses every entry.
Clean entries require no decision. Modified entries require Save, Discard, or
Cancel. No graph is detached until all decisions succeed. If a later decision
is canceled or a save fails, every graph remains live while any earlier
successful filesystem save remains published.

## Marked save and kill execution

The inventory workflow copies its exact semantic marked entries from one model
generation. Execution revalidates that generation and every checked entry
handle before effects begin.

Save marks publish independently in row order. A successful save is removed
from the current marked set. If a later save fails, completed and pending counts
remain truthful and the earlier filesystem effects are not rolled back.

Kill marks first assess every entry and collect every required Save, Discard,
or Cancel decision. Required saves complete before detachment. Cancellation or
save failure closes no entry. Once the complete set is admitted,
`session_close_buffer_set` allocates every detachment record and removes the set
without another allocation point. Killing the final set presents startup.

## Programmable session capability

The `command` package wraps the coordinator in one immutable
`Buffer_Session_Capability_Context`. Its copied scope contains editor-session
identity, the granted access set, session and registry generations, and the
exact visible target. Usage, descriptor, create, open, activate, save, kill,
and marked-execution authority can be granted independently.

Racket receives only copied scopes, handles, descriptors, usage, outcomes,
UI-root identities, decisions, and failures. Every operation reconstructs the
current scope and rejects a changed authority, session, registry, visible
target, entry, or UI root before delegating to this package. Successful
lifecycle publication returns a refreshed scope; the Racket facade never owns
an entry index or native cleanup responsibility.

Descriptor enumeration and marked execution cross as bounded batches. The
default programmable boundary copies at most 256 descriptors, 4 MiB of labels
or decision paths, 4,096 bytes of request text, and 128 marked decisions.
Editor-session policy remains independently authoritative and may reject below
those transport ceilings.

## Expected failures

Expected failures include invalid or stale session, registry, and entry
handles; malformed or colliding labels; invalid paths or object graphs;
policy, buffer, document, text, label, capability, operation, detach, and
activation limits; retained entries at close; allocator failure; busy
responsibility-owned objects; and delegated editor, history, document, or view
failure.

An expected preparation failure publishes nothing. An activation failure
preserves the visible target. A detach allocation failure leaves the complete
live graph indexed. An underlying cleanup failure retains an unreachable
detached owner rather than silently dropping storage.

`find-file` and `switch-to-buffer` expose these failures through a bounded
terminal diagnostic. Empty prompt input is rejected before session mutation.
Opening an indexed normalized path activates its existing entry and performs
no file read or canonical text replacement. An unmatched switch label creates
an unassociated buffer only after the complete graph can be admitted.

`kill-buffer` additionally reports missing or stale labels, busy lifecycle
owners, absent pane fallback, layout preparation or allocation failure before
detachment, cleanup failure, and first-save path or publication failures.
These failures do not grant implicit discard authority. Canceling a kill or
exit prompt preserves live state.

Buffer Menu failures additionally include stale model, root, or row generations,
descriptor, row, text, and mark limits, invalid return targets, projection
geometry or text limits, and terminal write failure. A failed refresh preserves
the previous complete UI root. A presentation failure does not transfer
canonical ownership to the frontend.

## Validation

| Command | Evidence |
| --- | --- |
| `odin test tests/session_reference` | Independent create, association, activation, MRU, dirty admission, close, and generation oracle. |
| `make editor-session-resource-study` | Optimized ordinary, demanding, stress, rejection, latency, and cleanup evidence. |
| `odin test src/editor_session -vet -warnings-as-errors` | Policies, handles, paths, publication, collisions, reservations, stale reuse, allocator faults, generated activation, detachment, accounting, and teardown. |
| `make terminal-presentation-test` | Pathless startup, Create/Open actions, normalized reuse, full-path switching, Buffer Menu navigation and marks, dirty resolution, truthful partial saves, resize, first save, final-buffer fallback, multi-buffer exit, and terminal restoration. |
| `make buffer-session-acceptance` | Generated session operations, final aggregate envelope, mixed-language composition, bounded batches, complete PTY lifecycle, accounting, and deterministic teardown. |
| `make verify` | Full mixed-language repository gate. |

See [Why the Editor Session Coordinates Complete Buffer Graphs](../../explanation/editor-session-ownership/index.md)
for the ownership rationale and lifecycle tradeoffs.

See [Manage Multiple Buffers](../../how-to/manage-multiple-buffers/index.md)
for the terminal procedures.

See [Programmable Buffer Session Reference](../programmable-buffer-sessions/index.md)
for Racket contracts, copied value shapes, record widths, and boundary failures.
