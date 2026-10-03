<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Capability Ledger

This ledger records complete Jan package behavior and linked editor acceptance
for baseline `jan-org-9.8.10-v1`. `.org` and `.jan` select the same
language identity, parser, provider, configuration, and document meaning.

## Status terms

| Status | Meaning |
| --- | --- |
| `factory-native` | The behavior has no optional external runtime. |
| `factory-adapter` | Odra owns the contract; an external tool can be unavailable. |
| `configured-provider` | A generation-checked provider supplies the behavior. |
| `package-complete` | The owning static package and focused acceptance are complete. |
| `linked-pending` | The package is complete, but linked editor composition and terminal acceptance remain pending. |
| `operational` | The current linked editor reports the capability available. |
| `unavailable` | The current build or configuration cannot perform the operation. |

Package completion does not imply that a development binary has linked the
command. Runtime status remains authoritative for that binary.

## Document language and structured editing

| Capability | Delivery | Runtime class | Contract |
| --- | --- | --- | --- |
| `.org` and `.jan` recognition | linked and accepted | `factory-native` | Both suffixes select identical Jan semantics. |
| Lossless parsing and analysis | linked and accepted | `factory-native` | Exact source bytes, revisions, recovery syntax, and indexes remain canonical. |
| Syntax presentation, inspection, and lint | linked and accepted | `factory-native` | Results match the current confirmed revision. |
| Visibility and structural editing | linked and accepted | `factory-native` | Folding is view-local; edits use checked transactions. |
| Lists, drawers, blocks, and tables | linked and accepted | `factory-native` | Structural edits preserve complete source regions. |
| Contextual authoring and presentation | linked and accepted | `factory-native` | Completion, templates, indentation, actions, and presentation preserve source. |

## Planning and agenda

| Capability family | Delivery | Runtime class |
| --- | --- | --- |
| Tasks, tags, properties, columns | linked and accepted | `factory-native`, operational |
| Timestamps, schedules, clocks, effort, timers | linked and accepted | `factory-native`, operational |
| Refile, copy, archive, and restore | linked and accepted | `factory-native` plus checked Resource effects |
| Capture, attachments, and feeds | linked and accepted | native workflow; optional providers can be unavailable |
| Agenda indexes, queries, views, and checked edits | linked and accepted | native workflow; optional providers can be unavailable |

## Computable documents

| Capability family | Delivery | Runtime class |
| --- | --- | --- |
| Table formulas, recalculation, inspection, and text plots | linked and accepted | `factory-native`, operational |
| Gnuplot handoff | linked and accepted | `factory-adapter`, unavailable without the tool |
| Explicit source execution and calls | linked and accepted | unavailable until an admitted adapter is selected |
| Typed results, sessions, and caches | linked and accepted | `factory-native` coordination |
| Focused source editing, noweb, tangling, and libraries | linked and accepted | native coordination plus checked Resource effects |
| Deterministic batch execution | linked and accepted | unavailable until an admitted adapter is selected |

## Output, publishing, and integration

| Capability family | Delivery | Runtime class |
| --- | --- | --- |
| Plain text, HTML, Markdown, normalized Jan/Org | linked and accepted | `factory-native`, operational |
| LaTeX, PDF, Beamer, ODT, Texinfo, Info, man, iCalendar | linked and accepted | `factory-adapter`, unavailable without the tool |
| Citations and bibliographies | linked and accepted | native resolution; optional processors can be unavailable |
| Deterministic local and remote publishing | linked and accepted | unavailable until a configured provider is admitted |
| Links, media, and external protocol requests | linked and accepted | unavailable until a configured provider is admitted |
| Encryption and mobile synchronization | linked and accepted | unavailable until a configured provider and credential handle are admitted |
| Programmable extension contributions | linked and accepted | unavailable until an extension generation is configured |

## Linked application boundary

The static domain packages, copied bridge records, command catalog, Direct and
Modal bindings, terminal surfaces, contextual help, teardown, and inspection
are composed in the linked editor. One bounded `.org` and `.jan` PTY acceptance
proves planning, agenda, computation inspection, native export, provider
unavailability, failure isolation, undo, redo, save, and clean exit.

Runtime inspection remains authoritative for optional adapters and configured
providers. Unavailability preserves source and does not narrow the accepted
factory-native product boundary.

## Failure contract

Malformed, stale, unavailable, unauthorized, conflicting, over-limit,
cancelled, timed-out, allocation-failed, provider-invalid, and incomplete work
preserves canonical source and the last confirmed generation. External effects
can have explicit partial states; their manifests remain recoverable and are
never rewritten as complete success.

See the [Jan Product Surface Reference](../jan-product-surface/index.md) for
commands, configuration, backends, providers, limits, and extensions.
