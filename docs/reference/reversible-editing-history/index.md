<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Reversible Editing History Reference

The `history` package owns bounded in-memory edit history. The `transaction`
package remains the only path that publishes text. A tracked transaction must
reserve its complete history record during validation before its private
revision can become canonical.

## Current delivery boundary

The complete reversible-history delivery provides:

1. One history store associated with one live buffer.
2. Complete immutable record reservation before transaction publication.
3. Parent, child, and preferred-child topology.
4. Engine-level single-buffer undo and redo with fresh editor revisions.
5. Retained alternate children after editing from an earlier state.
6. Explicit bounded pruning of old inactive leaf units.
7. Measured global and per-buffer resource contracts.
8. Bounded semantic grouping for compatible built-in typing and local
   Backspace corrections.
9. Initiating cursor restoration across grouped undo and redo.
10. Native `undo` and `redo` commands, with `Control-X`, then `u` bound to
    `undo` in the built-in terminal keymap.
11. Atomic inspection and replacement of the complete global policy through a
    copied Racket configuration value.
12. Immediate live increases and bounded pre-activation pruning for decreases.
13. Structured native-boundary diagnostics and generation checks that preserve
    the old policy and topology on failure.
14. Copied bounded projections of the active node, parent, preferred child,
    and immediate retained children.
15. Explicit selection of an immediate child or an admitted retained node.
16. Bounded selective dependency analysis with optional stable-anchor range
    narrowing and one ordinary compensating transaction on success.
17. Native and Racket request surfaces with opaque node identities and no
    provisional physical bindings.
18. Deterministic linked history reservation for explicit multibuffer
    transactions, with one shared `Link_ID` and one node per participant.
19. Atomic all-participant undo, redo, branch selection, and selective undo.
20. Complete-set pruning and teardown rules that never split a retained link.
21. Generated cancellation, fault, Unicode, and cleanup coverage.
22. Measured 1,000- and 10,000-participant reservation and publication
    evidence.

The final interaction profile, complete selection UI, and history visualizer
remain separate later work.

## Terminology

| Term | Meaning |
| --- | --- |
| Store | The Odin owner of the global policy and the histories associated with its live buffers. The first slice admits one buffer. |
| History | The retained tree for one buffer identity. |
| Node | One represented text state. The root is the session-start state; every other node owns one undo unit. |
| Record | One immutable buffer transition with normalized edits, source identities, metadata, and optional cursor context. |
| Active node | The node whose represented text agrees with the current confirmed buffer contents. |
| Preferred child | The child used by ordinary redo. |
| Semantic typing unit | Consecutive compatible built-in insertions and local corrections represented by one node with ordered records. |
| Reservation | Complete unpublished history storage bound to one validated transaction or navigation. |
| Navigation plan | Bounded borrowed edits and an opaque reservation for one undo or redo transition. |
| Inspection | Caller-owned copied projections of nearby retained nodes. It contains no native pointer and must be released with its allocator. |
| Branch selection | One checked transition from the active node to an immediate child or an admitted retained node. |
| Selective undo | A dependency-proven compensating edit recorded as a new ordinary history node. |
| Link | One immutable relation joining the exact per-buffer nodes created by an explicit multibuffer transaction. |
| Linked unit | One shared undo identity, deterministic participant set, and per-buffer record set that can move or be removed only as a whole. |
| Policy generation | One complete authoritative set of all thirteen resource fields. Generation one is installed at store initialization. |
| Racket configuration function | A live function from one copied current policy to one copied candidate policy. It has no native pointer or topology authority. |

## Package ownership

| Package | Responsibility |
| --- | --- |
| `history` | Identities, topology, retained payloads, links, policy, accounting, reservation, inspection, branch and selective planning, activity, and pruning. |
| `transaction` | Private working revisions, normalization, single- and multibuffer history attachment, complete validation, and canonical publication. |
| `editor` | Buffer identity, ropes, confirmed revisions, positions, anchors, and allocation-free root installation. |
| `view` | Live point, mark, and region state. `Cursor_Context` is only a bounded retained logical value. |

