<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Release Publication Manifest Reference

## Purpose

The publication manifest connects one canonical Odra source commit to its
curated source snapshot, release artifacts, validation phases, and publication
results. `scripts/release/publication-identity.rkt` owns the executable data
contract.

The manifest contains logical repository identities such as `odra/odra` and
`odra/editor`. It never stores remote URLs with credentials, access tokens,
authorization values, passwords, private keys, or equivalent secret fields.

## Release Request

| Field | Meaning |
| --- | --- |
| `mode` | `candidate` prepares and validates; `publish` consumes the same validated candidate for immutable publication. |
| `version` | Canonical `MAJOR.MINOR.PATCH` without a leading `v`. |
| `source.repository` | Logical canonical source repository identity. |
| `source.commit` | Exact 40-character lowercase Git commit. |
| `source.source_date_epoch` | Unsigned 63-bit reproducibility timestamp. |
| `snapshot_repository` | Logical target source-snapshot repository identity. |
| `platforms` | Ordered release platform list; currently only `linux-x86_64`. |
| `export_policy` | Version and SHA-256 identity of the source-classification policy. |
| `build_environment_sha256` | SHA-256 identity of declared build inputs. |
| `documentation_contract_version` | Version of the User Guide projection contract. |

Candidate and publish modes do not create different candidates. The candidate
digest excludes `mode` and covers every field that can change the source,
binary, or documentation result.

## Snapshot Identity

A resolved source snapshot records:

- its `refs/heads/candidates/vMAJOR.MINOR.PATCH` preparation ref;
- the snapshot commit and tree object IDs;
- the source inventory and export-policy SHA-256 digests; and
- an optional annotated release tag, absent before publication.

The snapshot identity is separate from the private canonical source commit.
The combined manifest preserves both.

## Source Export

`release/public-source-policy.json` classifies every tracked path through one
exact or prefix rule. A path with no rule, more than one matching rule, an
explicit `reject` result, an unsupported Git object, or a case-folding
collision stops export.

The initial policy includes product source, assets, documentation, build and
validation tooling, tests, release inputs, package catalog fixtures, license
metadata, and third-party source. It excludes private agent instructions,
Forgejo automation, and `ops/**` development records.

Create a candidate tree from an exact commit with:

```sh
racket scripts/release/public-source-export.rkt \
  --repository . \
  --commit <full-commit> \
  --policy release/public-source-policy.json \
  --output <absent-or-empty-directory>
```

The destination receives:

- `tree/`, the normalized candidate source;
- `inventory.json`, the complete included and excluded path inventory; and
- `summary.json`, the inventory, content, and materialized-tree digests.

The tree also contains `release/public-source-manifest.json`. File modes and
the commit-derived modification time are normalized. Existing non-empty
destinations are rejected without modification.

## Snapshot Audit

`release/public-source-closure.json` defines the minimum buildable source
closure and every admitted binary input. The snapshot audit rejects:

- private operational or Git paths;
- private keys, maintainer-local paths, and private remote forms;
- missing first-party SPDX notices or REUSE coverage;
- missing third-party license files and build inputs;
- undeclared binary files; and
- any mismatch among the exported tree, inventory, summary, and generated
  source manifest.

Audit an exported candidate before transferring it to the snapshot repository:

```sh
racket scripts/release/check-public-source-snapshot.rkt \
  --snapshot <export-output-directory> \
  --contract release/public-source-closure.json
```

This check reads only the exported output and its versioned closure contract.
It does not fall back to the canonical private checkout.

## Snapshot Repository Lifecycle

`scripts/release/snapshot-repository.rkt` converts an audited tree into a new
Git history owned by the snapshot repository. The first release has one root
commit. Each later release commit uses the current target `main` commit as its
only parent, so canonical development history never enters `odra/editor`.

Candidate mode writes `refs/heads/candidates/vMAJOR.MINOR.PATCH`, verifies the
exact commit and tree through a fresh checkout, and leaves `main` and SemVer
tags unchanged. Run the complete candidate transition with:

```sh
racket scripts/release/snapshot-repository.rkt \
  --snapshot <export-output-directory>/tree \
  --workspace <absent-workspace> \
  --version <MAJOR.MINOR.PATCH> \
  --source-date-epoch <epoch> \
  --target <credential-free-target-url> \
  --authorization-env <environment-variable-name> \
  --checkout <absent-verification-checkout> \
  candidate
```

Authorization is read only from the named environment variable and supplied
to Git through its subprocess environment. It is not accepted inside the
target URL, written into repository configuration, or serialized into release
state.

An absent candidate ref may be created. An identical ref is an idempotent
success, while different content is a conflict. Final publication applies the
same rule to `main` and the deterministic annotated SemVer tag and never uses
a force push.

## Build from a Snapshot

`scripts/release/snapshot-build.rkt` validates one clean snapshot checkout and
creates the Linux build plan. The requested commit, tree, and commit timestamp
must match `HEAD`; the worktree must be clean; and every required build input
must exist inside that checkout.

The container receives exactly two bind mounts:

- the snapshot checkout at `/workspace`, read-only; and
- an isolated output directory at `/output`.

The adapter invokes the existing `preview-tree` and `preview-archive` targets.
It does not introduce another packager. Build output, the assembled bundle,
the archive, checksums, logs, and provenance remain outside the source tree.
The resulting evidence binds the snapshot commit and tree to the canonical
source commit, source inventory, build-environment digest, and archive name.

Inspect and validate the exact plan without starting Docker or a native build:

