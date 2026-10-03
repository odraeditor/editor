<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Results, Sessions, and Cache Reference

Jan result handling converts complete adapter output into an exact-revision
publication candidate. Sessions and cache entries remain bounded operational
state: neither can replace canonical document content or authorize execution.

## Typed result decoding

One adapter result declares its operation, value or output collection, value
family, source representation, handling, row count, byte count, exit status,
and completeness.

Decoding requires:

- the exact confirmed analysis, source, adapter, and policy generations;
- the exact originating block or call;
- a complete successful adapter outcome;
- byte and row accounting within the effective limits;
- valid UTF-8 for textual value families; and
- caller-owned storage large enough for a complete copy.

Partial output, a nonzero exit status, malformed text, stale scope, excessive
rows, or insufficient storage rejects the whole candidate. Rejection never
removes the last successful result.

## Post-processing

Post-processing nodes identify their dependencies explicitly. Jan accepts only
a complete bounded acyclic graph and returns a stable topological order before
any processor runs. Missing dependencies, duplicate identities, cycles, or
excessive depth reject the graph.

A processor receives typed copied input. It cannot infer authority from the
result or widen the original execution effects.

## Exact-owner publication

Publication revalidates the complete computation scope and originating
semantic target. It can replace, append, prepend, suppress, or discard output
according to the decoded handling contract.

For a source mutation, Jan prepares one replacement range and then materializes
one whole-source candidate. The range is either the exact existing result owned
by the originating block or call, or the exact insertion point after that
owner. Unrelated source is copied unchanged. The editor owner performs the
eventual atomic buffer transaction.

Silent and discarded results produce complete non-mutating outcomes. A stale
owner, changed source revision, allocation failure, decoding failure, or
publication conflict produces no source candidate.

## Sessions

A session binds a stable identity to an exact language, adapter and policy
generation, source revision, document/Project/Workspace scope, process
identity, limits, last activity, and cleanup state.

- Reuse always names the session explicitly; unnamed execution never joins an
  arbitrary active context.
- Selection requires the exact language, adapter, generation, scope, and source
  revision.
- Provider invalidation moves a live session to recovery required.
- Restart clears the remembered process identity and moves every non-closed
  session to recovery required.
- Document loading never reconnects a session or executes source.
- Reconnection is an explicit lifecycle event after the adapter proves a safe
  process identity.
- Closure records positive cleanup confirmation. Failed termination remains
  inspectable as failed, quarantined, or recovery required.

Session state is operational metadata, never canonical document state.

## Execution cache

An exact cache key includes digests for normalized source, effective arguments,
variable inputs, referenced data, execution environment, adapter identity,
adapter version, and cache policy, plus exact adapter and policy generations.

Inspection distinguishes an exact hit, no entry, key mismatch, stale
generation, incomplete result, resource rejection, and explicit eviction.
Matching source text alone produces an invalidated outcome, not a hit.

The cache copies only complete decoded results into caller-owned bounded
storage. When an insertion would exceed the byte or entry ceiling, it evicts
the least recently used entry deterministically and compacts cache-owned bytes.
Explicit deletion accepts only a cache entry identity. It has no document
resource, result range, or source mutation capability, so eviction cannot
delete a document-owned result.

## Current boundary

Slice 12 owns result decoding, post-processing order, exact-owner publication
candidates, session lifecycle, restart recovery, cache reuse, inspection, and
eviction. The editor transaction owner still publishes a prepared source
candidate. Source editing and extraction are defined by the
[Jan Source Editing and Extraction Reference](../jan-source-editing-and-extraction/index.md).
Linked execution and publication acceptance remains reserved for Slice 24.
