<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Darek Commands

[Command and Keybinding Reference](index.md) | [Alphabetical Index](alphabetical-index.md)

Detailed behavior: [Darek Reference](../darek/index.md).


## Panel and navigation

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-darek-collapse-all-projects"></a>`darek-collapse-all-projects` | Contextual: `C-c C-p c a` | Collapse every visible Darek Project root. |
| <a id="command-darek-collapse-or-parent"></a>`darek-collapse-or-parent` | Contextual: `Left`, `M-h`, `h` | Collapse the selected Darek node or move to its parent. |
| <a id="command-darek-collapse-parent"></a>`darek-collapse-parent` | Contextual: `H` | Collapse the selected Darek node parent. |
| <a id="command-darek-focus-toggle"></a>`darek-focus-toggle` | Direct/Modal: `C-x t o` | Exchange focus between Darek and the most recent ordinary pane. |
| <a id="command-darek-next-node"></a>`darek-next-node` | Contextual: `Down`, `n` | Move to the next visible Darek node. |
| <a id="command-darek-next-project"></a>`darek-next-project` | Contextual: `C-j` | Move to the next visible Darek Project root. |
| <a id="command-darek-next-sibling"></a>`darek-next-sibling` | Contextual: `M-n` | Move to the next visible Darek sibling. |
| <a id="command-darek-other-pane-next-line"></a>`darek-other-pane-next-line` | Contextual: `M-N` | Scroll the Darek preview pane forward by one line. |
| <a id="command-darek-other-pane-next-page"></a>`darek-other-pane-next-page` | Contextual: `PageDown` | Scroll the Darek preview pane forward by one page. |
| <a id="command-darek-other-pane-previous-line"></a>`darek-other-pane-previous-line` | Contextual: `M-P` | Scroll the Darek preview pane backward by one line. |
| <a id="command-darek-other-pane-previous-page"></a>`darek-other-pane-previous-page` | Contextual: `PageUp` | Scroll the Darek preview pane backward by one page. |
| <a id="command-darek-parent-node"></a>`darek-parent-node` | Contextual: `u` | Move to the visible parent Darek node. |
| <a id="command-darek-previous-node"></a>`darek-previous-node` | Contextual: `Up`, `p` | Move to the previous visible Darek node. |
| <a id="command-darek-previous-project"></a>`darek-previous-project` | Contextual: `C-k` | Move to the previous visible Darek Project root. |
| <a id="command-darek-previous-sibling"></a>`darek-previous-sibling` | Contextual: `M-p` | Move to the previous visible Darek sibling. |
| <a id="command-darek-project-collapse"></a>`darek-project-collapse` | Contextual: `C-c C-p c c` | Collapse the current Darek Project root. |
| <a id="command-darek-project-collapse-others"></a>`darek-project-collapse-others` | Contextual: `C-c C-p c o` | Collapse every other Darek Project root. |
| <a id="command-darek-root-parent"></a>`darek-root-parent` | Contextual: `M-H` | Show the parent of the exclusive Darek root. |
| <a id="command-darek-toggle"></a>`darek-toggle` | Direct/Modal: `C-x t t` | Show or hide the Darek tree panel. |
| <a id="command-darek-toggle-diagnostics"></a>`darek-toggle-diagnostics` | M-x only | Show or hide copied diagnostic decorations in Darek. |
| <a id="command-darek-toggle-directory-compression"></a>`darek-toggle-directory-compression` | M-x only | Enable or disable compact single-directory hierarchy indentation. |
| <a id="command-darek-toggle-extra-width"></a>`darek-toggle-extra-width` | Contextual: `W` | Exchange Darek normal and extra-wide widths. |
| <a id="command-darek-toggle-file-follow"></a>`darek-toggle-file-follow` | Contextual: `t f` | Enable or disable revealing the active document in Darek. |
| <a id="command-darek-toggle-file-watch"></a>`darek-toggle-file-watch` | Contextual: `t a` | Enable or disable bounded filesystem watch reconciliation. |
| <a id="command-darek-toggle-hidden-files"></a>`darek-toggle-hidden-files` | Contextual: `t h` | Show or hide dot-prefixed Darek entries. |
| <a id="command-darek-toggle-peek"></a>`darek-toggle-peek` | Contextual: `P` | Enable or disable preview of the selected Darek file. |
| <a id="command-darek-toggle-vcs-decorations"></a>`darek-toggle-vcs-decorations` | Contextual: `t d`, `t g` | Show or hide copied version-control decorations in Darek. |
| <a id="command-darek-toggle-vcs-ignored"></a>`darek-toggle-vcs-ignored` | Contextual: `t i` | Show or hide Darek entries marked ignored by the active version-control provider. |
| <a id="command-darek-toggle-width-lock"></a>`darek-toggle-width-lock` | Contextual: `t w` | Enable or disable automatic Darek width fitting. |
| <a id="command-darek-workspace-next"></a>`darek-workspace-next` | Contextual: `C-c C-w n` | Select the next registered Workspace for Darek. |

