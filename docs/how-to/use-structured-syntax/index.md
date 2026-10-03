<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Use and Validate Structured Syntax

Factory structural editing is available for file-backed paths whose suffix is
exactly `.odin` and whose retained analysis is current for the active buffer
revision. No separate structural mode or parser is required.

## Run the factory commands

Use the direct profile or invoke the same command identity through `M-x`:

| Command | Binding | Result |
| --- | --- | --- |
| `structural-forward` | `C-M-f` | Move to the end of the next named node. |
| `structural-backward` | `C-M-b` | Move to the start of the previous named node. |
| `structural-up` | `C-M-u` | Move to the start of the nearest strict named ancestor. |
| `structural-down` | `C-M-d` | Move to the start of the first named child. |
| `structural-select` | `C-M-SPC` | Select the smallest containing node or expand to an ancestor. |
| `structural-indent` | `M-x` | Indent the current line or active-region lines as one transaction. |

The bindings are ordinary replaceable direct-profile entries. Keymap
customization may replace them without changing command semantics.

## Inspect availability and failures

Run `describe-structural-state` through `M-x`. For a current Odin document,
confirm that capability availability is true and that buffer, source,
selection, parser, and tree generations are nonzero and current.

The remaining rows report grammar rules, point and region, the last copied
target, operation and indentation summary, traversal and indentation usage,
selected limits, and the latest rejection. Inspection never triggers analysis
or changes point, selection, text, or history.

For unsupported files or contained analysis failure, structural commands are
rejected without changing canonical state. Continue editing normally, then
inspect the latest rejection. After indentation publishes a text revision,
Odra refreshes analysis before accepting the next structural operation.

## Run focused native and programmable checks

From the repository root:

```sh
make structural-syntax-reference-test
make structural-syntax-equivalence-test
make structural-syntax-resource-study
make native-command-test
raco test src/command/structural.rkt src/hosting/structural-bridge.rkt
```

These commands verify the independent language model, resource ceilings,
editor and transaction adaptation, native/Racket parity, scoped authority,
failure containment, and cleanup.

## Run the real terminal workflow

Run the complete terminal suite:

```sh
make terminal-presentation-test
```

To run only the structured syntax PTY scenario:

```sh
make odra
ODRA_PTY_EXECUTABLE="$PWD/.build/odra" \
  raco test tests/structured_syntax_workflow/workflow_test.rkt
```

The focused scenario verifies every direct binding, `M-x` execution,
selection expansion, indentation, undo, redo, save, themes, syntax color,
multiple panes, resize, copied inspection, unsupported-file fallback,
teardown, and exit.

At a delivery boundary, run:

```sh
make check
make test
make docs-check
make verify
git diff --check
```

See the [Structural Editor Operations Reference](../../reference/structural-editor-operations/)
for native state changes and the
[Programmable Structural Commands Reference](../../reference/programmable-structural-commands/)
for the Racket boundary.
