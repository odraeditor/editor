<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Define and Reload Personal Commands

This guide adds one text command, makes it discoverable through `M-x`, binds
it, reloads its implementation, and recovers from an invalid candidate.

## Create a command module

Create `$XDG_CONFIG_HOME/odra/modules/text-commands.rkt`, or use
`$HOME/.config/odra/modules/text-commands.rkt` when `XDG_CONFIG_HOME` is not
set:

```racket
(module text-commands racket/base
  (require odra/commands
           odra/keymaps)

  (provide odra-personal-commands
           odra-interaction-profile)

  (define (uppercase-line context)
    (define line (command-context-current-line context))
    (command-context-replace!
     context
     line
     (string-upcase (command-context-read context line))))

  (define odra-personal-commands
    (list
     (make-command
      'personal-uppercase-line
      uppercase-line
      #:description "Uppercase the current line."
      #:source "modules/text-commands.rkt")))

  (define provenance
    (odra-provenance "personal" "init.rkt" ""))
  (define factory (factory-interaction-profile))
  (define personal-map
    (odra-keymap
     3 1 "personal" 0 0 'user-global 0 0 0 0 0 'fallthrough
     (list
      (keymap-bind
       (key-sequence
        (odra-key-stroke 1 (char->integer #\c) 1)
        (odra-key-stroke 1 (char->integer #\u) 0))
       "personal-uppercase-line"
       provenance))
     '() '() provenance))

  (define odra-interaction-profile
    (compose-interaction-profile
     1 2 "personal-direct"
     (list (odra-interaction-profile-maps factory)
           (list personal-map))
     "insert-text")))
```

The binding uses `Control-C`, then `u`. The command remains available through
`M-x` even when it has no binding.

## Stay within the currently verified authoring surface

Use core forms and ordinary `racket/base` procedures in personal modules.
`for/list` currently triggers an embedded namespace rejection. Express the
same transformation with `map` while that loader limitation remains:

```racket
(map transform values)
```

Other non-core macros may require verification in the embedded runtime. A
rejected reload preserves the last confirmed command generation, so replace
the unsupported form and run `reload-personal-commands` again.

## Select the module from init.rkt

Create or replace `$XDG_CONFIG_HOME/odra/init.rkt`:

```racket
#lang racket/base

(require "modules/text-commands.rkt")

(provide odra-personal-commands
         odra-interaction-profile)
```

Start Odra. `M-x personal-uppercase-line` transforms the current logical line.
The configured binding performs the same registered command. Undo treats the
complete transformation as one unit.

## Reload a changed implementation

Change the procedure body in `text-commands.rkt`, then run:

```text
M-x reload-personal-commands
```

The new command implementation and its bindings become visible together. The
status area reports `Personal commands reloaded` after successful activation.

## Inspect the active command

Use the shared inspection commands:

```text
M-x where-is
M-x describe-bindings
M-x describe-keymap-state
```

`where-is` accepts the semantic name `personal-uppercase-line`. The resulting
surfaces show the active binding and logical personal provenance without an
absolute configuration path.

## Recover from a rejected reload

If the module has invalid syntax, unsupported metadata, a duplicate command,
or an invalid binding, reload reports a bounded rejection and preserves the
last confirmed generation. Correct the file and invoke
`reload-personal-commands` again.

To deactivate personal commands without deleting configuration files, export
an empty command list and omit the personal interaction profile:

```racket
#lang racket/base

(provide odra-personal-commands)

(define odra-personal-commands '())
```

Reload remains a factory command after deactivation or candidate rejection.
