<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Organize Personal Configuration

This chapter creates one isolated `init.rkt`, separates user-authored settings
from editor-managed state, grows the configuration into ordinary Racket
modules, reloads one valid generation, and recovers from rejected startup and
reload candidates.

## Before You Begin

Complete [Prepare the User Guide Exercises](../getting-started/prepare-exercises.md).
Reset the chapter-created configuration examples before writing them:

```sh
"$HOME/odra-guide/kit/bin/odra-guide" reset configuration-examples
```

## Use an Isolated Configuration Root

Exercise setup activates the isolated configuration root once. Launch Odra
normally from that same shell:

```sh
odra
```

Odra therefore resolves this personal entrypoint:

```text
~/odra-guide/config/odra/init.rkt
```

Without `XDG_CONFIG_HOME`, the default is `$HOME/.config/odra/init.rkt`. An
absent entrypoint is valid and silent. A present entrypoint begins with
`#lang racket/base`.

## Keep Authored and Managed State Distinct

The configuration root may contain both personal source and Odra-managed
operational state:

```text
init.rkt                 personal entrypoint
settings/                optional personal organization
modules/                 optional personal Racket modules
themes/                  reserved personal or package theme namespace
repos/                   configured extension sources
projects/                Odra-managed Project discovery state
workspaces/              Odra-managed Workspace composition
sessions/                Odra-managed restorable session state
state/                   other Odra-managed operational state
```

Edit `init.rkt` and modules it explicitly requires. Do not load managed
Project, Workspace, session, migration, or recency files as functional
configuration. A promoted Project keeps its authoritative local identity at
`<project-dir>/.odra/project.rkt`; global Project records support discovery
without scanning the filesystem.

## Start with One File

Create `~/odra-guide/config/odra/init.rkt` by pasting the complete admitted
policy below:

```racket
#lang racket/base

(provide odra-status-bar-configuration)

(define odra-status-bar-configuration
  '#hash((position . line-column-percentage)
          (visible . (encoding pane-state workspace project editing-context))
          (compact . automatic)))
```

Start Odra. `Personal configuration loaded` confirms the candidate. The
module is copied, evaluated within bounded time and memory, normalized through
the public configuration facade, and published only after the complete
generation is valid.

## Grow into Modules

Create `~/odra-guide/config/odra/settings/interface.rkt` by pasting this
complete chapter-owned file:

```racket
#lang racket/base

(provide odra-status-bar-configuration
         odra-gutter-configuration)

(define odra-status-bar-configuration
  '#hash((position . line-column)
          (visible . (project editing-context))
          (compact . prefer-compact)))

(define odra-gutter-configuration
  '#hash((mode . hybrid)
          (current-line . zero)
          (minimum-digits . 4)))
```

Replace `init.rkt` with the small entrypoint:

```racket
#lang racket/base

(require "settings/interface.rkt")

(provide odra-status-bar-configuration
         odra-gutter-configuration)
```

The directory names are conventions, not a generated schema. Relative
`require` and explicit `provide` keep the entrypoint as the visible composition
root.

## Reload a Valid Generation

Run `M-x reload-personal-commands`. Despite its historical command name, the
reload prepares the complete admitted personal generation: commands, keymap
profile, Status Bar policy, Gutter policy and provider, completion policy, and
recovery policy.

On success, `Personal commands reloaded` confirms that the new generation is
active. New Status Bar and Gutter observations use the module values without
restarting the editor.

Every export is optional. Omitting one retains its factory behavior unless a
specific public contract defines removal through `#f` or an empty value.

## Reject an Invalid Reload

Introduce an invalid Gutter mode in `settings/interface.rkt`:

```racket
(define odra-gutter-configuration
  '#hash((mode . diagonal)))
```

Run `M-x reload-personal-commands`. The bounded rejection identifies the
failed candidate and preserves the complete last confirmed generation. It
does not mix the new Status Bar value with an old Gutter or keymap generation.

Restore `hybrid`, reload again, and verify that the corrected generation
replaces the prior one.

## Recover from Startup Failure

Exit Odra, remove one closing parenthesis from `init.rkt`, and launch again.
Startup reports a bounded rejection diagnostic and keeps factory configuration
active. Command navigation and protected cancellation remain available.

Correct the syntax and run `reload-personal-commands`; restart is not required
to recover once the editor is running. A file that is unreadable or exceeds
the admitted source bound is unavailable or rejected through the same
preservation rule.

## Understand the Accepted Surface

Personal configuration is ordinary Racket within the currently verified
embedded authoring environment. Core forms, ordinary `racket/base`
procedures, relative module composition, and public `odra/...` modules form
the supported path.

Internal hosting, bridge, registry, and native modules are not public
configuration APIs. A form or transformer that has not been verified in the
embedded namespace may reject even when it works in a separate Racket
process; the last confirmed editor generation remains active.

## Verify the Result

You have completed this chapter when an absent entrypoint is silent, one valid
file loads, a modular entrypoint composes public settings, live reload replaces
the complete admitted generation, an invalid reload preserves the last valid
one, a broken startup falls back to factory behavior, and managed operational
state remains outside functional configuration.

For direct setup and path ownership, see
[Configure Personal Startup](../../../how-to/configure-personal-init/index.md).
For exact exports, bounds, diagnostics, and state classes, see the
[Configuration System Reference](../../../reference/configuration-system/index.md).

---

[Previous: Use the Gutter](../interface/gutter-and-transient-details.md) ·
[User Guide](../index.md) ·
[Next: Discover Commands and Bindings](discover-commands-and-bindings.md)
