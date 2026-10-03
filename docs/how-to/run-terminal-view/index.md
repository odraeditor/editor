<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Open, Edit, and Save a Local Document

Use the terminal frontend to open a UTF-8 local document, edit it, and save it.
Additional files and named buffers can remain live in the same session.

## Prerequisites

- Linux with a compatible POSIX terminal;
- Odin and Racket installed as required by the repository;
- an interactive terminal with UTF-8 support.

## Build Odra

From the repository root, run:

```sh
make odra
```

The executable is `.build/odra`.

## Open a document

Pass one existing regular file:

```sh
.build/odra notes.md
```

Passing a missing final path opens an empty document without creating the file.
The first successful save creates it. Starting without an argument presents
the non-buffer startup list:

```sh
.build/odra
```

Odra accepts at most one path. It rejects malformed UTF-8 and unsupported
targets before acquiring the terminal.

## Edit and save

The active fixture controls are:

| Input | Result |
| --- | --- |
| Arrow keys, Home, End | Move the cursor. |
| Printable UTF-8 | Insert text. |
| Backspace or Delete | Delete one complete grapheme. |
| Enter | Insert one line feed. |
| `Control-X`, then `Control-S` | Save the current document. |
| `Control-X`, then `Control-F` | Open or select a local file buffer. |
| `Control-X`, then `b` | Select an exact buffer label or create an unmatched name. |
| `Control-X`, then `Control-B` | Present the complete live Buffer Menu. |
| `Control-X`, then `k` | Kill an exact buffer label after any required dirty-state decision. |
| `Control-G` | Cancel a pending key sequence or active prompt. |
| `Control-X`, then `u` | Uppercase the current logical line through Racket. |
| `Control-Space` | Set mark at point and activate the region. |
| `M-w`, `Control-W` | Copy or kill the active region and attempt supported clipboard export. |
| `Control-Y`, `M-y` | Yank the newest retained entry or rotate the preceding yank. |
| `Control-X`, then `Control-C` | Request orderly exit. |

Saving an unassociated buffer displays `Save as:`. Enter a relative or absolute
path and press Enter. An empty or oversized path keeps the prompt active with
an invalid marker. `Control-G` cancels without creating a file.

A failed save displays a bounded diagnostic and returns to editing. An explicit
save replaces an externally changed regular target; it does not open a merge or
conflict dialog.

## Exit without losing work

A session with only clean buffers exits immediately after `Control-X`, then
`Control-C`. Each modified file-backed or unassociated buffer displays, in
most-recently-used order:

```text
Save changes? [s]ave [d]iscard [c]ancel
```

- `s` saves that buffer and continues. An unassociated buffer first enters
  `Save as:`.
- `d` explicitly discards that buffer for this exit request and continues.
- `c` or `Control-G` cancels the complete exit request and returns to editing.

No buffer is detached while the decisions are in progress. Canceling the path
prompt or encountering a save failure also returns to the editor with every
buffer live. A save completed earlier in the sequence remains on disk. Odra
restores the acquired terminal attributes on every orderly exit path.

## Use clipboard export when available

The terminal frontend always provides the internal kill ring. When it detects
the supported direct Herdr presentation path, `M-w` and `Control-W` also export
the retained text to the outer terminal clipboard after the editor operation
succeeds. Clipboard-read capability is unavailable on this path.

See [Use the System Clipboard](../use-system-clipboard/index.md) for the exact
path, physical verification, limits, fallback, and troubleshooting procedure.

## Run the lifecycle checks

```sh
make terminal-presentation-test
make document-evidence
make verify
```

The PTY suite checks visible prompts, document outcomes, process status, resize
signals, and terminal cleanup. The evidence command measures representative
open and save workloads.

See the [Local Document Lifecycle Reference](../../reference/document-lifecycle/index.md)
for exact state, path, persistence, and metadata contracts.

See [Manage Multiple Buffers](../manage-multiple-buffers/index.md) for creation,
full-path selection, retained view state, individual kill, and multi-buffer
exit.
