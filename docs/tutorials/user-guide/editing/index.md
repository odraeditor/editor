<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Editing

This part teaches ordinary text work: movement, selection, transfer, reversible
history, and saved editor state.

## Chapters

1. [Move and Edit Text](move-and-edit-text.md) covers grapheme, word, line, and
   page movement together with direct insertion, indentation, deletion, and
   overwrite input.
2. [Select Text](select-text.md) introduces point, mark, active regions,
   semantic selection, cancellation, and recent selection locations.
3. [Transfer Text](transfer-text.md) uses the internal kill ring to copy, kill,
   yank, rotate, and undo selected text.
4. [Undo and Redo Changes](undo-and-redo.md) traverses semantic editing units,
   creates an alternate future, and explains the current branch-selection
   boundary.
5. [Save and Revisit Editor State](save-and-revisit-state.md) persists named
   locations, text, values, and portable layout intent through typed candidate
   workflows.
6. [Recover Unsaved Work](recover-unsaved-work.md) reviews private recovery
   checkpoints after an interrupted editor process.

Follow the chapters in order. They share one disposable practice file and
progress from direct text movement to persistent editor state.

## Continue

Proceed to [Buffers and Panes](../buffers-and-panes/index.md) to turn individual
buffers and views into a complete working set.

## Related Material

These focused tutorials remain available while their workflows are integrated
into this part:

- [Navigate and Edit Directly](../../direct-navigation/index.md)
- [Select Text with Point and Mark](../../selection/index.md)
- [Copy, Kill, Yank, and Rotate Text](../../text-transfer/index.md)
- [Undo a Semantic Terminal Edit](../../reversible-editing-history/index.md)

---

[Previous: Use Commands and Interactions](../getting-started/commands-and-interactions.md) ·
[User Guide](../index.md) ·
[Next: Move and Edit Text](move-and-edit-text.md)
