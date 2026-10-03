<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Write and Reload a Personal Command

This chapter defines one useful Racket text command, publishes it into the
shared command registry, binds and invokes it, replaces its implementation
without restarting, inspects its provenance and execution limits, and recovers
from a rejected generation.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../getting-started/prepare-exercises.md).

Complete [Compose Keymaps and Profiles](keymaps-and-profiles.md).
Keep the isolated modular configuration and the `personal-direct` interaction
profile from that chapter.

Personal commands use public copied editor values and checked text
transactions. They do not receive native pointers or mutate buffer storage
directly.

## Define a Text Command

Create `~/odra-guide/config/odra/modules/text-commands.rkt` by pasting this
complete chapter-owned file:

```racket
(module text-commands racket/base
  (require odra/commands)

  (provide odra-personal-commands)

  (define (uppercase-line context)
    (define line (command-context-current-line context))
    (define text (command-context-read context line))
    (command-context-replace! context line (string-upcase text)))

  (define odra-personal-commands
    (list
     (make-command
      'personal-uppercase-line
      uppercase-line
      #:description "Uppercase the current line."
      #:requirements '(active-buffer)
      #:effects '(buffer view text-mutation)
      #:source "modules/text-commands.rkt"))))
```

`make-command` constructs an immutable definition; it does not register an
arbitrary procedure by side effect. The exported list is the sole command
contribution selected by personal configuration.

## Bind the Semantic Command

In `settings/keys.rkt`, add this operation to the `personal-map` binding list:

```racket
(keymap-bind
 (key-sequence (control #\c) (plain #\u))
 "personal-uppercase-line"
 source)
```

The profile refers to the command by semantic identity. Configuration
admission verifies that the command and binding arrive in the same complete
generation.

Update `init.rkt`:

```racket
#lang racket/base

(require "settings/interface.rkt"
         "settings/keys.rkt"
         "modules/text-commands.rkt")

(provide odra-status-bar-configuration
         odra-gutter-configuration
         odra-interaction-profile
         odra-personal-commands)
```

Run `M-x reload-personal-commands`. A successful reload publishes the command
catalog and interaction profile together.

## Invoke and Undo

Open `~/odra-guide/work/dirs/notes/editing-practice.txt`, place point on a
mixed-case line, and run `M-x personal-uppercase-line`. The complete logical
line becomes uppercase.

Press `C-/` once. The original line returns because the personal command
publishes its replacement as one ordinary history unit.

Repeat with `C-c u`, then undo again. Command navigation and the keybinding
reach the same registered command; the binding is not a second implementation.

## Inspect the Active Definition

Run `M-x where-is` and enter `personal-uppercase-line`. The result shows
`C-c u` and personal provenance. Run `M-x describe-key`, capture `C-c u`, and
inspect the effective map, profile, command identity, and source.

Open `M-x` and search for the command. Its row shows the description,
implementation provider, availability, and binding without exposing the
absolute configuration root.

## Replace the Implementation Live

Change `uppercase-line` to use `string-downcase` and update the command
description accordingly. Run `M-x reload-personal-commands`.

Invoke the same semantic command and binding. The new confirmed procedure runs
without restarting Odra. A command turn already in progress retains its owned
generation until it finishes; later invocations cannot call a retired
procedure.

Restore the uppercase implementation and reload before continuing.

## Observe the Execution Bound

Temporarily add `(sleep 3)` before `command-context-replace!`, reload, and
invoke the command. The default personal-command deadline ends the turn before
the delayed replacement can publish. The buffer and undo history remain
unchanged, and a bounded diagnostic reports the rejected invocation.

Restore the immediate implementation and reload. The execution deadline,
custodian memory, copied text, replacement text, splice count, transaction
memory, nested operations, and diagnostic size all have explicit ceilings.
Personal code may choose smaller limits but cannot raise the maintained native
maximums.

## Reject a Command Generation

Change the command identity from `personal-uppercase-line` to `save-buffer`
without changing the personal binding. Run `M-x reload-personal-commands`.
Personal code cannot replace a factory command, and the mismatched binding
cannot resolve to the rejected definition. The complete candidate is rejected
while the last confirmed personal command and `C-c u` behavior remain active.

Restore the personal identity and reload. Factory `M-x`, `C-g`, and
`reload-personal-commands` remain available throughout recovery.

## Stay Inside the Verified Authoring Surface

Use core forms, ordinary `racket/base` procedures, explicit recursion or
runtime combinators such as `map`, and public `odra/commands` and
`odra/keymaps` modules. A non-core macro that requires an unavailable
transformer phase may reject in the embedded namespace even if it works in a
separate Racket process.

That loader boundary does not reduce Racket's text-processing model. It marks
which source forms and editor capabilities are currently verified for live
personal generations. Rejection always preserves the last confirmed
generation.

## Verify the Result

You have completed this chapter when the command appears in `M-x`, both direct
and bound invocation transform one line, undo restores it in one step, live
reload replaces the implementation, inspection reports personal provenance,
the execution deadline prevents delayed publication, and an invalid command
candidate leaves the last confirmed behavior available.

For the concise authoring procedure, see
[Define and Reload Personal Commands](../../../how-to/define-personal-commands/index.md).
For public procedures, authoring compatibility, limits, lifecycle, and
recovery, see the
[Personal Commands Reference](../../../reference/personal-commands/index.md).
For the architectural boundary, see
[Core and Personal Command Boundaries](../../../explanation/core-and-personal-command-boundaries/index.md).

---

[Previous: Compose Keymaps and Profiles](keymaps-and-profiles.md) ·
[User Guide](../index.md) ·
[Next: Extend Ksawery](extend-ksawery.md)
