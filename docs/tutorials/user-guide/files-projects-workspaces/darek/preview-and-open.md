<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Preview and Open Files

This chapter uses Darek to preview files, open them in deliberate pane
placements, follow the active file, and fit the tree panel to the current
terminal.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../../getting-started/prepare-exercises.md).

Complete [Browse Trees](browse-trees.md). Open the maintained `User Guide`
Workspace and leave Darek visible with both Project roots available.

If the Workspace is not registered, recreate it through the installed helper
and launch Odra:

```sh
"$HOME/odra-guide/kit/bin/odra-guide" reset workspace-state
odra
```

## Open in the Active Pane

In Darek, select `Forecast Engine/src/forecast/model.odin` and press `RET`. Odra opens
the file in the active ordinary pane and moves focus there. The tree remains
visible with the same selection and expansion state.

Press `C-x t o` to return focus to Darek. Select
`Report Console/templates/daily.txt`, press `o o`, and confirm that the file
replaces the document shown in the active ordinary pane. `o o` provides the
explicit equivalent of the ordinary `RET` visit.

Press `o c` on another file to open it and hide Darek in one action. Press
`C-x t t` to restore the panel; its tree state remains available.

## Open in a New Pane

Select `Forecast Engine/main.odin` and press `o h`. Odra creates an ordinary
pane to the right and opens the file there. Return to Darek, select
`Report Console/main.rkt`, and press `o v` to create a pane below and open that
file.

Use `o r` to open the next selected file in the most recently used eligible
ordinary pane without creating another split. All placements revalidate the
selected file and layout before publication. A rejected placement leaves the
existing pane tree and documents unchanged.

## Preview Without Leaving the Tree

Select a regular file and press `P`. Its contents appear in an ordinary pane,
but input focus remains in Darek. Move to another file to replace the preview.

Press `M-N` and `M-P` to scroll the preview forward or backward by one line.
Use `PageDown` and `PageUp` to move by one page. These commands scroll the
preview rather than the tree.

Press `P` again to disable preview. A preview-owned document closes when it is
no longer needed, but a document that was adopted, modified, or referenced by
another pane remains open.

## Follow the Active File

With Darek focused, press `t f` to enable file follow. Move to an ordinary
pane with `C-x t o`, then switch among files. Darek reveals and selects the
newest active file whenever it belongs to the visible roots.

Rapid file changes are coalesced so the tree publishes only the newest checked
location. Press `t f` again to stop following; manual tree selection then
remains stable while ordinary files change.

## Fit the Panel

Press `<` or `>` to reduce or increase the normal panel width in four-column
steps. Press `=` to fit the current visible labels within the supported width
bounds. Press `W` to exchange the normal width with the 48-column wide
presentation.

Run `M-x darek-panel-right` to move Darek to the right edge, or
`M-x darek-panel-left` to return it to the left. Press `t w` to retain the
selected width during later layout adjustment; press it again to return width
control to normal fitting behavior.

Panel side and width affect presentation only. The shared layout remains the
owner of ordinary pane geometry and focus history.

## Hide, Restore, and Close Darek

Press `q` with Darek focused to hide the panel without discarding tree state.
Press `C-x t t` to restore it with its expansion, selection, viewport, preview
policy, and file-follow policy retained for the editor session.

Press `Q` to close Darek and release its retained tree state. A later
`C-x t t` creates a new tree from the active Workspace, Project, or document
context.

## Recover from Placement Problems

- If Odra reports insufficient terminal geometry, enlarge the terminal, close
  an ordinary pane, or reduce the panel width before retrying. No partial split
  is retained.
- If the selected file changed or disappeared, refresh with `r` and select the
  current node before opening it again.
- If preview has no eligible ordinary pane, create or retain one editing pane
  and retry without closing Darek.
- If file follow cannot reveal a document outside the visible roots, restore
  all Workspace Projects or show the applicable Dir or Project.
- Press `C-g` to cancel a pending placement or candidate interaction without
  changing the current layout.

## Verify the Result

You have completed this chapter when a selected file opens in the active,
right, below, and most-recently-used pane placements; preview scrolls while
Darek retains focus; file follow reveals the active file; panel side and width
change without losing tree state; and hiding, restoring, and closing have
distinct visible effects.

For exact placement, preview ownership, file-follow, panel bounds, and
commands, see the [Darek Reference](../../../../reference/darek/index.md).

---

[Previous: Browse Trees](browse-trees.md) ·
[Files, Projects, and Workspaces](../index.md) ·
[Next: Manage Resources](manage-resources.md)
