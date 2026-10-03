<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Undo a Semantic Terminal Edit

This tutorial opens one document, creates a user-visible typing unit, undoes
that complete unit, saves the resulting document, and exits cleanly.

## Build the terminal editor

From the repository root, run:

```sh
make odra
printf 'base\n' > /tmp/odra-history-tutorial.txt
.build/odra /tmp/odra-history-tutorial.txt
```

Odra opens the file with the cursor before `base`.

## Create one typing unit

Type `ax`, press Backspace once, and then type `界`.

The first line now begins with:

```text
a界base
```

Although this took four terminal events, the compatible insertions and the
Backspace correction form one semantic typing unit. Backspace remains in that
unit because it removed only the `x` produced by the same unit.

## Undo the unit

Press `Control-X`, release it, and then press `u`.

The complete `a界` insertion disappears and the cursor returns to its position
before the typing unit. The confirmed buffer receives a fresh revision even
though its bytes again equal the file's original `base` contents.

Pressing `Control-X`, then `u` again at the history root is a checked no-op.

## Understand redo at this delivery boundary

The semantic command registry also exposes `redo`. It reapplies the preferred
child as one complete unit and restores the unit's final cursor context. The
initial terminal keymap deliberately gives redo no physical binding; a named
command launcher and the final interaction profile belong to later delivery.
The command-level tests exercise the complete undo and redo path without
inventing a temporary key sequence:

```sh
make native-command-test
```

## Save and exit

Press `Control-X`, then `Control-S` to save the current state. Press
`Control-X`, then `Control-C` to exit.

Because the tutorial leaves the history at the parent state, the saved file
contains its original contents:

```sh
cat /tmp/odra-history-tutorial.txt
```

The result is `base`. Remove the tutorial file when finished.

## Recover an alternate retained future

This workflow is currently command-level; it does not depend on an
undelivered visualizer or physical key binding.

1. Commit edit A, then edit B.
2. Undo B.
3. Commit edit C from the same parent.
4. Undo C.
5. Inspect the current node with `history_command_inspect`.
6. Choose B's opaque child identity from `Inspection.children`.
7. Pass that identity, the inspected active identity and policy generation,
   and an explicit work bound to `history_command_select_branch`.

The complete transition to B publishes as one fresh editor revision. C remains
retained and can be selected later through another bounded inspection. No
caller reads or retains a native node pointer.

Run the checked native workflow with:

```sh
odin test src/history -vet -warnings-as-errors
odin test src/command -vet -warnings-as-errors \
  -define:ODRA_RACKET_RUNTIME_LIBRARY="../../.build/hosting/libodra_racket_runtime.a" \
  -extra-linker-flags:"/usr/lib/racket/../libracketcs.a -lm -lncursesw -lz -llz4 -ldl -lpthread -Wl,--export-dynamic-symbol=odra_racket_scoped_capability_call"
```

## Reverse one earlier unit selectively

Start from retained units A, B, and C where B and C do not overlap A. Inspect
the active node, then call `history_command_selective_undo` with A's
`Unit_ID`, the inspected policy generation, and an explicit analysis bound.
The command proves that later work remains valid, publishes A's inverse, and
records one new `selective-undo` node.

Undo once through the ordinary history command. The compensating node is
reversed and the document returns to its exact pre-compensation state.

For region narrowing, create two live editor anchors before the command and
pass them as `History_Anchor_Range`. The command resolves them at the current
revision. It rejects a stale range, a partial edit overlap, or a dependency
conflict without changing text or topology.

The deterministic selective success, range narrowing, conflict, budget,
cancellation, and cleanup scenarios run with:

```sh
odin test src/transaction -vet -warnings-as-errors
make history-fuzz
make history-resource-study
```
