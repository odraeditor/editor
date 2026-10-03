<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Validate the Extensible UI Foundation

Run commands from the repository root. The delivered system has separate gates
for the independent lifecycle model, production equivalence, source-verified
consumer migration, resource evidence, and complete repository acceptance.

## Check the independent model

Run the fixed-array lifecycle oracle:

```sh
make ui-reference-test
```

The suite covers root replacement, surfaces, view kinds, split composition,
status regions, model-owned and view-local list selection, transient focus
capture and return, stale generations, atomic rejection, accounting, and exact
teardown.

## Check production equivalence

Compare the production registry with the independent oracle over generated
valid and invalid operation sequences:

```sh
make ui-equivalence-test
```

Every valid sequence must produce equivalent roots, focus, and lifecycle state.
Every invalid replacement must preserve the previously published generation.

Run the focused production package checks while editing:

```sh
odin check src/ui -no-entry-point -vet -warnings-as-errors
odin test src/ui -vet -warnings-as-errors
```

The package tests include ownership, generation, focus, resource, snapshot,
allocation-fault, immutability, and cleanup cases.

## Validate transient input and prompts

Check the prompt semantic model and shared UI contracts independently:

```sh
odin test src/interaction -vet -warnings-as-errors
odin test src/ui -vet -warnings-as-errors
odin check src/odra -vet -warnings-as-errors
```

Then run the repository-owned terminal integration target:

```sh
make terminal-presentation-test
```

The native suite must cover every prompt and search-entry mode, fixed-choice
command resolution, Unicode and empty input, stale generations, nested
rejection, focus return, root-edge geometry, narrow labels, allocation failure,
accounting, query-replacement actions, search status, and teardown. The PTY
suites must preserve save, open, kill, marked operation, Project, exit, keymap
inspection, incremental search, regexp search, query replacement,
dirty-protection, resize, and multiple-pane behavior.

Confirm that every current consumer uses the shared pipeline and that the
superseded presentation entry points remain absent:

```sh
make ui-migration-check
```

The gate checks ordinary panes, Startup, Buffer Menu, Project inventory,
keymap inspection, candidate navigation, transient input, generic terminal
lowering, and programmable role boundaries. Then run the focused search
workflows:

```sh
ODRA_PTY_EXECUTABLE="$PWD/.build/odra" raco test tests/search/incremental_terminal_test.rkt
ODRA_PTY_EXECUTABLE="$PWD/.build/odra" raco test tests/search/regexp_terminal_test.rkt
ODRA_PTY_EXECUTABLE="$PWD/.build/odra" raco test tests/search/query_replacement_terminal_test.rkt
```

Verify that search labels and input values are separate logical surfaces,
query response exposes five checked actions, diagnostics use a semantic
root-edge status, and current-search styling overrides only overlapping active
region cells.

## Reproduce representation and limit evidence

Run the complete current-consumer and programmable-role resource gate:

```sh
make ui-resource-gates
```

This includes the UI registry, programmable roles, multiple views, Project,
candidate navigation, editor sessions, search, layouts, keymaps, display
projection, and terminal output. Ordinary, demanding, and stress profiles must
remain within their latency, memory, snapshot, crossing, render, and cleanup
gates.

For a focused registry-only rerun, use:

```sh
make ui-resource-study
```

Direct generational lookup must remain the selected registry representation,
packed snapshots must remain within the selected snapshot ceiling, over-limit
inputs must reject explicitly, and final retained bytes must be zero.

Validate copied role inspection, provider selection, fallback, and the
programmable resource profiles separately:

```sh
make ui-role-resource-study
```

See [Validate Programmable UI Roles](../validate-programmable-ui-roles/index.md)
for the focused mixed-language fixture and containment gates.

## Check public package documentation

Run:

```sh
make docs-check
```

This renders `src/ui` with the other public Odin packages and checks that every
public declaration has usable documentation.

## Run the complete repository gate

Run the complete UI acceptance matrix when you need the UI boundary without
the repository static and documentation gates:

```sh
make ui-acceptance
```

This gate includes the independent model, generated equivalence, properties,
allocation faults, stale generations, native and Racket integration, PTY
presentation, resize, output failure, end-to-end workflows, resource profiles,
and teardown.

At the pull-request boundary, run the repository gate once instead:

```sh
make verify
git diff --check
```

`make verify` invokes `ui-acceptance`, then adds static checks and documentation
validation. Do not run both commands back to back when `make verify` is the
selected boundary. Record the complete integrated result rather than treating
an isolated focused rerun as equivalent. Rerun the complete matrix after a
substantive review change; use focused gates while implementing individual
tasks.

See [Extensible UI Foundation Reference](../../reference/extensible-ui-foundation/index.md)
for the exact contracts and [Why the UI Foundation Publishes Complete Logical Generations](../../explanation/extensible-ui-foundation/index.md)
for the publication and ownership rationale.
