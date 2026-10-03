<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Language Diagnostics Reference

This reference describes the language-independent diagnostic publication,
presentation, candidate, command, and application contracts. The factory
workflow activates them for eligible documents in trusted Project memberships;
the underlying records and owners remain independent of the first language and
server.

## Publication and Ownership

`Diagnostic_Store` owns at most one complete diagnostic generation for each
open document binding in one exact language-service session. A successful
publication replaces the preceding generation atomically. Copied batch
inspection transfers records and shared text storage to the caller, which must
release the copy with `diagnostic_batch_copy_close`.

Each record carries its document binding, diagnostic generation and identity,
canonical revision, protocol document version, provenance, canonical UTF-8
byte range, point/range form, severity, message, source, and code. Records do
not retain JSON, protocol buffers, server memory, editor text, or Project
state.

## Revision Provenance and Normalization

Canonical diagnostic ranges are half-open UTF-8 byte ranges. Incoming LSP
positions are converted from the negotiated UTF-8, UTF-16, or UTF-32 encoding
against the exact synchronized document text. Positions inside a code point or
UTF-16 surrogate pair are invalid.

A server-versioned publication is accepted only when its document version
equals the current open binding version. A versionless publication is
receipt-bound: its recorded canonical revision must be current and the
synchronization queue must be empty. The next canonical edit invalidates the
published generation before newer text can be projected or navigated. Late
publications reject as stale and preserve the current confirmed generation.

Missing severity normalizes to `information`. Malformed individual items are
rejected without discarding valid items in the same admitted batch, and the
batch descriptor records the rejected-item count. Invalid document identity,
URI, version or receipt provenance, an excessive batch, resource overflow, or
allocation failure rejects the complete proposed publication without exposing
a partial generation.

## Presentation

The semantic roles are `diagnostic.error`, `diagnostic.warning`,
`diagnostic.information`, and `diagnostic.hint`. Every factory theme provides
a deterministic style for all four roles. True-color, 256-color, and 16-color
renderers use the existing theme degradation path; monochrome rendering keeps
distinct admitted attributes for the four severities.

UI projection accepts only a complete generation whose canonical revision
matches the `TextView` revision. Ranged and point diagnostics become semantic
decorations. Diagnostic styling composes over ordinary text and syntax;
current search and active region presentation remain above it. Cursor
placement is independent and remains visible. Pane status can expose current
error and warning counts together with copied service health.

## Candidate Navigation

The diagnostic candidate adapter builds one complete active-buffer or active-
Project source generation from caller-owned copied batches. Candidates are
ordered by severity, path, start byte, and diagnostic identity. Searchable
fields include path, source, code, and severity; visible annotations include
severity and location.

A candidate identity is stable within its source generation. Its navigation
action copies the buffer, canonical revision, document binding generation,
diagnostic generation and identity, and exact byte range. Invocation must
revalidate all of those values before ordinary document opening, pane display,
and point movement. Stale candidate or document generations cannot authorize
navigation.

## Command Routes

The canonical commands are:

- `list-language-diagnostics`
- `next-language-diagnostic`
- `previous-language-diagnostic`

Native registrations declare only view and lifecycle effects; diagnostic
navigation cannot mutate text. The programmable language-service capability
accepts the same exact names with positive diagnostic and source generations,
copies one bounded request, and returns a fixed outcome.

The factory direct profile binds `M-g n` to `next-language-diagnostic` and
`M-g p` to `previous-language-diagnostic`. Listing remains available through
`M-x`. Navigation outside a candidate list traverses the current complete
generation in deterministic document and range order.

`next-location` and `previous-location` provide provider-neutral movement over
the active diagnostic, search, symbol, or Project-search result source. A new
source replaces only the active navigation authority; it does not transfer
ownership of diagnostic generations to another subsystem.

The application also registers:

- `describe-language-service`, which presents copied provider, executable,
  process, protocol, document, diagnostic, resource, health, stderr, and
  failure rows; and
- `restart-language-service`, which admits one explicit restart only for a
  failed session whose process has been reaped.

An absent or failed service never changes ordinary editing command
availability. Listing without a current publication reports `No current
language diagnostics`; an invalid restart reports a stable diagnostic rather
than changing process state.

## Limits, Failures, and Cleanup

The selected limits admit 4,096 diagnostics per document, 65,536 per Project
generation, 64 KiB per diagnostic message, 32 related locations per item, 128
MiB of diagnostic storage per Project generation, 65,536 candidates, and 64
MiB of copied candidate text. Field counts, work per publication, retained
bytes, storage bytes, and arithmetic are checked before publication.

Closing a diagnostic store releases every owned generation, record array, and
text buffer. Closing a copied batch or candidate adapter releases its copied
storage. Allocation-fault tests require zero retained bytes and no partial
generation after every injected failure.

## Focused Validation

```sh
odin test src/language_service -vet -warnings-as-errors -define:ODIN_TEST_THREADS=1
odin test src/ui -vet -warnings-as-errors -define:ODIN_TEST_THREADS=1
odin test src/theme -vet -warnings-as-errors -define:ODIN_TEST_THREADS=1
odin test src/interaction -vet -warnings-as-errors -define:ODIN_TEST_THREADS=1
odin test src/terminal -vet -warnings-as-errors -define:ODIN_TEST_THREADS=1
make native-command-test
make language-service-workflow-acceptance
make docs-check
```
