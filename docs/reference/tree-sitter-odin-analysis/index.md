<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Tree-sitter Odin Analysis Reference

The `language` package integrates the maintained Tree-sitter runtime and Odin
grammar behind an Odin-owned boundary. The application selects this factory
provider for file-backed paths whose suffix is exactly `.odin`, maintains one
analysis owner per buffer, and projects exact-revision semantic syntax through
the shared terminal presentation path.

## Vendored Inputs

| Input | Revision | Commit | ABI | Repository path |
| --- | --- | --- | ---: | --- |
| Tree-sitter runtime | `v0.26.12` | `808e4b1fc06e269a107c4bd8bd936cc6fde18b00` | runtime 15, minimum 13 | `third_party/tree-sitter/0.26.12` |
| Odin grammar and highlight query | `v1.3.0` | `e8adc739b78409a99f8c31313f0bb54cc538cf73` | grammar 14 | `third_party/tree-sitter-odin/1.3.0` |

Each directory contains its upstream license, provenance record, and
`SHA256SUMS`. The grammar metadata records Tree-sitter CLI `0.24.5` as the
generator. The runtime, generated parser, scanner, and allocation-accounting
adapter compile into `.build/syntax-vendor/libtree-sitter-odin.a`; no ambient
Tree-sitter installation participates in the build.

Run the offline integrity and link checks from the repository root:

```sh
make syntax-vendor-check syntax-vendor-build
```

`make syntax-dependency-study` is the networked revision-reproduction check.
It downloads the selected tags into a temporary directory, verifies their
commits and digests, and removes the temporary inputs. It is not required for
an offline build.

## Foreign Ownership

`Tree_Sitter_Owner` is the only public foreign owner. Its private state owns
one language pointer, parser, confirmed tree, compiled query, query cursor,
progress record, and the exact confirmed `Parse_Snapshot`. Raw Tree-sitter
pointers never appear in public snapshots or inspection records.

Initialization installs the Odra allocator adapter once, reserves one of 128
accounting slots, verifies the grammar ABI, and creates the parser and cursor.
Every Tree-sitter allocation retains its accounting owner in a private header,
so a later `free` remains attributable even outside the allocating call. Owner
statistics expose exact live bytes, peak bytes, allocation calls, and frees.
Closing releases cursor, query, tree, parser, the accounting slot, and the Odin
owner state. A foreign allocation surviving that sequence is a failed cleanup
invariant.

The relevant lifecycle procedures are:

| Procedure | Effect |
| --- | --- |
| `tree_sitter_owner_init` | Create an ABI-checked parser, cursor, and accounting owner. |
| `tree_sitter_owner_compile_odin_query` | Compile and atomically install the pinned factory query. |
| `tree_sitter_owner_parse_snapshot` | Parse one immutable exact buffer revision. |
| `tree_sitter_owner_parse_incremental` | Apply one exact normalized commit to a copied confirmed tree and parse its result revision. |
| `tree_sitter_owner_query_spans` | Query one bounded visible range and return owned normalized spans. |
| `tree_sitter_owner_request_cancel` | Mark the current or next progress window cancelled. |
| `tree_sitter_owner_clear_cancel` | Admit work after cancellation handling. |
| `tree_sitter_owner_stats` | Copy pointer-free lifecycle, progress, revision, work, and foreign-allocation state. |
| `tree_sitter_owner_close` | Deterministically release the complete foreign and Odin owner. |

## Initial Parsing

Initial parsing accepts an immutable `editor.Buffer_Snapshot`, a checked
language and provider identity, selection generation, and new tree generation.
The Tree-sitter input callback reads copied chunks no larger than 64 KiB from
the snapshot; it never borrows canonical buffer storage. The source must be no
larger than 64 MiB and the default initial work budget is 8 MiB.

The candidate tree is not observable while parsing. A successful parse
atomically replaces the prior confirmed tree and publishes a `Parse_Snapshot`
for the snapshot's exact buffer revision. Input failure, cancellation, work
exhaustion, or an invalid generation preserves the prior confirmed tree.

## Incremental Parsing and Refresh

Incremental parsing requires all of the following identities to agree:

1. the owner's confirmed buffer and revision;
2. the immutable base snapshot;
3. the `Commit_Event` base revision;
4. the immutable result snapshot and event result revision; and
5. a strictly newer tree generation.

The implementation copies the confirmed tree, applies ordered
`Normalized_Splice` edits, and validates removed and replacement bytes against
the two immutable snapshots. Tree-sitter parses the result snapshot with that
edited candidate and a default 2 MiB work budget. Only a complete successful
candidate replaces the confirmed tree.

A stale identity, invalid transaction, unavailable snapshot, cancelled parse,
or exhausted work budget keeps the confirmed tree and coalesces one full
refresh request for the newest revision. A stale tree is never returned as an
approximate syntax result.

## Query and Span Mapping

The pinned Odin highlight query is compiled atomically. Every capture name
must have a known mapping before the query can replace the confirmed query.
The upstream `error` and `spell` captures are recognized and disabled. An
unknown capture rejects the complete candidate query.

