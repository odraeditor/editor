<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Feedback and Progress Reference

Odra publishes command outcomes, warnings, failures, and long-running work as
semantic feedback. Producers describe the event. Routing policy chooses a
destination that the active frontend can present.

## Producer Channels

The editor adapter maintains one current generation for each producer family:

| Channel | Typical events |
| --- | --- |
| Command | ordinary command acknowledgement or rejection |
| Save | file and Project save outcomes |
| Recovery | unsaved-work recovery outcomes |
| Language service | lifecycle, restart, and interaction outcomes |
| Project | discovery, promotion, navigation, and catalog outcomes |
| Package | catalog and installed-package outcomes |
| Long operation | measured work, completion, cancellation, or failure |

A newer publication from one channel replaces that channel's active
generation. It does not replace records owned by another channel.

## Semantic Records

A notification records class, severity, attention, lifecycle, retention,
visibility, source identity, public text, optional diagnostic metadata, and
optional actions. A progress record also includes state, measurement kind,
current and total units, and phase.

Public text is written for the editor user. Implementation values such as enum
names, transport failures, and internal owner codes belong in the
`diagnostic-detail` metadata field. Compact status presentation uses only the
public text.

Record and source identities are generation checked. Content, metadata, and
actions are copied into bounded registry storage. A producer cannot publish an
unbounded string or retain caller-owned memory.

## Factory Routing

The maintained route table defines these logical destinations:

| Destination | Purpose | Fallback |
| --- | --- | --- |
| Status | compact root-edge acknowledgement and progress | none |
| Floating | transient warning, error, and completion | Status |
| History | retained outcomes and actions | Status |
| Diagnostic | attention-level and error detail | Status |

Routing evaluates protected safety rules before factory and extension rules.
Attention-level and error records always retain an inspectable route. A
frontend that cannot provide overlap, history, or diagnostic presentation uses
the bounded fallback chain. The terminal editor adapter currently advertises
the Status destination, so unsupported destinations appear there as compact
feedback.

The factory table is one complete immutable generation. A replacement must
pass route, destination, projection, fallback, and safety validation before it
becomes current. Rejection preserves the last valid generation. Personal route
configuration is not currently exposed through `init.rkt`.

## History and Dismissal

Active presentation and retained history are separate. Dismissing an active
record removes its current presentation but does not imply cancellation or
clear unrelated provider diagnostics. Retained records live in bounded memory
and follow deterministic eviction policy. Feedback history is not persisted
across editor restarts.

Completed and failed long operations retain a terminal outcome. A successful
or cancelled operation stops being live; a failed operation remains available
for attention and inspection.

## Actions

The initial action vocabulary is Inspect, Retry, Cancel, Open Source, and Show
Log. Each action contains a bounded ID, a registered command name, optional
copied argument text, and sensitivity policy. Cancel is marked separately so
the operation owner can distinguish a cancellation request from navigation or
inspection.

Before returning command authority, the editor revalidates the exact record
identity and generation, source identity and generation, action ID, and current
command registration. Stale or replaced feedback cannot authorize an action.
The source workflow remains responsible for the operation and its
operation-specific checks.

## Recovery Behavior

- A rejected publication leaves the prior admitted feedback generation active.
- A rejected routing configuration leaves the prior complete route generation
  active.
- Missing frontend capabilities select a declared fallback; they do not change
  semantic identity or source state.
- Closing the editor releases presentation state, routing state, active
  records, retained history, and copied action storage.
- Dismissing progress does not cancel work. Cancellation requires its checked
  action.

## Bounds

The semantic registry bounds active records, history records, retained bytes,
inspection results, updates per record, metadata, actions, and content. Routing
bounds routes, destinations, projections, fallback depth, projected content,
and visible presentation capacity. Exact constants are declared in
`src/feedback/contracts.odin` and `src/feedback_routing/contracts.odin`.

For the ownership rationale, see
[Why Feedback Separates Meaning from Presentation](../../explanation/feedback-ownership/index.md).
