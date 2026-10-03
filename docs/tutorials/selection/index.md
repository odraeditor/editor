<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Select Text with Point and Mark

This tutorial exercises Odra's first visible region workflow in the terminal.
You will establish mark, move point, exchange the endpoints, cancel the active
region, and observe undo restore its complete logical context.

## Prepare a document

From the repository root, build the editor and create a small UTF-8 document:

```sh
make odra
printf 'alpha beta\nsecond line\n' > /tmp/odra-selection.txt
.build/odra /tmp/odra-selection.txt
```

Point begins at the start of the document.

## Establish a region

Press `Control-Space` to run `set-mark-command`. Mark is now retained at the
initial point, and the region is active even though it is still empty.

Press Right five times. Point moves after `alpha`; mark stays at the beginning.
The active non-empty region is shown with the current theme's selection
background. `Terminal Default` uses reverse video instead.

## Exchange and deactivate

Press `Control-X`, then `Control-X`. Point and mark exchange positions. The
same text remains highlighted because the ordered region bounds do not depend
on which endpoint is point.

Press `Control-G`. The highlight disappears, but mark remains retained. This
is deactivation, not deletion of mark.

## Restore a region through undo

Press `Control-Space`, move Right twice, and type `Z`. The character is
inserted at point; it does not replace the active region. Successful insertion
deactivates the region while retaining mark.

Press `Control-X`, then `u`. Undo removes the insertion and restores the point,
mark, and activation state recorded before it. The two-character region is
highlighted again.

Press `Control-X`, then `Control-S` to save. Press `Control-X`, then
`Control-C` to exit.

For exact state transitions and command names, see the
[Selection Reference](../../reference/selection/index.md).

## Expand and revisit selections

Open a document containing several words and paragraphs. Use `M-@` to select
the word at point, `M-h` to select its paragraph, or `Control-X`, then `h` to
select the complete buffer. `Control-Meta-H` selects the current language
definition when current structural analysis is available.

Run two of these commands at different positions, then press `Control-U`
followed by `Control-Space`. Repeating that sequence walks backward through
the bounded session-local selection and location history.

## Save and visit a location

Press `Control-X`, `r`, `m`, enter a name, and press Enter. Move elsewhere or
open another file. Press `Control-X`, `r`, `b`, filter the location list, and
press Enter to restore the saved document position and selection state.

`Control-X`, `r`, `l` opens the same persistent location inventory without
starting from a specific name.

## Store and insert named text

Select nonempty text and press `Control-X`, `r`, `Space`. Enter a slot name and
press Enter. A successful save deactivates the region while retaining mark.
Move point to an insertion target, press `Control-X`, `r`, `i`, select the
slot, and press Enter. The stored text is inserted as an ordinary reversible
edit.

`Control-X`, `r`, `s` stores text entered through a prompt. `Control-X`, `r`,
`n` stores a signed integer, and `Control-X`, `r`, `+` increments one existing
integer slot with overflow checking. Storage prompts identify the value type,
and retrieval lists show only compatible slots. Text and integer entries show
a short value preview beside the name. Type to filter, move with Up or Down,
and press Enter to choose.

## Store and restore a pane layout

Arrange the current panes and documents, then press `Control-X`, `r`, `w` and
name the snapshot. Change the layout. Press `Control-X`, `r`, `f`, choose the
saved name, and press Enter.

Odra restores the portable pane arrangement, targets, active pane, and pane
dedication. When the current terminal is too small for the complete tree, it
restores the compatible portion and reports the partial result.
