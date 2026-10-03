<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Inspection and Lint Reference

Jan Stage 1 exposes four read-only commands for current `.org`, `.jan`, and
explicitly selected Jan buffers. Command names are stable semantic identities;
the factory profile assigns no mandatory physical binding.

## Commands

| Command | Result |
| --- | --- |
| `jan-inspect-syntax` | Reports the syntax path at point, node identity and kind, raw half-open byte range, attribute count, recovery code, source revision, analysis generation, and configuration generation. |
| `jan-lint` | Derives a bounded diagnostic generation from the current confirmed analysis and reports the count plus the first severity, confidence, range, and explanation. |
| `jan-lint-refresh` | Recomputes the same read-only lint contract for the current confirmed revision. It neither reparses nor edits the document. |
| `jan-language-status` | Opens the existing language-state list with recognition, association, provider, baseline, generations, resource limits, zero remaining future-stage capabilities, and latest rejection. |

The first three commands use bounded command feedback. `jan-language-status`
uses the existing read-only list presentation and returns to the previous
buffer view through the ordinary list close action.

All four commands require an active current Jan analysis. A plain-text or Odin
buffer reports `Unsupported`; pending or absent Jan analysis reports
`Incomplete`; a generation mismatch reports `Stale`. These are contained
command outcomes and do not make the buffer unavailable for ordinary editing.

## Syntax Inspection

Inspection selects the deepest Jan node whose range contains point. Its path
is reconstructed from copied node identifiers and parent identifiers in the
same confirmed generation. Node-kind names and typed attributes come only from
that copied analysis; raw Tree-sitter nodes, cursors, pointers, and borrowed
parser strings never cross the language boundary.

The reported range is expressed in canonical UTF-8 bytes as `[start, end)`.
Recovery at point is one of `Malformed`, `Unterminated`, `Context_Invalid`,
`Ambiguous`, or `Limited`. `Invalid` means the selected node has no recovery
record.

## Lint Records

Each `Jan_Lint_Record` contains:

- a nonzero record identity and lint generation;
- the complete exact `Jan_Analysis_Scope`;
- an optional canonical source range;
- a stable lint code;
- severity and confidence;
- a copied checker identity; and
- a copied explanation.

Recovery syntax maps deterministically to lint facts. Malformed and
unterminated forms are errors with certain confidence. Context-invalid and
ambiguous forms are warnings; ambiguous evidence has likely confidence.
Resource-limited and configuration-invalid current-generation failures are
errors with certain confidence.

Linting reads only copied syntax, recovery, resource, and failure records. It
does not resolve links, open files, read directories, start processes, access
the network, evaluate source blocks, call Racket, or mutate UI and document
ownership. Closing a lint result releases its copied record storage without
affecting the confirmed analysis.

## Copied Bridge Records

Native contract schema version 25 retains the Jan language record family and
adds the independent Jan Planning record family.
It includes fixed-width records for:

- exact document, language, provider, parser, grammar, configuration,
  baseline, and analysis scope;
- command operation and point;
- inspection headers and syntax paths;
- typed attributes and recovery ranges;
- lint severity, confidence, checker, and explanation offsets;
- the complete selected resource policy;
- provider and baseline generations;
- the latest contained rejection; and
- operational availability.

Variable text is addressed by checked offset and byte-count pairs. A complete
copy is rejected when any count exceeds its family limit or the aggregate
result exceeds `MAX_JAN_INSPECTION_BYTES`.

## Baseline and Limits

The factory baseline is `jan-org-9.8.10-v1`, the syntax reference is
`Org Syntax v2`, and the accepted specification commit is copied into every
analysis scope. `jan-language-status` reports the active provider and the
selected source, diagnostic, inspection, and candidate-time limits.

Lint record count cannot exceed `MAX_JAN_DIAGNOSTICS`. Aggregate copied lint
records cannot exceed the selected inspection-byte limit. Allocation failure,
an invalid request, a stale generation, or an exceeded limit rejects the new
result atomically and leaves confirmed analysis and canonical source intact.

## Future-Stage Availability

The Stage 1 availability catalog contains 19 recognized capability families
owned by Jan Structured Editing, Planning and Agenda, Computable Documents,
and Export, Publishing, and Integration. Every entry is currently classified
as `Future_Stage`, reports its owning stage, is explicitly unavailable, and
states that the source remains recognized and preserved.

Future-stage reporting grants no document, process, filesystem, network,
resource-provider, or UI authority. Later Jan delivery stages replace those
records with their final factory-native, factory-adapter, or
configured-provider classifications when the owning behavior is accepted.

## Failure Behavior

Expected lint and inspection rejection codes include `Unsupported`,
`Incomplete`, `Malformed`, `Limited`, `Cancelled`, `Stale`, `Provider_Failed`,
`Allocation_Failed`, `Invalid_Configuration`, and `Timeout`. A rejection
records the responsible operation, exact scope when available, limit, actual
usage, and bounded diagnostic text.

No rejection changes source bytes, buffer revision, document association,
provider selection, process state, or external resources. The latest confirmed
analysis remains diagnostic evidence only and cannot authorize a command over
a newer revision.
