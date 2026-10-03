<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Verification Evidence Reference

The native workflow producer exports bounded verification records for the
separate Evidence ledger. It observes existing commands and release job results.
It does not dispatch checks, publish a release, or write to the ledger.

## Workflow Identity

| Workflow | Recorded phases |
| --- | --- |
| `odra/main-check` | Source hygiene, documentation, build, Project and Workspace migration |
| `odra/nightly` | Source hygiene, compile checks, UI migration, test suite, hosting, documentation |
| `odra/release` | The thirteen product jobs from preflight through public verification |

Candidate and publication runs share `odra/release`. Their execution inputs
include the selected mode and version. Each phase has a stable identifier,
operation class, and definition version. Display labels and shell-block position
do not define identity.

The canonical encoding, validator, and registries are pinned to Evidence commit
`9fc02187596112605dd1b3bb764be2e8b68eaf32`. The producer definition records this
pin and its observation policies. Changed policies require an updated producer
definition; changed registered workflows require matching registry changes.

Execution fingerprints include source identity, observed tools, declared build
configuration, available artifact inputs, and phase input digests. Attempt IDs,
observation timestamps, and logical source refs do not change those fingerprints.
An immutable run identity also includes its actual observations and attempt.

## Main Check and Nightly Commands

The workflow starts a private session with:

```sh
racket scripts/evidence/producer.rkt \
  --directory .build/verification-evidence \
  --workflow odra/main-check --commit "$(git rev-parse HEAD)" \
  --ref main --attempt forgejo-native:odra/odra:420 start
```

The supported actions are:

| Action | Required inputs | Result |
| --- | --- | --- |
| `start` | `--directory`, `--workflow`, `--commit`, `--attempt` | Creates a new session for an exact clean source checkout |
| `prepare` | `--directory`, `--stage` | Records input fingerprints and pressure samples before execution |
| `observe` | `--directory`, `--stage`, `--exit-code`, `--finished-ms`, `--metrics` | Records the original command result and available measurements |
| `skip` | `--directory`, `--stage` | Records a known phase that was not executed |
| `finish` | `--directory` | Validates and atomically publishes the final `bundle/` directory |

`--source-root` defaults to the current directory. `--ref` defaults to
`detached`. Workflow and phase identities must exist in the pinned registry.
Session and final bundle destinations must be new.

`bash scripts/evidence/run-stage.sh <phase> -- <command> [arguments...]` wraps
each owned Main Check or nightly stage. With no usable evidence session, it
executes the command directly. Preparation, measurement-file, and observation
failures do not retry the command or replace its exit code.

Exit zero records `passed`; 124 records `timed-out`; conventional crash exits
134 and 139 record `crashed`. Other nonzero exits record `failed`.
Missing phase observations record `unavailable` and make the bundle partial.
Phases explicitly skipped after the nightly deadline record `skipped`.

## Measurements and Input Privacy

GNU time supplies CPU user and system milliseconds and peak RSS bytes when
available. Peak RSS is the value reported by GNU time for the reaped command,
not a simultaneous sum of every descendant's memory. Wall time covers stage
preparation through observed command completion.

Linux PSI samples are deltas of host-wide cumulative microsecond counters for
CPU, memory, and I/O pressure. They describe the host during a phase, not
pressure attributable exclusively to that command.

Unobserved CPU/RSS, I/O bytes, process counts, and cache decisions remain absent
or explicitly unknown. No missing measurement becomes zero. Main Check and
nightly do not retain output artifacts; this limitation is explicit.

Available input files contribute content digests: publication policy and
closure, the Linux build environment, the product-module manifest, the Racket
runtime archive, Tree-sitter, and the terminal vendor archive. Allowlisted build
overrides contribute a digest only. No raw overrides, credentials, runner
names, host paths, commands, or command logs enter the bundle.

Metadata probes use GNU timeout in foreground mode with a five-second deadline
and a one-second termination grace. Probe output is capped at 16 KiB. Foreground
mode preserves reliable subprocess completion notification in the Racket host.

## Candidate and Publication Observation

`scripts/evidence/release-producer.rkt --source-root <checkout> --output <bundle>`
reads the exact source checkout and the existing candidate state. It does not
create or modify that state.

The workflow provides `ODRA_EVIDENCE_SOURCE_COMMIT`,
`ODRA_EVIDENCE_ADAPTER_COMMIT`, `ODRA_EVIDENCE_VERSION`,
`ODRA_EVIDENCE_RELEASE_MODE`, `ODRA_EVIDENCE_RUN_ID`,
`ODRA_EVIDENCE_STARTED_AT`, `ODRA_EVIDENCE_CANDIDATE_ID`,
`ODRA_EVIDENCE_NEEDS`, and `ODRA_RELEASE_CANDIDATE_STORE`.
Candidate version must match the requested version.

Current Forgejo job results determine each phase outcome. Retained candidate
phase inputs contribute semantic fingerprints, not replacement results.
An unchanged prior successful phase can establish reuse when every mapped
phase is present and predates this attempt. Other cache decisions remain
unknown.

The overall observed interval begins during request validation and ends at
bundle finalization. Individual release-job timing and resource measurements
are unavailable. Observed tool versions describe the collector host; the
pinned build-environment digest describes the declared build container.
Neither is presented as measured compiler telemetry from inside that container.

Retained artifact metadata exports name, size, content digest, media type,
and a logical `odra-candidate` storage reference. Private filesystem paths are
omitted. Artifacts are not downloaded or revalidated by this observer.

## Bundle and Failure Boundary

The final directory contains `bundle.json`, `run.json`, `steps.jsonl`, and
`summary.md`. It appears only after validation against the pinned contract.
Maximum bundle size is 8 MiB, individual file size 1 MiB, file count 256, and
step count 4096. Native output contains four files and four, six, or thirteen
phase records. Release job input JSON is bounded to 64 KiB; candidate state
is bounded to 1 MiB; artifact metadata is bounded to 32 entries.

Each eligible workflow uploads one finalized bundle as
`verification-evidence-<workflow>-<run-id>`. A non-admitted nightly uploads no
native bundle. Cancellation or runner loss can prevent finalization or upload;
absence is not evidence of successful verification.

Evidence steps have one-minute limits and use step-level
`continue-on-error: true`. The release observer has a ten-minute job limit and
no product job depends on it. Forgejo does not implement job-level
`continue-on-error`; each observer step therefore owns this setting.
Ordinary evidence-step failure does not change product-command results.
Runner provisioning and infrastructure failures remain workflow-level events.
[Forgejo compatibility reference](https://forgejo.org/docs/latest/user/actions/github-actions/).

The release observer is enabled only after successful preflight. No bundle is
claimed for an attempt that cannot establish its source and candidate identity.

## Focused Validation

`make verification-evidence-test` checks identity, bounded finalization,
privacy, command-result preservation, release outcomes, source admission,
candidate-state immutability, and workflow failure isolation. It does not
compile the editor or execute a remote workflow.
