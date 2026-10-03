<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Configure Personal Startup

Use `init.rkt` under the Odra configuration root to provide personal startup
configuration. The current implementation validates and records the startup
configuration state, evaluates the trusted Racket module within bounded startup
limits, and applies its admitted Status Bar, Gutter, and completion policies.

## Create the configuration root

Odra resolves the configuration root as:

```text
$XDG_CONFIG_HOME/odra/
```

When `XDG_CONFIG_HOME` is not set, Odra uses:

```text
$HOME/.config/odra/
```

Create only the root and the file you need:

```sh
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/odra"
```

## Add a minimal init.rkt

Create:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/odra/init.rkt
```

with:

```racket
#lang racket/base
```

An absent `init.rkt` is valid and silent. A present `init.rkt` must currently
start with `#lang racket/base`.

## Configure the Status Bar

Export one complete Status Bar policy from `init.rkt`:

```racket
#lang racket/base

(provide odra-status-bar-configuration)

(define odra-status-bar-configuration
  '#hash((position . line-column-percentage)
          (visible . (encoding pane-state workspace project editing-context))
          (compact . automatic)))
```

`position` also accepts `line-column` and `byte-offset`. `compact` also accepts
`prefer-compact` and `essential-only`. The `visible` list may contain each
admitted optional segment at most once. Omit the exported binding to retain the
complete factory policy.

This startup value configures factory presentation only. Programmable segment
providers use the separate runtime-scoped registration lifecycle documented in
the [Status Bar Reference](../../reference/status-bar/index.md); placing a
provider value in `init.rkt` does not register it.

## Organize a larger configuration

A single-file `init.rkt` remains valid. If the file grows, keep the entrypoint
small and require user-authored modules from it:

```racket
#lang racket/base

(require "settings/editor.rkt"
         "settings/keys.rkt")
```

The `settings/` directory is an organization convention, not a mandatory
schema. Odra does not require it and does not create it for an empty
configuration.

For a complete executable module, command contribution, and live reload
workflow, see [Define and Reload Personal Commands](../define-personal-commands/index.md).
For a declarative logical-line marker provider, see
[Configure and Reload a Programmable Gutter](../configure-programmable-gutter/index.md).
For the factory completion policy, see
[Configure and Diagnose Language Completion](../configure-language-completion/index.md).

## Configure language support

Export one complete declarative contribution to add a language and its server:

```racket
#lang racket/base

(require odra/languages)

(provide odra-language-support)

(define odra-language-support
  (language-support
   #:language 'zig
   #:suffixes '(".zig")
   #:server
   (language-service
    #:id 'zls
    #:command '("zls")
    #:root-markers '("build.zig"))))
```

This data does not start or stop a process while `init.rkt` is evaluated.
Odra validates and copies the complete candidate with the rest of the personal
configuration generation. An invalid contribution rejects that generation and
preserves the last confirmed configuration.

Maintained Odin, Racket, Go, and Rust support does not require a Personal
definition. Use this pattern for an additional language or a deliberate
complete replacement.

See the
[Language Support Configuration Reference](../../reference/language-support-configuration/index.md)
for modular multi-language composition, settings, environment, features,
explicit selections, limits, and failure behavior.

## Keep operational state separate

The same configuration root also contains Odra-managed operational state.
Do not treat these files as personal startup configuration:

```text
projects/
workspaces/
promotion-suppressions.rkt
migration.rkt
sessions/
state/
```

Project identity remains local to the promoted Dir:

```text
<project-dir>/.odra/project.rkt
```

Global Project files are discovery and recent-selection state. Workspace files
are stored globally because they compose several Projects. Neither kind is
loaded from `init.rkt`.

## Check startup feedback

On startup:

- missing `init.rkt` produces no message;
- a valid present `init.rkt` reports `Personal configuration loaded`; and
- invalid syntax or unsupported content reports a bounded rejection diagnostic
  and keeps the factory configuration active.

Fix the file and restart Odra to validate it again.

## Validate the repository contracts

For repository development, run:

```sh
raco test src/configuration/root.rkt src/configuration/personal.rkt tests/configuration/personal_test.rkt
raco test tests/configuration/example_test.rkt
make docs-check
```

See the [Configuration System Reference](../../reference/configuration-system/index.md)
for the exact path classes and ownership boundaries.
