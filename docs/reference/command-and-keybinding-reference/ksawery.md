<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Ksawery Commands

[Command and Keybinding Reference](index.md) | [Alphabetical Index](alphabetical-index.md)

Detailed behavior: [Ksawery Reference](../ksawery/index.md).


## Status and staging

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-ksawery-clear-marks"></a>`ksawery-clear-marks` | Contextual: `0` | Clear the current repository target group. |
| <a id="command-ksawery-conflict-mark-resolved"></a>`ksawery-conflict-mark-resolved` | Contextual: `x` | Stage the exact saved text result for the selected conflict. |
| <a id="command-ksawery-discard"></a>`ksawery-discard` | Contextual: `k` | Discard the selected tracked working-tree path after confirmation. |
| <a id="command-ksawery-mark"></a>`ksawery-mark` | Contextual: `*` | Add the selected repository target to the current group. |
| <a id="command-ksawery-sequence-mark"></a>`ksawery-sequence-mark` | Contextual: `a` | Append the selected exact History commit and chosen merge mainline to the ordered sequence set. |
| <a id="command-ksawery-sequence-unmark"></a>`ksawery-sequence-unmark` | Contextual: `U` | Remove the selected exact History commit from the ordered sequence set. |
| <a id="command-ksawery-stage"></a>`ksawery-stage` | Contextual: `s` | Stage the selected repository target or compatible group. |
| <a id="command-ksawery-unmark"></a>`ksawery-unmark` | Contextual: `-` | Remove the selected repository target from the current group. |
| <a id="command-ksawery-unstage"></a>`ksawery-unstage` | Contextual: `u` | Unstage the selected repository target or compatible group. |

## History and commits

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-ksawery-amend"></a>`ksawery-amend` | Contextual: `A` | Compose a confirmed replacement of the observed repository HEAD. |
| <a id="command-ksawery-blame"></a>`ksawery-blame` | Contextual: `B B`, `B b` | Attribute the selected repository path to bounded exact commits. |
| <a id="command-ksawery-commit"></a>`ksawery-commit` | Contextual: `c` | Compose a checked normal repository commit. |
| <a id="command-ksawery-fixup"></a>`ksawery-fixup` | Contextual: `F` | Create a non-rewriting fixup commit for the selected exact revision. |
| <a id="command-ksawery-history"></a>`ksawery-history` | Contextual: `h` | Open bounded repository history in the current Ksawery session. |
| <a id="command-ksawery-history-next-page"></a>`ksawery-history-next-page` | Contextual: `f` | Load the next bounded repository history page. |
| <a id="command-ksawery-reflog"></a>`ksawery-reflog` | Contextual: `l r` | Open bounded checked repository reflog entries. |

## Branches and sequences

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-ksawery-bisect-bad"></a>`ksawery-bisect-bad` | Contextual: `B` | Mark the exact bad boundary or classify the current bisect candidate as bad. |
| <a id="command-ksawery-bisect-good"></a>`ksawery-bisect-good` | Contextual: `G` | Mark an exact good boundary or classify the current bisect candidate as good. |
| <a id="command-ksawery-bisect-reset"></a>`ksawery-bisect-reset` | Contextual: `~` | Reset the checked active bisect to its verified origin. |
| <a id="command-ksawery-bisect-skip"></a>`ksawery-bisect-skip` | Contextual: `\|` | Skip classification of the checked current bisect candidate. |
| <a id="command-ksawery-bisect-start"></a>`ksawery-bisect-start` | Contextual: `?` | Start manual bisect from the checked exact bad and good boundaries. |
| <a id="command-ksawery-branch-create"></a>`ksawery-branch-create` | Contextual: `n` | Create one confirmed local branch at the checked repository HEAD. |
| <a id="command-ksawery-branch-delete"></a>`ksawery-branch-delete` | Contextual: `D` | Delete one confirmed exact merged local branch without force. |
| <a id="command-ksawery-branch-rename"></a>`ksawery-branch-rename` | Contextual: `R` | Rename one confirmed exact local branch. |
| <a id="command-ksawery-branch-switch"></a>`ksawery-branch-switch` | Contextual: `S` | Switch to one confirmed exact local branch when repository and editor state are safe. |
| <a id="command-ksawery-cherry-pick"></a>`ksawery-cherry-pick` | Contextual: `P` | Confirm and cherry-pick the marked exact History commits in order. |
| <a id="command-ksawery-cherry-pick-abort"></a>`ksawery-cherry-pick-abort` | Contextual: `Y` | Abort the checked active cherry-pick after exact confirmation. |
| <a id="command-ksawery-cherry-pick-continue"></a>`ksawery-cherry-pick-continue` | Contextual: `{` | Continue the checked active cherry-pick and its retained ordered set. |
| <a id="command-ksawery-cherry-pick-skip"></a>`ksawery-cherry-pick-skip` | Contextual: `l` | Skip the checked cherry-pick step and continue its retained ordered set. |
| <a id="command-ksawery-merge"></a>`ksawery-merge` | Contextual: `i` | Merge the selected exact ref while allowing a merge commit. |
| <a id="command-ksawery-merge-abort"></a>`ksawery-merge-abort` | Contextual: `X` | Abort the checked active merge after exact confirmation. |
| <a id="command-ksawery-merge-continue"></a>`ksawery-merge-continue` | Contextual: `&gt;` | Continue the checked active merge after all conflicts are resolved. |
| <a id="command-ksawery-merge-fast-forward"></a>`ksawery-merge-fast-forward` | Contextual: `=` | Merge the selected exact ref only when it can fast-forward. |
| <a id="command-ksawery-merge-no-fast-forward"></a>`ksawery-merge-no-fast-forward` | Contextual: `I` | Merge the selected exact ref through a required merge commit. |
| <a id="command-ksawery-rebase"></a>`ksawery-rebase` | Contextual: `e` | Replay the checked current branch onto the selected exact base. |
| <a id="command-ksawery-rebase-abort"></a>`ksawery-rebase-abort` | Contextual: `Z` | Abort the checked active rebase after exact confirmation. |
| <a id="command-ksawery-rebase-autosquash"></a>`ksawery-rebase-autosquash` | Contextual: `E` | Review and apply an exact bounded autosquash plan onto the selected base. |
| <a id="command-ksawery-rebase-continue"></a>`ksawery-rebase-continue` | Contextual: `]` | Continue the checked active rebase after all conflicts are resolved. |
| <a id="command-ksawery-rebase-skip"></a>`ksawery-rebase-skip` | Contextual: `;` | Skip the exact current replay step after confirmation. |
| <a id="command-ksawery-revert"></a>`ksawery-revert` | Contextual: `V` | Confirm and revert the marked exact History commits in order. |
| <a id="command-ksawery-revert-abort"></a>`ksawery-revert-abort` | Contextual: `Q` | Abort the checked active revert after exact confirmation. |
| <a id="command-ksawery-revert-continue"></a>`ksawery-revert-continue` | Contextual: `}` | Continue the checked active revert and its retained ordered set. |
| <a id="command-ksawery-revert-skip"></a>`ksawery-revert-skip` | Contextual: `j` | Skip the checked revert step and continue its retained ordered set. |
| <a id="command-ksawery-tag-create"></a>`ksawery-tag-create` | Contextual: `t` | Create one confirmed lightweight local tag at the selected exact commit. |
| <a id="command-ksawery-tag-delete"></a>`ksawery-tag-delete` | Contextual: `T` | Delete one confirmed exact local tag. |

