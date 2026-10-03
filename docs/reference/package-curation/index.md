<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Package Curation Reference

Curation records one accountable human decision about one exact package
release. It is distinct from assessment evidence, catalog publication, package
installation, capability consent, and activation.

## Release Projection

One release records package and publisher identities, semantic version, exact
source URI and revision, optional source label, manifest digest, target-specific
artifacts, dependency-set digest, compatibility digest, capability-set digest,
and contribution-set digest. Each artifact records platform, architecture,
locations, SHA-256, size, optional builder and provenance, and reproducibility
state.

## Workflow Records

| Record | Purpose |
| --- | --- |
| Submission | Propose add, update, transfer, deprecate, quarantine, restore, or withdraw. |
| Change summary | Classify semantic direction and risk by package dimension. |
| Assessment | Attribute bounded evidence to a human, deterministic tool, isolated runtime, or AI-assisted process. |
| Human decision | Accept, reject, or request changes under an exact policy generation. |
| Curation assertion | Project the accepted status of one exact release into snapshots. |
| Publication proposal | Bind decision, sequence, validity, advisory set, and publisher authorization. |
| Publication audit | Retain validation, build, and publication events. |

An assessment has no admission or signing authority. AI-assisted evidence is
allowed only as an attributable assessment. Curator authorization requires a
human subject, and publication requires a current authorized human decision.

Assertion statuses are `admitted`, `deprecated`, `quarantined`, and
`withdrawn`. History is append-only by assertion identity and sequence.
Restoration and status changes create new generations; they do not erase the
prior decision.

## Manual Provenance

Manual source kinds are `development-directory`, `local-artifact`, and `git`.
The acquisition binds one source, exact resolved Git revision when applicable,
artifact and manifest digests, release projection, explicit-only update policy,
and prepared generation. Its curation state is either `manual-uncurated` or
`matches-curated-release` with exact assertion identifiers.

Manual acquisition does not add a catalog, follow a moving source, grant
authority, or fabricate curation. Installation remains inactive until the
package family's separate activation workflow succeeds.

## Principal Limits

| Resource | Maximum |
| --- | --- |
| Artifacts per release | 16 |
| Locations per artifact | 16 |
| Submission changes | 64 |
| Assessment identifiers per submission | 128 |
| Inputs per assessment | 128 |
| Findings per assessment | 256 |
| Assessments per human decision | 128 |
| Assertion history or publication assertions | 4,096 |
| Matching assertions for manual provenance | 64 |
| Files in a manual package | 8,192 |
| Expanded manual package content | 1 GiB |
| General rationale or reference text | 4,096 UTF-8 bytes |

Curator starting material is under
`assets/package-catalog/curator-kit/`. The public conformance runner is
`scripts/check-package-catalog-conformance.rkt`; curator workflows are exposed
by `scripts/package-catalog-curator.rkt`.