`history` imports editor and view contracts. `transaction` imports `history`
and maps normalized transaction results into `Record_Input`. `history` does
not import `transaction`, so history policy cannot become a second publication
coordinator.

## Record publication sequence

1. `transaction_begin` opens one private working revision.
2. The command applies base-relative or sequential edits.
3. `transaction_track_history` verifies the store's buffer and current
   revision before attaching it to the root.
4. `transaction_validate` normalizes the complete transition and calls
   `record_reserve`.
5. `record_reserve` copies every edit payload, origin descriptor, command, and
   topology object into owned bounded storage.
6. Validation reaches `Ready` only after the reservation succeeds.
7. `transaction_commit` publishes the editor root and then calls
   `reservation_commit_reserved` without further allocation.
8. Observer delivery occurs after canonical text and history agree.

Cancellation, validation failure, explicit abort, or close calls
`reservation_abort`. The provisional node and payload are released without
changing topology. A history capacity failure is returned as transaction
`History_Failure` before canonical publication.

A tracked transaction with no normalized text changes uses `revision_reserve`.
It advances store revision agreement but creates no node or undo record.

An explicit multibuffer transaction uses `multibuffer_track_history` to attach
the complete store set. Validation normalizes every participant and calls
`multibuffer_record_reserve`, which sorts by buffer identity, checks one shared
transaction and undo identity, copies every record, and allocates the complete
link before `Ready`. Publication installs every editor root first and then
calls `multibuffer_reservation_commit_reserved` without allocation.

## Public declarations