Visible-query evaluation applies the maintained `any-of?`, `lua-match?`, and
`not-has-parent?` predicates against the exact retained source revision before
normalizing captures. Predicate filtering prevents generic identifier patterns
from overriding more specific function, parameter, type, constant, macro, and
variable classifications.

Factory captures map to the stable semantic roles as follows:

| Capture family | Semantic role |
| --- | --- |
| `attribute` | attribute |
| `boolean` | boolean |
| `comment` | comment |
| `constant`, `constant.builtin` | constant |
| `function`, `function.call` | function |
| `function.macro` | built-in function |
| conditionals, includes, keywords, preprocessing, repetition, storage class | keyword |
| `label` | label |
| `float`, `number` | number |
| `operator` | operator |
| punctuation captures | punctuation |
| character and string captures | string |
| type and namespace captures | type |
| `parameter` | variable parameter |
| field and variable captures | variable |

Visible queries accept a half-open byte range and at most a 64 KiB halo. The
query cursor admits at most 16,384 simultaneous matches and one pass admits at
most 131,072 foreign captures. Zero-width captures are ignored; out-of-bounds
foreign captures reject the query. Normalization applies capture precedence,
splits overlaps, merges adjacent equal roles, and returns at most 65,536 sorted,
non-overlapping, non-empty `Syntax_Span` values carrying the
exact source revision and provider identity.

`Syntax_Query_Result` owns the normalized span allocation. Call
`syntax_query_result_close` exactly once after use.

## Resource and Latency Evidence

`make tree-sitter-resource-study` builds and runs the production parser,
grammar, query, incremental path, visible query, cancellation path, allocation
accounting, and teardown. The selected validation profiles are:

| Profile | Source | Samples | Initial p99 gate | Incremental p99 gate | Visible query | Visible p99 gate |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| ordinary | 64 KiB | 16 | 100 ms | 50 ms | 16 KiB | 25 ms |
| demanding | 2 MiB | 3 | 1.5 s | 1.5 s | 16 KiB | 25 ms |

Both profiles use a 100 ms cancellation gate and a 100 ms owner-teardown
gate. They also require zero Odin-owned bytes after teardown and keep the
combined Odin and foreign allocation peak below the 512 MiB retained-analysis
ceiling.

One Linux x86-64 run with Odin `dev-2026-07:301c287de` measured:

| Profile | Initial p99 | Incremental p99 | Visible p99 | Cancellation | Foreign peak | Teardown | Cleanup |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ordinary | 18.0 ms | 15.1 ms | 4.9 ms | 0.07 ms | 8.6 MiB | 2.0 ms | 0 bytes |
| demanding | 549.1 ms | 522.9 ms | 4.1 ms | 0.06 ms | 272.3 MiB | 78.9 ms | 0 bytes |

The measurements are reproducible evidence for the gates, not a promise of
identical timings on every host.

## Failures and Preservation

Initialization contains missing runtime values, ABI mismatch, allocation
failure, and owner-slot exhaustion. Query compilation contains invalid syntax,
query-size exhaustion, unknown capture mapping, and stale query generation.
Parsing contains unavailable snapshots, source and work limits, cancellation,
stale identities, invalid transactions, and allocation failure. Visible
queries contain invalid ranges, halo, capture, span, and allocation limits.

Expected rejection returns a copied `Failure` and does not publish a partial
tree, query, or span result. Unit coverage compares full and incremental
syntax, parses incomplete source, exercises two visible queries over one
owner, proves cancellation and work-limit preservation, injects an Odin
allocation failure, checks foreign accounting, and repeats owner teardown.

## Application Composition

The factory syntax workflow associates case-sensitive `.odin` file-backed
documents with the maintained provider. It creates one buffer-owned parser
lifecycle shared by every view. Transaction commit observation copies bounded
splice records after canonical publication; the application maintenance step
performs incremental work or a coalesced full refresh. Visible views query only
the exact confirmed revision.

Provider disable closes the active owners and leaves eligible documents as
plain text. A confirmed native replacement becomes the only selected provider.
Failure containment restores the maintained factory provider when possible,
and explicit restoration selects it again without duplicate analysis owners.
These lifecycle operations are native integration contracts; the MVP does not
expose a user-facing provider configuration interface.

`describe-language-state` copies the active buffer association, provider,
revision, parser, query, syntax, style, renderer, usage, pending-work, and
latest-rejection state into the shared list UI. Unsupported documents report
plain-text state and retain every ordinary editor workflow.

The retained exact tree also supplies bounded pointer-free structural targets
and indentation plans without adding a second parser or tree. See the
[Structural Syntax Contract Reference](../structural-syntax-contracts/) for
that language-side contract. Editor commands and bindings remain deferred to
later delivery slices.

See [Configure and Validate Factory Syntax Presentation](../../how-to/configure-factory-syntax-presentation/)
for dependency reproduction and focused terminal acceptance.
