<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Inspect Interaction Profile Compatibility

Use the built-in inspection commands to diagnose the confirmed interaction
catalog without exposing live resolver or Racket state.

## Inspect the active catalog

1. Open command navigation with `M-x`.
2. Run `describe-keymap-state`.
3. Read the snapshot, catalog, profile, state, and command-entry surface rows.
4. Use `Up` and `Down` to move through the copied list.
5. Press `q` or `C-g` to close it.

The active state row reports whether ordinary text input is admitted and lists
its admitted command effects. An inactive row is a retained definition, not
an input participant.

## Inspect a binding

Run one of these commands through `M-x`:

| Command | Use |
| --- | --- |
| `describe-key` | Enter one complete key sequence and inspect its effective and alternative bindings. |
| `where-is` | Enter one canonical command name and inspect its bindings and active command-entry surfaces. |
| `describe-bindings` | Inspect the active binding set in precedence order. |
| `describe-keymap` | Enter a positive map identifier and inspect that map, its bindings, and its remaps. |

For a binding row, check `scope`, `profile`, `state`, `effects-admitted`, and
`source`. Shared-continuity rows also list every selected profile/state pair.

## Diagnose a rejected candidate

Run `describe-keymap-conflicts` immediately after a failed profile reload. The
row identifies the available catalog generation, profile, state, binding
scope, selector index, surface, map, owner, and exceeded resource bound.

The rejection is diagnostic only. It does not replace the confirmed catalog,
snapshot, pending-input rule, visible UI, or canonical editor state.

## Verify the complete path

```sh
make profile-compatibility-resource-study
ODRA_PTY_EXECUTABLE="$PWD/.build/odra" \
  raco test tests/keymap_inspection/inspection_terminal_test.rkt
make verify
```

See the [Compatibility Inspection Reference](../../reference/interaction-profile-compatibility/inspection.md)
for exact query and record contracts.
