<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Migrate Legacy Project State

## Preview the migration

From the Odra source checkout, run:

```sh
racket scripts/migrate-project-workspaces.rkt
```

The preview inventories legacy Project and candidate state below
`$HOME/.odra/`, computes the complete target plan, and reports Project,
Workspace, state, and rejection counts. It does not publish target records or
change source files.

Resolve every reported rejection before applying the plan. An unavailable
root can be retried after the Dir is restored. A conflicting local `.odra/`
requires explicit inspection because migration never overwrites unrelated
metadata.

## Apply the migration

Run the same command with explicit publication enabled:

```sh
racket scripts/migrate-project-workspaces.rkt --apply
```

A successful run writes local Project records, global discovery references,
Workspace records, candidate state, and the migration journal under the
current Odra configuration root. Legacy records remain byte-for-byte intact.

Run the command again after interruption or uncertainty. Exact published
targets are reported as `already-published`; staged or planned entries resume
from the journal without creating different identities.

## Use isolated roots

For inspection or recovery with nondefault locations, provide both roots:

```sh
racket scripts/migrate-project-workspaces.rkt \
  --legacy-root /absolute/legacy/root \
  --configuration-root /absolute/configuration/root
```

Add `--apply` only after the preview matches the intended sources and targets.

The command exits with status `0` when every admitted source is complete,
status `1` when publication fails, and status `2` when one or more sources are
rejected and remain retryable.
