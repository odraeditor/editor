<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Product Surface Reference

This reference is the entry point for Jan commands, configuration, capability
state, backends, providers, resource limits, and extensions. Detailed contracts
remain in the linked subsystem references.

## Command discovery

All public operations use the `jan-` prefix and are discoverable through
`M-x`. Direct and Modal profiles resolve the same command identities. A command
can be present in the accepted product surface while unavailable in a specific
development build or configuration. Inspect the owning status before acting.

| Domain | Status command | Principal commands |
| --- | --- | --- |
| Language | `jan-language-status` | `jan-inspect-syntax`, `jan-lint`, `jan-lint-refresh` |
| Structured editing | `jan-inspect-availability` | `jan-cycle`, `jan-global-cycle`, `jan-toggle-drawer`, structural, list, table, presentation, completion, and context commands |
| Planning | `jan-planning-status` | `jan-todo`, metadata, time, refile, capture, attachment, feed, and `jan-agenda*` commands |
| Computation | `jan-computation-status` | `jan-table-recalculate`, `jan-execute`, result, session, cache, source, tangle, and batch commands |
| Output | provider and extension inspection through `M-x` | `jan-export`, backend-specific exports, `jan-export-region`, citation, publishing, protocol, protection, synchronization, help, and dynamic-block commands |

The complete planning catalog is in
[Jan Planning and Agenda Operations Reference](../jan-planning-and-agenda-operations/index.md).
The complete computation catalog is in
[Jan Computation Operations Reference](../jan-computation-operations/index.md).
The output command vocabulary is defined by the
[Jan Output, Publishing, and Integration specification](../../../ops/default/spec/stable/jan-export-publishing-and-integration.md).

## Configuration and precedence

Jan configuration is copied and generation checked. Document values request
behavior; they do not grant external authority.

- Document analysis and structured editing use the bounded configuration in
  the [Jan Document Language Analysis Reference](../jan-document-language-analysis/index.md)
  and [Jan Structured Editing Commands and Configuration](../jan-structured-editing-commands/index.md).
- Planning uses workflow, source-set, capture, agenda, provider, and persistent
  clock generations from the
  [Jan Planning Contracts Reference](../jan-planning-contracts/index.md).
- Computation uses adapter, execution-policy, session, cache, library, and
  resource generations from the
  [Jan Computation Contracts Reference](../jan-computation-contracts/index.md).
- Output scalar settings resolve from factory, user configuration, Workspace,
  Project, document, ancestor subtree, selected subtree, and explicit
  invocation. Backend-specific settings beat general settings only at the same
  scope. See [Jan Output Contracts Reference](../jan-output-contracts/index.md).

## Backend inventory

| Class | Backends | Availability |
| --- | --- | --- |
| Native | plain text, HTML, Markdown, normalized Jan/Org | no external converter |
| Tool adapter | LaTeX, PDF, Beamer, ODT, Texinfo, Info, man page, iCalendar | explicit tool and provider state |
| Processor | CSL and LaTeX citation processing | exact processor and bibliography state |
| Publication | local and remote project targets | exact project and provider generations |

Native behavior is specified in
[Jan Native Output Backends Reference](../jan-native-output-backends/index.md).
Optional plans and cleanup are specified in
[Jan Tool Output Backends Reference](../jan-tool-output-backends/index.md).

## Provider classes and authority

Optional providers can contribute agenda rows, capture values, execution,
links, media, citation processors, output backends and filters, publishing,
encryption, synchronization, and extension families. Each invocation binds an
exact provider generation, requested capability, declared authority subset,
resource limits, and result boundary.

Registration, selection, and availability are distinct. None grants
filesystem, process, network, credential, clipboard, document-mutation, or
publication authority. See
[Why Jan Keeps Authority Outside Providers](../../explanation/jan-authority-and-provider-boundaries/index.md).

## Resource ceilings

Providers can reduce these ceilings but cannot enlarge them.

| Domain | Principal factory ceilings |
| --- | --- |
| Planning | 4,096 semantic targets; 1,024 sources; 65,536 agenda entries; 16,384 capture candidates; 4,096 attachment outcomes; 256 feeds; 16,384 feed entries; 16 MiB copied text; 64 MiB derived state |
| Computation | 65,536 cells; 16,384 formula dependencies; graph depth 1,024; 4,096 execution targets; 64 sessions; 32 child processes per operation; 64 MiB output per target; 256 MiB retained output; 4,096 files; 16,384 result rows; 256 MiB cache |
| Output | 1,024 includes; include depth 128; 4,096 macro expansions; 1,048,576 normalized nodes; 256 MiB output; 65,536 diagnostics; 65,536 manifest entries; 16,384 links; 4,096 publication targets; 128 active provider operations; 512 MiB cache; 1 MiB protocol payload |

Elapsed-time and RSS budgets are mandatory request inputs. A limit failure
reports its scope and observed usage without publishing partial success.

## Extension families

One atomic extension generation can contribute lifecycle hooks, packages,
properties, mapping, agenda sources, searches and views, capture templates and
values, custom links, exporters, derived backends, filters, citation
processors, table translators, dynamic blocks, execution adapters, publishing
providers, and synchronization providers.

Extension results are copied candidates. The editor, transaction, Resource,
process, credential, and provider owners retain canonical state and effects.
See [Jan Extension Surface Reference](../jan-extension-surface/index.md).

## Capability state and recovery

Use the [Jan Capability Ledger](../jan-stage-1-capabilities/index.md) to
distinguish package-complete behavior from linked application acceptance.
Malformed, stale, unavailable, unauthorized, limited, cancelled, conflicting,
and provider-invalid states preserve source. Publication and synchronization
manifests retain attributable partial outcomes for explicit recovery.
