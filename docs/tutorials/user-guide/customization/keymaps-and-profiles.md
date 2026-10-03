<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Compose Keymaps and Profiles

This chapter activates one personal keymap, observes a direct binding,
semantic remap, and mask, verifies contextual precedence, and recovers from a
profile that attempts to remove protected editor access.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../getting-started/prepare-exercises.md).

Complete [Use Familiar Interaction](use-familiar-interaction.md).
Keep the isolated tutorial `init.rkt` and `settings/interface.rkt` from the
previous chapters.

## Add a Personal Keymap

Create `~/odra-guide/config/odra/settings/keys.rkt` by pasting this complete
chapter-owned file:

```racket
#lang racket/base

(require odra/keymaps)

(provide odra-interaction-profile)

(define source
  (odra-provenance "personal" "settings/keys.rkt" ""))

(define (key character modifiers)
  (odra-key-stroke 1 (char->integer character) modifiers))

(define (control character)
  (key character #x01))

(define (plain character)
  (key character 0))

(define personal-map
  (odra-keymap
   3 1 "personal-discovery" 0 0 'user-global 10
   0 0 0 0 'fallthrough
   (list
    (keymap-bind
     (key-sequence (control #\c) (plain #\i))
     "describe-keymap-state"
     source)
    (keymap-mask
     (key-sequence (control #\x) (control #\s))
     source))
   (list
    (keymap-remap
     "cursor-line-start"
     "cursor-line-first-non-whitespace"
     source))
   '()
   source))

(define factory (factory-interaction-profile))

(define odra-interaction-profile
  (compose-interaction-profile
   2 1 "personal-direct"
   (list (odra-interaction-profile-maps factory)
         (list personal-map))
   "insert-text"))
```

Update `init.rkt` to require and export both settings modules:

```racket
#lang racket/base

(require "settings/interface.rkt"
         "settings/keys.rkt")

(provide odra-status-bar-configuration
         odra-gutter-configuration
         odra-interaction-profile)
```

Run `M-x reload-personal-commands`. The complete command registry and profile
relationship is checked before publication.

## Observe Binding, Remap, and Mask

Press `C-c i`. The new binding runs `describe-keymap-state`. Its row identifies
the active `personal-direct` profile and `personal-discovery` map.

In an indented source line, press `C-a`. The inherited physical binding first
resolves `cursor-line-start`; the personal semantic remap redirects it to
`cursor-line-first-non-whitespace`.

Run `describe-key` and capture `C-x C-s`. The personal map masks the lower
factory binding, so the result records the masked disposition rather than
silently exposing another command. Save through `M-x save-buffer` while this
tutorial profile is active.

## Verify Contextual Precedence

Open `M-x` and type ordinary query text. The command navigator's contextual
map owns filtering, movement, acceptance, and cancellation above the personal
global map. Open a fixed prompt or Darek and observe that its current
component commands likewise retain local meaning.

Contextual owners activate and retire their maps with the interaction. A
personal profile should bind semantic editor commands, not reproduce prompt
responses or component-local navigation.

## Reject an Unsafe Profile

Replace the `C-x C-s` mask with a mask for protected `M-x`:

```racket
(keymap-mask
 (key-sequence (key #\x #x02))
 source)
```

Run `M-x reload-personal-commands`. The candidate is rejected before
publication because `M-x` and `C-g` are protected recovery routes. The prior
personal generation remains active, so `M-x` still opens command navigation.

Run `M-x describe-keymap-conflicts` to inspect the protected-binding
rejection. Restore the `C-x C-s` example or remove the mask, increment the
profile and map revisions, and reload successfully.

## Recover from Keymap Problems

- Use `describe-key` for one surprising sequence before changing a profile.
- Use `where-is` when the command is known but its effective route is not.
- Use `describe-keymap-state` to separate profile, interaction state, pending
  prefix, and command-catalog generations.
- Use `describe-keymap-conflicts` immediately after rejection, before another
  candidate replaces the latest failure context.
- Preserve `M-x` and `C-g`; they remain available for recovery even when a
  personal candidate is malformed or unsafe.

## Verify the Result

You have completed this chapter when the personal profile publishes one
binding, remap, and mask; inspection explains each result; contextual maps
retain local ownership; and a protected-binding rejection preserves both the
prior profile and recovery commands.

For profile construction and recovery, see
[Configure a Runtime Keymap Profile](../../../how-to/configure-keymaps/index.md).
For exact precedence, operations, contextual ownership, and protection, see
the [Contextual Keymap Reference](../../../reference/contextual-keymaps/index.md).

---

[Previous: Use Familiar Interaction](use-familiar-interaction.md) ·
[User Guide](../index.md) ·
[Next: Write and Reload a Personal Command](personal-commands.md)