## Remotes and repositories

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-ksawery-fetch"></a>`ksawery-fetch` | Contextual: `&amp;` | Fetch the selected checked repository remote. |
| <a id="command-ksawery-push"></a>`ksawery-push` | Contextual: `p` | Confirm and push one exact tracked repository branch. |
| <a id="command-ksawery-stashes"></a>`ksawery-stashes` | Contextual: `z l`, `z z` | Open checked repository stashes in the current Ksawery session. |
| <a id="command-ksawery-worktrees"></a>`ksawery-worktrees` | Contextual: `Z Z`, `Z l` | Open checked linked worktrees in the current Ksawery session. |

## Inspection and operations

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-ksawery-conflict-assist"></a>`ksawery-conflict-assist` | Contextual: `H` | Inspect the selected conflict with the configured assistance provider. |
| <a id="command-ksawery-conflict-delete"></a>`ksawery-conflict-delete` | Contextual: `K` | Record a resolved deletion for the selected conflict after confirmation. |
| <a id="command-ksawery-conflict-use-applied"></a>`ksawery-conflict-use-applied` | Contextual: `3` | Replace the selected conflict with its complete applied side after confirmation. |
| <a id="command-ksawery-conflict-use-base"></a>`ksawery-conflict-use-base` | Contextual: `1` | Replace the selected conflict with its complete base side after confirmation. |
| <a id="command-ksawery-conflict-use-current"></a>`ksawery-conflict-use-current` | Contextual: `2` | Replace the selected conflict with its complete current side after confirmation. |
| <a id="command-ksawery-processes"></a>`ksawery-processes` | Contextual: `$` | Inspect bounded repository processes in the current Ksawery session. |
| <a id="command-ksawery-provider-disable"></a>`ksawery-provider-disable` | M-x only | Disable the active personal Ksawery provider and restore built-in fallback behavior. |
| <a id="command-ksawery-provider-reload"></a>`ksawery-provider-reload` | Contextual: `L` | Reload personal configuration and atomically replace its Ksawery provider generation. |
| <a id="command-ksawery-providers"></a>`ksawery-providers` | Contextual: `v` | Inspect active and retained Ksawery extension provider state. |
| <a id="command-ksawery-raw-command"></a>`ksawery-raw-command` | Contextual: `!` | Compose one separately confirmed raw Git or shell command in the current Ksawery session. |
| <a id="command-ksawery-refs"></a>`ksawery-refs` | Contextual: `b` | Open bounded repository refs in the current Ksawery session. |
| <a id="command-ksawery-sequence"></a>`ksawery-sequence` | Contextual: `o` | Inspect the active repository sequence in the current Ksawery session. |
| <a id="command-ksawery-status"></a>`ksawery-status` | M-x only | Open repository Status in a full-canvas Ksawery session. |