| Area | Declarations | Contract |
| --- | --- | --- |
| Identity | `Store_ID`, `History_ID`, `Node_ID`, `Unit_ID`, `Record_ID`, `Link_ID`, `Policy_Generation` | Zero identities are invalid. `Node_ID` contains history, slot, and generation data rather than a pointer. |
| Lifecycle | `Store`, `store_init`, `store_is_valid`, `store_stats`, `store_close` | The caller owns handle storage and keeps both allocators live until close. |
| Policy | `Policy`, `DEFAULT_POLICY`, `policy_validate`, `Policy_Field` | Every field and cross-field relationship is checked before use. |
| Live policy | `Policy_Snapshot`, `Policy_Replacement_Request`, `Policy_Replacement_Result`, `store_policy_inspect`, `store_policy_replace` | Inspection copies one complete generation. Replacement either publishes the complete next generation or changes nothing. |
| Policy capability | `History_Policy_Capability`, `History_Policy_Capability_Registry`, and the `history_policy_capability_*` operations | A fixed-capacity opaque token binds one live store to its owner thread and retains no authority after release. |
| Racket policy facade | `history-policy-inspect`, `history-policy-replace`, `reload-history-policy!`, `reset-history-policy!` | Racket inspects immutable hash data and returns a complete copied candidate. Native range, relationship, retention, and generation validation remains authoritative. |
| Policy application | `runtime_history_policy_exchange`, `history_policy_apply_racket_configuration` | Hosting copies exactly thirteen unsigned fields and one generation. The command turn inspects, configures, validates, prunes, and replaces synchronously. |
| Record input | `Record_Input`, `Edit_Payload`, `Cursor_Context`, `Record_Origin` | Input strings and slices are borrowed only during reservation and are copied on success. |
| Grouping | `Grouping_Kind`, `Grouping_Context`, `DEFAULT_TYPING_GROUP_IDLE_MILLISECONDS` | One command turn declares independent work, insertion, or Backspace correction with checked view, continuity, sequence, and time data. |
| Cursor restoration | `Cursor_Context`, `Cursor_Restore` | A unit retains only its initiating logical before and after boundaries. |
| Reservation | `Reservation`, `record_reserve`, `revision_reserve`, `reservation_commit_reserved`, `reservation_abort` | One store admits one provisional update. Commit performs no allocation; abort changes no topology. |
| Linked reservation | `Multibuffer_Record_Input`, `Multibuffer_Reservation`, `multibuffer_record_reserve`, `multibuffer_reservation_commit_reserved`, `multibuffer_reservation_abort` | One deterministic complete participant set succeeds or releases every provisional record and link. |
| Linked inspection | `Link_Participant`, `Link_Projection`, `link_inspect` | The caller supplies participant storage and receives copied identities, revisions, and node identities without retained pointers. |
| Inspection | `Inspection_Request`, `Inspection`, `Node_Projection`, `store_inspect`, `inspection_release` | The caller supplies exact state plus result and traversal bounds. The result owns copied labels and projections until release. |
| Navigation | `Navigation_Kind`, `Navigation_Request`, `Navigation_Plan`, `Navigation_Edit`, `Navigation_Result` | Undo, redo, and branch plans borrow retained payload until committed or aborted. |
| Branch navigation | `transaction_history_navigate`, `history_command_select_branch` | One admitted target is reached through a fresh root transaction; activity changes only after text publication. |
| Selective analysis | `Selective_Request`, `Selective_Range`, `Selective_Plan`, `selective_prepare`, `selective_plan_release` | Analysis copies compensating edits, rejects unsafe dependencies, and changes no store state. |
| Selective publication | `transaction_history_selective_undo`, `history_command_selective_undo` | A successful proof publishes and records one ordinary `selective-undo` transaction. |
| Linked navigation | `Multibuffer_Navigation_Request`, `Multibuffer_Navigation_Plan`, `multibuffer_navigation_prepare`, `transaction_multibuffer_history_navigate` | Undo, redo, and branch selection prepare every participant before one allocation-free multibuffer publication. |
| Linked selective undo | `Multibuffer_Selective_Request`, `Multibuffer_Selective_Plan`, `multibuffer_selective_prepare`, `transaction_multibuffer_history_selective_undo` | Every participant proof succeeds before one new linked compensating transaction is admitted. |
| Racket navigation facade | `history-inspection-view`, `history-branch-request`, `history-selective-undo-request`, `runtime-history-request-fields` | Racket consumes copied immutable data and returns intent using node identities obtained from native projections. |
| Pruning | `store_prune`, `multibuffer_prune` | Single-buffer pruning skips linked nodes; linked pruning validates and removes one complete eligible participant set. |
| Coordinated close | `multibuffer_stores_close` | Linked stores validate complete ownership, detach shared links, and release all stores with exact accounting. |
| Diagnostics | `Resource_Usage`, `Store_Stats`, `Failure_Code`, `Failure_Context` | Results expose copied scalar state and accounting, not internal storage pointers. |

## Undo, redo, and branches

Undo uses the active node's inverse transition and targets its parent. After a
successful fresh transaction, the parent becomes active and remembers the
undone child as preferred. Undo at the root returns `At_Root` without changing
the buffer revision.

Redo uses the active node's preferred child's forward transition. Absence of a
child returns `No_Child`; an unresolved retained choice returns
`Branch_Choice_Required`. Successful redo publishes a new editor revision and
makes the selected child active.

Editing after undo attaches a new child to the active parent and makes the new
child preferred. Existing siblings remain retained.

`store_inspect` requires the current buffer revision, active node, and policy
generation. It copies projections for the active node, optional parent,
optional preferred child, and a bounded prefix of immediate children. Each
projection contains opaque identity, unit identity, copied command label,
creation order, retained and payload bytes, record count, depth, and child
count. `child_count`, `traversed_nodes`, and `truncated` distinguish a complete
result from a bounded prefix.

Both `result_limit` and `traversal_limit` must be nonzero and cannot exceed the
live `inspection_nodes` policy. Allocation failure releases every partial
label and projection. The caller releases a successful result with
`inspection_release`.

`Select_Branch` requires the exact inspected active node and policy generation,
a target `Node_ID`, and an explicit operation bound. The engine checks an
immediate child first, then admits a reachable retained node through bounded
identity and ancestry traversal. It prepares the complete undo-to-common-
ancestor and redo-to-target transition before publication. `Already_Active`
is a successful no-op. A missing, pruned, stale, foreign, or over-budget target
changes neither activity nor revision.

