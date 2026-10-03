<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Citations and Bibliographies Reference

Jan citation processing separates source recognition, bibliography resource
admission, key resolution, rendering, completion, and output publication. The
`jan_output` package operates on copied values and caller-owned storage. It
does not edit citation source, read files implicitly, install a processor, or
publish an output resource.

## Processors

The factory adapter inventory recognizes two processor families:

- CSL-compatible processing through `citeproc`; and
- LaTeX-oriented processing through `latex-citations`.

A selected processor descriptor includes its stable identity, version,
provider generation, kind, state, and trust decision. Resolution requires one
matching descriptor with the exact requested generation. Missing, duplicate,
stale, unavailable, quarantined, or untrusted processors reject before key
resolution. CSL and LaTeX availability are inspected independently.

## Bibliography sources and entries

Each bibliography source records an admitted Resource identity, exact
revision, format, and digest. Supported source representations are CSL JSON
and BibTeX. The source set rejects zero identities or revisions, empty
digests, unknown formats, and duplicate Resource identities.

Normalized entries record a stable key, author, title, optional container,
year, optional URL, and source index. Every entry must refer to one admitted
source. Duplicate keys reject the whole source set because resolution would be
ambiguous. Invalid entries remain attributable bibliography failures; they do
not remove or rewrite citation syntax.

One operation admits at most 1,024 bibliography resources, 4,096 normalized
entries, and 4,096 citation references. Lower confirmed output limits still
apply.

## Resolution and diagnostics

`resolve_citations` receives one explicit operation, exact Jan output scope,
processor identity and generation, rendering backend, style identity and
optional style Resource revision, source and reference digests, bibliography
sources, entries, and references.

Every reference records its key, variant, optional prefix, suffix, locator, and
source range. Resolution produces a stable reference-to-entry index only when
all keys resolve uniquely. A missing key returns an attributable diagnostic
with its original range. Duplicate keys, invalid entries, malformed ranges,
and unavailable processors return distinct failure codes.

The resolver never changes a citation, inserts a placeholder, chooses another
processor, or silently omits a failed reference.

## Cache identity

A citation cache key binds:

- exact processor generation;
- style identity and optional Resource revision;
- backend context;
- complete bibliography-source digest; and
- complete citation-reference digest.

Reuse requires full key equality. A source revision, style, processor,
backend, or reference change invalidates the retained result. Timestamp-only
reuse is not valid.

## Citation rendering

Supported variants are parenthetical, narrative, suppress-author, and
author-only. Rendering applies global and per-reference affixes, locators,
locale selection, style identity, optional links, and backend context.

CSL-compatible output supports plain text, HTML, Markdown, and LaTeX-safe text
contexts. HTML escapes text and attributes independently before adding an
admitted entry URL. Markdown escapes structural inline characters. A
LaTeX-oriented processor emits `cite`, `textcite`, `citeauthor`, or `citeyear`
commands and escapes keys and locators. A LaTeX processor rejects a non-LaTeX
backend context.

Rendering writes only into bounded caller-owned storage and returns a result
only when the complete citation sequence fits.

## Bibliography planning and rendering

A bibliography request selects one placement:

- document end;
- an explicit bibliography directive; or
- a selected section.

It can filter by key prefix, author substring, and inclusive year range.
Deterministic sort modes cover citation order, key, author, year, and title,
with stable key tie-breaking. The plan returns caller-owned selected entry
indices before any rendering or destination effect.

Plain-text, HTML, Markdown, and LaTeX bibliography renderers use the same
normalized entries and selected order. Style and locale remain explicit
request values. Optional links are included only when requested and present in
the admitted entry.

## Completion handoff

`complete_citation_keys` filters normalized entries by key prefix, sorts them
by key, and returns the title plus exact source Resource identity and revision.
It performs no file read and gives the completion UI no parser or provider
objects.

## Failure and preservation

Malformed sources, duplicate entries, missing keys, stale resolution indices,
unavailable dependencies, invalid processor/backend combinations, and output
limits fail atomically. Canonical `.org` and `.jan` source remains unchanged.
No invalid provider result reaches an output destination or cache.

## Focused validation

Use:

```sh
make jan-output-focused-test
```

The target checks CSL and LaTeX adapter models, exact source admission, key
resolution, cache identity, variants, affixes, locale and backend context,
bibliography filtering and sorting, completion, failures, resource bounds,
and deterministic offline goldens. It does not invoke a citation executable,
read a network bibliography, build `src/odra`, or run the full repository
gate.
