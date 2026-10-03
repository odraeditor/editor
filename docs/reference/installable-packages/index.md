<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Installable Package Reference

The installable package subsystem defines the inert manifest, exact release
resolution, verified archive acquisition, and durable inactive installation
shared by ordinary extensions and language-support packages. It also defines
authenticated private catalog and artifact transport plus restricted Racket
command preparation and activation. Lifecycle commands and remote package
publication use the same package identity and installed-state owner.

## Identity

A package identity is a bounded lowercase value composed of alphanumeric
segments separated by `.` or `-`. A release is the pair of package identity and
SemVer version. Repository paths, endpoint URLs, catalog order, installation
time, and display names do not participate in identity.

Both `extension` and `language-support` are package kinds. They use the same
manifest format, installed-state owner, activation-lock shape, operation
journal, reachability rules, and persistence path.

## Manifest

Manifest format 1 records:

- package identity, kind, display name, version, description, and SPDX license;
- publisher identity and exact 40- or 64-hex source revision;
- minimum and maximum compatible package API versions;
- supported platform and architecture pairs;
- required or optional dependencies with bounded SemVer constraints;
- the complete requested authority set;
- immutable artifact descriptors;
- an optional restricted Racket entrypoint;
- complete contribution summaries;
- bounded HTTPS documentation links; and
- managed-state compatibility and cleanup policy.

The manifest candidate is confirmed as one canonical value. Targets,
dependencies, authorities, artifacts, contributions, and documentation are
ordered by stable semantic identity. Duplicate targets, dependencies,
artifacts, contributions, and documentation roles reject rather than depending
on declaration order. `package-manifest->canonical-bytes` emits the inert
canonical record, and `package-manifest-digest` binds its complete contents to
one SHA-256 identity.

## Authority Taxonomy

The package authority contract owns the complete vocabulary shared by package
manifests, installed state, runtime grants, agent capabilities, language
bundles, and the native language-bundle bridge. The current identities are:

- `racket-extension`;
- `external-process`;
- `project-read`;
- `project-write`;
- `network-acquisition`; and
- `native-grammar`.

`src/package/authority-contract.rkt` is the Racket source of truth. It exports
the identities, stable comparison, set validation, and conversions between
public symbols and text. Persisted authority collections remain unique and
sorted by their public text. The schema sequence separately preserves the
native bridge ordinals, and `make package-authority-contract-test` checks the
Odin enum and decoder against that sequence.

Unknown authority text always rejects during decoding or construction.
Recognizing an authority does not grant it: installation remains inactive and
the existing local confirmation and runtime admission rules still decide each
grant. A new authority must be appended to the schema, fit the native bit-set
representation, acquire an explicit meaning and admission policy, and pass the
parity check before any consumer can use it. Renaming, reordering, or removing
an existing identity requires an explicit persistence and bridge migration;
it must not be performed as an ordinary vocabulary edit.

## Artifacts and Entrypoints

Artifact descriptors bind role, kind, normalized relative path, SHA-256 digest,
exact byte size, optional target, required authority, and immutable HTTPS
locations. Initial package artifacts are never executable. Absolute paths,
parent traversal, symbolic path components, invalid digests, and excessive
expanded size reject.

A Racket entrypoint names one declared `racket-module` artifact and the export
`odra-package-contributions`. Declared executable contributions require an
entrypoint, and an entrypoint requires the `racket-extension` authority. The
entrypoint must use `#lang racket/base`. It may require `odra/commands`,
`odra/agents`, other declared package modules, and the admitted direct Racket
libraries listed below. Its exported contribution list must match every
declared identity, facet, requirement, and effect exactly.

## Restricted Command Runtime

Preparation revalidates the installed package, manifest digest, entrypoint
digest and size, exact package authority grant, and requested contribution
generation. It then compiles and evaluates the entrypoint under a fresh
package-owned namespace, custodian, module resolver, security guard, empty
environment, bounded deadline, and bounded memory. Preparation creates an
unpublished candidate; neither loading nor successful validation changes the
active command catalog.

The package resolver materializes the complete declared `racket-module` tree
from verified content and admits package-relative imports within that tree. It
also admits the `racket/base` runtime closure, the public `odra/commands`
module, and these direct library modules: `db`, `file/sha1`, `openssl/sha1`,
`racket/contract/base`, `racket/date`, `racket/file`, `racket/format`,
`racket/list`, `racket/path`, `racket/port`, `racket/runtime-path`, and
`racket/string`. Every admitted module still executes in the same package
namespace, custodian, resolver, security guard, deadline, and memory limit.
Agent and capability definitions remain inert during preparation and
activation; only ordinary command turns are executable at this stage.

