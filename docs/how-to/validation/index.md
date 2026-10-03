<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Validate the Editor Core

Run commands from the repository root.

## Use focused checks during development

```sh
make syntax-workflow-test
make language-workflow-focused-test
```

Run the smallest target that owns the changed behavior. Language recognition
and language-service changes use the static package targets above; they do not
build or link the complete editor executable. Racket test compilation is
retained in ignored `compiled/` directories for the current worktree.

`make verify` is the exhaustive scheduled-nightly command. Do not run it during
ordinary implementation or slice closure.

## Queue exhaustive work outside development

After focused checks pass, select one exact integrated candidate and leave its
exhaustive verification to Forgejo after the development window. Do not wait
for the run during implementation. Inspect it at the start of the next window.

Run a complete acceptance locally only when explicitly required. Use the same
150-minute deadline as the nightly, ensure Forgejo is inactive, and use no
`MemoryHigh`, `MemoryMax=90%`, and `MemorySwapMax=0`. Do not repeat exhaustive
acceptance after each focused correction.

## Resume local verification after a failure

Use the resumable gate only when explicitly reconciling a nightly or release
candidate failure locally:

```sh
make verify-resume
```

The command records each successful verification step under `.build/`. After a
failure, running it again skips the recorded steps and retries from the failed
or next unseen step. A completed run starts clean on the next invocation.

Discard an incomplete run explicitly with:

```sh
make verify-resume-reset
```

The local ledger is an iteration aid: it does not invalidate earlier successes
after source changes and is not publication evidence. Forgejo owns the
exhaustive result from a fresh `main` checkout.

## Inspect generated API documentation

```sh
odin doc src/text -in-source-order
odin doc src/editor -in-source-order
odin doc src/transaction -in-source-order
odin doc src/history -in-source-order
odin doc src/bridge -in-source-order
odin doc src/hosting -in-source-order
odin doc src/command -in-source-order
odin doc src/search -in-source-order
odin doc src/project -in-source-order
odin doc src/editor_session -in-source-order
```

These commands show public declarations and their source comments. Private
implementation details should not appear. Odin requires test cases to remain
public to its test runner, so package test procedures also appear and carry
comments describing the guarantee they verify.

Run only the documentation gate with:

```sh
make docs-check
```

This generates Odin documentation metadata under ignored `.build/docs/` state
and verifies local Markdown links under `docs/` and `ops/`.

## Validate the Racket boundary

Run the focused correctness and evidence gate with:

```sh
make hosting-evidence
```

This runs Racket module contracts, the production lifecycle and command
scenarios, startup failures, the retained host comparison, ordinary command
measurements, and forced-GC command measurements.

## Run the benchmark separately

```sh
make benchmark
```

The benchmark is not part of `make verify`. Record the Odin version, operating
system line, corpus size, operation count, throughput, latency percentiles,
and persistent-memory measurements when comparing runs.

`make hosting-benchmark` is also not part of `make verify`; it is included by
`make hosting-evidence`.

Run the complete transaction evidence with:

```sh
make transaction-benchmark
```

This runs the single-buffer splice profiles and the 1,000-buffer and
10,000-buffer publication profiles. It fails when a publication latency exceeds
its recorded gate or when cleanup retains accounted transaction storage.

Run only the deterministic generated proposal corpus with:

```sh
make transaction-fuzz
```

The command prints its fixed seed and case count so a failure is reproducible.

## Validate reversible history

Run the focused native suites with:

```sh
odin test src/history -vet -warnings-as-errors
odin test src/transaction -vet -warnings-as-errors
```

These cover record and link reservation, allocator faults, cancellation,
single- and multibuffer undo and redo, branch selection, selective undo,
pruning, Unicode normalization, exact accounting, and teardown.

Run the retained-history model and resource evidence with:

```sh
make history-fuzz
make history-resource-study
make multibuffer-history-benchmark
```

The linked benchmark executes 1,000-participant demanding and
10,000-participant stress profiles. Each line reports reservation and no-fail
finalization latency, accounted peak bytes, retained link count, and cleanup
bytes. A valid run reports one retained shared link and zero cleanup bytes.

Validate the Racket policy and navigation facade with:

```sh
make hosting-test
```

Validate programmable search values, policy reload, semantic invocation,
failure containment, and the dedicated boundary measurement with:

```sh
raco test src/command/search-bridge.rkt src/command/search.rkt
make native-command-test
make search-command-benchmark
```

The search benchmark runs 64 warmups and 512 measured scope calls. It fails
when p99 exceeds the recorded 8 ms gate, when any callback is missing, or when
the adapter does not report zero retained native bytes.

Validate the visible semantic undo workflow with:

```sh
make terminal-presentation-test
```

This target also runs the factory structured syntax PTY workflow. To isolate
that workflow after building Odra, run:

```sh
make odra
ODRA_PTY_EXECUTABLE="$PWD/.build/odra" \
  raco test tests/structured_syntax_workflow/workflow_test.rkt
```

The scenario covers direct and `M-x` structural commands, selection,
indentation, undo, redo, themes, syntax presentation, multiple panes, resize,
inspection, unsupported-file fallback, teardown, and exit. See
[Use and Validate Structured Syntax](../use-structured-syntax/) for the native,
Racket, resource, and repository gates.

## Validate candidate navigation

Run the focused production resource and acceptance gates with:

```sh
make candidate-navigation-resource-study
make candidate-navigation-acceptance
```

The first command enforces all four factory-source latency, memory, refresh,
history, callback, retry, and cleanup profiles. The second combines independent
models, generated parity, native and Racket suites, restart and fault behavior,
and terminal PTY workflows. See
[Validate Candidate Navigation](../validate-candidate-navigation/) for the
individual commands and diagnostic interpretation.

## Validate pane layouts

Use the focused runtime probe while iterating and the complete layout gate when
finishing layout work:

```sh
make layout-acceptance-runtime
make layout-acceptance
```

See [Validate Pane Layouts](../validate-pane-layouts/) for the native, Racket,
PTY, resource, restart, cleanup, and repository-gate procedure.
