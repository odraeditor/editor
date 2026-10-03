<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Export and Publish

This chapter exports one document through a native backend, inspects an
optional backend, and prepares one deterministic publication.

## Before You Begin

Prepare the supplied exercises through
[Prepare the User Guide Exercises](../getting-started/prepare-exercises.md).
Open
`~/odra-guide/work/projects/forecast-engine/notes/jan-workflows/publishing/site.org`.
Use the Jan availability inspection before continuing. Native text, HTML,
Markdown, and normalized Jan/Org output require no external converter.

## Export with a Native Backend

Run `M-x jan-export`. Choose HTML and a preview or checked resource
destination. Review the scope, settings, includes, macros, filters, backend,
destination, and limits. Accept the plan and inspect the output.

Repeat with Markdown or plain text. Use `M-x jan-export-region` only after
selecting a region. Export changes copied normalized content; it does not save,
rewrite, execute, follow links, or publish the source document.

## Inspect Optional Backends

LaTeX, PDF, Beamer, ODT, Texinfo, Info, man-page, and iCalendar workflows can
require a configured tool adapter. Select one through the export dispatcher.
When its executable or provider is unavailable, Jan reports that exact state
before creating a process handoff. Continue with a native backend; do not
install or invoke a tool implicitly.

Citations use `jan-citation-insert`, `jan-citation-follow`, and
`jan-bibliography-insert`. The supplied bibliography is inert data. Processor
selection, resource revisions, key resolution, and output context are checked
before a citation result is accepted.

## Publish a Project

Run `M-x jan-publish-project` for the supplied project. Review its root,
discovery rules, components, destination, manifest, provider generation, and
overwrite policy. A local publication and a remote upload are separate
outcomes. The first successful local build does not prove remote delivery.

Use `jan-publish` for one configured target and `jan-publish-all` only after
reviewing the complete target count. A later run can reuse output only when
the semantic digest, backend, configuration, and dependencies match. Partial
remote delivery enters recovery or reconciliation; it is not reported as a
complete publication.

## Verify the Result

You have completed this chapter when a native export produces deterministic
output, one optional missing tool reports unavailable without changing source,
and publication exposes a complete manifest with separate local and remote
states.

See the [Jan Product Surface Reference](../../../reference/jan-product-surface/index.md)
for backend, provider, publication, and resource-limit details.

---

[Previous: Compute in Documents](compute-in-documents.md) ·
[Structured Documents](index.md) ·
[Next: Connect and Extend Jan](connect-and-extend.md)