## Opening and presentation

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-darek-bulk-actions"></a>`darek-bulk-actions` | Contextual: `M-m` | Open the selected Darek context in Maksym for checked bulk actions. |
| <a id="command-darek-close"></a>`darek-close` | Contextual: `Q` | Close Darek and release its retained state. |
| <a id="command-darek-context-actions"></a>`darek-context-actions` | Contextual: `M-RET`, `secondary-button press` | List commands applicable to the selected Darek node. |
| <a id="command-darek-decrease-width"></a>`darek-decrease-width` | Contextual: `&lt;` | Reduce Darek width by one bounded step. |
| <a id="command-darek-filter"></a>`darek-filter` | Contextual: `/` | Filter Darek by a bounded copied name substring. |
| <a id="command-darek-find-current-file"></a>`darek-find-current-file` | M-x only | Reveal the active document file in Darek. |
| <a id="command-darek-fit-width"></a>`darek-fit-width` | Contextual: `=` | Fit Darek width to visible bounded content. |
| <a id="command-darek-help"></a>`darek-help` | Contextual: `?` | Describe effective Darek commands and bindings. |
| <a id="command-darek-help-advanced"></a>`darek-help-advanced` | Contextual: `C-?` | Describe the complete effective Darek command and prefix map. |
| <a id="command-darek-hide"></a>`darek-hide` | Contextual: `q` | Hide Darek while preserving its view state. |
| <a id="command-darek-increase-width"></a>`darek-increase-width` | Contextual: `&gt;` | Increase Darek width by one bounded step. |
| <a id="command-darek-narrow-current-project"></a>`darek-narrow-current-project` | M-x only | Show only the current Project tree in Darek. |
| <a id="command-darek-open"></a>`darek-open` | Contextual: `o o` | Open the selected Darek node in the current destination. |
| <a id="command-darek-open-and-hide"></a>`darek-open-and-hide` | Contextual: `o c` | Open the selected Darek node and hide Darek. |
| <a id="command-darek-open-external"></a>`darek-open-external` | Contextual: `o x` | Open the selected Darek node through an external provider. |
| <a id="command-darek-open-mru-pane"></a>`darek-open-mru-pane` | Contextual: `o r` | Open the selected Darek node in the most recent eligible pane. |
| <a id="command-darek-open-split-below"></a>`darek-open-split-below` | Contextual: `o v` | Open the selected Darek node in a new pane below. |
| <a id="command-darek-open-split-right"></a>`darek-open-split-right` | Contextual: `o h` | Open the selected Darek node in a new pane to the right. |
| <a id="command-darek-panel-left"></a>`darek-panel-left` | M-x only | Place Darek at the left editor edge. |
| <a id="command-darek-panel-right"></a>`darek-panel-right` | M-x only | Place Darek at the right editor edge. |
| <a id="command-darek-project-add"></a>`darek-project-add` | Contextual: `C-c C-p a` | Add a registered Project to the current Darek Workspace. |
| <a id="command-darek-refresh"></a>`darek-refresh` | Contextual: `g`, `r` | Refresh the selected Darek directory generation. |
| <a id="command-darek-root-current-directory"></a>`darek-root-current-directory` | Contextual: `M-L` | Show the selected Darek directory as the exclusive root. |
| <a id="command-darek-select"></a>`darek-select` | M-x only | Show and focus the Darek tree panel. |
| <a id="command-darek-select-sort"></a>`darek-select-sort` | Contextual: `s` | Select the deterministic Darek sibling ordering. |
| <a id="command-darek-shell-command"></a>`darek-shell-command` | Contextual: `!` | Run a shell command from the selected Darek context. |
| <a id="command-darek-shell-command-project"></a>`darek-shell-command-project` | Contextual: `M-!` | Run a shell command from the selected Darek Project root. |
| <a id="command-darek-show-all-projects"></a>`darek-show-all-projects` | M-x only | Show every Darek Project root. |
| <a id="command-darek-show-current-project"></a>`darek-show-current-project` | M-x only | Show the active Project in Darek. |
| <a id="command-darek-show-directory"></a>`darek-show-directory` | M-x only | Select and show one local directory in Darek. |
| <a id="command-darek-structure-action"></a>`darek-structure-action` | Contextual: `M-l`, `Right`, `TAB`, `l` | Expand, collapse, or visit the selected Darek node. |
| <a id="command-darek-visit-action"></a>`darek-visit-action` | Contextual: `RET` | Visit the selected Darek node. |
| <a id="command-darek-workspace-switch"></a>`darek-workspace-switch` | Contextual: `C-c C-w s` | Select a registered Workspace for Darek. |

