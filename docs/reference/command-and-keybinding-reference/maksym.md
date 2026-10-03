<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Maksym Commands

[Command and Keybinding Reference](index.md) | [Alphabetical Index](alphabetical-index.md)

Detailed behavior: [Maksym Reference](../maksym/index.md).


## Opening and navigation

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-maksym-editable-next-line"></a>`maksym-editable-next-line` | Contextual: `C-n`, `Down` | Move to the next editable Maksym filename. |
| <a id="command-maksym-editable-previous-line"></a>`maksym-editable-previous-line` | Contextual: `C-p`, `Up` | Move to the previous editable Maksym filename. |
| <a id="command-maksym-next-entry"></a>`maksym-next-entry` | Contextual: `C-n`, `SPC`, `n` | Move to the next Maksym entry. |
| <a id="command-maksym-next-marked-entry"></a>`maksym-next-marked-entry` | Contextual: `M-}` | Move to the next marked Maksym entry. |
| <a id="command-maksym-open-containing-directory"></a>`maksym-open-containing-directory` | Direct/Modal: `C-x C-j` | Open the active document directory and select its entry. |
| <a id="command-maksym-open-containing-directory-other-pane"></a>`maksym-open-containing-directory-other-pane` | Direct/Modal: `C-x 4 C-j` | Open the active document directory in another pane and select its entry. |
| <a id="command-maksym-open-directory"></a>`maksym-open-directory` | Direct/Modal: `C-x d` | Select and open one directory in Maksym. |
| <a id="command-maksym-open-directory-below"></a>`maksym-open-directory-below` | M-x only | Split below and open one selected directory there. |
| <a id="command-maksym-open-directory-other-pane"></a>`maksym-open-directory-other-pane` | Direct/Modal: `C-x 4 d` | Select and open one directory in another pane. |
| <a id="command-maksym-open-directory-right"></a>`maksym-open-directory-right` | M-x only | Split right and open one selected directory there. |
| <a id="command-maksym-open-entry"></a>`maksym-open-entry` | Contextual: `RET`, `e`, `f` | Open the selected Maksym entry. |
| <a id="command-maksym-open-entry-other-pane"></a>`maksym-open-entry-other-pane` | Contextual: `o` | Open the selected Maksym entry in another pane. |
| <a id="command-maksym-parent-directory"></a>`maksym-parent-directory` | Contextual: `^` | Open the parent directory in Maksym. |
| <a id="command-maksym-previous-entry"></a>`maksym-previous-entry` | Contextual: `C-p`, `p` | Move to the previous Maksym entry. |
| <a id="command-maksym-previous-marked-entry"></a>`maksym-previous-marked-entry` | Contextual: `M-{` | Move to the previous marked Maksym entry. |

## Listing and presentation

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-maksym-cancel-editable-listing"></a>`maksym-cancel-editable-listing` | Contextual: `C-c C-[`, `C-c C-k` | Discard prepared Maksym filename changes. |
| <a id="command-maksym-cycle-sort"></a>`maksym-cycle-sort` | Contextual: `s` | Cycle the active Maksym listing sort order. |
| <a id="command-maksym-describe-entry-type"></a>`maksym-describe-entry-type` | Contextual: `y` | Report the type of the selected Maksym entry. |
| <a id="command-maksym-display-entry-other-pane"></a>`maksym-display-entry-other-pane` | Contextual: `C-o` | Display the selected Maksym entry in another pane without changing focus. |
| <a id="command-maksym-find-file-relative"></a>`maksym-find-file-relative` | Contextual: `C-x C-f` | Find a path relative to the active Maksym directory. |
| <a id="command-maksym-jump-to-entry"></a>`maksym-jump-to-entry` | Contextual: `j` | Select and visit one entry in the active Maksym buffer. |
| <a id="command-maksym-refresh"></a>`maksym-refresh` | Contextual: `g` | Refresh the active Maksym directory generation. |
| <a id="command-maksym-shell-command"></a>`maksym-shell-command` | Contextual: `!`, `X` | Run a shell command on the active Maksym target set. |
| <a id="command-maksym-shell-command-async"></a>`maksym-shell-command-async` | Contextual: `&amp;` | Run an asynchronous shell command on the active Maksym target set. |
| <a id="command-maksym-shell-command-current-directory"></a>`maksym-shell-command-current-directory` | Contextual: `M-!` | Run a shell command from the active Maksym directory. |
| <a id="command-maksym-toggle-details"></a>`maksym-toggle-details` | Contextual: `(` | Toggle Maksym listing metadata. |
| <a id="command-maksym-toggle-editable-listing"></a>`maksym-toggle-editable-listing` | Contextual: `C-x C-q` | Enter or leave editable filename mode for the active Maksym listing. |

## Target sets

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-maksym-invert-marks"></a>`maksym-invert-marks` | Contextual: `t` | Invert marks in the active Maksym listing. |
| <a id="command-maksym-mark-entry"></a>`maksym-mark-entry` | Contextual: `m` | Add the selected Maksym entry to the target set. |
| <a id="command-maksym-unmark-all"></a>`maksym-unmark-all` | Contextual: `U` | Clear every mark in the active Maksym listing. |
| <a id="command-maksym-unmark-entry"></a>`maksym-unmark-entry` | Contextual: `u` | Remove the selected Maksym entry from the target set. |

## Filesystem changes

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-maksym-apply-editable-listing"></a>`maksym-apply-editable-listing` | Contextual: `C-c C-c`, `C-x C-s` | Validate, review, and apply prepared Maksym filename changes. |
| <a id="command-maksym-copy-absolute-paths"></a>`maksym-copy-absolute-paths` | Contextual: `C-0 w` | Copy absolute paths for the active Maksym target set. |
| <a id="command-maksym-copy-names"></a>`maksym-copy-names` | Contextual: `w` | Copy names for the active Maksym target set. |
| <a id="command-maksym-copy-targets"></a>`maksym-copy-targets` | Contextual: `C` | Copy the active Maksym target set to a selected directory. |
| <a id="command-maksym-create-directory"></a>`maksym-create-directory` | Contextual: `+` | Create a directory below the active Maksym directory. |
| <a id="command-maksym-delete-targets"></a>`maksym-delete-targets` | Contextual: `D` | Delete the active Maksym target set after review. |
| <a id="command-maksym-move-targets"></a>`maksym-move-targets` | Contextual: `R` | Move or rename the active Maksym target set. |
| <a id="command-maksym-rename-pattern"></a>`maksym-rename-pattern` | Contextual: `% R` | Prepare a bounded pattern rename for marked Maksym entries. |
