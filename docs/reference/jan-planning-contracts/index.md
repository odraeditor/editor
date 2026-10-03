<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Planning Contracts Reference

Jan Planning is the static Stage 3 domain over exact Jan Document Language
analysis. `src/jan_planning` defines copied planning identities, bounded
requests and results, checked configuration generations, capability lifecycle,
and the durable active-clock schema without registering application commands.

## Package boundary

`src/jan_planning` consumes `language.Jan_Analysis_Scope`, copied source ranges,
and configuration values. It does not parse source, retain syntax-tree
pointers, own canonical document bytes, publish transactions, execute resource
operations, or import `src/odra`.

Task and metadata behavior is defined by the
[Jan Tasks and Metadata Reference](../jan-tasks-and-metadata/index.md), and time
behavior by the [Jan Time Workflows Reference](../jan-time-workflows/index.md).
[Jan Refile and Archive](../jan-refile-and-archive/index.md) defines checked
subtree movement, recoverable publication, and archive origin data. Later
[Jan Capture and Intake](../jan-capture-and-intake/index.md) defines bounded
capture sessions, public-owner attachment effects, recoverable link
publication, and explicit feed refresh. [Jan Agenda Queries](../jan-agenda-queries/index.md)
defines source-health-preserving indexes, complete query families, bounded
presentation, and exact cache invalidation. [Jan Planning and Agenda Operations](../jan-planning-and-agenda-operations/index.md)
defines the public commands, copied bridge records, agenda interaction,
checked remote edits, and final domain availability. Slice 24 alone composes and
exercises the linked editor.

## Exact identities

Every planning request carries:

- one nonzero operation identity;
- an exact Jan analysis scope and canonical source byte length;
- confirmed planning and provider generations;
- one confirmed source-set identity;
- copied semantic targets whose source scope matches the request; and
- explicit limits no greater than the stable resource ceilings.

A path or heading label is never sufficient identity. Resource definitions
retain a provider identity and bounded resource key, while source mutation must
re-resolve an exact semantic target.

## Lifecycle and availability

The package distinguishes prepared, confirmed, active, completed, cancelled,
failed, recovery-required, and closed lifecycle states. Failures identify the
operation, contract field, resource limit, actual count, and any attributable
committed or unattempted outcomes.

The complete Planning and Agenda capability inventory covers tasks, metadata,
time, refile and archive, capture, attachments, feeds, and agenda. The final
domain inventory reports factory-native families as available and preserves
separate factory-adapter or configured-provider availability for attachments
and feeds. Availability never grants filesystem, network, process, credential,
or publication authority.

## Checked configuration

Racket may contribute workflow, source-set, capture, and agenda definitions.
The Racket admission model validates one complete bounded generation before it
crosses a native boundary. `jan_planning.planning_configuration_publish` then
validates and copies the complete candidate into an immutable native
generation.

One rejected, stale, conflicting, over-limit, or allocation-failed candidate
leaves the prior confirmed generation active. Confirmed accessors borrow values
only until replacement or close.

Configured values include:

- ordered workflows with unique unfinished and finished states, semantic
  presentation roles, optional fast keys, and logging instructions;
- ordered file, directory, Project, Workspace, or provider source sets with
  explicit discovery depth and document limits;
- capture keys, labels, entry kinds, targets, templates, and immediate-finish
  policy; and
- agenda keys, labels, queries, spans, and result limits.

No configured value grants filesystem, process, network, credential, or
publication authority.

## Active-clock persistence schema

`Active_Clock_Record` is versioned and records one clock domain, provider-owned
resource identity, exact semantic target, UTC start instant, interpretation
time zone, source revision, last transition, and recovery state.

Startup returns the record as active only when its exact source scope still
matches. A stale scope becomes `Recovery_Required`; a resolved record remains
resolved. An incompatible or malformed schema is invalid and must be
quarantined by the persistence owner. Startup never silently resumes, discards,
or invents elapsed activity.

## Resource limits

| Resource | Limit |
| --- | ---: |
| Semantic targets per operation | 4,096 |
| Source documents | 1,024 |
| Agenda entries | 65,536 |
| Capture candidates | 16,384 |
| Refile candidates | 16,384 |
| Attachment outcomes | 4,096 |
| Feed sources | 256 |
| Feed entries | 16,384 |
| Copied agenda or capture text | 16 MiB |
| Process-wide derived agenda and feed state | 64 MiB |
| Entries between cancellation checks | 4,096 |

Planning configuration additionally bounds workflows, workflow states, source
sets, sources, capture definitions, agenda definitions, individual text
fields, and total copied configuration bytes.

## Focused validation

Use:

```sh
make jan-planning-focused-test
```

The target runs the implementation-independent Racket workflow, time, refile,
archive, capture, attachment, feed, agenda, multi-resource, recovery,
configuration, and resource models, followed by strict unoptimized
`src/jan_planning` package tests. Disabling
optimization avoids an LLVM module-pass cost in the inner test loop without
changing source checks or runtime assertions; linked optimized behavior remains
part of the final product closure. The target does not import or build
`src/odra`.
