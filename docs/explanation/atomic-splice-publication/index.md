<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Atomic Splice Publication

A splice is logically one operation: replace `[start, end)` and advance the
buffer revision. Its implementation contains work that can fail for ordinary
reasons: invalid positions, malformed UTF-8, configured limits, cancellation,
or allocation failure. Atomic publication separates that fallible work from the
canonical state transition.

## Three phases

```text
Splice request
     |
     v
  Validate ----failure----> canonical state unchanged
     |
     v
  Prepare -----failure----> release candidate; canonical state unchanged
     |
     v
  Publish ----------------> new root + exactly one new revision
```

Validation proves that the request belongs to the current buffer revision and
fits every relevant input and resource bound. It does not allocate and does not
change editor state.

Preparation constructs the candidate rope, change set, and undo record. This
phase may allocate and fail, but its resources have a separate owner. The old
root remains canonical throughout preparation.

Publication performs the minimal state transition. It installs the candidate
root and records, advances the revision, and consumes the preparation. Once the
transition starts, the code permits no expected failure, cancellation check,
allocation, or callback.

## Why revision-bound positions matter

A numeric byte offset alone has no stable meaning after an edit. Binding an
offset to both buffer identity and revision turns accidental reuse into an
explicit `Wrong_Buffer` or `Stale_Revision` failure before preparation begins.

## Why the rope helps

The prepared root is a complete immutable candidate. Publication swaps a small
handle rather than modifying many text chunks in place. The old and candidate
roots may share unchanged subtrees safely because shared nodes are immutable.

## Observable guarantees

1. Every expected failure before publication leaves canonical text and revision unchanged.
2. Every successful splice advances the revision exactly once.
3. Readers observe either the old complete root or the new complete root, never a partial edit.
4. Change and undo records describe the same base and result revisions as the published root.
5. Old storage is released only after the new root is canonical.

The exact declarations are listed in
[Editor Core API](../../reference/editor-core/index.md).
