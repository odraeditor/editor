<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Local Document Lifecycle Reference

This reference defines the delivered single-document Linux lifecycle. Source
declaration comments under `src/document` remain authoritative for the Odin API.

## Capability boundary

One Odra process may retain several document-backed entries, each with one
associated buffer and primary view, behind one terminal frontend. Starting
without a path presents the non-buffer startup list. The external encoding
is strict UTF-8.

## Startup forms

| Arguments | Result |
| --- | --- |
| none | Startup list with Create and Open actions; no buffer or file is created. |
| one existing regular-file path | Exact bytes are validated as UTF-8 and opened as a clean materialized document. |
| one missing final path | Empty unmaterialized document associated with that target; no file is created. |
| more than one path | Rejected before terminal acquisition. |

The final component may be absent or an existing regular file. A final symbolic
link, directory, device, FIFO, or socket is rejected. The parent must already
exist as an accessible directory. Relative paths are resolved once against the
startup working directory.

UTF-8 byte-order marks, LF, CRLF, and admitted isolated carriage returns are
ordinary canonical bytes. Odra performs no normalization or replacement.

## Persistence states

| State | Meaning |
| --- | --- |
| `Unassociated` | The buffer has no target. |
| `Unmaterialized` | A target is associated but no file exists there. |
| `Clean` | The live buffer revision equals the saved revision. |
| `Modified` | The live buffer revision differs from the saved revision. |
| `Saving` | One bounded save operation owns the document. |
| `Closed` | The document handle no longer owns resources. |

Document status includes the document and buffer identities, encoding, target
presence, materialization, saved revision, external observation, and a borrowed
target path.

## Save request

`Control-X`, then `Control-S` selects `save-associated-document` through the
Racket-defined fixture keymap.

- An unassociated buffer enters the bounded `Save as:` path prompt.
- An associated document saves to its current target.
- Cancellation leaves canonical text and document association unchanged.
- A successful first save publishes the private association and materializes
  the target.
- Only the captured buffer revision becomes saved.
- A newer live revision remains modified.

An explicit save observes but does not block on external target replacement.

## Linux publication sequence

1. Retain one immutable buffer snapshot and exact revision.
2. Create an exclusive same-directory temporary file.
3. Select the replacement mode and stream UTF-8 in bounded chunks.
4. Sync and close the temporary file.
5. Open the parent directory and atomically rename over the target.
6. Sync the parent directory.
7. Refresh observation and saved-revision state.

The result distinguishes:

| Publication | Meaning |
| --- | --- |
| `Not_Published` | Rename did not succeed; the prior target remains authoritative. |
| `Published_Durable` | Rename and parent-directory sync succeeded. |
| `Published_Durability_Uncertain` | Rename succeeded but directory sync failed. |

Pre-publication failure closes and removes temporary resources. A post-rename
durability failure never reports that the target was unchanged.

## Metadata behavior

Existing POSIX permission bits are preserved. New files use mode `0666` subject
to the process umask. Atomic replacement creates a new inode. The first Linux
contract does not preserve hard-link identity, ownership beyond normal creation
rules, ACLs, extended attributes, or filesystem-specific metadata.

The external observation records target existence, device and inode, encoded
size, modification time, and mode. It is diagnostic state and grants no
background mutation authority.

## Exit behavior

`Control-X`, then `Control-C` selects `request-editor-exit`.

- A clean document exits directly.
- Unassociated, unmaterialized, or modified work displays
  `Save changes? [s]ave [d]iscard [c]ancel`.
- Save follows the ordinary save workflow and exits only after success.
- Discard is the explicit authorization to exit without saving.
- Cancel or `Control-G` returns to editing.
- Canceling a chained path prompt or encountering a save failure returns to
  editing and preserves unsaved work.

The terminal presents one bounded bottom-row prompt or diagnostic. Unsupported
choice input leaves the prompt active. Orderly shutdown restores the acquired
terminal attributes, resize signal ownership, cursor visibility, and style.
EOF after the PTY disappears is reported as a read failure; restoration is
still consumed and may itself report failure when the terminal device is gone.

## Resource limits

| Resource | Limit |
| --- | ---: |
| Encoded file or save snapshot | 256 MiB |
| Path | 4,096 UTF-8 bytes |
| Diagnostic | 4,096 bytes |
| Streaming I/O chunk | 64 KiB |
| Live document operations | 1 |
| Live save snapshots | 1 |
| Temporary-name attempts | 16 |
| Interrupted zero-progress retries | 16 |

The save path retains no second whole-document byte string. Prompt text and
rendered prompt output are separately bounded.

## Measured evidence

Reference environment: Odin `dev-2026-07:301c287de`, Linux
`7.0.5-arch1-1` x86_64.

| Encoded bytes | Open latency | Open peak tracked storage | Save latency | Save peak extra |
| ---: | ---: | ---: | ---: | ---: |
| 4,096 | 69,220 ns | 2,394,424 bytes | 67,366 ns | 4,320 bytes |
| 4,194,304 | 7,710,479 ns | 10,704,552 bytes | 1,438,755 ns | 4,320 bytes |
| 268,435,456 | 486,057,866 ns | 551,812,936 bytes | 77,912,991 ns | 4,320 bytes |

All save runs reported `Published_Durable`; all open and save runs released
tracked storage after document and buffer closure. These are measurements from
one reference run, not latency acceptance thresholds.

## Validation

```sh
make document-evidence
make terminal-presentation-test
make docs-check
make verify
```

See [Why Documents Are Separate from Buffers](../../explanation/document-lifecycle/index.md)
for the design rationale.
