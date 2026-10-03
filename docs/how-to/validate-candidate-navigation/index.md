<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Validate Candidate Navigation

Run these commands from the repository root.

## Check resource gates

```sh
make candidate-navigation-resource-study
```

The target fails unless command, session-buffer, Project-buffer, and
Project-file source kinds pass both selected profiles:

- ordinary: 256 candidates, two query components, 5 ms p99, and a 16 MiB peak
  memory gate;
- demanding: 4,096 candidates, eight query components, 100 ms p99, and a
  128 MiB peak memory gate.

Each profile also performs one complete refresh and requires zero cleanup
bytes. The target then runs the independent candidate oracle and the Project
history study, including entry, key, module, dirty-generation, retry, callback,
renormalization, and cleanup limits.

## Run the acceptance matrix

```sh
make candidate-navigation-acceptance
```

This target covers the independent models, generated production parity,
native source and owner suites, the real constrained Racket history boundary,
coordinator reload after owner restart, fault paths, deterministic teardown,
and PTY workflows for commands, buffers, and Project content.

## Run focused package tests

```sh
odin test tests/candidate_kernel
odin test src/interaction -vet -warnings-as-errors
odin test src/project -vet -warnings-as-errors
make hosting-test
```

Use the first command for model parity, `src/interaction` for session and
adapter ownership, `src/project` for enumeration and native history, and
`hosting-test` for Racket schema, publication, recovery, and copied-boundary
behavior.

## Replay terminal paths directly

Build the executable, then run the focused PTY suites:

```sh
make odra
ODRA_PTY_EXECUTABLE="$PWD/.build/odra" \
  raco test tests/command_navigation/navigation_test.rkt
ODRA_PTY_EXECUTABLE="$PWD/.build/odra" \
  raco test tests/buffer_session/navigation_test.rkt
ODRA_PTY_EXECUTABLE="$PWD/.build/odra" \
  raco test tests/project_context/command_workflows_test.rkt
```

These tests require util-linux `script`. A passing run reports no stderr,
restores the terminal, removes temporary state, and validates the visible
candidate labels, annotations, query behavior, actions, and cancellation.

## Interpret failures

Candidate diagnostics name the failed operation and typed failure code. Limit
failures include the selected limit and observed value. Stale source, session,
or owner failures require refresh or reopening; they must not be bypassed.

History load or publication failures include the native or Racket boundary
classification. Navigation remains available with process-local ordering. Do
not delete or rewrite a rejected Project history record while diagnosing it;
the loader deliberately avoids overwriting evidence it could not validate.

Finish with the repository gate:

```sh
make verify
git diff --check
```
