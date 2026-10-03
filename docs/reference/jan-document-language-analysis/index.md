<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Document Language Analysis Reference

Jan Document Language Stage 1 defines the native, revision-bound contract used
to recognize and preserve the accepted `jan-org-9.8.10-v1` syntax baseline.
This reference describes the Stage 1 contract and parser boundary. Structural
classification is implemented by Slice 2, inline classification and semantic
indexes by Slice 3, and `.org` and `.jan` application selection begins in
Slice 5.

## Responsibility Map

| Owner | Responsibility |
| --- | --- |
| `editor` | Canonical UTF-8 bytes, immutable snapshots, buffer identity, revisions, point, selection, and editable text. |
| `document` | External decoding, document identity, file association, save, and publication. |
| `transaction` | Normalized splices, atomic text publication, observation, history, undo, redo, and conflicts. |
| `language` | Jan identities, parser ownership, copied analysis records, source ranges, typed nodes and attributes, indexes, recovery, limits, failures, and cleanup. |
| Tree-sitter Jan | Incremental concrete parsing inside the `language` foreign boundary. |
| `ui` and `terminal` | Semantic presentation after exact-revision validation. |

Jan receives canonical UTF-8 after document decoding. It never owns raw file
encoding, canonical text, save publication, or frontend styling.

## Baseline Identity

`jan_factory_baseline` returns the immutable factory baseline:

| Field | Value |
| --- | --- |
| Baseline | `jan-org-9.8.10-v1` |
| Syntax reference | `Org Syntax v2` |
| Specification commit | `a0d1feaa414a0236f4fafc035cb890109d76c00a` |
| Baseline generation | `1` |

`Jan_Baseline_Identity` copies all three textual identities under fixed limits.
`jan_baseline_identity_is_valid` accepts only the exact baseline and a nonzero
generation. Baseline advancement therefore requires an explicit contract
change rather than a parser-only replacement.

## Analysis Scope

`Jan_Analysis_Scope` binds every derived result to:

1. exact buffer and optional document identity;
2. canonical source revision;
3. language identity and provider generation;
4. buffer language-selection generation;
5. parser and Jan grammar generations;
6. confirmed configuration generation and digest;
7. baseline identity; and
8. Jan analysis generation.

Zero generations, a provider for another language, a missing configuration
digest, or inconsistent document presence reject the complete scope. A copied
result from one scope cannot authorize inspection, lint, indexing, or rewrite
against another.

## Source Records

`Jan_Source_Range` is a half-open canonical UTF-8 byte range within one exact
analysis scope. Empty ranges are permitted for syntactic boundaries; node and
operation contracts decide when content must be non-empty.

`Jan_Node_Record` copies node identity, parent identity, structural or inline
layer, public kind, bounded kind label, structural and inline depth, exact
range, and attribute count. The closed `Jan_Node_Kind` vocabulary contains the
72 accepted structural and inline source-form families plus
`Preserved_Whitespace` and `Recovery`.

`Jan_Attribute_Record` copies one typed lexical field and its raw range.
Attribute interpretations distinguish raw, text, Boolean, integer, range,
timestamp part, compatible regular expression, and availability values.

`Jan_Recovery_Record` gives malformed, unterminated, context-invalid,
ambiguous, or limited source an explicit deterministic owner. Recovery does not
permit the parser to discard or normalize bytes.

`Jan_Index_Fact` identifies a node and range within one of the complete Stage 1
source-fact indexes. It contains no filesystem, network, process, bibliography,
agenda, export, or execution result.

All public records are copied and pointer-free. Tree-sitter nodes, cursors,
borrowed strings, parse tables, and parser pointers remain inside the language
owner.

## Rewrite Boundary

`Jan_Rewrite_Plan_Descriptor` identifies one exact-generation proposal and its
aggregate splice, replacement, and metadata usage. `Jan_Rewrite_Edit` addresses
replacement text through offsets into a separately owned bounded arena rather
than retaining borrowed text.

