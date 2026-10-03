<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Language Catalog Reference

The `language` package owns a bounded, provider-independent catalog of
semantic document languages. The catalog recognizes a document language before
syntax providers or language services are selected, so a confirmed identity
does not imply that a parser or server exists.

## Ownership and Publication

`Language_Catalog` owns one immutable confirmed snapshot. Initialization
allocates the catalog owner, and `language_catalog_confirm` validates a complete
candidate in separately allocated storage before publishing it. A stale,
invalid, conflicting, excessive, or allocation-failed candidate leaves the
previous generation unchanged and records one copied rejection. Closing the
catalog releases its owner exactly once.

`Language_Catalog_ID` identifies the owner,
`Language_Catalog_Generation` identifies its exact immutable snapshot, and
`Language_Source_Generation` identifies the contribution revision. Zero
identities and generations are invalid. Previously confirmed language names
retain their IDs across generations, and canonical sorting makes new ID
assignment independent from candidate order.

## Definitions and Sources

Each `Language_Definition_Candidate` supplies:

- an optional factory-assigned numeric ID;
- a lowercase semantic identity and copied display name;
- one contribution source, scope, and source generation;
- bounded exact filenames and filename suffixes; and
- copied provenance.

Only factory definitions may pin numeric IDs. Project definitions require an
exact project scope. The deterministic source precedence is:

1. Project;
2. personal configuration;
3. package contribution; and
4. factory data.

Definitions with the same identity may occur at different source levels and
retain one semantic language ID. Duplicate identities or selectors within the
same source and scope reject the candidate. Equal-precedence selectors for
different identities are ambiguous and also reject the complete candidate.

## Resolution

`language_catalog_resolve` accepts a path, an optional explicit language
identity, and an optional Project scope. Matching is case-sensitive.

An explicit identity bypasses filename matching and selects the highest
applicable source for that confirmed identity. Path resolution first applies
source precedence. Within the winning source and scope, an exact basename is
more specific than a suffix, and the longest matching suffix wins. The copied
association records the selected catalog generation, semantic identity,
selector kind and value, contribution provenance coordinates, and number of
shadowed matches.

The factory snapshot currently contains:

| Identity | ID | Exact filenames | Suffixes | Syntax provider |
| --- | ---: | --- | --- | --- |
| `odin` | 1 | none | `.odin` | maintained Tree-sitter Odin |
| `jan` | 2 | none | `.org`, `.jan` | maintained Tree-sitter Jan |
| `racket` | 3 | none | `.rkt` | maintained Tree-sitter Racket |
| `go` | 4 | none | `.go` | maintained Tree-sitter Go |

`info.rkt`, `go.work`, and `go.mod` are language-service root markers rather
than document-language selectors. Racket syntax targets the default readtable;
unsupported custom-reader lexical forms remain editable and may degrade to
ordinary text roles. Racket and Go recognition and local syntax do not depend
on an external language-server executable.

## Limits

| Resource | Limit |
| --- | ---: |
| Confirmed language definitions | 32 |
| Selectors per definition | 16 |
| Exact filenames per definition | 8 |
| Suffixes per definition | 8 |
| Selectors per catalog | 512 |
| Semantic identity bytes | 64 |
| Display-name bytes | 96 |
| Scope bytes | 256 |
| Selector bytes | 32 |
| Provenance bytes | 256 |

The independent resource study exercises ordinary, demanding, and boundary
profiles against these limits. A one-selector overflow is rejected.

## Inspection and Failures

`language_catalog_inspect` returns a complete pointer-free copy containing the
catalog identity and generation, definition and selector counts, all confirmed
bounded descriptors, and the latest rejected candidate. Associations and
failures also retain no candidate storage.

Failures distinguish invalid or stale generations, limits, invalid fields,
duplicate identities and selectors, ambiguous selectors, unknown explicit
identities, no path match, generation exhaustion, and allocation failure. No
rejection partially publishes a candidate.

Run `make language-catalog-test` for the independent model, resource profiles,
native model-equivalence cases, conflict and ambiguity handling,
order-independent identity assignment, allocation-fault preservation, and
zero-byte teardown checks.
