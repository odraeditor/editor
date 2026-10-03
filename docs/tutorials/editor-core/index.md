<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Follow One Splice Through the Editor

This tutorial follows the successful replacement of `world` with `rope` in
`hello world`. It is a code-reading path: each step identifies the state being
created and the file that owns it.

## 1. Start with a live buffer

`editor.buffer_init` in `src/editor/buffer.odin` validates the buffer identity,
limits, allocators, and initial UTF-8 text. The initial text becomes a
`text.Root`, and the canonical editor revision starts at zero.

At this point the important state is:

```text
buffer 7, revision 0
canonical text: "hello world"
```

## 2. Create revision-bound positions

Call `editor.buffer_position` for byte offsets 6 and 11. Each resulting
`editor.Position` contains three values:

```text
(buffer 7, revision 0, byte 6)
(buffer 7, revision 0, byte 11)
```

The buffer identity prevents positions from one buffer being used in another.
The revision prevents an old position from silently addressing changed text.
The byte offset must lie on a UTF-8 code-point boundary.

## 3. Describe the replacement

The two positions and replacement text form an `editor.Splice`:

```text
[6, 11) -> "rope"
```

The range is half-open: byte 6 is included and byte 11 is excluded.

## 4. Validate without mutation

`editor.buffer_validate_splice` in `src/editor/splice.odin` checks identity,
revision, range order, UTF-8 boundaries, replacement validity, resulting size,
memory budgets, and bounded node work. It produces a
`editor.Validated_Splice` with a `editor.Splice_Reservation`.

No canonical state changes during validation. A failure still leaves revision
zero and `hello world` as the canonical text.

## 5. Prepare an immutable candidate

`editor.buffer_prepare_splice` asks `text.root_prepare_splice` in
`src/text/rope.odin` for a candidate root. The rope creates replacement storage
and the necessary ancestor path while retaining unchanged structure.

The editor also prepares a change set and undo record. The candidate owns those
resources, but the buffer still exposes the old root and revision:

```text
canonical: revision 0, "hello world"
candidate: revision 1, "hello rope"
```

`editor.prepared_splice_inspect` can copy text from the candidate before it is
published. `editor.prepared_splice_abort` releases the candidate without
changing the canonical state.

## 6. Publish through the atomic path

The public convenience operation `editor.buffer_splice` performs preparation
and then enters the private publication step. All expected failures,
allocations, and cancellation checks occur before publication begins.

Publication swaps the canonical root, advances the revision exactly once, and
installs the prepared change and undo records:

```text
buffer 7, revision 1
canonical text: "hello rope"
```

After the swap, the old root is released. Because roots are persistent, any
separately retained old version remains valid until its own handle is released.

## 7. Compare semantic and structural correctness

The reference model in `tests/reference` performs the same operation on a
contiguous string. Tests compare its final bytes with the production editor.
The reference model answers whether the resulting text is correct; rope tests
also check sharing, summaries, ownership, and bounded reclamation.

Continue with [Atomic Splice Publication](../../explanation/atomic-splice-publication/index.md)
for the transaction boundary and [Editor Core API](../../reference/editor-core/index.md)
for the complete public surface.