Slice 4 implements exact node ownership, UTF-8-aware minimalization, overlap,
stale-generation, ambiguity, size, splice-count, and transaction-admission
checks. The plan owns its replacement arena and exposes an ordinary
`transaction.Base_Splice` adapter. No Stage 2 or Stage 3 structured command is
published by this contract layer.

## Availability

`Jan_Availability_Record` gives a stable capability name one availability
class and specification owner. Stage 1 factory-native behavior belongs to
`Document_Language`. A `Future_Stage` record must be unavailable, name a later
stage, and contain bounded explanatory detail.

The later owners are:

1. `Structured_Editing`;
2. `Planning_And_Agenda`;
3. `Computable_Documents`; and
4. `Export_Publishing_And_Integration`.

Recognized syntax is not a parse error merely because its operation belongs to
a later stage.

## Selected Limits

| Resource | Limit |
| --- | ---: |
| Canonical source per analysis | 64 MiB |
| Aggregate retained analysis | 512 MiB |
| Temporary analysis storage | 128 MiB |
| Typed nodes | 1,048,576 |
| Structural depth | 1,024 |
| Inline recursion depth | 256 |
| Attributes per node | 128 |
| Index facts | 1,048,576 |
| Diagnostics | 4,096 |
| Text per diagnostic | 4 KiB |
| Incremental edits per update | 16,384 |
| Copied inspection | 1 MiB |
| Rewrite splices | 16,384 |
| Rewrite replacement and metadata | 16 MiB |
| Parser cancellation interval | 64 KiB |
| Initial work per maintenance step | 8 MiB |
| Incremental work per maintenance step | 2 MiB |
| Monotonic time per maintenance step | 50 ms |
| Cumulative time per candidate | 5 s |

Every subordinate limit remains under the existing language-analysis and
transaction ceilings. `Jan_Resource_Usage` reports source, retained and
temporary bytes, nodes, depths, attributes, facts, diagnostics, incremental
edits, logical work, and elapsed monotonic time for one candidate.

The independent ordinary, demanding, and adversarial profiles estimate a
maximum retained footprint of 335,675,392 bytes at the admitted logical
ceilings, beneath the 512 MiB aggregate limit. Runtime parser measurements
replace model estimates as structural and inline parsing land.

## Failures

`Jan_Failure` copies the rejected operation, exact scope, outcome, applicable
limit, actual value, and bounded diagnostic. Expected Stage 1 outcomes include:

- `Unsupported`;
- `Incomplete`;
- `Malformed`;
- `Limited`;
- `Cancelled`;
- `Stale`;
- `Provider_Failed`;
- `Allocation_Failed`; and
- invalid baseline, configuration, range, node, index, rewrite, or timeout.

Failures never grant a derived result authority over newer text. Ordinary text
editing remains available independently of Jan analysis status.

## Parser Provenance

The repository-owned grammar boundary lives under
`third_party/tree-sitter-jan/jan-org-9.8.10-v1/`. Slices 2 and 3 recognize the
complete structural and inline families, preserve blank lines, line endings,
and an unterminated final inline line through an external scanner, and project
checked pointer-free syntax in Odin. Confirmed configuration controls semantic
classification and every source-fact index shares that exact analysis scope.
Application registration remains deferred.

The committed generated parser uses Tree-sitter grammar ABI 15 and the already
vendored Tree-sitter 0.26.12 runtime. `SHA256SUMS` covers the grammar,
metadata, generated C, external scanner, support headers, C binding, local
license record, and provenance documentation. Normal validation compiles those
committed sources offline and does not run Node.js, npm, or an external Org
implementation.

## Focused Validation

Run:

```sh
make jan-document-language-focused-test
```

The target verifies digests and ABI, compiles and runs the isolated parser
probe, validates the independent 72-family fixture manifest, runs all three
resource profiles, checks contract-to-model parity and deferred application
registration, performs strict Odin checking, and runs the focused language
package tests.
