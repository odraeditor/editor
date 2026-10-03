<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Computation Contracts Reference

Jan Computation is the static Stage 4 domain over exact Jan Document Language
analysis. `src/jan_computation` defines copied computation identities, bounded
requests, typed result descriptors, session and cache records, checked adapter
and policy generations, extraction plans, deterministic batch accounting, and
capability lifecycle without evaluating source or owning editor effects.

## Package boundary

`src/jan_computation` consumes `language.Jan_Analysis_Scope`, copied source
ranges, and Racket-originated adapter and execution-policy definitions. It does
not parse source, retain syntax-tree pointers, evaluate formulas, launch a
process, mutate a buffer, write a resource, or import `src/odra`.

Formula evaluation and plotting are defined by the
[Jan Formulas and Plots Reference](../jan-formulas-and-plots/index.md). Runtime
adapters and authority enforcement are defined by the
[Jan Execution Adapters Reference](../jan-execution-adapters/index.md). Result
decoding, exact-owner publication candidates, sessions, and cache behavior are
defined by the
[Jan Results, Sessions, and Cache Reference](../jan-results-sessions-and-cache/index.md).
Focused editing, noweb expansion, shared libraries, and tangling are defined by
the
[Jan Source Editing and Extraction Reference](../jan-source-editing-and-extraction/index.md).
The [Jan Computation Operations Reference](../jan-computation-operations/index.md)
defines the completed command, batch, bridge, and availability surface. Slice
24 alone composes and exercises the linked editor.

## Exact identities

Every request carries:

- one nonzero operation identity and semantic family;
- an exact Jan analysis scope and source byte length;
- confirmed computation, adapter, and policy generations;
- one or more copied semantic targets tied to the exact source revision;
- an explicit interactive, batch, or export invocation context;
- declared authority-relevant effects; and
- complete limits no greater than the stable resource ceilings.

Loading, parsing, syntax presentation, indexing, previewing, saving, following
a link, or restoring a session cannot construct an executable request.

## Result, session, cache, extraction, and batch records

A typed result descriptor separates collection semantics, value family,
representation, publication handling, rows, bytes, exit status, and
completeness. It is a candidate result and does not grant publication.

Session records remain adapter-owned operational state. They bind adapter and
policy generations, source revision, process identity, lifecycle, and last
activity; they never become canonical document state.

A cache key includes normalized source, arguments, inputs, referenced data,
environment, adapter identity and version, cache policy, adapter generation,
and policy generation. Every digest must be present before reuse. Cache
deletion cannot delete document-owned results.

Extraction descriptors represent only complete checked plans. Batch plans sort
targets by document, source position, and operation identity after exact
authority, policy-generation, adapter-generation, and concurrency checks.
Summaries account for every target as completed, cache hit, rejected,
unattempted, or cancelled. Atomic batches publish no results after any
non-successful outcome; best-effort batches publish only attributable
successes. Existing process, transaction, and resource owners retain execution
and publication.

## Adapter and policy generations

Racket may contribute adapter definitions and deny-first policy rules. One
candidate generation is validated wholly, copied into native-owned storage,
and atomically replaces the prior confirmed generation.

Adapter definitions include identity, exact language responsibility, version,
ownership class, in-process or runtime requirements, and complete resource
limits. Only one adapter may own a language in a confirmed generation.

Policy definitions include identity, optional exact adapter, language, source
origin, interactive and batch decisions, and admitted effects. Batch policy cannot request interactive
confirmation: it must already allow or deny. A rejected, stale, conflicting,
over-limit, malformed, or allocation-failed candidate leaves the prior
generation active.

The initial admitted configuration demonstrates a bounded Racket adapter. It
does not substitute Racket for compatible embedded Emacs Lisp and does not
grant execution authority by itself.

## Capability lifecycle

The declared inventory covers formulas, text and graphical plots, execution,
results, sessions, cache, source editing, noweb, tangling, and batch execution.
Language-owned capabilities become available with confirmed Jan analysis.
Graphical plots additionally require a graphical adapter; execution, sessions,
and batches require an execution adapter and process owner; tangling requires a
resource owner. Factory-adapter availability carries its exact adapter
generation.

## Resource limits

| Resource | Limit |
| --- | ---: |
| Table cells | 65,536 |
| Formula dependencies | 16,384 |
| Graph depth | 1,024 |
| Executable targets | 4,096 |
| Active sessions | 64 |
| Child processes per operation | 32 |
| Captured output per target | 64 MiB |
| Aggregate retained output | 256 MiB |
| Generated files | 4,096 |
| Result rows | 16,384 |
| Execution cache | 256 MiB |
| Entries between cancellation checks | 4,096 |

Elapsed time, CPU time, RSS, and environment-entry limits are mandatory on
every admitted adapter even though the stable specification does not impose a
single universal numeric ceiling for them. An adapter may reduce any stable
ceiling but cannot enlarge it.

## Focused validation

Use:

```sh
make jan-computation-focused-test
```

The target runs independent Racket models for graphs, precedence, authority,
typed results, sessions, cache keys, extraction, batch order, configuration,
and resource profiles, followed by strict unoptimized `src/jan_computation`
package tests. It does not import or build `src/odra`, launch an external
runtime, or execute document source.