## Selective undo

`Selective_Request` names the current buffer, revision, active node, target
unit, policy generation, and analysis budget. The target must be an ancestor
of the active node with complete retained payload. The proof transforms its
inverse coordinates through every later retained edit. An insertion at the
same boundary or any overlapping later edit is a dependency conflict.

An optional `Selective_Range` is resolved from live editor anchors by
`history_command_selective_undo`. It may include complete transformed edits;
partial overlap is rejected rather than splitting an unproven operation. A
stale anchor or reversed range fails before analysis.

`selective_prepare` owns copied replacement strings until
`selective_plan_release`. It changes no topology. On success,
`transaction_history_selective_undo` submits those edits through the ordinary
transaction path with command `selective-undo`. The resulting node is an
ordinary reversible child, so undoing it restores the pre-compensation state.

## Linked multibuffer history

`Link_ID` is the shared undo identity of one explicit multibuffer unit. The
link stores participants in ascending `Buffer_ID` order. Each participant
names its store, history, buffer, node, base revision, and result revision.
Temporal proximity never creates a link; only explicit attachment through
`multibuffer_track_history` does.

Linked reservation requires the exact store set, one source transaction
identity, one source undo identity, unique buffer identities, compatible live
revisions, and a participant count admitted by every store policy. The first
ordered store owns the single shared link allocation and accounts one retained
link. Every participant owns its ordinary record and node storage.

Undo requires every participant node to be active. Redo requires every active
node to prefer the corresponding linked child. Branch selection names one
retained `Link_ID`; every participant prepares its path to the corresponding
node. Selective undo proves the corresponding target unit independently in
every active ancestry, then records the compensation as a new linked unit.

Missing stores, a divergent active node, a stale link or revision, a
dependency conflict, cancellation, or any allocation failure rejects the
whole operation before publication. Successful navigation uses the existing
deterministically ordered multibuffer publication boundary and moves history
activity only after every text root is canonical.

`store_prune` does not remove linked nodes. `multibuffer_prune` admits only an
inactive leaf relation outside every participant's protected recent window
and removes every linked node together. `store_close` rejects a store that
still retains a link; `multibuffer_stores_close` validates the complete store
set and releases shared ownership exactly once.

## Semantic typing groups

A built-in insertion starts a semantic typing unit. A later record joins that
unit only when all of these conditions remain true:

1. It comes from the same live view identity and generation.
2. Its continuity token agrees with the active unit.
3. Its command event sequence immediately follows the previous record.
4. Its monotonic timestamp does not move backward and its idle gap is at most
   1,000 milliseconds.
5. It contains exactly one built-in insertion or Backspace edit at the unit's
   current contiguous byte boundary.
6. The resulting unit remains within the configured record and retained
   payload limits.

A Backspace record joins only while it retracts text inserted by that same
unit. Crossing the unit's starting boundary, deleting preexisting text,
forward deletion, a Racket command, cursor movement, another resolved command,
a view or generation change, an idle timeout, or a resource boundary starts a
separate unit or leaves history unchanged as appropriate.

Grouped records remain ordered. Undo applies their inverse transitions from
last to first; redo applies their forward transitions from first to last. The
group is one user-visible history node even though each atomic transaction
retains its own complete record.

## Logical view restoration

Each tracked logical edit may retain the initiating view handle, buffer and
revision identity, and the complete before and after point, optional mark,
region activation, and desired display column. Undo selects the first record's
before boundary; redo selects the last record's after boundary.

If the initiating view remains live for the same buffer, navigation restores
buffer selection through that view and updates its stored point. If it has
closed, the invoking live view for that buffer is the fallback. Other live
views keep independent stored points and viewports while all views observe the
restored buffer mark and activation.

## Command surface

