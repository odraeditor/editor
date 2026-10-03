<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Navigate and Indent Odin Structure

This tutorial opens one Odin document, moves through its syntax tree, expands
a structural selection, indents code as one reversible edit, and inspects the
exact analysis state used by the commands.

## 1. Create a sample document

Create `/tmp/odra-structure-demo.odin` with:

```odin
package main

import "core:fmt"

main :: proc(input: int) -> int {
fmt.println("hello", input)
return input
}
```

Build and open it:

```sh
make odra
COLORTERM=truecolor TERM=xterm-256color .build/odra /tmp/odra-structure-demo.odin
```

The case-sensitive `.odin` suffix selects the factory Odin provider. Wait for
syntax color to appear before using structural commands so the retained tree
matches the current buffer revision.

## 2. Move through named syntax nodes

Move point into the `fmt.println` statement. Use these direct-profile
bindings:

| Binding | Movement |
| --- | --- |
| `C-M-f` | End of the next named node at the current level |
| `C-M-b` | Start of the previous named node at the current level |
| `C-M-u` | Start of the nearest strict named ancestor |
| `C-M-d` | Start of the first named child |

Each operation is also available through `M-x` as `structural-forward`,
`structural-backward`, `structural-up`, or `structural-down`.

At a structural boundary with no applicable target, the command is a checked
no-op. It does not move point to an approximate byte position.

## 3. Expand a structural selection

Press `C-M-SPC` to run `structural-select`. The first invocation selects the
smallest named node containing point. Repeat the binding to expand the region
to strict named ancestors.

The selection is shared by every view of the buffer. Split with `C-x 3`, focus
the other pane with `C-x o`, and repeat the command to observe the same active
region in both panes.

Press `C-g` to cancel the active interaction and return to ordinary editing.

## 4. Indent and reverse one structural edit

Place point on the `fmt.println` line and run `structural-indent` through
`M-x`. The factory Odin rules change leading horizontal whitespace only.
Select both statement lines with an active region and run the command again to
indent every intersecting line as one transaction.

Use `C-/` to undo the complete indentation operation, then run `redo` through
`M-x`. Syntax analysis refreshes after the text revision publishes, so the
next structural command uses a new exact tree generation.

Save with `C-x C-s`.

## 5. Inspect the structural state

Run `describe-structural-state` through `M-x`. The shared list shows the exact
buffer and analysis generations, grammar rules, point and region, last target,
last operation, indentation range, resource usage and limits, and latest
contained rejection.

Press `q` or `C-g` to close the list. Inspection copies existing state and
does not trigger parsing or movement.

## 6. Confirm plain-text fallback

Open a `.txt` document and invoke `structural-forward`. The command records an
unavailable-analysis rejection and changes no editor state. Ordinary insertion,
search, save, pane, and exit commands remain available. Run
`describe-structural-state` to inspect the rejection.

See [Use and Validate Structured Syntax](../../how-to/use-structured-syntax/)
for focused validation and rejection diagnosis.
