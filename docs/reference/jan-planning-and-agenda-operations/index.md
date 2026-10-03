<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Planning and Agenda Operations Reference

The Planning and Agenda domain exposes public `jan-*` command identities,
pointer-free bridge records, and exact workflow plans without composing the
linked editor. `src/jan_planning` remains the semantic owner; document,
transaction, resource, provider, navigation, and export owners perform their
canonical effects.

## Public command catalog

The native catalog declares 71 Planning and Agenda commands. Registration does
not execute a command or grant authority.

| Family | Commands |
| --- | --- |
| Tasks and metadata | `jan-todo`, `jan-set-priority`, `jan-toggle-checkbox`, `jan-update-statistics`, `jan-set-tags`, `jan-set-property`, `jan-property-search`, `jan-column-view` |
| Time and clocks | `jan-timestamp`, `jan-schedule`, `jan-deadline`, `jan-clock-in`, `jan-clock-out`, `jan-clock-cancel`, `jan-clock-switch`, `jan-clock-resume`, `jan-clock-report`, `jan-set-effort` |
| Relative timers | `jan-timer-start`, `jan-timer-pause`, `jan-timer-resume`, `jan-timer-stop`, `jan-timer-reset` |
| Refile and archive | `jan-refile`, `jan-copy-subtree`, `jan-archive-subtree`, `jan-toggle-archive`, `jan-restore-archive`, `jan-visit-archive-origin` |
| Capture | `jan-capture`, `jan-capture-finalize`, `jan-capture-abort`, `jan-store-link` |
| Attachments | `jan-attach`, `jan-attachment-open`, `jan-attachment-reveal`, `jan-attachment-list`, `jan-attachment-rename`, `jan-attachment-delete`, `jan-attachment-synchronize` |
| Feeds | `jan-feed-refresh` |
| Agenda lifecycle | `jan-agenda`, `jan-agenda-refresh`, `jan-agenda-quit`, `jan-agenda-close`, `jan-planning-status` |
| Agenda movement | `jan-agenda-next-entry`, `jan-agenda-previous-entry`, `jan-agenda-next-date`, `jan-agenda-previous-date`, `jan-agenda-reveal-source`, `jan-agenda-calendar` |
| Agenda view | `jan-agenda-set-span`, `jan-agenda-toggle-follow`, `jan-agenda-filter`, `jan-agenda-change-presentation`, `jan-agenda-export` |
| Agenda editing | `jan-agenda-todo`, `jan-agenda-set-priority`, `jan-agenda-set-tags`, `jan-agenda-set-property`, `jan-agenda-schedule`, `jan-agenda-deadline`, `jan-agenda-set-effort`, `jan-agenda-clock-in`, `jan-agenda-clock-out`, `jan-agenda-refile`, `jan-agenda-archive`, `jan-agenda-capture`, `jan-agenda-delete`, `jan-agenda-apply-selection` |

Source-changing identities declare buffer, view, lifecycle, and text-mutation
effects. Read-only or handoff identities declare view and lifecycle effects.
All routes remain ordinary native commands with prohibited free-text arguments;
interactive argument collection belongs to the eventual application surface.

## Copied bridge ABI

`bridge.JAN_PLANNING_SCHEMA_VERSION` identifies the initial fixed-width ABI.
Records carry:

- exact operation, index, configuration, provider, source-set, document,
  source-revision, analysis, and baseline generations;
- one bounded command request and payload size;
- pointer-free semantic target references;
- immutable agenda result, source-health, and row presentation records;
- bulk committed, rejected, and unattempted counts;
- durable recovery and capability summaries; and
- attributable failures with limits and partial-outcome counts.

The bridge validator rejects unsupported schemas, stale or zero identities,
count mismatches, invalid enum values, out-of-range UTF-8 text, oversized
payloads, malformed targets, and derived-state overflow before adaptation.

## Navigation and source reveal

Agenda movement operates only within one immutable query result. First, last,
next, and previous movement is bounded at the result edges. Date movement uses
the row timestamp, schedule, or deadline and never invents a date for an
undated row.

Source reveal succeeds only for a document-backed row whose source is still
confirmed and whose semantic target revision equals the indexed document
revision. Provider-only diary, calendar, anniversary, reminder, and extension
rows have no fabricated document target.

## Checked remote editing

Remote agenda editing means preparing a change for the represented source
without activating its source view. The planner revalidates index,
configuration, provider, source, and target revisions, then returns a plan for
the canonical owner:

- task state, priority, tags, and properties route to task and metadata;
- schedule, deadline, effort, and clocks route to time workflows;
- refile and archive route to their recoverable owner;
- capture routes through ordinary capture; and
- delete routes through checked structured editing.

The planner never writes to cached agenda rows. A source commit invalidates the
old index through its generation and requires refresh before another edit.

## Bulk outcome policy

One explicit selection contains at most 4,096 targets. The entire set is
validated before any plan is published and retains stable selection order.

| Mode | Failure behavior |
| --- | --- |
| Atomic | A rejection before commit fails the set. An impossible observed partial commit becomes recovery-required evidence. |
| Recoverable | A rejection after a reported commit records recovery-required state and preserves every count. |
| Best effort | Targets commit independently in stable order; completion reports partial state when any target was rejected. |

Cancellation stops before the next target, preserves prior commits, and
reports the exact unattempted count. No mode silently rolls back a reported
commit.

## Refresh, providers, and export

Refresh requires an explicit command, configuration change, provider change,
or recovery reason. Merely opening a document is not a refresh reason. The
planner returns a rediscovery handoff containing the replaced index and exact
source-set, configuration, and provider generations; it does not contact a
provider.

Optional providers contribute typed diary, calendar, anniversary, reminder,
or extension rows under one nonzero provider generation and the ordinary
agenda entry limit. Failure remains isolated to that source.

Agenda export returns an immutable handoff containing format, index generation,
row count, completeness, and truncation. Text, HTML, calendar, and provider
formats are executed later by the Jan export owner.

## Capability and recovery inspection

Factory task, metadata, time, refile/archive, capture, and agenda capabilities
are available at domain closure. Attachment and feed state remains separately
reported by its adapter or configured provider generation. The global Jan
availability inventory replaces the six Planning and Agenda future-stage
records while retaining the eight Computable Documents and Output/Integration
records as unavailable future work.

Recovery inspection validates durable active-clock, refile-publication,
attachment-workflow, and agenda-bulk records. It reports valid, active,
completed, recovery-required, and malformed counts without resuming,
discarding, rolling back, or mutating any record.

## Current integration boundary

The domain packages, public identities, bridge records, deterministic fixtures,
and capability state are complete. `src/odra` does not dispatch these commands
yet; application composition, profile bindings, running-editor behavior, and
linked `.org`/`.jan` acceptance remain reserved for Slice 24.