`undo` and `redo` are native semantic commands resolved through the ordinary
command registry and published through `transaction_history_navigate`.
`Control-/`, `Control-_`, and `Control-X`, then `u` resolve to `undo`. The
terminal protocol encodes the first two physical forms as the same `0x1f`
control byte. `redo` is command-addressable but has no provisional physical
binding in the initial terminal keymap. Undo at the root and redo without a
preferred child complete as no-ops without publishing a buffer revision.

## Revision rules

History nodes identify represented text states, not reusable editor revisions.
Every edit, undo, and redo that publishes text advances `editor.Revision` by
one. A later state can contain exactly the same bytes as an older node while
having a newer confirmed revision.

`Store_Stats.current_revision` must agree with the associated live buffer
before a transaction can attach or navigation can prepare. Stale revision or
node generation input fails without mutation.

## Resource policy

| Resource | Default | Validated range |
| --- | ---: | ---: |
| Global retained bytes | 512 MiB | 16 MiB to 8 GiB |
| Per-buffer retained bytes | 256 MiB | 1 MiB to 2 GiB and not above global |
| Global nodes | 250,000 | 4,096 to 1,000,000 |
| Per-buffer nodes | 100,000 | 256 to global nodes |
| Guaranteed recent units | 256 | 32 to 65,536 and not above per-buffer nodes |
| Retained depth | 65,536 | 64 to 250,000 and not above per-buffer nodes |
| Sibling branches | 1,024 | 2 to 65,536 |
| Records per unit | 100,000 | 1 to 100,000 |
| Payload bytes per unit | 256 MiB | 64 KiB to 1 GiB and not above global bytes |
| Multibuffer participants | 1,000 | 1 to 10,000 and not above records per unit |
| Selective-analysis operations | 1,000,000 | 1,024 to 10,000,000 |
| Inspection nodes | 256 | 8 to 4,096 |
| Pruning operations per turn | 4,096 | 64 to 65,536 |

Some fields prepare later slices but are validated now so the public policy
has one stable shape.

### Racket field names

`history-policy-inspect` returns an immutable hash with exactly these symbols,
in the native field order used by the fixed-width hosting record:

1. `global-retained-bytes`
2. `buffer-retained-bytes`
3. `global-nodes`
4. `buffer-nodes`
5. `guaranteed-recent-units`
6. `retained-depth`
7. `sibling-branches`
8. `records-per-unit`
9. `payload-bytes-per-unit`
10. `multibuffer-participants`
11. `selective-operations`
12. `inspection-nodes`
13. `pruning-operations`

Each Racket value must be an unsigned 64-bit integer. Unknown fields and other
values fail in the Racket facade. Odin then checks the exact native ranges and
relationships in the table above.

### Replacement generations

`store_policy_replace` requires the exact nonzero generation returned by the
preceding inspection. A successful replacement increments that generation by
exactly one, including a replacement whose field values equal the current
values. Zero, stale, or exhausted generations fail without mutation.

Cancellation, Racket exceptions, malformed hosting results, invalid fields,
invalid relationships, temporary-memory failure, and unenforceable retention
leave the policy generation, active node, recent window, links, and retained
nodes unchanged.

`Resource_Usage` accounts for retained store and node metadata, records,
payload bytes, links, and completed pruning or selective-analysis work.
Provisional operation scratch storage has a separate temporary allocator and
is released on commit or abort.

## Pruning behavior

`store_prune` removes only complete inactive leaf units. It preserves
the root, active node, active ancestry, preferred reachable activity, and the
configured recent creation window. It updates node, record, payload, and byte
accounting together. If no eligible leaf exists within the work bound, it
returns zero rather than deleting an active transition or partial payload.

Admission does not silently discard retained topology when a new reservation
cannot fit. It rejects the edit before publication.

Linked nodes are not candidates for independent pruning. Their shared
participant relation remains complete until `multibuffer_prune` proves that
every corresponding node is an eligible inactive leaf and the caller supplied
the exact live store set.

A policy decrease first validates the complete candidate, then plans every
required removable leaf in temporary storage. The smaller request and policy
pruning bound limits this proof. If the proof cannot satisfy every new field,
the old policy and topology remain exact. Once the proof succeeds, selected
children are released before parents without further allocation, accounting is
updated, and the new generation becomes authoritative.

