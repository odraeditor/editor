<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Atomic Edit Transaction Reference

The `transaction` package is the only coordinator for command-scoped text
publication. It owns private revisions, lifecycle validation, normalized
changesets, participant ordering, resource accounting, and the decision to
publish or abort. The `editor` package retains ownership of canonical buffers
and the allocation-free publication primitive.

## Terminology

| Term | Meaning |
| --- | --- |
| Root transaction | The owner of one atomic outcome and one transaction identity. |
| Working revision | A private buffer revision that supports read-your-writes behavior. |
| Base-relative batch | Ordered non-overlapping splices expressed against one confirmed revision. |
| Sequential edit | An edit expressed against the current private working revision. |
| Nested command | A command joined to the root through a bounded savepoint; it cannot commit. |
| Participant | A declared buffer or logical view state that must publish or abort with the root. |
| Normalized changeset | The immutable base-relative description of one committed buffer transition. |
| Edit proposal | A complete set of producer-observed snapshots and base-relative batches. |
| Observer | A post-commit consumer with no authority over the completed transaction. |

Atomicity, undo grouping, and observation are separate contracts. One root
publishes atomically and carries one `Undo_Unit_ID`; later history work decides
how linked records are traversed or grouped.

## Lifecycle

```text
Building -> Validating -> Ready -> Publishing -> Committed
    \            \          \
     -----------------------> Aborted
```

`Building` admits private edits and savepoints. `Validating` freezes the
participant set, normalizes transitions, verifies every base revision, and
reserves publication storage. `Ready` accepts only commit, cancellation, or
abort. `Publishing` performs no allocation, callback, cancellation check, or
expected-failure operation. `Committed` and `Aborted` are terminal until the
handle is closed.

## Single-buffer declarations

| Area | Declarations | Contract |
| --- | --- | --- |
| Root | `Transaction`, `transaction_begin`, `transaction_close` | The caller owns the handle and allocator lifetime. Unclosed unpublished work aborts during close. |
| Batch editing | `Base_Splice`, `transaction_apply_batch` | Positions share one base revision; overlap and ambiguous order are rejected. |
| Sequential editing | `transaction_position`, `transaction_inspect`, `transaction_splice` | Positions carry private identity and generation; every successful edit invalidates older working positions. |
| Composition | `Nested_Command`, `transaction_nested_begin`, `transaction_nested_succeed`, `transaction_nested_fail` | A child joins the root or restores its savepoint. Only the root publishes. |
| Lifecycle | `transaction_validate`, `transaction_request_cancel`, `transaction_commit`, `transaction_abort` | Validation reserves the no-fail publication input. Cancellation remains cooperative until publication begins. |
| Result | `Commit_Result`, `Commit_Event`, `Normalized_Splice` | The result borrows transaction-owned storage until close. Observer failure is reported separately. |

## Multibuffer declarations

| Area | Declarations | Contract |
| --- | --- | --- |
| Root | `Multibuffer_Transaction`, `multibuffer_begin`, `multibuffer_close` | The complete non-empty set is sorted by `Buffer_ID`; duplicate identities fail before editing. |
| Private editing | `multibuffer_apply_batch`, `multibuffer_position`, `multibuffer_inspect`, `multibuffer_splice` | Every operation addresses one declared participant and contributes to shared budgets. |
| Publication | `multibuffer_validate`, `multibuffer_commit`, `multibuffer_abort` | Every participant reaches `Ready` before one deterministic non-cancelable publication section begins. |
| Shared result | `Multibuffer_Commit_Event`, `Buffer_Commit_Result` | Results are ordered by buffer identity and share one transaction and undo identity. |
| Filtering | `multibuffer_event_for_buffer`, `Buffer_Commit_Event` | A per-buffer view preserves the shared transaction identity and metadata. |

Odra executes the publication section during one exclusive editor turn. It
installs prepared roots in deterministic order without yielding to readers,
frontends, Racket, hooks, or other callbacks. No expected failure remains after
the first installation.

## Optimistic proposal admission

`Edit_Proposal` contains an `Origin`, command name, `Proposal_Snapshot` list,
and `Proposal_Edit` list. `proposal_admit` requires:

