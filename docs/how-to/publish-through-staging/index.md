<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Publish Development to Main

Use this procedure to publish integrated development work directly from `dev`
to `main` after explicit maintainer authorization.

```text
work branches -> dev -> main
                         |-- bounded Main Check
                         `-- exhaustive nightly
```

## Integrate work into dev

Merge completed feature, fix, documentation, and test pull requests into
`dev`. Use focused checks while implementing each change.

Before promotion, confirm that local `dev` matches `origin/dev` and that the
candidate contains no incomplete work.

## Prepare the dev candidate

Fetch the publication branches and inspect the candidate after the maintainer
authorizes publication:

```sh
git fetch origin dev main
git diff --check origin/main..origin/dev
```

Do not run `make verify` as a local publication gate. Focused slice checks own
development feedback; Forgejo owns integrated Main Check and nightly evidence.

## Publish dev to main

Open a `dev` to `main` pull request titled:

```text
chore(publish): align dev with main
```

Merge it after review. The maintainer controls the merge. The resulting `main`
push starts the bounded `Main Check` workflow.

## Observe integrated evidence

Main Check validates source and documentation hygiene and builds the integrated
application. A red run is a correction signal; it does not stop focused work
or authorize an automatic repair.

The exhaustive `make verify` suite runs in the non-blocking Nightly
Verification workflow. Do not wait for it before continuing ordinary focused
development.

When Main Check or nightly fails:

1. reproduce and diagnose the failed area from `dev`;
2. use focused checks while correcting it;
3. use `make verify-resume` only when explicitly reconciling an integrated
   nightly or release-candidate failure;
4. merge the correction into `dev`; and
5. publish the corrected `dev` candidate through another authorized pull
   request.

Run `make verify-resume-reset` only when abandoning the recorded local run or
when its evidence no longer applies. Its local state is not publication
evidence.

## Verify publication

Fetch the remote branches and confirm that `main` contains the selected `dev`
commit:

```sh
git fetch origin dev main
git merge-base --is-ancestor origin/dev origin/main
```

An ordinary `dev` to `main` publication does not authorize a SemVer tag or
release artifact. A stable release additionally requires a green exhaustive
nightly for the exact selected `main` commit and explicit maintainer approval.
