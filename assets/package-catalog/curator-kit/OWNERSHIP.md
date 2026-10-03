<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Package Catalog Curator Kit Ownership

| Concern | Owner |
| --- | --- |
| Catalog identity, policy, authorization, and endpoint records | `src/package_catalog/contracts.rkt` |
| Submission and attributable assessment records | `src/package_catalog/curation-submissions.rkt` |
| Human decisions and publication proposals | `src/package_catalog/curation-decisions.rkt` |
| Package releases and curation assertions | `src/package_catalog/curation-records.rkt` |
| Security advisory records | `src/package_catalog/security-advisories.rkt` |
| Snapshot records and canonical payloads | `src/package_catalog/snapshot-records.rkt` |
| Signature domains and public verification | `src/package_catalog/integrity.rkt` |
| Publication validation and persistence | `src/package_catalog/curation-publication.rkt` |
| Curator-facing starting material | `assets/package-catalog/curator-kit/` |
| Noninteractive curator workflows | `scripts/package-catalog-curator.rkt` |

The kit supplies examples only. A catalog governance repository owns its
policies, human authority, key custody, endpoints, and publication history.
Odra owns the bounded protocol and local trust decisions.