During preparation and command turns, filesystem access outside the declared
module tree, admitted Project root, configured package resources, and package
data root remains unavailable. Named resources are configured by the user in
`init.rkt`; see [Configured File Resources](authoring.md#configured-file-resources).
Network access, process execution, foreign-interface loading, inherited
environment values, and private Odra modules also remain unavailable. Project
read or write access is granted only when the manifest requests the matching
authority and the user confirms it. A command receives editor authority only
through its checked command context and declared requirements and effects.

Activation first composes the complete candidate catalog and rejects semantic
collisions. A successful publication binds the exact authority-grant and
contribution generations, invalidates the replaced generation, and makes the
new commands visible atomically. A failed or stale candidate preserves the
confirmed catalog. Deactivation removes the complete package contribution set
before retiring its namespace and custodian. Turns admitted before replacement
or deactivation may finish; no new turn can enter, and teardown occurs when the
last admitted turn exits.

## Exact Resolution

Catalog and manual sources converge on one installation candidate. The
candidate binds the confirmed manifest and digest to the exact package ID,
version, publisher, source revision, platform artifact, and provenance.
Catalog provenance retains exact catalog, snapshot, and assertion digests.
Manual provenance retains the resolved source generation and immutable content
identity without inventing a catalog assertion.
Bundled provenance retains the default-distribution identity, publisher, and
exact source revision without inventing catalog enrollment.

Any package, version, publisher, source, target, manifest, archive, or manual
content mismatch rejects before acquisition or installation.

## Default Distribution

Odra's default distribution can include official packages without compiling
their product policy into the editor core. A closed `#lang odra/config`
composition record declares its distribution identity, package runtime API
version, and an ordered set of exact package releases. Each package declaration
selects a canonical manifest, a target archive, and whether the distribution
activates it by default.

Manifest and archive paths are relative to the installed distribution. Parent
traversal, absolute paths, links, missing files, incompatible package APIs,
release mismatches, duplicate package identities, and changed archive bytes
reject during preflight. Preflight completes for the whole declaration before
the lifecycle installs or activates any package.

Accepted archives pass through the same acquisition, content-addressed
storage, installation, runtime preparation, contribution validation, and
activation owners used by catalog and manual packages. The local distribution
path replaces transport locations for this acquisition, so first startup does
not require network access or catalog enrollment. Confirmed state records the
package as `bundled` provenance. Restart restores it from verified local
content through the ordinary package lifecycle.

Bundling is a product-distribution decision. It does not grant private editor
access, create another extension system, imply eager loading, or make the
package part of the core compilation closure. A later catalog release can use
the same package identity and lifecycle for updates.

## Deterministic Archives

`produce-package-archive` accepts one confirmed manifest and exact target. The
source directory must contain the canonical `odra-package.rktd` plus exactly
the declared target-independent and target-specific artifacts. Missing,
additional, changed, linked, or special files reject.

The producer writes deterministic portable TAR metadata and deterministic Zstd
output. The manifest is the first archive member, followed by manifest-ordered
artifacts. Repeated production from the same source yields identical bytes and
archive digest.

Acquisition enforces archive digest and compressed size, normalized member
paths, exact order and count, regular-file type, per-member digest and size,
expanded-byte limits, cancellation, deadlines, redirects, and retries. It
stages privately, validates completely, and publishes immutable bytes below:

Catalog installation first performs a bounded bootstrap pass because the
canonical manifest is the first member of the archive whose digest it
describes. That pass verifies the complete compressed archive identity,
requires the manifest to be the first regular member, bounds total entries and
expanded bytes, verifies the catalog-pinned manifest digest, and publishes both
objects immutably. Full acquisition then reuses the verified archive and
validates the exact member set declared by the confirmed manifest.

```text
packages/
|-- content/
|   `-- sha256/<prefix>/<digest>
`-- staging/<operation-id>/
```

An existing digest path is reused only when its bytes verify. A collision
rejects without replacement. Successful and failed acquisition remove their
private staging directory.

## Private Transport

Catalog configuration and artifact bindings retain only an opaque credential
reference, provider identity, provider generation, HTTPS origin, and allowed
header names. Secret values are resolved for one request and are never copied
into catalog snapshots, package manifests, installed state, operation journals,
failures, or inspection projections.

The initial live provider reads an `Authorization` value from the process
environment. Its credential reference is the exact environment variable name.
The provider contract also supports local lookup and refresh implementations
for later keyring or secret-service adapters. Missing, expired, malformed, or
provider-rejected values fail before transport begins.

Credential headers are sent only to the configured HTTPS origin. A same-origin
redirect may retain them; a credentialed redirect to another host or port
rejects. A private artifact on another origin needs its own explicit binding.
Authentication never replaces catalog signatures, exact artifact digests,
manifest verification, compatibility checks, or local activation authority.

The factory official catalog is public and has no credential reference.
Independent private catalogs can attach an opaque credential reference to
their own endpoint without changing the catalog signature or trust model.

## Inactive Installation

Installation revalidates the acquired archive, canonical manifest, and every
content handle against the exact candidate. It first publishes an idempotent
`durable-install` operation journal, then atomically publishes the installed
record as `installed-disabled`. Requested authorities remain ungranted,
contribution generation remains zero, and the package entrypoint is never
evaluated.

Repeating the same exact installation is idempotent. Reusing one package ID and
version for different immutable content rejects and quarantines the acquired
digests. Other verification failures likewise retain bounded quarantine
references without creating an installed record.

## Installed State

Editor-managed package state is stored below the data root as:

```text
packages/
`-- state.rktd
```

The state contains exact installed releases, provenance, manifest and artifact
digests, dependencies, requested and granted authorities, lifecycle state,
contribution generations, activation locks, operation journals, quarantine
references, accounting, migration provenance, and checksums.

Only `active-confirmed` packages may appear in the current activation lock.
The previous lock may retain an installed or rollback-available release.
Installed, active, rollback, pending, pinned, and quarantined content remains
reachable. Garbage collection returns only immutable digests outside the
complete reachable set.

## Lifecycle Commands

Package commands accept the public package identity or an exact release written
as `package.name@1.2.3`. They never require catalog registration IDs, snapshot
digests, operation IDs, or content digests.

| Command | Result |
| --- | --- |
| `package-list` | List installed releases with lifecycle, publisher, and authority state. |
| `package-discover` | Refresh first-use catalog state when needed, open confirmed releases, and filter them incrementally. Selecting one verifies and installs that exact release, then offers its authority transition. |
| `package-describe` | Inspect one package or exact release, including provenance and lifecycle. |
| `package-install` | Select and install an exact resolved release as `installed-disabled`. |
| `package-enable` | Confirm requested authority and atomically activate one installed release. |
| `package-disable` | Remove active contributions while retaining verified installed content. |
| `package-update` | Activate an installed update and retain the prior confirmed release. |
| `package-rollback` | Revalidate and activate the retained prior release. |
| `package-remove` | Mark one inactive, unrequired release as removed. |
| `package-cleanup` | Delete only content outside the complete reachability set. |
| `package-doctor` | Report empty, healthy, recovery, missing-manifest, and degraded state. |

Selecting an exact release is sufficient installation intent. Refreshing or
disabling a catalog and disabling a package are also direct, reversible
operations. Adding catalog trust, enabling requested package authorities,
updating or rolling back active code, removing content, and cleanup retain
explicit confirmation. In the guided discovery flow, Odra verifies and installs
the selected release as inactive, then asks once before granting the displayed
authorities and activating it.
Discovery, installation, and activation remain separate internal transitions:
installation does not evaluate package code, and only confirmed enablement
grants authority and publishes contributions.

The lifecycle owner persists each confirmed generation and binds activation to
monotonic authority-grant and contribution generations. Update retains the
previous activation lock for bounded rollback. Restart reloads canonical
manifests from verified content-addressed storage and reconstructs only the
packages named by confirmed active state. A missing or invalid manifest yields
an actionable degraded diagnosis rather than silently dropping or activating
code.

Activating, updating, rolling back, disabling, or removing a command package
also republishes the editor command registry. Package commands therefore enter
or leave the ordinary `M-x` and modal command surfaces without an editor
restart. Dispatch still resolves the active package generation and runs through
the same checked command context and edit transaction as personal Racket
commands.

See [Package Authoring](authoring.md) for the canonical source layout, release
archive, and publication handoff.

## Persistence and Recovery

State and activation-lock payloads have deterministic SHA-256 checksums.
Publication uses private staging, complete decode validation, file
synchronization, atomic replacement, and parent-directory synchronization.

Startup behavior is explicit:

- a valid state with no unfinished operation is `confirmed`;
- one idempotent unfinished phase is `resume-operation`;
- an ambiguous publication with a valid previous lock is
  `rollback-previous`;
- malformed generic state is quarantined and enters recovery-only behavior;
- safe mode never migrates or activates state; and
- missing required immutable content blocks migration without changing the
  legacy source.

An interrupted final installation publication leaves the prior active state
unchanged and the durable operation journal resumable. Installation recovery
removes that abandoned journal in a new atomic state generation; unreferenced
content becomes eligible for the separate reachability-based cleanup path.

## Language-Bundle Migration

When generic state is absent, a valid language-bundle v2 state can be adapted
into package state with `kind = language-support`. The adapter preserves
package identity, version, manifest and artifact digests, exact dependency
versions, publisher and source identity, platform, architecture, authorities,
lifecycle, contribution generations, locks, operations, quarantine, and
accounting.

Migration rejects missing or ambiguous dependency versions. It publishes one
checksummed generic candidate atomically and retains the language-bundle state
as the recovery source. Repeated startup reads the confirmed generic state and
does not rewrite or remove the legacy record.

## Limits and Failures

Manifest and state owners bound identities, text, targets, dependencies,
authorities, artifacts, contributions, documentation, installed releases,
operations, content references, failure text, and aggregate expanded bytes.
Invalid input raises a constructor contract failure or returns a typed manifest
or migration rejection before managed state changes.

Persistence failures report the failed phase and publication certainty.
Partial writes do not replace current state and do not leave staging files.
Ordinary diagnostics contain semantic identities and bounded failure details,
not credentials or package source text.
