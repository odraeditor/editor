<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Configuration System Reference

Odra resolves configuration, state, cache, package-data, Project-catalog, and
legacy Project roots once during startup. Racket owns the platform policy and
passes one confirmed absolute-path record to the native runtime.

On Linux, the roots are:

```text
configuration       $XDG_CONFIG_HOME/odra/
state               $XDG_STATE_HOME/odra/
cache               $XDG_CACHE_HOME/odra/
package data        $XDG_DATA_HOME/odra/
Project catalog     $XDG_CONFIG_HOME/odra/
legacy Projects     $HOME/.odra/projects/
```

Each absent XDG variable uses its standard home-relative fallback:

```text
configuration       $HOME/.config/odra/
state               $HOME/.local/state/odra/
cache               $HOME/.cache/odra/
package data        $HOME/.local/share/odra/
```

On macOS, configuration, package data, and the Project catalog use
`$HOME/Library/Application Support/Odra/`; state uses its `State/` child and
cache uses `$HOME/Library/Caches/Odra/`.

On Windows, configuration and the Project catalog use `%APPDATA%\Odra\`.
Package data uses `%LOCALAPPDATA%\Odra\`, with state and cache in its `State\`
and `Cache\` children. The legacy Project root remains `.odra\projects\` below
the user profile on every platform for compatibility.

User-authored configuration and editor-managed catalog records can share the
configuration root. Package state and candidate history use their dedicated
data and state roots.

## Entrypoint

The canonical personal configuration entrypoint is:

```text
init.rkt
```

relative to the resolved configuration root.

An absent `init.rkt` means no personal configuration has been provided. It is
not an error by itself.

`init.rkt` is user-authored functional configuration. It is distinct from
Odra-managed Racket files used for Project discovery, Workspace composition,
promotion suppression, migration, sessions, and candidate state.

The current accepted form is a Racket module beginning with:

```racket
#lang racket/base
```

At startup, Odra validates and copies the module through a bounded
configuration boundary. A valid present file publishes a confirmed startup
configuration state. A rejected or unavailable file reports a bounded
diagnostic and preserves factory configuration.

Current startup loading applies only admitted configuration contracts. The
applied factory contracts are exported as `odra-status-bar-configuration`,
`odra-gutter-configuration`, and `odra-completion-configuration`.

The Status Bar value is a hash with `position`, `visible`, and `compact` keys.
The bridge evaluates the confirmed copied module within fixed time and memory
limits, normalizes the exported value through the public Racket facade, and
copies only bounded numeric policy values into native startup state. Rejection
preserves the factory Status Bar policy.

The Gutter value is a hash containing the admitted visibility, side, order,
numbering mode and scope, current-line presentation, digit bounds, padding,
and separator values. The same bounded startup generation applies both
presentation policies atomically. Rejection preserves the factory Gutter
policy. See the [Gutter Reference](../gutter/index.md) for the complete field
contract.

The completion value is constructed through `odra/completion`. It selects the
admitted factory roles, invocation and filtering policy, prefix threshold, and
resource limits. Reload prepares the complete completion generation before
publishing it with the other admitted configuration. Rejection preserves the
last valid generation. See the
[Language Completion Reference](../language-completion/index.md) for the
complete field contract.

The optional `odra-language-support` value is constructed through
`odra/languages`. It provides one complete declarative set of language
associations, language-service definitions, and explicit selections. The
bounded encoded candidate publishes atomically with the other admitted
exports; rejection preserves the last confirmed startup generation. See the
[Language Support Configuration Reference](../language-support-configuration/index.md)
for constructors, examples, defaults, limits, and failure behavior.

The optional `odra-recovery-policy` value is constructed through
`odra/recovery`. It controls auxiliary checkpoint timing, retention, storage,
startup review, and the separate source-autosave policy. The factory policy
enables private checkpoints and leaves source autosave disabled. See the
[Unsaved-Work Recovery Reference](../unsaved-work-recovery/index.md) for the
complete contract.

This startup contract does not register programmable Status Bar providers.
Provider definitions and lifecycle operations use a separate session-scoped
Racket capability and native registry.

## Darek keymap helpers

`src/command/darek.rkt` provides the extension-facing Darek command catalog and
checked keymap constructors. `darek-global-command-names` and
`darek-context-command-names` identify the supported semantic commands.
`darek-bind-key`, `darek-mask-key`, and `darek-remap-command` create ordinary
profile operations after validating the referenced Darek command. The
`darek-factory-bindings` procedure returns the factory global bindings for
`darek-toggle` and `darek-focus-toggle`.

These procedures compose a session profile through the existing programmable
keymap boundary. They do not mutate the native registry during module loading,
persist panel state, or grant filesystem access. See
[Configure a Runtime Keymap Profile](../../how-to/configure-keymaps/index.md)
for profile construction and activation, and the
[Darek Reference](../darek/index.md) for the complete command catalogs and
factory bindings.

## Progressive Layout

Odra does not require a generated configuration tree. A minimal valid
configuration root can contain only:

```text
init.rkt
```

A larger user-authored layout may grow by convention:

```text
init.rkt
settings/
themes/
modules/
repos/
```

`settings/` is only an organization convention. A user may split files any way
that remains loadable from `init.rkt`.

## Layout Classes

The initial root contract classifies top-level paths as follows:

| Path | Class | Ownership |
| --- | --- | --- |
| `init.rkt` | personal entrypoint | user-authored functional configuration |
| `settings/` | functional configuration | user-authored organization convention |
| `themes/` | theme namespace | user-authored, imported, or package-provided themes |
| `modules/` | module namespace | user-authored, local, or installed Racket modules |
| `repos/` | repo configuration | configured extension/package sources |
| `projects/` | operational Project discovery | Odra-managed discovery, recency, and selection state |
| `workspaces/` | operational Workspace state | Odra-managed Workspace composition |
| `promotion-suppressions.rkt` | operational prompt state | Odra-managed interaction preference |
| `migration.rkt` | operational migration state | Odra-managed migration journal |
| `sessions/` | operational session state | Odra-managed restorable editor state |
| `state/` | legacy operational state | compatibility data predating the dedicated platform state root |

Unknown top-level entries are unclassified configuration-root entries until a
later contract assigns ownership.

## Project and Workspace State

Project identity remains local to the promoted Dir:

```text
<project-dir>/.odra/project.rkt
```

Global Project files under:

```text
projects/<project-id>.rkt
```

are discovery references and operational state. They let Odra present bounded
Project lists, recents, and startup selectors without scanning arbitrary
filesystem trees for `.odra/` dirs. They do not become Project authority.

Workspace files under:

```text
workspaces/<workspace-id>.rkt
```

are global compositions of Projects. A Workspace references Projects and does
not rewrite member Project metadata implicitly.

## Startup Diagnostics

Startup personal configuration has these visible outcomes:

| Condition | Result |
| --- | --- |
| `init.rkt` is absent | No personal configuration, no diagnostic noise |
| `init.rkt` is present and valid | `Personal configuration loaded` |
| `init.rkt` is rejected | Bounded rejection diagnostic, factory configuration preserved |
| `init.rkt` is unavailable | Bounded unavailable diagnostic, factory configuration preserved |

## Related Procedures

See [Configure Personal Startup](../../how-to/configure-personal-init/index.md)
for a task-focused setup guide.

## Focused Validation

```sh
raco test src/configuration/platform-roots.rkt src/configuration/root.rkt src/configuration/personal.rkt tests/configuration/personal_test.rkt
raco test tests/configuration/startup_test.rkt tests/configuration/example_test.rkt
make docs-check
```

These checks cover platform root resolution, path classification, personal loading,
startup batch diagnostics, single-file examples, modular examples, and
documentation links.
