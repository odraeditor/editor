<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Execution Adapters Reference

Jan execution adapters convert an explicit, authorized computation request
into bounded data for an existing process or in-process runtime owner. They do
not execute while a document opens, parses, highlights, folds, completes,
navigates, searches, lints, indexes, previews, saves, follows links, or restores
a session.

## Header-argument precedence

Header arguments resolve from lowest to highest precedence:

1. factory general defaults;
2. factory language defaults;
3. user general and language configuration;
4. Workspace general and language policy;
5. Project general and language policy;
6. document general and language properties;
7. inherited subtree general and language properties;
8. affiliated header lines;
9. block or inline-block arguments;
10. call-site arguments; and
11. explicit invocation arguments.

Scalar values replace lower-precedence values. Additive values compose only
when every contribution declares the same additive contract. Resolution copies
the effective value and every selected or shadowed contribution for
inspection. Unknown provider arguments remain copied and are counted; they do
not broaden authority.

## Adapter selection

One confirmed configuration generation owns at most one adapter for an exact
language identity. Selection validates:

- exact adapter generation;
- exact language and optional requested adapter identity;
- adapter version and ownership class;
- in-process or external-runtime requirement;
- runtime availability; and
- adapter-specific limits no larger than the stable ceilings.

A missing runtime returns unavailable. A stale generation returns stale. A
requested replacement that is not the confirmed owner returns conflict.
`racket` and `emacs-lisp` are different language identities: the Racket adapter
never substitutes for an Emacs Lisp compatibility provider.

The deterministic `jan-test` factory adapter is in-process and requires no
external runtime. It exists for focused contract validation and does not grant
general execution authority.

## Serialization and conversion

Variables retain explicit scalar, list, table, source, result, property, or
resource kinds. The deterministic serialization includes name, kind,
dimensions, and copied value. Duplicate names, malformed UTF-8, excessive
values, or insufficient output storage reject the complete input.

Serialized data is not a shell command. Text such as `$()`, quotes, redirects,
or separators remains literal adapter input. Headers, prologues, epilogues, and
command-line options require the selected adapter's explicit conversion path.

## Deny-first authority

Authority binds operation, exact language and adapter, adapter and policy
generations, source origin, invocation context, requested effects, trust, and
trigger reason.

- No matching rule denies.
- Any matching deny rule denies.
- Confirmation is possible only for a trusted interactive command.
- Batch and export use noninteractive policy and never infer confirmation as
  approval.
- A confirmation is one-shot and matches the exact operation, generations,
  and effects.
- Implicit editor events deny even when an allow rule otherwise matches.

File-local arguments cannot change this decision.

## Process requests

A checked process request contains the exact computation scope, selected
adapter, allowed authority result, provider-owned working resource, serialized
input descriptor, effective environment descriptor, adapter limits, absolute
deadline, and cancellation grace interval. It contains no shell fragment,
mutable buffer pointer, credential, or operating-system process handle.

The process owner alone may start a child or in-process runtime. Lifecycle
records distinguish prepared, starting, running, cancelling, completed,
failed, timed out, quarantined, cleaning, and closed states. Cancellation and
timeout cannot publish a partial result.

## Quarantine and cleanup

A timed-out or unresponsive adapter generation is quarantined from new work.
Quarantine remains bound to the exact adapter generation and operation until
explicit reconciliation begins cleanup. Closure requires a positive cleanup
confirmation; losing the controlling session is not evidence that a process
exited.

Normalized diagnostics classify parse, reference, conversion, authorization,
adapter, process, evaluation, result decoding, stale publication, and resource
failures. Optional source ranges must match the exact request scope.

## Current boundary

Slice 11 prepares and validates adapters, environments, authority, serialized
inputs, process requests, lifecycle observations, diagnostics, and quarantine.
Result decoding, publication candidates, sessions, and cache entries are
defined by the
[Jan Results, Sessions, and Cache Reference](../jan-results-sessions-and-cache/index.md).
Neither package composes execution commands into the editor; linked execution
acceptance remains reserved for Slice 24.
