<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Configure and Validate Factory Syntax Presentation

Factory Odin syntax presentation is active automatically for file-backed paths
whose suffix is exactly `.odin`. This MVP has no user-facing language-package,
theme, or runtime toggle. Configuration is limited to terminal color capability;
native provider lifecycle operations remain an integration boundary for later
extensions.

## Select terminal color capability

Odra derives one explicit renderer capability when the process starts. Set the
environment before launching the editor:

```sh
COLORTERM=truecolor TERM=xterm-256color .build/odra example.odin
```

The selection order is:

1. `NO_COLOR` present or `TERM=dumb`: monochrome;
2. `COLORTERM=truecolor`, `COLORTERM=24bit`, or a true-color/direct `TERM`:
   true color;
3. a `TERM` containing `256color`: indexed 256 color;
4. any other nonempty `TERM`: basic 16 color; and
5. no capability hint: monochrome.

To test the deliberate monochrome fallback:

```sh
NO_COLOR=1 TERM=xterm-256color .build/odra example.odin
```

Attributes remain available in monochrome. Syntax providers never select ANSI
codes or concrete palette entries.

## Inspect the active state

Open `M-x`, run `describe-language-state`, and inspect the copied rows. For an
ordinary `.odin` file, confirm:

- `Language: odin`;
- `Provider: factory-odin-tree-sitter`;
- equal confirmed, parse, and syntax source revisions after maintenance;
- `status=Current` when analysis is current;
- the renderer color capability expected from the environment; and
- no pending work or latest rejection during steady state.

For `.ODIN`, unassociated buffers, and other suffixes, expect plain text. The
suffix comparison is case-sensitive.

## Reproduce dependency selection

Run the offline integrity and link checks used by ordinary builds:

```sh
make syntax-vendor-check syntax-vendor-build
```

To reproduce the selected upstream revisions with network access:

```sh
make syntax-dependency-study
```

The networked study downloads Tree-sitter `v0.26.12` and the Odin grammar
`v1.3.0` into temporary storage, verifies commits, licenses, ABI compatibility,
and selected digests, then removes the downloaded inputs. It does not replace
the vendored production sources.

## Run focused parser and resource checks

```sh
make syntax-reference-test
make syntax-resource-study
make tree-sitter-resource-study
```

These targets cover registry lifecycle, revision validation, initial and
incremental parsing, full-refresh fallback, capture normalization,
cancellation, work limits, allocation accounting, and zero-byte teardown.

## Run terminal acceptance

Build the executable and run the complete presentation target:

```sh
make terminal-presentation-test
```

For only the factory syntax PTY scenario:

```sh
make odra
ODRA_PTY_EXECUTABLE="$PWD/.build/odra" \
  raco test tests/syntax_presentation/presentation_test.rkt
```

The focused PTY test forces true color and verifies real Odin categories,
editing, undo, redo, save, search, region precedence, viewport movement,
multiple views, resize, inspection, unsupported text, and terminal cleanup.

At a delivery boundary, run:

```sh
make docs-check
make verify
git diff --check
```

See the [Tree-sitter Odin Analysis Reference](../../reference/tree-sitter-odin-analysis/)
for pinned inputs and parser ownership, and the
[Semantic Syntax Presentation Reference](../../reference/semantic-syntax-presentation/)
for roles, styles, projection, and color degradation.