## Resource operations

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-darek-copy-absolute-path"></a>`darek-copy-absolute-path` | Contextual: `y a` | Retain the selected Darek node absolute path. |
| <a id="command-darek-copy-name"></a>`darek-copy-name` | Contextual: `y n` | Retain the selected Darek node filesystem name. |
| <a id="command-darek-copy-node"></a>`darek-copy-node` | Contextual: `y f` | Copy the selected Darek filesystem node. |
| <a id="command-darek-copy-project-relative-path"></a>`darek-copy-project-relative-path` | Contextual: `y r` | Retain the selected Darek node path relative to its Project. |
| <a id="command-darek-copy-project-root"></a>`darek-copy-project-root` | Contextual: `y p` | Retain the selected Darek node Project root. |
| <a id="command-darek-create-directory"></a>`darek-create-directory` | Contextual: `c d` | Create a directory beneath the resolved Darek directory. |
| <a id="command-darek-create-file"></a>`darek-create-file` | Contextual: `c f` | Create a file beneath the resolved Darek directory. |
| <a id="command-darek-delete-node"></a>`darek-delete-node` | Contextual: `d` | Review and permanently delete the selected Darek filesystem node. |
| <a id="command-darek-move-node"></a>`darek-move-node` | Contextual: `m` | Move the selected Darek filesystem node. |
| <a id="command-darek-move-project-down"></a>`darek-move-project-down` | Contextual: `M-Down` | Move the current Darek Project later in its Workspace. |
| <a id="command-darek-move-project-up"></a>`darek-move-project-up` | Contextual: `M-Up` | Move the current Darek Project earlier in its Workspace. |
| <a id="command-darek-project-remove"></a>`darek-project-remove` | Contextual: `C-c C-p d` | Remove the current Project from the Darek Workspace. |
| <a id="command-darek-project-rename"></a>`darek-project-rename` | Contextual: `C-c C-p r` | Rename the current Darek Project. |
| <a id="command-darek-rename-node"></a>`darek-rename-node` | Contextual: `R` | Rename the selected Darek filesystem node. |
