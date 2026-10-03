<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Unsaved-Work Recovery Reference

Odra checkpoints modified UTF-8 buffers into a private auxiliary store below
the platform state root. Recovery never grants implicit authority to write a
source file.

## Storage Location and Permissions

The versioned store is `<platform-state-root>/recovery/v1`. On Unix systems,
directories use mode `0700` and files use mode `0600`. The store contains
immutable payloads and records, atomic current-record references, and a
quarantine directory. Odra does not scan Projects to discover recovery state.

## Factory Policy

| Field | Value |
| --- | ---: |
| Enabled | true |
| Strategy | `hybrid` |
| Debounce | 300 ms |
| Maximum interval | 5,000 ms |
| Maximum age | 7 days |
| Records per buffer | 8 |
| Total records | 512 |
| Record payload | 128 MiB |
| Buffer storage | 512 MiB |
| Store storage | 2 GiB |
| Cleanup work per turn | 128 records |
| Startup policy | `ask` |
| Source autosave | `disabled` |

`transaction-debounced`, `interval`, and `hybrid` are valid strategies.
`ask`, `inspect`, and `restore-matching` are valid startup policies. Recovery
and source autosave are independent settings.

## Checkpoint Contract

Each current checkpoint binds its payload digest to a recovery buffer identity,
record identity, saved and recovered revisions, optional source identity and
fingerprint, UTF-8 encoding, LF or CRLF policy, creation time, policy
generation, and format version.

Publication writes and synchronizes temporary payload, record, and current
reference files before atomic replacement. A failed publication leaves either
the prior valid checkpoint or the complete new checkpoint. Empty modified
buffers are valid checkpoints.

Confirmed save, buffer close, and clean editor shutdown retire only the exact
current checkpoint owned by that buffer. Abnormal termination leaves valid
published checkpoints available for the next start.

## Candidate States and Actions

| State | Meaning | Actions |
| --- | --- | --- |
| `Restorable` | The current source matches the checkpoint fingerprint. | restore, inspect, compare, discard |
| `Conflict` | The source changed independently. | restore, inspect, compare, discard |
| `Pathless` | The original buffer had no source. | restore, inspect, discard |
| `Missing_Source` | The recorded source is absent. | restore, inspect, discard |
| `Inaccessible` | The source cannot be inspected safely. | restore, inspect, discard |

Malformed, truncated, incompatible, excessive, permission-invalid, and
digest-mismatched state is quarantined. One rejected record does not prevent
ordinary startup or the admission of other valid candidates.

Every action revalidates the exact record, buffer, and recovered revision.
Stale requests fail. **Restore** produces an ordinary modified buffer and
preserves the checkpoint bytes. **Inspect** creates a review buffer.
**Compare** includes both recovered and current source content. **Discard**
retires the candidate explicitly.

## Commands

| Command | Result |
| --- | --- |
| `recover-unsaved-work` | Present all pending recovery actions. |

Automatic startup review is restricted to the explicit launch file or the
selected directory, Project, and Workspace roots. Identities are normalized
absolute paths; a shared path prefix alone does not establish root membership.
An explicit file takes precedence over wider roots. Starting without a selected
context does not open a blocking recovery list.

Discovery still uses the global private store. Unrelated and pathless candidates
remain pending, with a nonblocking notification directing the user to
`recover-unsaved-work`. That command always presents the complete pending list.

`ask` and `inspect` present launch-related candidates for review.
`restore-matching` automatically restores only launch-related candidates in the
`Restorable` state; other related states require review. Source compatibility
alone never authorizes automatic restoration of an unrelated file.

`C-g` returns to the prior file, directory view, or startup screen without
retiring checkpoints or writing sources. Discarding the last displayed candidate
also returns there, even when unrelated checkpoints remain pending.

## Personal Configuration

Import `odra/recovery`, construct one policy with `recovery-policy`, and export
it as `odra-recovery-policy`. The retention and storage subrecords use
`recovery-retention` and `recovery-storage-limits`.

Invalid candidates preserve the complete last confirmed personal
configuration generation. The immutable bounds are enforced before native
startup state is published.

## Source Preservation

Restore, inspect, compare, discovery, cleanup, and quarantine do not write the
source. Only an ordinary explicit save may publish recovered buffer content to
an associated target.
