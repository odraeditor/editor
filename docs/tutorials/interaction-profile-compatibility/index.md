<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Inspect the Direct Interaction Profile

This tutorial follows the shipped direct interaction profile from its catalog
identity to one scoped binding and the shared command-entry surface. It does
not add or configure another interaction grammar.

## 1. Build Odra

```sh
make odra
.build/odra path/to/file.txt
```

The factory catalog activates profile `direct` and state `direct-editing`.
Ordinary typing and existing key bindings therefore behave as before.

## 2. Inspect the catalog selection

Press `M-x`, enter `describe-keymap-state`, and press `Enter`.

The first row identifies the registry and snapshot generations. The remaining
rows show:

1. The confirmed catalog generation.
2. The active `direct` profile.
3. The active `direct-editing` state and its text-input and effect policy.
4. The `extended-command` surface used by `M-x`.

Inactive profile and state definitions would appear as `inactive`; the factory
catalog currently contains no second profile.

## 3. Inspect binding scope

Press `q`, open `M-x`, and run `describe-bindings`.

Find the `C-g` and `M-x` rows. Each identifies its effective command, source,
active profile and state, effect admission, and `protected-recovery` scope.
Ordinary factory bindings report `profile-specific`. A future explicitly
shared contribution reports `shared-continuity` followed by every selected
profile/state pair.

## 4. Inspect one command and its surface

Press `q`, open `M-x`, run `where-is`, and enter `undo`.

The binding rows show the canonical command name and every active sequence.
The surface row shows that the same registered command is available through
`extended-command`; the surface does not create another command identity.

## 5. Inspect rejection context

Press `q`, open `M-x`, and run `describe-keymap-conflicts`.

When a candidate has been rejected, the row identifies its failure code and
available catalog, profile, state, scope, selector, surface, map, owner,
generation, and resource context. The active rows remain from the prior
confirmed generation.

## 6. Run the focused validation

```sh
raco test src/command/keymap-inspection.rkt
odin test src/interaction -vet -warnings-as-errors
make profile-compatibility-resource-study
ODRA_PTY_EXECUTABLE="$PWD/.build/odra" \
  raco test tests/keymap_inspection/inspection_terminal_test.rkt
```

The tests cover copied ownership, active and inactive definitions, binding
scopes, shared selectors, state admission, command-entry surfaces, rejection,
allocation faults, bounds, cleanup, and terminal presentation.

See [Inspect Interaction Profile Compatibility](../../how-to/inspect-interaction-profile-compatibility/index.md)
for the task-oriented command summary and the
[Compatibility Inspection Reference](../../reference/interaction-profile-compatibility/inspection.md)
for exact records and limits.
