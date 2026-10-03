<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Text Transfer Reference

This reference defines the current internal kill-ring, region-transfer, yank,
rotation, physical clipboard, resource, history, and failure contracts.

## Ownership and ordering

One editor session owns one Odin `kill_ring.Ring`. It stores immutable valid
UTF-8 entries from newest to oldest. Each entry owns its copied text and has a
stable nonzero identity. The ring has a monotonically changing generation for
each admitted copy, kill, or external entry.

The ring is independent from buffers, views, history stores, Racket, and the
frontend. Inspection returns copied metadata and entry access returns copied
text; neither exposes internal storage. Physical clipboard state is never
canonical editor or ring state.

## Physical clipboard adapter

`src/terminal` owns one optional opaque clipboard adapter. It reports read and
write capabilities independently and exchanges only bounded copied values.
`src/odra` coordinates the adapter with semantic commands; `src/command`
validates ring admission, retained-entry export, change tokens, and
deduplication. Racket receives no physical clipboard handle or operation.

The admitted production path is direct BEL-terminated OSC 52 export through a
Herdr-owned pane to its outer terminal client. Odra recognizes exact inherited
Herdr identifiers or an exact `herdr` executable within eight parent
processes. Nested tmux and Zellij sessions are rejected. Generic SSH sessions,
remote graphical clipboard utilities, and OSC 52 queries are not claimed.

| Path | Read | Write | Presentation |
| --- | --- | --- | --- |
| Direct Herdr pane | No | Yes | Outer terminal client |
| Nested tmux or Zellij | No | No | Unavailable |
| Generic SSH terminal | No | No | Unavailable |
| Deterministic test adapter | Configurable | Configurable | Test-owned copied values |

Copy and kill attempt export only after the internal ring transition and any
canonical text publication complete. Export copies the exact retained entry.
Failure produces a bounded diagnostic and cannot roll back canonical state.

Yank requests external text only when the active adapter reports read
capability. A valid changed UTF-8 value is admitted through the ordinary
bounded `.External` ring path before yank. The coordinator retains only the
last successful import and export tokens, never payload text. It suppresses a
self-export token, a repeated import token, and content identical to the newest
ring entry. Read absence or failure falls back to the internal ring.

The production Herdr adapter is write-only. Clipboard read behavior is a
replaceable frontend contract covered by deterministic adapters, not a claimed
Herdr capability.

## Programmable capability

Racket can inspect and compose the delivered selection and transfer behavior
through a dynamically scoped capability. Odin owns the capability context and
validates the exact editor session, granted access set, view identity and state
generation, buffer and revision, ring identity and generation, and command
registry generation before each operation.

The capability grants four independent authorities:

- copied region inspection;
- copied ring metadata inspection;
- copied entry-text access; and
- invocation of admitted selection and transfer commands.

Ring inspection returns at most 256 fixed 40-byte metadata records. Entry text
is copied as immutable valid UTF-8 and is limited to 12 MiB per call. Semantic
invocation admits only `set-mark-command`, `deactivate-mark`,
`exchange-point-and-mark`, `copy-region`, `kill-region`, `delete-region`,
`yank`, and `yank-pop`. These names resolve through the existing command
registry and retain the ordinary native transaction and history semantics.

Racket receives an active transport generation, an opaque scalar token, and
little-endian copied records. It never receives an Odin pointer, anchor,
buffer, view, ring entry, or commit operation. Escaped sessions, wrong kinds,
generations, tokens, or threads, nested entry, malformed records, excess
quotas, cancellation, Racket exceptions, and continuation escape are contained
before an unvalidated effect. The shared C transport clears its callback and
user-data pointer before returning to the editor, and every temporary ring or
text copy is explicitly released.

## Measured policy

| Resource | Default | Validated range |
| --- | ---: | ---: |
| Retained entries | 60 | 16 to 4,096 |
| Bytes per entry | 12 MiB | 4 KiB to 12 MiB |
| Total retained text | 256 MiB | 1 MiB to 256 MiB |
| Consecutive coalesced kills | 10,000 | 16 to 10,000 |
| Copied inspection entries | 256 | 1 to 256 |
| Rotation search work | 4,096 entries | 16 to 4,096 entries |
| Temporary transfer bytes | 64 MiB | 1 MiB to 256 MiB |
| Cancellation interval | 256 KiB | 64 KiB to 4 MiB |
| Clipboard text | 196,602 bytes | 1 to 196,602 bytes |
| Clipboard timeout | 1 second | 10 milliseconds to 5 seconds |
| Clipboard cancellation interval | 64 KiB | 64 KiB to 4 MiB |
| Clipboard temporary storage | 512 KiB | Must hold one text copy and complete OSC 52 frame |