```sh
racket scripts/release/snapshot-build.rkt \
  --checkout <clean-snapshot-checkout> \
  --snapshot-commit <full-snapshot-commit> \
  --snapshot-tree <full-snapshot-tree> \
  --version <MAJOR.MINOR.PATCH> \
  --source-date-epoch <snapshot-commit-epoch> \
  --output <absent-output-directory> \
  --plan-only
```

Omitting `--plan-only` executes the declared environment check, pinned image
preparation, toolchain probe, existing bundle build, archive assembly, and
provenance recording. Native execution belongs to the final private rehearsal,
not ordinary slice validation.

## Snapshot-Bound User Guide

The standalone User Guide consumes the exact snapshot checkout or tag from
`odra/editor`. It does not synchronize documentation from the canonical
development checkout. Its source manifest records the snapshot repository,
reference, commit, tree, and the canonical source identity embedded in
`release/public-source-manifest.json`.

The guide repository owns documentation closure, authored Book order, Spore
projection, rendering, local-link validation, Pages staging, and deployment.
Candidate mode performs all stages through Pages staging in an isolated
workspace and retains a content-addressed site without changing the guide
checkout. Publish mode accepts an exact candidate identity, promotes only its
release metadata, and stages the same site bytes; it does not deploy them.

`scripts/release/user-guide-publication.rkt` is the Odra-side adapter. It plans
the companion candidate command and rejects returned evidence unless the
version, logical repository, snapshot commit and tree, canonical source commit,
manifests, and site digest match the release request. The later release
orchestrator can therefore compose the guide phase without taking ownership of
the companion repository's projection implementation.

Run the focused adapter contract check with:

```sh
make user-guide-publication-contract-test
```

## Artifacts

Each artifact has a unique logical name and relative storage path. It records
its media type, byte size, SHA-256 digest, and producing phase. Artifact paths
cannot be absolute, contain `..`, use backslash separators, or otherwise
escape the candidate root.

Artifacts are serialized by logical name so producer discovery order cannot
change the manifest digest.

## Phases

The ordered phase vocabulary is:

1. `request`
2. `preflight`
3. `export`
4. `snapshot-transfer`
5. `snapshot-validation`
6. `bundle-build`
7. `bundle-validation`
8. `guide-preparation`
9. `candidate-retention`
10. `source-publication`
11. `bundle-publication`
12. `guide-publication`
13. `public-verification`

A phase record contains its complete input digest, attempt number, state,
timestamps, evidence artifacts, and an optional structured failure. Terminal
states require a completion timestamp. Only a failed phase carries failure
detail.

Candidate rehearsals may mark public-access checks `unavailable` while the
target remains private. That state is not a successful public verification.

## Retained Candidates

Candidate mode stores phase state and validated artifacts in a private local
candidate directory. The directory is keyed by the complete candidate digest.
Its state records the release request digest, exact phase input digests,
ordered attempts, and retained artifact identities.

A retry reuses a passed phase only when its complete input digest matches. A
running phase with the same input remains running until the caller explicitly
marks the prior attempt as interrupted. A different input cannot replace a
running attempt. The workflow resumes at the first phase that has no reusable
passed attempt.

Snapshots, Linux bundles, rendered guide sites, manifests, and summaries can
remain in the candidate directory after a transfer or publication failure.
Each retained file must match its declared path, byte size, and SHA-256 digest
before it can become phase evidence. Candidate, attempt, artifact-count, and
total-byte limits bound local retention. State and textual evidence reject
credential-bearing fields, URLs, query parameters, and assignments.

Run the focused recovery check with:

```sh
make release-candidate-store-test
```

## Unified Workflow

`.forgejo/workflows/publish-release.yml` is the single manual release graph.
Its dispatch request requires a canonical version, an exact canonical source
commit, the `dev` or `main` branch whose current head proves that integration,
and either `candidate` or `publish` mode. Publish mode also requires the exact
confirmation `publish:MAJOR.MINOR.PATCH`. The workflow has no push,
pull-request, or scheduled trigger.

Candidate mode validates the runner, exports and audits the public source,
transfers and verifies the private snapshot candidate, builds and validates the
Linux bundle once, prepares the snapshot-bound User Guide, and retains the
combined candidate. It creates no release tag, package upload, or site
deployment. Publish mode addresses the same candidate identity and enables the
three credential-scoped publication jobs plus final public verification.

The runner configuration supplies credential-free repository and public URLs,
the private candidate-store path, the exact User Guide commit, and the exact
Spore repository and commit through Forgejo variables. The guide job builds
that pinned Spore source inside its workspace. Snapshot, package, and GitHub
publication credentials are repository secrets. The preflight, native build,
guide preparation, retention, and public-verification jobs receive no
publication secret.

Run the workflow contract check with:

```sh
make release-publication-workflow-test
```

## Canonical Encoding

The canonical form is compact UTF-8 JSON with lexically sorted object keys.
Artifact records are sorted by name and phase records follow the declared
phase order. SHA-256 over those exact bytes provides stable candidate and
manifest evidence independent of hash iteration or producer discovery order.

Run the focused contract check with:

```sh
make release-publication-identity-test
make release-candidate-store-test
make release-publication-workflow-test
make public-source-export-test
make public-source-snapshot-test
make snapshot-repository-lifecycle-test
make snapshot-build-adapter-test
make user-guide-publication-contract-test
```

These checks cover malformed identities, stable encoding, mode independence,
path safety, collection ordering, duplicate identities, terminal phase rules,
candidate recovery, bounded private retention, credential redaction, source
licensing, declared build closure, and exact exported-tree shape.
