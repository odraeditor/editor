<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Interaction Profiles Share Canonical Commands

An interaction profile should change how input reaches an editor operation,
not create a second meaning for that operation. Odra therefore keeps command
identity, profile policy, physical bindings, interaction state, and
command-entry presentation as separate contracts.

## One name survives different entry paths

The stable pattern is:

```text
registered command: command-name
direct entry:        M-x command-name
future profile entry: :command-name
```

Only the direct `M-x` entry exists today. A future profile may supply the
second presentation, but both entries must query and invoke the same checked
registry identity. The profile does not gain an alias catalog or expose every
callable Racket function as an editor command.

This pattern lets documentation name the command once. Binding reinforcement
and profile-specific entry syntax can be explained where a workflow needs
them, without redefining the command for every interaction grammar.

## Scope replaces global key reservation

Odra does not reserve an arbitrary set of physical keys for future profiles.
Each binding declares its actual applicability:

- protected recovery is the small factory-owned `C-g` and `M-x` policy;
- shared continuity explicitly names every compatible profile and state; and
- profile-specific bindings remain inside their owning profile.

This makes continuity reviewable. A user can share a useful modified binding
without forcing direct text keys into a future state that interprets those
keys as commands.

## State policy controls inherited editing

A binding can be structurally present while its command is unavailable. The
active interaction state decides whether ordinary text input and declared
command effects are admitted. In particular, inherited direct text mutation
does not execute in a state that rejects `Text_Mutation`.

The shipped `direct-editing` state admits current behavior. Synthetic
non-editing states prove the rejection boundary without shipping a modal
grammar or guessing its state names.

## Surfaces are presentation, not authority

The `extended-command` surface owns the current command-name interaction, but
the registry owns command identity and the dispatcher owns admission. A later
surface can reuse candidate navigation, input, and diagnostics without
bypassing state policy or acquiring canonical editor state.

## Inspection keeps the boundary honest

Compatibility inspection shows the catalog selection, active and inactive
profiles and states, binding scope and selectors, effect admission,
command-entry surfaces, provenance, alternatives, and rejection context. The
records are copied from confirmed native owners, so a profile reload cannot
change an already presented explanation.

This separation is what lets another interaction profile be added later
without invalidating the direct profile, rewriting the command vocabulary, or
requiring users to remap every operation before they can edit.

See the [Compatibility Inspection Reference](../../reference/interaction-profile-compatibility/inspection.md)
for exact queries and records.
