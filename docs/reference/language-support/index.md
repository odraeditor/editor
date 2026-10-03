<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Language Support Reference

This is the uniform discovery point for every language in Odra's basic pack.
Each page records the same identity, provider, setup, capability, inspection,
recovery, and version fields. Installed bundles use the same inspection model.

## Basic Language Pack

| Language | Bundle | Selectors | Local syntax | External service |
| --- | --- | --- | --- | --- |
| [Jan](jan/index.md) | `org.odra.jan` | `.org`, `.jan` | Tree-sitter plus native Jan analysis | none |
| [Odin](odin/index.md) | `org.odra.odin` | `.odin` | Tree-sitter Odin | `ols` |
| [Racket](racket/index.md) | `org.odra.racket` | `.rkt` | Tree-sitter Racket | `racket -l racket-langserver` |
| [Go](go/index.md) | `org.odra.go` | `.go` | Tree-sitter Go | `gopls serve` |
| [Rust](rust/index.md) | `org.odra.rust` | `.rs` | Tree-sitter Rust | `rust-analyzer` |
| [JavaScript](javascript/index.md) | `org.odra.javascript` | `.js`, `.jsx`, `.mjs`, `.cjs` | JavaScript and JSX | `typescript-language-server --stdio` |
| [TypeScript](typescript/index.md) | `org.odra.typescript` | `.ts`, `.tsx`, `.mts`, `.cts` | TypeScript and TSX | `typescript-language-server --stdio` |
| [HTML](html/index.md) | `org.odra.html` | `.html`, `.htm` | HTML plus script/style injections | `vscode-html-language-server --stdio` |
| [CSS](css/index.md) | `org.odra.css` | `.css` | Tree-sitter CSS | `vscode-css-language-server --stdio` |

## Shared Behavior

- Recognition and local syntax do not launch an external process.
- Factory bundles are included and enabled without Personal configuration.
- External services start only for admitted trusted Projects.
- Executables use direct argument vectors; Odra does not invoke a shell or
  install a compiler, SDK, package, or server as a side effect.
- Missing or failed services preserve ordinary editing and local syntax.
- `M-x describe-language-support` reports association, bundle, provider,
  service, formatter, capability, origin, generation, and failure evidence.
- `M-x describe-language-service` reports the selected session;
  `M-x restart-language-service` spends one bounded explicit restart.
- `C-M-i` requests completion. The Direct `C-c C-l` and Modal `g l` maps route
  common semantic commands when the required capability is available.

Personal and trusted Project definitions can replace complete lower-precedence
definitions. They do not patch Factory fields. See the
[Language Support Configuration Reference](../language-support-configuration/index.md).

## Installed Languages

An installed bundle contributes languages to the same effective catalog. Use
`M-x language-bundle-list`, `M-x describe-language-bundle`, and
`M-x describe-language-support` to discover its exact origin and support.
Bundle-provided documentation should use the same headings as the pages above
and be linked from its inspection record.

For installation, trust, lifecycle, commands, keybindings, and the authoring
API, see the [Language Bundle Reference](../language-bundles/index.md).

## Playground Verification

Keep manual language Projects under `~/Projects/playground/odra/`, with a
separate trusted root for each root-marker policy. For each language, open a
matching file, confirm local syntax before the service starts, inspect support
and service health, exercise one declared capability, then verify the document
remains editable when the executable is unavailable.