1. One non-empty snapshot set and exactly one edit entry per snapshot.
2. Unique buffer identities and matching live buffer handles.
3. Exact current revisions for every declared snapshot.
4. Matching base revisions in every edit and splice position.
5. Ordered, non-overlapping batches within the shared resource limits.

Success leaves a `Multibuffer_Transaction` in `Ready`; only Odin can commit it.
A stale or incomplete proposal fails without retry, coordinate transformation,
or incremental publication. `Origin_Kind` is diagnostic metadata. Built-in,
Racket, language-tool, and external-proposal origins receive identical
validation and authority.

## Racket transaction facade

`src/command/transaction.rkt` exports an intentional `racket/base` facade.
`call-with-transaction` creates a dynamically bounded opaque session.
`transaction-inspect`, `transaction-apply-batch!`, and `transaction-splice!`
operate on private state. `transaction-invoke-nested` composes through native
savepoints. `transaction-reject` returns an expected failure, and
`transaction-request-abort!` requests root abort.

Racket cannot commit, retain a usable session after dynamic extent, use it from
another thread, access an Odin pointer, or bypass native validation. The bridge
checks registry identity, slot generation, transaction identity, command
identity, owner thread, reentrancy, and lifecycle on every operation.

## Observer behavior

Observers run synchronously only after the root reaches `Committed`. One
multibuffer event contains every `Buffer_Commit_Result`. An observer cannot
reenter or close the transaction during delivery. Returning failure changes
`Observer_Status` to `Failed`; it does not hide or roll back the real commit.

## Resource limits

| Dimension | Default or maximum |
| --- | --- |
| Buffer participants | Maximum 10,000 |
| Splices | 100,000 default |
| Inserted, removed, and retained text | 1 GiB default |
| Temporary storage | 512 MiB default |
| Metadata | 16 MiB default |
| Nested depth | 32 maximum |
| Active savepoints | 256 maximum |
| Logical view participants | 1 current maximum |
| Cancellation checkpoint interval | 1,024 operations default |

The limits are independent. A transaction can reach the participant maximum
only when its metadata budget also covers the complete prepared set. The
10,000-buffer evidence profile raises metadata to 512 MiB explicitly; the
ordinary default is not widened silently.

## Expected failures

`Failure_Code` distinguishes identity, lifecycle, origin, participant,
revision, position, UTF-8, overlap, limit, cancellation, changeset,
reentrancy, and view failures. `Incomplete_Participant_Set` identifies missing
or duplicate proposal entries. Every expected failure occurs before
publication and releases or preserves all private participants together.

Assertions protect publication invariants that cannot be represented as
ordinary operating failures, including a prepared participant leaving `Ready`
before the root publication section.

## Measured evidence

The following optimized results were recorded on Linux 7.0.5 x86-64 with Odin
`dev-2026-07:301c287de` on 2026-08-13:

| Profile | Workload | Preparation | Publication | Gate | Transaction memory added |
| --- | ---: | ---: | ---: | ---: | ---: |
| Single ordinary | 1 splice | 97,061 ns | 1,173 ns | 1 ms | Included in package metadata evidence |
| Single demanding | 100,000 splices | 250,765,846 ns | 119,284 ns | 4 ms | 7,231,262 metadata bytes |
| Single stress | 1,000,000 splices | 2,364,079,706 ns | 1,825,458 ns | 16 ms | 72,031,262 metadata bytes |
| Multibuffer demanding | 1,000 buffers, 12 samples | 24,983,694 ns maximum | 617,446 ns p99 | 4 ms | 31,602,232 bytes peak added |
| Multibuffer stress | 10,000 buffers, 1 sample | 736,491,921 ns | 4,941,985 ns | 16 ms | 316,020,232 bytes peak added |

The multibuffer harness uses a bounded 1 MiB text profile, 16 MiB per-buffer
persistent limit, and 64-node reclamation queue. Its pre-existing canonical
buffer storage measured 293,488,000 bytes for 1,000 buffers and 2,934,880,000
bytes for 10,000 buffers. Transaction memory is reported separately so the
measurement does not hide the cost of already-open buffers.

Run `make transaction-benchmark` to rebuild both single-buffer and
multibuffer evidence. Run `make transaction-fuzz` for the fixed-seed generated
proposal corpus.

