<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Browse Trees

This chapter opens Darek beside an ordinary pane and navigates directory and
Project roots while preserving the active editing context.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../../getting-started/prepare-exercises.md).

Complete [Manage a Workspace](../manage-a-workspace.md), then recreate the
maintained tutorial Workspace if the preceding exercises dissolved it:

```sh
"$HOME/odra-guide/kit/bin/odra-guide" reset workspace-state
```

Launch Odra with the isolated configuration base and open `User Guide` from
the Startup screen:

```sh
odra
```

The Workspace opens both `Forecast Engine` and `Report Console` atomically.

## Show and Focus Darek

Press `C-x t t`. Darek opens at the left edge and receives input focus while
the active file remains visible in its ordinary pane. Both Project roots are
visible, and the first directory level beneath every available root starts
expanded.

Press `C-x t o` to exchange focus between Darek and the ordinary pane. This
command works in both directions, so the same binding returns to the tree.

Run `M-x darek-select` when Darek is visible but you want to move focus to it
without toggling visibility.

## Move Through Visible Nodes

Use `n` and `p`, or `Down` and `Up`, to move through the visible tree in
display order. Movement stops at the first and last visible node.

Use `M-n` and `M-p` to move only among visible siblings. These commands skip
children and nodes in neighboring directory branches.

The selected row uses the active theme's selection role. Icons, labels, and
hierarchy remain semantic: color and shape assist recognition, but neither is
the only indication of a node's kind.

## Expand and Collapse Directories

Select a directory and press `TAB`, `l`, `M-l`, or `Right` to expand it. The
same structure action collapses an already expanded directory.

Press `h`, `M-h`, or `Left` to collapse an expanded directory. On a collapsed
node, the command selects its parent instead. Press `H` to select and collapse
the parent in one step, or `u` to select the visible parent without changing
its expansion.

Darek retains explicit expansion, collapse, selection, and viewport state for
the editor session. Press `r` or `g` to refresh the selected expanded
directory from one complete filesystem observation; a failed refresh leaves
the prior valid tree intact.

## Adjust Tree Presentation

Press `t h` to reveal dot-prefixed entries and press it again to hide them.
When the version-control provider marks ignored paths, `t i` applies the same
visibility control to those entries. Neither command changes the filesystem.

Press `s` to exchange ascending and descending name order. The selected
resource remains selected after the reorder. Press `/`, enter part of a name,
and press `RET` to retain matching entries and the directories that contain
them. Run `/` again and submit an empty value to restore the complete tree.

Press `t g` or `t d` to toggle the current version-control decoration
generation. Diagnostic decoration remains independently available through
`M-x darek-toggle-diagnostics`. These annotations arrive after the filesystem
tree and never delay initial browsing.

Press `t a` to enable provider-supported file watching. Watch activity marks a
bounded refresh as required; press `r` or `g` to reconcile it immediately.
Darek uses a complete directory observation after event loss or overflow
instead of replaying an uncertain event stream.

## Move Between Workspace Roots

Press `C-j` and `C-k` to move directly to the next or previous Project root.
The Workspace has no extra wrapper row: its ordered Projects are the
top-level siblings. A Workspace with one Project therefore has the same tree
shape as an exclusive Project.

Run `M-x darek-narrow-current-project` to show only the selected Project.
Run `M-x darek-show-all-projects` to restore every active Workspace root.
These commands change only Darek presentation; they do not alter Workspace
membership.

## Browse an Exclusive Dir or Project

Run `M-x darek-show-directory` to replace the tree with an ordinary local Dir.
Type to filter filesystem candidates, use the arrow keys to move, press `TAB`
to complete the first candidate, and press `RET` on the desired directory.

When a document is active without Project or Workspace context, `C-x t t`
uses its containing directory as the initial root. Run
`M-x darek-show-current-project` to return to the active Project as an
exclusive root, or `M-x darek-find-current-file` to reveal the active
document's directory.

In an exclusive Dir or Project tree, select a directory and press `M-L` to
make it the visible root. Press `M-H` to replace that root with its parent.
Neither command promotes a Dir, changes Project identity, or changes Workspace
membership.

## Inspect the Effective Controls

Press `?` for the common Darek commands. Run `M-x darek-help-advanced` for the
complete effective map, including remaps, masked bindings, prefixes, and
commands unavailable in the current context. Traditional terminal input may
report the factory `C-?` chord as Backspace inside Darek; the named command is
the unambiguous route.

## Recover from Tree Problems

- If a root is unavailable, restore or repair that Project before refreshing;
  Darek keeps the unavailable root visible instead of silently removing it.
- If a directory changed after observation, press `r` and retry the operation
  against the new complete generation.
- If the tree reaches its node or depth bound, collapse unrelated branches or
  choose a narrower exclusive root.
- If the terminal is too narrow for Darek and an ordinary pane, enlarge it or
  reduce the current pane layout before showing the panel again.
- Press `C-g` to cancel directory or Workspace candidate navigation without
  changing the current tree.

## Verify the Result

You have completed this chapter when Darek can move between the two tutorial
Project roots, expand and collapse nested directories with direct or arrow
keys, retain tree state while focus moves to editing and back, reveal hidden
entries, sort and filter without losing a retained selection, show an exclusive
Dir, and restore all Workspace roots without modifying durable membership.

For exact tree commands, session state, presentation, and bounds, see the
[Darek Reference](../../../../reference/darek/index.md).

---

[Previous: Darek](index.md) ·
[Files, Projects, and Workspaces](../index.md) ·
[Next: Preview and Open Files](preview-and-open.md)
