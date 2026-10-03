<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Tool Output Backends Reference

Jan tool output backends separate deterministic source generation from optional
external-tool execution. The `jan_output` package creates bounded source bytes
and complete process plans. It does not start a process, write a canonical
resource, or publish an artifact.

## Backend inventory

| Backend | Source owned by Odra | Optional tool | Final artifact |
| --- | --- | --- | --- |
| Beamer | LaTeX presentation | `pdflatex` | PDF presentation |
| LaTeX | LaTeX document | `pdflatex` | PDF document |
| PDF | LaTeX source from the selected document backend | `pdflatex` | validated PDF |
| ODT | checked package description | `odra-odt-packager` | validated ODT archive |
| Texinfo | Texinfo document | `makeinfo` | Info document |
| Info | Texinfo source | `makeinfo` | Info document |
| man page | roff document | optional `groff` validation | man-page source |
| iCalendar | RFC 5545 text | optional `icalendar-validator` | calendar text |

Source availability and final-artifact availability are independent. LaTeX,
Beamer, Texinfo, man-page, and iCalendar source remains available when an
optional executable is absent. Inspection reports this distinction for every
stable backend identity.

## Exact tool selection

`prepare_tool_backend_plan` accepts one explicit request, one provider
generation, and copied tool descriptors. A descriptor must have the required
identity, the exact requested generation, an available state, and trusted
configuration. Missing, duplicate, stale, unavailable, quarantined, or
untrusted descriptors reject the complete plan. The adapter does not search
`PATH`, substitute a different executable, or use a later generation.

Every step records its order, tool index, input and output resource identities,
timeout, maximum output bytes, and cleanup requirement. A PDF plan performs two
ordered compile passes. Requested output validation is a separate final step.
The process owner remains responsible for execution, cancellation, limits,
diagnostics, and termination.

## Temporary resources and cleanup

A complete plan allocates one temporary directory, bounded intermediate
artifacts, and one log obligation. Temporary identities are derived before
handoff. `tool_backend_cleanup_complete` accepts completion only when every
created temporary resource was cleaned. A process failure, validation failure,
or cancellation does not transfer ownership of these resources to the editor.

## LaTeX and Beamer source

The source renderers map normalized headings, paragraphs, list items,
quotations, source and example blocks, rules, links, images, emphasis, strong
text, code, and math. LaTeX control characters are escaped in text and target
contexts. Beamer headings open fragile frames so source blocks remain valid.

Source blocks reject an embedded `\\end{verbatim}` terminator. Raw fragments
remain unsupported. The renderer returns a complete caller-owned byte count or
an attributable unsupported or limit failure; it never returns partial output
as a successful result.

## OpenDocument Text handoff

`Odt_Package_Request` binds the style resource and revision, optional template
resource and revision, media, math, link, and content counts, and converter
requirement. A template identity and revision must be present together. Counts
and content bytes must remain within the confirmed output limits.

The ODT packager receives only a validated description and admitted resources.
Styles, templates, media, math inputs, links, conversion, and output validation
therefore remain explicit inputs to the bounded adapter workflow. A third-party
template or converter does not gain filesystem or publication authority from
its presence in the request.

## Texinfo, Info, and man pages

Texinfo source includes a deterministic header, top node, section mapping,
inline markup, links, images, quotations, lists, examples, and final `@bye`.
Texinfo control characters are escaped, including inside example blocks. Info
production is a checked `makeinfo` plan.

The man-page renderer emits deterministic roff. It escapes backslashes and
neutralizes a leading dot or apostrophe on every content line so document text
cannot become a roff request. Raw fragments reject.

## iCalendar

The iCalendar renderer produces CRLF-delimited `VCALENDAR` data with `VEVENT`
or `VTODO` components. Events require a non-empty UID and summary plus a UTC
timestamp in `YYYYMMDDTHHMMSSZ` form. Completed state is valid only for a task.
Text escapes backslashes, commas, semicolons, and line breaks. Descriptions,
locations, categories, end times, completion, and private visibility are
optional copied fields.

Calendar rendering does not read an agenda source, infer authority, contact a
calendar service, or publish an event. Higher-level selection, alarms, time
zones, refresh hints, and Resource publication remain inputs and effects owned
by their later composition boundaries.

## Failure behavior

Malformed requests, invalid normalized input, unavailable tools, stale
generations, duplicate descriptors, unsupported forms, insufficient caller
storage, and exceeded limits fail before an executable handoff or publication.
Failure preserves source and confirmed resources. One failed backend does not
disable unrelated source renderers or backend capabilities.

## Focused validation

Use:

```sh
make jan-output-focused-test
```

The target checks deterministic LaTeX, Beamer, Texinfo, man-page, and
iCalendar goldens; exact tool plans; unavailable states; ODT request bounds;
temporary cleanup; source escaping; and strict `src/jan_output` package tests.
It does not invoke an external converter, build `src/odra`, publish a resource,
or run the full repository gate.
