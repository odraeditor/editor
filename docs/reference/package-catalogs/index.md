<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Package Catalog Reference

Package catalogs are explicitly enrolled, identity-pinned sources of signed
package assertions. The official default and independent catalogs use the same
records, signature verification, snapshot history, endpoint transport, local
state, and resolution rules.

## Identity and Authority Records

| Record | Required identity |
| --- | --- |
| Root key | Key identifier, generation, Ed25519 public key, and validity interval. |
| Catalog profile | Catalog identity derived from generation-one root material. |
| Curator authorization | Human subject, validity interval, and policy identities. |
| Publisher authorization | Publisher key identifiers, threshold, and validity interval. |
| Policy | Identity, generation, effective snapshot sequence, and five bounded references. |
| Endpoint | Identity, catalog identity, URI, transport, role, priority, and enabled state. |

Catalog identity is independent of display name, forge, repository, DNS name,
origin, and mirror. Only the exact catalog/root pair compiled into Odra can use
the `official` designation. Other identities remain valid as `independent`,
`private`, or `local` registrations.

## Registration and Configuration

Registration kinds are `official`, `independent`, `private`, and `local`.
Configuration origins are `built-in`, `administrator`, `user`, and `project`.
Each registration records an exact trust reference, endpoint set, precedence,
advisory policy, enabled state, and refresh state.

Endpoint roles are `origin`, `mirror`, and `local`; transports are HTTPS and
local file. A local registration accepts only file endpoints. A private
registration carries an opaque credential reference for HTTPS resolution.
Credential values are resolved outside the configuration record and redacted
from failures.

The initial live credential provider interprets the reference as an
environment variable name and reads one complete `Authorization` header value
at request time. References are non-secret; values remain process-local and do
not enter durable catalog state. The provider boundary records its identity and
generation so later keyring and secret-service adapters can preserve the same
transport contract.

Credentials apply to one HTTPS origin. Same-origin redirects may reuse them;
cross-origin redirects reject without forwarding them. A missing, expired, or
rejected credential produces a redacted transport failure and preserves the
last confirmed snapshot.

The factory refresh policy allows 4 MiB, a 60-second deadline, four redirects,
two retries, direct proxy policy, hourly automatic refresh, and 24 hours of
offline grace. The configured values remain bounded by the native maxima.

## Snapshot and Mirror Rules

A snapshot binds catalog identity, sequence, predecessor digest, policy,
issue and expiry times, assertion and advisory set digests, metadata size,
publisher authorization, and signatures. Sequence one has no predecessor;
later sequences name the exact prior snapshot.

Origins and mirrors are transport locations for the same bytes. A valid mirror
does not receive curation authority. Divergent valid snapshots, rollback,
history gaps, wrong catalog identity, expired data, metadata mismatch, or an
invalid publisher threshold reject the candidate and preserve confirmed state.

## Resolution

Resolution considers only confirmed enabled catalog state. It preserves
catalog and curator attribution, applies explicit package source pins,
organization overrides, and precedence, and reports symmetric integrity
conflicts when the same release identity names different immutable content.
Search returns at most 4,096 results per bounded result set.

## Commands

| Command | Current runtime behavior |
| --- | --- |
| `package-catalog-list` | List registration identifiers, enabled state, refresh state, and abbreviated catalog identity. |
| `package-catalog-add` | Decode a local KASPER-compatible publication, show an exact confirmation, enroll it, and perform its first verified refresh. |
| `package-catalog-disable` | Disable one selected registration without changing installed packages. |
| `package-catalog-remove` | Confirm and remove one exact registration without uninstalling packages. |
| `package-catalog-refresh` | Refresh one selected registration through its retained endpoint. |
| `package-catalog-search` | Search confirmed enabled snapshots with catalog and curator attribution. |
| `package-catalog-describe` | Inspect one exact registration identity, designation, refresh state, and confirmed snapshot. |
| `package-catalog-doctor` | Diagnose durable state generation, registrations, confirmed snapshots, failures, and missing trust metadata. |
| `package-manual-acquire` | Reserved semantic command; not connected to the runtime service in this development build. |
| `package-advisory-list` | Reserved semantic command; not connected to the runtime service in this development build. |
| `package-curator-validate` | Reserved semantic command; not connected to the runtime service in this development build. |

All commands are discoverable through `M-x` in Direct and Modal profiles. The
eight connected catalog commands report bounded results through Odra command
feedback. Reserved commands report their current unavailability without
changing catalog state.

## Local Publication Layout

Explicit enrollment accepts either a publication directory or its
`catalog.rktd` path. The containing directory must also provide the matching
`snapshot.rktd` and `assertions.rktd`. Odra reads static data modules and never
executes a curator repository's governance source.

The metadata pins the catalog profile and authorized publisher public keys.
The snapshot pins the assertion-set digest and carries the publisher
signatures. Addition succeeds only when all three files agree and the refresh
verifies the exact catalog identity and signature threshold.

The generated registration identifier has the form `local-` followed by the
first twelve hexadecimal characters of the catalog identity. Durable state,
verified snapshots, metadata, and assertions live below the active Odra
configuration root and survive application restart.

## Principal Limits

| Resource | Maximum |
| --- | --- |
| Catalog identity or record identity | 128 UTF-8 bytes |
| Display name | 256 UTF-8 bytes |
| URI or policy reference | 4,096 UTF-8 bytes |
| Root keys | 16 |
| Curator authorizations | 64 |
| Publisher authorizations | 64 |
| Policies | 256 |
| Profile endpoints | 64 |
| Registrations | 64 |
| Durable endpoints | 256 |
| Confirmed snapshots per state | 64 |
| Retained immutable snapshots | 1,024 |
| Snapshot metadata | 4 MiB |
| Signatures per record | 16 |
| Search results | 4,096 |
| Transport deadline | 600,000 ms |
| Transport redirects or retries | 8 each |

Expected failures include unsupported formats, invalid authority, identity or
signature mismatch, duplicate identities, stale generations, rollback,
divergent mirrors, expiry, transport, credential, cancellation, byte or count
limits, corrupt state, interrupted publication, and allocation failure.
