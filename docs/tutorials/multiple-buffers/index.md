<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Start, Create, and Navigate Multiple Buffers

This tutorial uses the terminal frontend to keep several texts live, move
between their retained views, inspect the complete Buffer Menu, and perform
marked operations.

## 1. Prepare two files

From the repository root, create two small files outside the repository:

```sh
printf 'alpha one\n' > /tmp/odra-alpha.txt
printf 'beta two\n' > /tmp/odra-beta.txt
make odra
```

## 2. Open the first file from startup

Start Odra without a path:

```sh
.build/odra
```

The startup list contains `Create a new buffer` and `Open File`.
It is not an editable buffer and retains no document, history, or primary-view
graph.

Press Down, then Enter. At `Find file:`, enter `/tmp/odra-alpha.txt` and press
Enter. The file becomes the visible buffer. Its complete normalized path is
its selection label.

## 3. Create a named buffer

Press `Control-X`, then `b`. The terminal displays:

```text
Switch to buffer:
```

Enter `λ-notes` and press Enter. No live buffer has that label, so Odra
creates an empty unassociated buffer and makes its primary view visible.

Type `temporary notes`. The original file buffer remains live and unchanged.

## 4. Return to the first file

Press `Control-X`, then `b`. Enter the complete selection label:

```text
/tmp/odra-alpha.txt
```

Press Enter. The first buffer becomes visible again. Its point, mark, region,
desired column, viewport, and independent history remain attached to that
buffer's retained primary view.

Type `X` at the beginning, then press `Control-X`, followed by `Control-S`.
The file now contains `Xalpha one`.

## 5. Open another file

Press `Control-X`, then `Control-F`. The terminal displays:

```text
Find file:
```

Enter `/tmp/odra-beta.txt` and press Enter. Odra opens the file in a new live
buffer and selects it.

Invoke `find-file` again with `/tmp/./odra-beta.txt`. Lexical normalization
resolves the same canonical path. Odra selects the existing live buffer
without rereading or replacing its text.

## 6. Observe independent history

Insert `Y` in the second file and undo it with `Control-/`. Switch to
`λ-notes`; its text and cursor remain where you left them. Undo there affects
only that buffer's history.

Switch back to `/tmp/odra-beta.txt`. The second file's point and undo state are
restored independently.

## 7. Inspect and select buffers

Press `Control-X`, then `Control-B`. The Buffer Menu lists every live entry in
active-then-most-recently-used order. File-backed rows contain complete paths;
the named buffer contains `λ-notes`.

Press Down or Up to move the highlighted row. Press Enter on
`/tmp/odra-alpha.txt`. That row's retained primary view becomes visible.

Open the Buffer Menu again. Press `q` to return without selecting another
entry. `Control-G` has the same local cancel behavior.

## 8. Save and kill through marks

Open the Buffer Menu and move to a modified file-backed row. Press `s`. The
row gains an `S` mark and selection advances. Press `x` to execute. Successful
saves are published independently and the menu refreshes from current session
state.

Move to `λ-notes`, press `d`, then `x`. Because it is modified and
unassociated, Odra displays:

```text
Marked buffer: [s]ave [d]iscard [c]ancel
```

Press `d`. The complete admitted kill set closes and the Buffer Menu refreshes
with the surviving entries. Press `u` before execution whenever you need to
remove the current row's mark.

## 9. Finish safely

Press `Control-X`, followed by `Control-C`. Odra visits modified buffers in
most-recently-used order. For each one, choose `s` to save, `d` to discard, or
`c` to cancel the complete exit request. Saving an unassociated buffer first
opens the `Save as:` prompt.

The process exits only after every modified buffer has been saved or explicitly
discarded. A cancellation keeps every buffer live; any earlier successful save
remains an external fact.

## 10. Verify the complete workflow

From the repository root, run the focused acceptance target:

```sh
make buffer-session-acceptance
```

The target replays generated registry operations, aggregate resource profiles,
mixed Odin and Racket capability calls, multi-buffer transaction and history
benchmarks, and PTY workflows for create, open, reuse, activation, selection,
transfer, search, save, kill, Buffer Menu, and exit. Every scenario closes its
temporary files, native owners, hosted callbacks, and terminal state.

Continue with [Manage Multiple Buffers](../../how-to/manage-multiple-buffers/index.md)
for the direct command procedures and failure behavior.
