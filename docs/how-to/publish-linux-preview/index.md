<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Prepare and Publish an Odra Release

Use the manual `Publish Odra Release` workflow to prepare one source snapshot,
Linux x86-64 bundle, and User Guide candidate from an exact integrated Odra
commit. Candidate mode validates and retains the complete release without
creating final public state. Publish mode later consumes that same retained
candidate.

## Configure the Workflow Once

Set these Forgejo Actions repository variables:

| Variable | Value |
| --- | --- |
| `ODRA_RELEASE_CANDIDATE_STORE` | Private persistent directory writable by the runner. |
| `ODRA_SNAPSHOT_REPOSITORY_URL` | Credential-free clone URL for `odra/editor`. |
| `ODRA_SPORE_REPOSITORY_URL` | Credential-free clone URL for the Spore source repository. |
| `ODRA_SPORE_COMMIT` | Exact 40-character Spore commit used to build the renderer. |
| `ODRA_USER_GUIDE_REPOSITORY_URL` | Credential-free clone URL for the User Guide source repository. |
| `ODRA_USER_GUIDE_COMMIT` | Exact 40-character User Guide commit used to prepare the site. |

Candidate mode also requires these Actions secrets:

- `ODRA_SNAPSHOT_REPOSITORY_TOKEN` for the private snapshot repository; and
- `ODRA_USER_GUIDE_GITHUB_TOKEN` for the private User Guide source.

Publish mode additionally requires:

- `ODRA_PREVIEW_PACKAGE_TOKEN` for the Forgejo Generic Package;
- the `ODRA_USER_GUIDE_REPOSITORY`, `ODRA_PUBLIC_SNAPSHOT_URL`,
  `ODRA_PUBLIC_PACKAGE_URL`, and `ODRA_PUBLIC_USER_GUIDE_URL` variables.

Do not put credentials in workflow inputs, repository URLs, committed files,
or logs.

## Prepare a Candidate

Choose a canonical `MAJOR.MINOR.PATCH` version and an exact commit at the head
of `dev` or `main`. In Forgejo, open `Actions`, select `Publish Odra Release`,
and dispatch it from the revision that contains the intended release adapter.
Enter:

```text
version: MAJOR.MINOR.PATCH
source_commit: FULL_40_CHARACTER_COMMIT
source_branch: dev | main
mode: candidate
publish_confirmation:
```

The selected branch head must equal `source_commit`. Candidate mode then:

1. validates the request, runner, and private snapshot authority;
2. exports and audits the curated public source tree;
3. transfers and verifies a candidate commit in `odra/editor`;
4. builds, smokes, and audits the Linux bundle from that snapshot checkout;
5. prepares the matching Spore User Guide site; and
6. retains the source, binary, guide, manifest, and phase evidence under one
   candidate identity.

It does not update snapshot `main`, create a SemVer tag, upload a package, or
deploy the User Guide. Public verification is recorded as unavailable while
the targets remain private.

Follow the run in Forgejo. Do not start a concurrent request for the same
version and source commit. If a transient failure occurs, dispatch the exact
same request again from the same adapter revision. Passed phases whose complete
inputs and retained artifacts still match are reused; the native bundle is not
rebuilt.

## Publish the Retained Candidate

Publication requires separate maintainer authority. Before dispatching it,
confirm that the intended commit is the exact approved `main` commit and that
the repository's stable-release requirements have passed for that commit.

Dispatch `Publish Odra Release` again from the same adapter revision with the
same version, source commit, and `main` branch, then enter:

```text
mode: publish
publish_confirmation: publish:MAJOR.MINOR.PATCH
```

Publish mode promotes the retained snapshot to `odra/editor` `main` and its
immutable annotated tag, uploads the retained Linux files, publishes the
retained User Guide candidate, and checks the public source, package, and site
entrypoints. It fails rather than moving a tag or replacing different content.

## Build from the Released Source

After `odra/editor` is public, reproduce the release bundle from its annotated
tag in a clean checkout:

```sh
git clone https://forge.adrianpk.com/odra/editor.git odra-editor
cd odra-editor
git checkout --detach vMAJOR.MINOR.PATCH

snapshot_commit=$(git rev-parse HEAD^{commit})
snapshot_tree=$(git rev-parse HEAD^{tree})
source_date_epoch=$(git show -s --format=%ct HEAD)
adapter_commit=$(jq -r .source_commit release/public-source-manifest.json)

racket scripts/release/snapshot-build.rkt \
  --checkout . \
  --snapshot-commit "$snapshot_commit" \
  --snapshot-tree "$snapshot_tree" \
  --adapter-commit "$adapter_commit" \
  --version MAJOR.MINOR.PATCH \
  --source-date-epoch "$source_date_epoch" \
  --output ../odra-release-build
```

The adapter validates the clean snapshot, checks the pinned build environment,
uses the declared container image and resource limits, and writes the bundle,
checksum, logs, and provenance outside the checkout.

## Recover from Failures

- A preflight or authority failure creates no candidate work. Correct the
  request or repository configuration and repeat the dispatch.
- A failed source, bundle, or guide phase retains completed evidence. Repeat
  only the exact request after correcting the adapter or external condition.
- An identical snapshot or published artifact is an idempotent success.
  Different content at an immutable identity is a conflict.
- Never delete, force-update, or replace a complete published version. Correct
  a released defect with a new patch version.

The complete identity, retention, and phase schema is documented in the
[Release Publication Manifest Reference](../../reference/release-publication/index.md).