Policy validation requires one admitted entry to fit within total retained
text and three complete maximum-size preparation copies to fit within the
temporary budget. A candidate that exceeds the per-entry or total byte limit
is rejected before any eviction.

When a valid candidate needs space, admission evicts complete oldest entries
until both count and total-byte limits hold. It never truncates an entry or a
UTF-8 sequence.

## Region commands and bindings

Copy, kill, and delete require an active non-empty region with a live mark at
the current buffer revision.

| Command | Direct binding | Result |
| --- | --- | --- |
| `copy-region` | `M-w` | Retain exact region text without changing buffer revision, view state, or history. |
| `kill-region` | `C-w` | Retain exact region text and publish one reversible deletion. |
| `delete-region` | Unbound | Publish one reversible deletion without changing the ring. |
| `yank` | `C-y` | Insert the newest complete entry through one reversible transaction. |
| `yank-pop` | `M-y` | Replace only the immediately preceding valid yank range with the next entry. |

Terminal Escape followed by one printable ASCII key is normalized as logical
Meta, so Escape then `w` and Escape then `y` provide the factory `M-w` and
`M-y` bindings when Alt is not transmitted directly.

On a write-capable frontend, successful `copy-region` and `kill-region` also
attempt physical export. `yank` requests physical import only from a
read-capable frontend. `delete-region` and `yank-pop` do not access the
clipboard.

Successful kill and delete leave point at the beginning of the removed region
and deactivate the region while retaining mark. Copy preserves both endpoints
and activation. Yank and yank-pop leave point at the end of inserted text and
deactivate an active region through the ordinary logical-edit result.

## Consecutive kill coalescence

Only compatible consecutive `kill-region` commands coalesce. Compatibility is
derived from semantic metadata:

- the same nonzero kill-sequence identity;
- adjacent command event sequences;
- the same source buffer;
- the same direction; and
- the required source-position continuity.

Forward kills append to the newest entry. Backward kills prepend. A different
command, copy, sequence, event gap, buffer, direction, or incompatible source
position starts a new entry. Time and command-name string comparison are not
used as intent.

## Yank rotation context

Successful yank records a transient context containing:

- the exact live view and buffer;
- the result revision;
- the complete inserted byte range;
- the ring generation; and
- the retained entry identity.

`yank-pop` is valid only as the immediately following command while every
recorded value remains current. It copies the next entry and atomically
replaces the complete recorded range. Another command, undo, text publication,
ring admission, stale view, changed generation, missing entry, or invalid range
ends the chain. Rotation never reorders the ring. Undo and redo affect the text
transactions but do not rewind the ring.

## Reservation and history

Admission reservation copies and validates the complete candidate and computes
complete eviction before canonical ring state changes. Abort releases all
private storage.

Kill coordinates its ring reservation with the ordinary text transaction,
logical view result, and complete immediate history record. Expected failure
during preparation aborts every participant unchanged. After validation, the
ring and transaction publish without allocation or an expected-failure
boundary.

Copy creates no history node. Delete, kill, yank, and yank-pop each create an
ordinary reversible history transition. Undo and redo restore buffer point,
optional mark, and activation through the initiating view when it remains live.
A selective-history
request uses the active region's ordered checked range when a live initiating
view is supplied and no explicit anchor range overrides it.

## Expected failures

Expected rejection includes inactive, absent-mark, and empty regions; stale
view, buffer, revision, generation, or yank context; empty ring; missing entry;
invalid UTF-8; policy, entry, total-byte, coalescence, inspection, rotation,
temporary-memory, or persistent-memory exhaustion; pending reservation; and
cancellation.

Clipboard-specific expected failure includes unavailable capability, empty or
invalid UTF-8 text, the 196,602-byte text ceiling, the temporary-memory limit,
timeout, cancellation, exhausted change tokens, partial response, physical
read or write failure, descriptor restoration failure, and transport teardown
failure. These failures do not alter a completed copy, kill, or internal yank.

These failures preserve all canonical state not explicitly documented as
already committed. Partial entry storage, invalid UTF-8 in retained storage,
incorrect accounting, and failure after coordinated publication begins are
invariant violations.

Use `odin doc src/kill_ring -in-source-order` and
`odin doc src/command -in-source-order` for generated editor declaration
reference. Use `odin doc src/terminal -in-source-order` for the clipboard
adapter contracts.