## Expected failures

`Failure_Code` distinguishes invalid identity or lifecycle, invalid policy,
stale revision or generation, retained root and redo alternatives, missing
payload, dependency or participant conflicts, resource limits, allocation,
cancellation, and bounded work failure.

`Failure_Context` includes the relevant store, history, node, buffer,
revision, policy generation, field, range, and actual value. Transaction
callers receive the original history context under transaction
`History_Failure`.

Policy boundary failures preserve their native detail:

| Native history failure | Bridge failure | Relevant context |
| --- | --- | --- |
| `Stale_Generation` | `Stale_Generation` | `policy_generation`, expected value in `actual` |
| `Policy_Range` | `Policy_Range` | `policy_field`, minimum, maximum, and actual value |
| `Policy_Relationship` | `Policy_Relationship` | `policy_field`, maximum, and actual value |
| `Policy_Retention_Blocked` | `Retention_Blocked` | `policy_field`, blocking maximum and actual retained value |
| `Temporary_Memory_Limit` | `Temporary_Memory_Limit` | No topology or generation change |
| `Cancelled` | `Cancelled` | No topology or generation change |

Hosting reports a contained `Racket_Exception` for configuration exceptions
and `Wrong_Result` for malformed envelopes, generations, field counts, or
unsigned values. Wrong-thread, reentrant, stale-capability, and retained-token
failures are rejected before native policy access.

## Measured evidence

The resource study ran on Linux 7.0.5 x86-64 with Odin
`dev-2026-07:301c287de`:

| Profile | Shape | Exact candidate bytes | Navigation p99 | Result |
| --- | --- | ---: | ---: | --- |
| Ordinary | 10,000 nodes, 10,031 records, 16 MiB payload | 18,779,696 | 511 ns | Admitted below 2 ms gate |
| Demanding | 100,000 nodes, 109,999 records, 256 MiB payload | 289,235,376 | 581 ns | Admitted below 8 ms gate |
| Stress | 1,000,000 nodes, 1,099,999 records, 1 GiB payload | 1,281,741,744 | Not run | Truthfully rejected by 512 MiB and 250,000-node defaults |

The candidate node is 120 bytes and the candidate record is 80 bytes. Exact
tracking matched calculated storage in both admitted profiles. Teardown left
zero tracked bytes.

Live policy replacement evidence from the same harness is:

| Profile | Inspection | Branch selection | Selective analysis | Policy replacement | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| Ordinary | 37,720 ns | 1,693 ns | 722 ns | 60,524 ns; 45 nodes pruned | All operations below 2 ms gate |
| Demanding | 57,989 ns | 1,744 ns | 701 ns | 1,439,576 ns; 769 nodes pruned | All operations below 8 ms gate |
| Stress | 107,872 ns | 2,144 ns | 712 ns | 15,359 ns; no partial pruning | Bounded navigation succeeds; policy decrease is truthfully rejected below 8 ms gate |

Cancellation completed in 741 ns or less in the recorded runs. Every profile
preserved its active node and 32-unit protected window, and teardown left zero
tracked bytes. The measurements support the existing defaults and validated
ranges; no adjustment was required.

Run the evidence with:

```sh
make history-resource-study
make history-fuzz
```

The fixed-seed history oracle compares generated edit, undo, redo, retained
node selection, branch creation, and prune behavior with a contiguous text
model.

Linked history evidence from the same machine and compiler is:

| Profile | Participants | Reservation | No-fail finalization | Accounted peak | Cleanup |
| --- | ---: | ---: | ---: | ---: | ---: |
| Demanding | 1,000 | 3,760,532 ns | 21,981 ns | 1,023,080 bytes | 0 bytes |
| Stress | 10,000 | 34,108,472 ns | 1,092,746 ns | 10,230,080 bytes | 0 bytes |

Run the linked profiles directly with:

```sh
make multibuffer-history-benchmark
```
