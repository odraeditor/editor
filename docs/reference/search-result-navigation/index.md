<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Search Result Navigation Reference

Materialized search results use one session-local result-set registry and the
shared candidate surface. The rendered list is a projection: result identity,
selection, source revision, refresh metadata, and editing authority remain in
the result registry.

## Commands and bindings

| Context | Binding | Command | Behavior |
| --- | --- | --- | --- |
| Active search | `M-s o` | `search-materialize-results` | Publish the current query and its retained matches as a result set. |
| Editor | `M-x project-search-text` | `project-search-text` | Search literal text across the active Project and open the result surface. |
| Editor | `M-x project-search-text-regexp` | `project-search-text-regexp` | Search a regular expression across the active Project. |
| Editor | `M-x project-search-repeat` | `project-search-repeat` | Repeat the most recent Project search against the current active Project. |
| Result surface | `M-n`, `M-p`, Down, Up | Shared candidate movement | Select the next or previous visible result. |
| Result surface | `<`, `>` | `result-first`, `result-last` | Select the first or last result. |
| Result surface | `RET` | Shared candidate activation | Visit the selected revision-checked location. |
| Result surface | `g` | `result-refresh` | Re-run the captured active-buffer search and replace the result generation. |
| Result surface | `e` | `result-edit` | Edit the selected matched text in a checked prompt and stage the replacement. |
| Result surface | `C-c C-c` | `result-apply` | Preflight and atomically apply every staged replacement. |
| Result surface | `q` | Shared candidate close | Close a clean result set and return to the editor. |
| Result surface | `C-g` | `keyboard-quit` | Discard staged edits first; otherwise close the result set. |
| Editor | `M-g M-n`, `M-g M-p` | `next-location`, `previous-location` | Move through the active result or diagnostic source. |

Unreserved text input on the result surface filters its copied rows. Filtering changes the
projection and selects the exact location represented by the current row; it
does not create another result set or derive navigation from rendered text.

## Result-set contract

A result set has a nonzero identity, immutable generation, source descriptor,
completeness state, optional continuation, refresh descriptor, declared edit
capability, zero or more groups, and ordered revision-bound locations. One
location contains a stable generation-local identity, source identity, buffer
identity, revision, half-open byte range, preview, and annotation.

Publication copies all retained text and replaces a prior generation only
when its expected generation matches. Refresh preserves the selected location
identity when that identity remains present. Closing releases the generation
and clears unified location authority when it still refers to that generation.

The default registry admits at most:

| Resource | Limit |
| --- | ---: |
| Live result sets | 32 |
| Locations per publication | 65,536 |
| Groups per publication | 4,096 |
| Copied result text | 8 MiB |
| One preview | 4 KiB |
| One annotation | 1 KiB |
| Temporary publication work | 32 MiB |

The shared candidate adapter admits at most 4,096 visible candidates. A
larger canonical result set therefore remains valid but requires a later
bounded projection or narrowing policy before all locations can be presented
at once.

## Editing and publication

Only a provider that declares an editing capability can create an editable
projection. Active-buffer search results currently declare single-buffer
editing; Project search and symbol results are read-only. `e`
copies the selected source range into a 4 KiB text-entry prompt. Accepting the
prompt stages one exact replacement; it does not modify the source buffer.

`C-c C-c` performs complete revision and range preflight before publication.
One-buffer application is one transaction and one semantic undo unit. The
general edit kernel also admits a provider-declared multi-buffer proposal:
stale or incomplete preflight applies nothing, and every participating buffer
retains atomic history through the shared transaction owner.

Refresh and close reject while staged changes exist. `q` reports that
protection. `C-g` on the result surface explicitly discards staged changes;
`C-g` inside the edit prompt cancels only that prompt and preserves edits
staged earlier in the same projection.

## Unified location source

The editor session owns one active location-source descriptor. Active-buffer
search, Project search, symbol indexes, and language diagnostics publish
through the common result-set registry
and activate that descriptor. `next-location` and `previous-location` move the
canonical result selection, revalidate the target buffer and revision, visit
the exact byte position, and retain the previous editor location when
available.

Provider-specific labels, paths, line numbers, previews, and candidate rows
never become navigation authority. A stale, closed, or unavailable target is
reported without moving point.

## Project search

Project search uses only the exact admitted roots and generations of the
active Project. The maintained native provider requires neither a repository
nor an external search executable. It applies explicit hidden, ignore, binary,
include, and exclude policies while reusing the literal and regular-expression
matching semantics of active-buffer search.

Each retained match carries its source fingerprint, exact byte range, line and
column, preview, membership identity, and stable logical identity. The result
surface groups matches by file, but rendered paths and coordinates never
authorize navigation. Visiting a match revalidates its fingerprint before
opening or reusing the file and moving point.

`g` reruns the captured query and replaces the exact result generation while
preserving the selected logical match when it remains present. A Project
refresh invalidates the provider and its result generation. An unavailable
root, stale Project, changed source, cancellation, or failed replacement
cannot publish over the preceding valid result generation. Bounded scans
report incomplete state and continuation metadata instead of claiming a
complete result set.

## Programmable result providers

`src/command/results.rkt` is the provider-facing Racket facade.
`src/hosting/result-provider-bridge.rkt` owns only low-level transport and
record conversion. Native admission lives in `src/command/`, and the fixed
little-endian records live in `src/bridge/result_records.odin`.

The boundary transfers copied scope, publication, location, group, movement,
inspection, and outcome records. Publication validates complete text ranges,
UTF-8, identities, counts, and aggregate size before native state changes.
No Racket value receives a native pointer, buffer owner, result-registry
allocation, candidate session, UI object, or transaction commit authority.

The current fixed widths are 48 bytes for scope, 264 bytes for publication
headers, 336 bytes for inspection headers, 88 bytes per location, 24 bytes per
group, 56 bytes for movement, and 96 bytes for outcomes. One proposal or
inspection is bounded to approximately 14 MiB by the native record limits.

## Validation

The focused workflow is covered by result-set, editor-session, Project-search,
interaction, transaction, native/Racket boundary, resource, and PTY tests. The
active-buffer PTY scenario materializes a real incremental search, stages a
changed match, applies it, saves the document, and verifies the resulting file
contents. The Project PTY scenario searches two real files and visits one
checked match.

See [Search and Replacement Reference](../search-and-replacement/) for the
active search engine and [Racket Runtime Boundary Reference](../racket-runtime-boundary/)
for shared capability transport and lifecycle.
