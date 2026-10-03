<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Curate a Package Release

This procedure uses the public curator kit and CLI from an Odra source checkout.
It records evidence and a human decision without giving automation curation
authority or repository deployment access.

## Bootstrap a Governance Workspace

```sh
racket scripts/package-catalog-curator.rkt bootstrap \
  --output /path/to/catalog-governance
```

Replace every example identity, public verification key, endpoint, digest,
timestamp, and policy statement. Keep signing material and deployment
credentials outside the repository. Validate that the profile identity is
derived from the intended initial root public key.

## Review a Submission

1. Bind the submission to one exact package release, source revision,
   manifest, artifacts, dependency set, compatibility set, capability set, and
   contribution set.
2. Record deterministic tools, isolated execution, human review, or AI-assisted
   assessment as attributable evidence with exact input digests and limits.
3. Compare the semantic change with the last accepted assertion.
4. Have an authorized human curator accept, reject, or request changes under
   one exact policy generation.

Assessment output cannot accept a package, change policy, or sign a snapshot.

## Build and Validate a Publication

Prepare the repository module, then run:

```sh
racket scripts/package-catalog-curator.rkt dry-run \
  --repository /path/to/repository.rkt
racket scripts/validate-package-catalog-publication.rkt \
  --repository /path/to/repository.rkt
```

Review the added, changed, removed, and unchanged assertions before requesting
a signature. Publication must be deterministic for the same inputs.

## Exchange a Signature Offline

Prepare a snapshot request with the authorized publisher key identifier. The
command writes `.rktd` metadata and the exact domain-separated `.bin` bytes:

```sh
racket scripts/package-catalog-curator.rkt prepare-snapshot-signing \
  --repository /path/to/repository.rkt \
  --signing-key-id <publisher-key-id> \
  --output /path/to/exchange/snapshot
```

Sign the `.bin` file in the custody environment. Return only the detached
signature, then verify it before adding it to the publication record:

```sh
racket scripts/package-catalog-curator.rkt verify-signature \
  --request /path/to/exchange/snapshot.rktd \
  --public-key <publisher-public-key> \
  --signature <128-lowercase-hex-characters>
```

Use `prepare-root-rotation` or `prepare-publisher-rotation` for authority
changes. Both produce root-domain requests and preserve the catalog identity.

## Publish Locally and Check Mirrors

```sh
racket scripts/publish-package-catalog-snapshot.rkt \
  --repository /path/to/repository.rkt \
  --output /path/to/publication
racket scripts/package-catalog-curator.rkt validate-mirror \
  --origin /path/to/origin-snapshot.rktd \
  --mirror /path/to/mirror-snapshot.rktd
```

The publication command writes immutable local output only. Repository push,
hosting, and deployment remain separate authorized operations.
