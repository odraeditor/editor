<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Recover Unsaved Work

Odra keeps private recovery checkpoints for modified buffers. A checkpoint is
separate from the source file: it protects recent editor content but does not
save or overwrite the source.

## Observe the Startup Recovery List

After an interrupted editor process, start Odra with the file or directory you
want to work on. The startup recovery list shows only retained work for that
file or inside the selected directory, Project, or Workspace roots. Each row
names the buffer, explains its action and source condition, and shows how long
ago the checkpoint was created.

Unrelated checkpoints do not interrupt startup. A short notification points
to `M-x recover-unsaved-work`, which shows all pending candidates. Starting
without a file or selected roots leaves recovery review to that command.
If you are on the startup screen or a directory view, open a file or create a
buffer first to use `M-x`.

Move with Up or Down and press Enter to apply the selected action:

- **Restore** opens the recovered content as a modified editor buffer.
- **Inspect** opens a copy of the recovered content for review.
- **Compare** opens recovered content beside the current source content in one
  comparison buffer.
- **Discard** removes that retained checkpoint.

Press `C-g` to return to the file, directory, or startup screen you opened,
without changing a candidate. Run
`M-x recover-unsaved-work` to return to pending candidates later in the same
session.

## Handle Source Conflicts

Odra compares a file-backed checkpoint with the current source. A matching
source may be restored directly into a modified buffer. A source that changed
after the checkpoint is marked as a conflict and is not overwritten.

Use **Compare** or **Inspect** before **Restore** when the source changed. A
restore still changes only the editor buffer. Save explicitly when the
recovered buffer contains the version that should replace the source.

A missing, inaccessible, or pathless source restores into an unassociated
buffer. Choose a target through the ordinary save workflow.

## Configure Recovery

The factory policy uses a 300 ms quiet-period debounce and a 5 second maximum
interval. It retains bounded private checkpoints for seven days. Source-file
autosave is disabled.

Personal configuration can replace the policy:

```racket
#lang racket/base

(require odra/recovery)

(provide odra-recovery-policy)

(define odra-recovery-policy
  (recovery-policy
   #:strategy 'hybrid
   #:debounce-milliseconds 500
   #:maximum-interval-milliseconds 5000
   #:startup 'ask
   #:source-autosave 'disabled))
```

Use `inspect` to present launch-related candidates for review or
`restore-matching` to automatically restore only launch-related candidates
whose current source still matches. Conflicts remain explicit in every startup
mode. Unrelated and untitled checkpoints remain available through
`recover-unsaved-work`; no startup mode automatically restores them without a
matching launch context.

## Verify the Result

Recovery is complete when the chosen content is open as an ordinary modified
buffer, the source file remains unchanged until an explicit save, and handled
candidates no longer appear in `recover-unsaved-work`.

For exact states, limits, paths, and action rules, see the
[Unsaved-Work Recovery Reference](../../../reference/unsaved-work-recovery/index.md).

---

[Previous: Save and Revisit Editor State](save-and-revisit-state.md) ·
[User Guide](../index.md) ·
[Next: Buffers and Panes](../buffers-and-panes/index.md)
