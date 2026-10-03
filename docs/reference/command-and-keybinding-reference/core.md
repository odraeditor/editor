<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Core Commands

[Command and Keybinding Reference](index.md) | [Alphabetical Index](alphabetical-index.md)

Detailed behavior: [Core Reference](../editor-core/index.md).


## Help and discovery

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-apropos-command"></a>`apropos-command` | Direct/Modal: `C-h a` | Search registered interactive commands and inspect one selection. |
| <a id="command-describe-bindings"></a>`describe-bindings` | Direct/Modal: `C-h b` | List active keymaps in resolution order. |
| <a id="command-describe-completion-state"></a>`describe-completion-state` | M-x only | Inspect the active completion session and provider state. |
| <a id="command-describe-function"></a>`describe-function` | Direct/Modal: `C-h f` | Select and describe one registered interactive command. |
| <a id="command-describe-key"></a>`describe-key` | Direct/Modal: `C-h k` | Describe the active command and alternatives for a key sequence. |
| <a id="command-describe-keymap"></a>`describe-keymap` | M-x only | Describe one keymap and its bindings and remaps. |
| <a id="command-describe-keymap-conflicts"></a>`describe-keymap-conflicts` | M-x only | Describe the most recent rejected keymap candidate. |
| <a id="command-describe-keymap-state"></a>`describe-keymap-state` | Direct/Modal: `C-h m` | Describe the catalog, profiles, states, surfaces, pending input, and generations. |
| <a id="command-describe-language-bundle"></a>`describe-language-bundle` | M-x only | Inspect one installed or factory language bundle and its lifecycle. |
| <a id="command-describe-language-service"></a>`describe-language-service` | M-x only | Inspect the selected language service and its current health. |
| <a id="command-describe-language-state"></a>`describe-language-state` | M-x only | Inspect copied language-analysis state for the active buffer. |
| <a id="command-describe-language-support"></a>`describe-language-support` | Direct: `C-c C-l i`; Modal: `g l i` | Inspect effective language and service catalogs for the active document. |
| <a id="command-describe-modal-repeat"></a>`describe-modal-repeat` | M-x only | Inspect the bounded semantic record used by modal last-change repetition. |
| <a id="command-describe-project"></a>`describe-project` | M-x only | Inspect the active Project identity and root summary. |
| <a id="command-describe-project-bindings"></a>`describe-project-bindings` | Direct/Modal: `C-c p C-h` | Inspect effective and reserved Project-prefix bindings. |
| <a id="command-describe-structural-state"></a>`describe-structural-state` | M-x only | Inspect copied structural syntax state for the active buffer. |
| <a id="command-describe-syntax-table"></a>`describe-syntax-table` | Direct/Modal: `C-h s` | Inspect the active structural syntax provider. |
| <a id="command-describe-theme"></a>`describe-theme` | M-x only | Inspect the active session theme and registry policy. |
| <a id="command-describe-variable"></a>`describe-variable` | Direct/Modal: `C-h v` | Inspect Odra configuration owners and their discovery commands. |
| <a id="command-execute-extended-command"></a>`execute-extended-command` | Modal: `:` | Select and execute a registered interactive command. |
| <a id="command-help-about-help"></a>`help-about-help` | Direct/Modal: `C-h ?` | List the built-in help and discovery commands. |
| <a id="command-info"></a>`info` | Direct/Modal: `C-h i` | Open the built-in User Guide index. |
| <a id="command-open-tutorial"></a>`open-tutorial` | Direct/Modal: `C-h t` | Open the built-in editing tutorial. |
| <a id="command-where-is"></a>`where-is` | Direct/Modal: `C-h w` | List active key sequences associated with a command. |

## Movement and locations

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-cursor-buffer-end"></a>`cursor-buffer-end` | Direct: `M-&gt;`; Modal: `G`, `M-&gt;` | Move to the end of the active buffer. |
| <a id="command-cursor-buffer-start"></a>`cursor-buffer-start` | Direct: `M-&lt;`; Modal: `M-&lt;`, `g g` | Move to the start of the active buffer. |
| <a id="command-cursor-find-next-character"></a>`cursor-find-next-character` | M-x only | Move to the next matching character on the logical line. |
| <a id="command-cursor-find-previous-character"></a>`cursor-find-previous-character` | M-x only | Move to the previous matching character on the logical line. |
| <a id="command-cursor-line-end"></a>`cursor-line-end` | Direct: `C-e`, `End`; Modal: `$`, `C-e`, `End` | Move to the logical line end. |
| <a id="command-cursor-line-first-non-whitespace"></a>`cursor-line-first-non-whitespace` | Direct: `M-m`; Modal: `M-m`, `^` | Move to the first non-whitespace grapheme on the logical line. |
| <a id="command-cursor-line-start"></a>`cursor-line-start` | Direct: `C-a`, `Home`; Modal: `0`, `C-a`, `Home` | Move to the logical line start. |
| <a id="command-cursor-next-grapheme"></a>`cursor-next-grapheme` | Direct: `C-f`, `Right`; Modal: `C-f`, `Right`, `l` | Move to the next grapheme. |
| <a id="command-cursor-next-line"></a>`cursor-next-line` | Direct: `C-n`, `Down`; Modal: `C-n`, `Down`, `j` | Move to the next logical line. |
| <a id="command-cursor-next-word"></a>`cursor-next-word` | Direct/Modal: `C-Down`, `C-Right`, `M-Right`, `M-f` | Move to the next word. |
| <a id="command-cursor-next-word-start"></a>`cursor-next-word-start` | Modal: `w` | Move to the next word start. |
| <a id="command-cursor-previous-grapheme"></a>`cursor-previous-grapheme` | Direct: `C-b`, `Left`; Modal: `C-b`, `Left`, `h` | Move to the previous grapheme. |
| <a id="command-cursor-previous-line"></a>`cursor-previous-line` | Direct: `C-p`, `Up`; Modal: `C-p`, `Up`, `k` | Move to the previous logical line. |
| <a id="command-cursor-previous-word"></a>`cursor-previous-word` | Direct: `C-Left`, `C-Up`, `M-Left`, `M-b`; Modal: `C-Left`, `C-Up`, `M-Left`, `M-b`, `b` | Move to the previous word. |
| <a id="command-cursor-till-next-character"></a>`cursor-till-next-character` | M-x only | Move immediately before the next matching character on the logical line. |
| <a id="command-cursor-till-previous-character"></a>`cursor-till-previous-character` | M-x only | Move immediately after the previous matching character on the logical line. |
| <a id="command-cursor-word-end"></a>`cursor-word-end` | Modal: `e` | Move to the current or next word end. |
| <a id="command-goto-char"></a>`goto-char` | Direct/Modal: `M-g c` | Move to a one-based grapheme position. |
| <a id="command-goto-line"></a>`goto-line` | Direct/Modal: `M-g g` | Move to a one-based logical line number. |
| <a id="command-list-locations"></a>`list-locations` | Direct/Modal: `C-x r l` | List persistent named locations. |
| <a id="command-next-location"></a>`next-location` | Direct/Modal: `M-g n` | Move to the next location from the active source. |
| <a id="command-previous-location"></a>`previous-location` | Direct/Modal: `M-g p` | Move to the previous location from the active source. |
| <a id="command-recenter"></a>`recenter` | Direct/Modal: `C-l` | Center point vertically in the active viewport. |
| <a id="command-save-location"></a>`save-location` | Direct/Modal: `C-x r m` | Save the active location under a persistent name. |
| <a id="command-scroll-next-page"></a>`scroll-next-page` | Direct/Modal: `Next` | Move toward the next viewport page. |
| <a id="command-scroll-previous-page"></a>`scroll-previous-page` | Direct/Modal: `Prior` | Move toward the previous viewport page. |
| <a id="command-visit-location"></a>`visit-location` | Direct/Modal: `C-x r b` | Visit one persistent named location. |

## Selection and narrowing

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-narrow-to-definition"></a>`narrow-to-definition` | Direct/Modal: `C-x n d` | Restrict the active view to the current language definition. |
| <a id="command-narrow-to-region"></a>`narrow-to-region` | Direct/Modal: `C-x n n` | Restrict the active view to the selected region. |
| <a id="command-pop-selection-location"></a>`pop-selection-location` | Direct/Modal: `C-u C-SPC` | Return to the prior retained selection or location. |
| <a id="command-select-buffer"></a>`select-buffer` | Direct/Modal: `C-x h` | Select the complete active buffer. |
| <a id="command-select-definition"></a>`select-definition` | Direct/Modal: `C-M-h` | Select the current language definition at point. |
| <a id="command-select-interaction-profile"></a>`select-interaction-profile` | M-x only | Select one interaction profile for this editor session. |
| <a id="command-select-paragraph"></a>`select-paragraph` | Direct: `M-h`; Modal: `M-h`, `a p`, `i p` | Select the logical paragraph at point. |
| <a id="command-select-rectangle"></a>`select-rectangle` | M-x only | Project the active canonical region as a logical grapheme rectangle. |
| <a id="command-select-theme"></a>`select-theme` | M-x only | Select one confirmed session theme. |
| <a id="command-select-word"></a>`select-word` | Direct: `M-@`; Modal: `M-@`, `a w`, `i w` | Select the direct-profile word at point. |
| <a id="command-set-mark-command"></a>`set-mark-command` | Direct/Modal: `C-SPC` | Set mark at point and activate the region. |
| <a id="command-widen"></a>`widen` | Direct/Modal: `C-x n w` | Restore the complete active buffer projection. |

## Editing and text transfer

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-capitalize-word"></a>`capitalize-word` | Direct/Modal: `M-c` | Capitalize the next word. |
| <a id="command-copy-rectangle"></a>`copy-rectangle` | M-x only | Copy the active logical rectangle as newline-separated retained text. |
| <a id="command-copy-region"></a>`copy-region` | Direct: `M-w`; Modal: `M-w`, `y` | Copy the active region into retained text. |
| <a id="command-delete-blank-lines"></a>`delete-blank-lines` | Direct/Modal: `C-x C-o` | Delete surrounding blank logical lines. |
| <a id="command-delete-next-grapheme"></a>`delete-next-grapheme` | Direct: `Delete`; Modal: `Delete`, `x` | Delete the next grapheme. |
| <a id="command-delete-previous-grapheme"></a>`delete-previous-grapheme` | Direct: `Backspace`; Modal: `Backspace`, `X` | Delete the previous grapheme. |
| <a id="command-delete-region"></a>`delete-region` | M-x only | Reversibly delete the active region without retaining it. |
| <a id="command-increment-number"></a>`increment-number` | Direct/Modal: `C-x r +` | Increment a persistent named integer. |
| <a id="command-indent-lines"></a>`indent-lines` | Direct: `C-M-\`; Modal: `&gt;`, `C-M-\` | Indent every logical line intersecting the active range. |
| <a id="command-indent-rigidly"></a>`indent-rigidly` | Direct/Modal: `C-x TAB` | Begin checked rigid indentation for the active region. |
| <a id="command-insert-indentation"></a>`insert-indentation` | Direct/Modal: `TAB` | Insert one resolved indentation unit. |
| <a id="command-insert-line-break"></a>`insert-line-break` | Direct/Modal: `RET` | Insert one canonical line feed. |
| <a id="command-insert-slot"></a>`insert-slot` | Direct/Modal: `C-x r i` | Insert one persistent named text value. |
| <a id="command-kill-line"></a>`kill-line` | Direct/Modal: `C-k` | Kill text from point through the logical line end. |
| <a id="command-kill-rectangle"></a>`kill-rectangle` | M-x only | Remove and retain every range in the active logical rectangle atomically. |
| <a id="command-kill-region"></a>`kill-region` | Direct: `C-w`; Modal: `C-w`, `c`, `d` | Copy and reversibly delete the active region. |
| <a id="command-kill-word"></a>`kill-word` | Direct/Modal: `M-d` | Kill the next word. |
| <a id="command-redo"></a>`redo` | Modal: `C-r` | Redo the preferred user-visible edit unit. |
| <a id="command-store-number"></a>`store-number` | Direct/Modal: `C-x r n` | Store a persistent named integer. |
| <a id="command-store-position"></a>`store-position` | Direct/Modal: `C-x r SPC` | Store the active document position under a persistent name. |
| <a id="command-store-region-text"></a>`store-region-text` | Direct/Modal: `C-x r s` | Store the active region as persistent named text. |
| <a id="command-store-text"></a>`store-text` | M-x only | Store a persistent named text value. |
| <a id="command-toggle-overwrite-mode"></a>`toggle-overwrite-mode` | Direct/Modal: `Insert` | Enable or disable direct overwrite input. |
| <a id="command-transpose-words"></a>`transpose-words` | Direct/Modal: `M-t` | Transpose the words around point. |
| <a id="command-undo"></a>`undo` | Direct: `C-/`, `C-_`, `C-x u`; Modal: `C-/`, `C-_`, `C-x u`, `u` | Undo one user-visible edit unit. |
| <a id="command-uppercase-current-line"></a>`uppercase-current-line` | M-x only | Uppercase the current logical line. |
| <a id="command-yank"></a>`yank` | Direct: `C-y`; Modal: `C-y`, `P` | Insert the newest retained text entry. |
| <a id="command-yank-after-point"></a>`yank-after-point` | Modal: `p` | Insert the newest retained text entry after the current grapheme. |
| <a id="command-yank-pop"></a>`yank-pop` | Direct/Modal: `M-y` | Replace the preceding yank with the next retained entry. |

## Files and buffers

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-find-alternate-file"></a>`find-alternate-file` | Direct/Modal: `C-x C-v` | Replace the current clean buffer with another local file. |
| <a id="command-find-file"></a>`find-file` | Direct/Modal: `C-x C-f` | Open or select a local file buffer. |
| <a id="command-find-file-other-pane"></a>`find-file-other-pane` | Direct/Modal: `C-x 4 f` | Open or select a local file buffer in another pane and focus it. |
| <a id="command-insert-file"></a>`insert-file` | Direct/Modal: `C-x i` | Insert the contents of a selected local file at point. |
| <a id="command-kill-buffer"></a>`kill-buffer` | Direct/Modal: `C-x k` | Close one selected buffer with dirty-state protection. |
| <a id="command-list-buffers"></a>`list-buffers` | Direct/Modal: `C-x C-b` | Present the live buffer inventory. |
| <a id="command-next-buffer"></a>`next-buffer` | Direct/Modal: `C-x Right` | Select the next buffer in stable session order. |
| <a id="command-previous-buffer"></a>`previous-buffer` | Direct/Modal: `C-x Left` | Select the previous buffer in stable session order. |
| <a id="command-save-associated-document"></a>`save-associated-document` | Direct/Modal: `C-x C-s` | Save the associated document. |
| <a id="command-save-some-buffers"></a>`save-some-buffers` | Direct/Modal: `C-x s` | Review or save every modified file-visiting buffer in the current session. |
| <a id="command-switch-to-buffer"></a>`switch-to-buffer` | Direct/Modal: `C-x b` | Select a live buffer or create a named buffer. |
| <a id="command-switch-to-buffer-other-pane"></a>`switch-to-buffer-other-pane` | Direct/Modal: `C-x 4 b` | Show a live or newly named buffer in another pane and focus it. |
| <a id="command-write-file"></a>`write-file` | Direct/Modal: `C-x C-w` | Save the current buffer to a selected file and visit that file. |

## Panes and layouts

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-balance-pane-areas"></a>`balance-pane-areas` | M-x only | Balance visible pane areas. |
| <a id="command-balance-panes"></a>`balance-panes` | Direct: `C-x +`; Modal: `C-w =`, `C-x +` | Balance visible pane dimensions. |
| <a id="command-restore-layout"></a>`restore-layout` | M-x only | Restore one persistent portable pane layout. |
| <a id="command-split-pane-below"></a>`split-pane-below` | Direct: `C-x 2`; Modal: `C-w s`, `C-x 2` | Split the active pane below. |
| <a id="command-split-pane-right"></a>`split-pane-right` | Direct: `C-x 3`; Modal: `C-w v`, `C-x 3` | Split the active pane to the right. |
| <a id="command-store-layout"></a>`store-layout` | Direct/Modal: `C-x r w` | Store the current portable pane layout. |

## Search and replacement

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-highlight-lines-matching-regexp"></a>`highlight-lines-matching-regexp` | Direct/Modal: `M-s h l` | Highlight matches on lines selected by a regular expression. |
| <a id="command-highlight-phrase"></a>`highlight-phrase` | Direct/Modal: `M-s h p` | Highlight every match for entered text. |
| <a id="command-highlight-regexp"></a>`highlight-regexp` | Direct/Modal: `M-s h r` | Highlight every match for an entered regular expression. |
| <a id="command-highlight-symbol-at-point"></a>`highlight-symbol-at-point` | Direct/Modal: `M-s h .` | Highlight every match for the symbol at point. |
| <a id="command-isearch-backward"></a>`isearch-backward` | Direct: `C-r`; Modal: `?`, `C-r` | Start or repeat backward incremental literal search. |
| <a id="command-isearch-backward-regexp"></a>`isearch-backward-regexp` | Direct/Modal: `C-M-r` | Start or repeat backward incremental regular-expression search. |
| <a id="command-isearch-forward"></a>`isearch-forward` | Direct: `C-s`; Modal: `/`, `C-s` | Start or repeat forward incremental literal search. |
| <a id="command-isearch-forward-regexp"></a>`isearch-forward-regexp` | Direct/Modal: `C-M-s` | Start or repeat forward incremental regular-expression search. |
| <a id="command-occur"></a>`occur` | Direct/Modal: `M-s o` | List lines matching a regular expression. |
| <a id="command-query-replace"></a>`query-replace` | Direct/Modal: `M-%` | Start interactive literal query replacement. |
| <a id="command-query-replace-regexp"></a>`query-replace-regexp` | Direct/Modal: `C-M-%` | Start interactive regular-expression query replacement. |
| <a id="command-search-next-occurrence"></a>`search-next-occurrence` | Modal: `n` | Visit the next occurrence from the most recent confirmed search. |
| <a id="command-search-previous-occurrence"></a>`search-previous-occurrence` | Modal: `N` | Visit the previous occurrence from the most recent confirmed search. |
| <a id="command-search-symbol-at-point"></a>`search-symbol-at-point` | Direct/Modal: `M-s .` | Search forward for the symbol at point. |
| <a id="command-search-word"></a>`search-word` | Direct/Modal: `M-s w` | Search forward for words matching entered text. |
| <a id="command-unhighlight-regexp"></a>`unhighlight-regexp` | Direct/Modal: `M-s h u` | Remove the active search highlight. |

## Projects and workspaces

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-project-close-buffers"></a>`project-close-buffers` | Direct/Modal: `C-c p k` | Close active Project buffers with ordinary dirty-state protection. |
| <a id="command-project-command-menu"></a>`project-command-menu` | Direct/Modal: `C-c p m` | Present the active Project command collection. |
| <a id="command-project-find-file"></a>`project-find-file` | Direct/Modal: `C-c p f` | Select and open one file in the active Project. |
| <a id="command-project-promote"></a>`project-promote` | M-x only | Save the active Dir as a Project. |
| <a id="command-project-refresh"></a>`project-refresh` | Direct/Modal: `C-c p i` | Reconcile active Project directory observations. |
| <a id="command-project-save-buffers"></a>`project-save-buffers` | Direct/Modal: `C-c p S` | Save modified file-backed buffers owned by the active Project. |
| <a id="command-project-search-repeat"></a>`project-search-repeat` | M-x only | Repeat the most recent Project search. |
| <a id="command-project-search-text"></a>`project-search-text` | M-x only | Search literal text across the active Project. |
| <a id="command-project-search-text-regexp"></a>`project-search-text-regexp` | M-x only | Search a regular expression across the active Project. |
| <a id="command-project-switch-buffer"></a>`project-switch-buffer` | Direct/Modal: `C-c p b` | Select one live buffer owned by the active Project. |
| <a id="command-project-unregister"></a>`project-unregister` | M-x only | Remove one selected Project from the global Project registry. |
| <a id="command-workspace-add-project"></a>`workspace-add-project` | M-x only | Add one selected Project to one selected Workspace. |
| <a id="command-workspace-remove-project"></a>`workspace-remove-project` | M-x only | Remove one selected Project from one selected Workspace. |
| <a id="command-workspace-unregister"></a>`workspace-unregister` | M-x only | Remove one selected Workspace from the global Workspace registry. |

## Language intelligence

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-complete-at-point"></a>`complete-at-point` | Direct/Modal: `C-M-i` | Request completion candidates at point. |
| <a id="command-completion-accept"></a>`completion-accept` | M-x only | Accept the selected completion candidate. |
| <a id="command-completion-cancel"></a>`completion-cancel` | M-x only | Cancel the active completion interaction. |
| <a id="command-completion-first"></a>`completion-first` | M-x only | Select the first completion candidate. |
| <a id="command-completion-inspect"></a>`completion-inspect` | M-x only | Inspect the active completion candidate. |
| <a id="command-completion-last"></a>`completion-last` | M-x only | Select the last completion candidate. |
| <a id="command-completion-next"></a>`completion-next` | M-x only | Select the next completion candidate. |
| <a id="command-completion-previous"></a>`completion-previous` | M-x only | Select the previous completion candidate. |
| <a id="command-completion-show-documentation"></a>`completion-show-documentation` | M-x only | Show documentation for the active completion candidate. |
| <a id="command-language-bundle-disable"></a>`language-bundle-disable` | M-x only | Deactivate language bundle contributions while preserving installed artifacts. |
| <a id="command-language-bundle-enable"></a>`language-bundle-enable` | M-x only | Review authority and prepare atomic language bundle activation. |
| <a id="command-language-bundle-install"></a>`language-bundle-install` | M-x only | Resolve, review, verify, and install one exact language bundle candidate. |
| <a id="command-language-bundle-list"></a>`language-bundle-list` | M-x only | List factory and installed language bundles with exact states. |
| <a id="command-language-bundle-refresh-catalogs"></a>`language-bundle-refresh-catalogs` | M-x only | Refresh configured language bundle catalogs without changing installed state. |
| <a id="command-language-bundle-remove"></a>`language-bundle-remove` | M-x only | Deactivate and remove an unrequired installed language bundle. |
| <a id="command-language-bundle-rollback"></a>`language-bundle-rollback` | M-x only | Restore the retained prior confirmed language bundle version. |
| <a id="command-language-bundle-search"></a>`language-bundle-search` | M-x only | Search confirmed language bundle catalog snapshots. |
| <a id="command-language-bundle-update"></a>`language-bundle-update` | M-x only | Prepare and activate one compatible language bundle update. |
| <a id="command-language-code-actions"></a>`language-code-actions` | Direct: `C-c C-l a`; Modal: `g l a` | Select and apply one checked language code action. |
| <a id="command-language-document-symbols"></a>`language-document-symbols` | Direct: `C-c C-l s`; Modal: `g l s` | Present document symbols through the shared candidate surface. |
| <a id="command-language-find-references"></a>`language-find-references` | Direct: `C-c C-l r`; Modal: `g r` | Present references through the shared result surface. |
| <a id="command-language-format-buffer"></a>`language-format-buffer` | Direct: `C-c C-l f`; Modal: `g l f` | Format the active document as one checked transaction. |
| <a id="command-language-format-region"></a>`language-format-region` | Modal: `g l f` | Format the active region as one checked transaction. |
| <a id="command-language-go-to-definition"></a>`language-go-to-definition` | Direct: `C-c C-l d`; Modal: `g d` | Visit a selected definition and retain the prior location. |
| <a id="command-language-rename"></a>`language-rename` | Direct: `C-c C-l n`; Modal: `g l n` | Preview and atomically apply one checked workspace rename. |
| <a id="command-language-show-hover"></a>`language-show-hover` | Direct: `C-c C-l h`; Modal: `K` | Show copied language hover content at point. |
| <a id="command-language-signature-help"></a>`language-signature-help` | M-x only | Show copied callable signatures at point. |
| <a id="command-language-support-doctor"></a>`language-support-doctor` | M-x only | Diagnose language selectors, providers, artifacts, executables, trust, and recovery. |
| <a id="command-language-workspace-symbols"></a>`language-workspace-symbols` | Direct: `C-c C-l S`; Modal: `g l S` | Query workspace symbols through the shared candidate surface. |
| <a id="command-structural-backward"></a>`structural-backward` | Direct/Modal: `C-M-b` | Move to the start of the previous named structural node. |
| <a id="command-structural-down"></a>`structural-down` | Direct/Modal: `C-M-d` | Move to the start of the first named child structural node. |
| <a id="command-structural-forward"></a>`structural-forward` | Direct/Modal: `C-M-f` | Move to the end of the next named structural node. |
| <a id="command-structural-indent"></a>`structural-indent` | M-x only | Indent the active structural range. |
| <a id="command-structural-select"></a>`structural-select` | Direct/Modal: `C-M-SPC` | Select the enclosing named structural node. |
| <a id="command-structural-up"></a>`structural-up` | Direct/Modal: `C-M-u` | Move to the start of the enclosing named structural node. |

## Terminals and processes

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-async-shell-command"></a>`async-shell-command` | Direct/Modal: `M-&amp;` | Run a shell command without replacing the active editor view. |
| <a id="command-compile"></a>`compile` | M-x only | Run and retain a compilation command. |
| <a id="command-recompile"></a>`recompile` | M-x only | Run the last retained compilation command. |
| <a id="command-shell-command"></a>`shell-command` | Direct/Modal: `M-!` | Run a shell command and present its output. |
| <a id="command-terminal-beginning-of-line"></a>`terminal-beginning-of-line` | M-x only | Move terminal copy point to the projected line beginning. |
| <a id="command-terminal-clear"></a>`terminal-clear` | M-x only | Clear the active terminal display through ordinary terminal input. |
| <a id="command-terminal-clear-scrollback"></a>`terminal-clear-scrollback` | M-x only | Clear retained scrollback for the active terminal. |
| <a id="command-terminal-copy-mode"></a>`terminal-copy-mode` | M-x only | Enter retained terminal text navigation. |
| <a id="command-terminal-copy-mode-done"></a>`terminal-copy-mode-done` | M-x only | Return from terminal copy mode to live input. |
| <a id="command-terminal-end-of-line"></a>`terminal-end-of-line` | M-x only | Move terminal copy point to the projected line end. |
| <a id="command-terminal-list"></a>`terminal-list` | M-x only | List retained terminal sessions. |
| <a id="command-terminal-new"></a>`terminal-new` | M-x only | Create and present another terminal session. |
| <a id="command-terminal-next-error"></a>`terminal-next-error` | M-x only | Visit the next recognized result location through unified location navigation. |
| <a id="command-terminal-next-prompt"></a>`terminal-next-prompt` | M-x only | Navigate to the next confirmed retained prompt boundary. |
| <a id="command-terminal-open"></a>`terminal-open` | M-x only | Select or create the active scope default terminal. |
| <a id="command-terminal-open-here"></a>`terminal-open-here` | M-x only | Create a terminal in the active resource directory. |
| <a id="command-terminal-open-link"></a>`terminal-open-link` | M-x only | Activate the validated hyperlink at the active terminal cursor. |
| <a id="command-terminal-open-other-pane"></a>`terminal-open-other-pane` | M-x only | Create or present a terminal in another pane. |
| <a id="command-terminal-open-project"></a>`terminal-open-project` | M-x only | Create a terminal in the active or recent Project. |
| <a id="command-terminal-previous-prompt"></a>`terminal-previous-prompt` | M-x only | Navigate to the previous confirmed retained prompt boundary. |
| <a id="command-terminal-rename"></a>`terminal-rename` | M-x only | Rename the active terminal session. |
| <a id="command-terminal-reset-cursor-point"></a>`terminal-reset-cursor-point` | M-x only | Align terminal copy point with the live cursor. |
| <a id="command-terminal-send-backspace"></a>`terminal-send-backspace` | M-x only | Send Backspace to the active terminal. |
| <a id="command-terminal-send-delete"></a>`terminal-send-delete` | M-x only | Send Delete to the active terminal. |
| <a id="command-terminal-send-down"></a>`terminal-send-down` | M-x only | Send Down to the active terminal. |
| <a id="command-terminal-send-escape"></a>`terminal-send-escape` | M-x only | Send Escape to the active terminal. |
| <a id="command-terminal-send-left"></a>`terminal-send-left` | M-x only | Send Left to the active terminal. |
| <a id="command-terminal-send-next"></a>`terminal-send-next` | M-x only | Send Page Down to the active terminal. |
| <a id="command-terminal-send-next-key"></a>`terminal-send-next-key` | M-x only | Forward the next normalized input to the active terminal. |
| <a id="command-terminal-send-prior"></a>`terminal-send-prior` | M-x only | Send Page Up to the active terminal. |
| <a id="command-terminal-send-return"></a>`terminal-send-return` | M-x only | Send Return to the active terminal. |
| <a id="command-terminal-send-right"></a>`terminal-send-right` | M-x only | Send Right to the active terminal. |
| <a id="command-terminal-send-space"></a>`terminal-send-space` | M-x only | Send Space to the active terminal. |
| <a id="command-terminal-send-tab"></a>`terminal-send-tab` | M-x only | Send Tab to the active terminal. |
| <a id="command-terminal-send-up"></a>`terminal-send-up` | M-x only | Send Up to the active terminal. |
| <a id="command-terminal-terminate"></a>`terminal-terminate` | M-x only | Request termination of the active terminal process. |
| <a id="command-terminal-toggle"></a>`terminal-toggle` | M-x only | Show or hide the remembered terminal presentation. |
| <a id="command-terminal-undo"></a>`terminal-undo` | M-x only | Send the configured terminal-side undo input. |
| <a id="command-terminal-yank"></a>`terminal-yank` | M-x only | Paste the newest retained text into the active terminal. |
| <a id="command-terminal-yank-pop"></a>`terminal-yank-pop` | M-x only | Replace the preceding terminal yank with the next retained entry. |

## Packages

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-package-advisory-list"></a>`package-advisory-list` | M-x only | List retained advisory evidence and effective local responses. |
| <a id="command-package-catalog-add"></a>`package-catalog-add` | M-x only | Confirm and add one exact package catalog identity and trust reference. |
| <a id="command-package-catalog-describe"></a>`package-catalog-describe` | M-x only | Inspect one catalog or package without collapsing trust dimensions. |
| <a id="command-package-catalog-disable"></a>`package-catalog-disable` | M-x only | Disable one configured package catalog without changing installed packages. |
| <a id="command-package-catalog-doctor"></a>`package-catalog-doctor` | M-x only | Diagnose catalog identity, endpoints, snapshots, failures, and recovery. |
| <a id="command-package-catalog-list"></a>`package-catalog-list` | M-x only | List explicitly configured catalogs and their confirmed refresh state. |
| <a id="command-package-catalog-refresh"></a>`package-catalog-refresh` | M-x only | Refresh selected catalog discovery state through configured endpoints. |
| <a id="command-package-catalog-remove"></a>`package-catalog-remove` | M-x only | Remove one configured package catalog without changing installed packages. |
| <a id="command-package-catalog-search"></a>`package-catalog-search` | M-x only | Search confirmed package catalog snapshots with curator attribution. |
| <a id="command-package-cleanup"></a>`package-cleanup` | M-x only | Delete only unreachable editor-owned package content. |
| <a id="command-package-curator-validate"></a>`package-curator-validate` | M-x only | Validate curator records without granting curation authority. |
| <a id="command-package-describe"></a>`package-describe` | M-x only | Inspect package provenance, authority, lifecycle, operation, and failure state. |
| <a id="command-package-disable"></a>`package-disable` | M-x only | Deactivate one package while preserving installed content. |
| <a id="command-package-discover"></a>`package-discover` | M-x only | Find human-readable package release candidates in confirmed catalogs. |
| <a id="command-package-doctor"></a>`package-doctor` | M-x only | Diagnose installed package state, recovery, authority, and activation. |
| <a id="command-package-enable"></a>`package-enable` | M-x only | Confirm authority and activate one installed package release. |
| <a id="command-package-install"></a>`package-install` | M-x only | Install one exact selected package release without activating it. |
| <a id="command-package-list"></a>`package-list` | M-x only | List installed package releases and their exact lifecycle states. |
| <a id="command-package-manual-acquire"></a>`package-manual-acquire` | M-x only | Resolve and confirm one exact manual package source. |
| <a id="command-package-remove"></a>`package-remove` | M-x only | Remove one inactive package release after dependency checks. |
| <a id="command-package-rollback"></a>`package-rollback` | M-x only | Restore the retained prior confirmed package release. |
| <a id="command-package-update"></a>`package-update` | M-x only | Activate one installed update while retaining the prior release for rollback. |

## Interface

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-gutter-cycle-line-number-mode"></a>`gutter-cycle-line-number-mode` | M-x only | Cycle the active view through line-number modes. |
| <a id="command-gutter-inspect-markers"></a>`gutter-inspect-markers` | M-x only | Inspect semantic markers at the active line. |
| <a id="command-gutter-inspect-numbering"></a>`gutter-inspect-numbering` | M-x only | Inspect the active view's effective numbering policy. |
| <a id="command-gutter-invoke-primary-marker-action"></a>`gutter-invoke-primary-marker-action` | M-x only | Invoke the primary semantic marker action at the active line. |
| <a id="command-gutter-refresh-markers"></a>`gutter-refresh-markers` | M-x only | Refresh semantic markers for the active buffer. |
| <a id="command-gutter-set-line-numbers-absolute"></a>`gutter-set-line-numbers-absolute` | M-x only | Use absolute numbering in the active view. |
| <a id="command-gutter-set-line-numbers-hybrid"></a>`gutter-set-line-numbers-hybrid` | M-x only | Use hybrid numbering in the active view. |
| <a id="command-gutter-set-line-numbers-none"></a>`gutter-set-line-numbers-none` | M-x only | Disable numbering in the active view. |
| <a id="command-gutter-set-line-numbers-relative"></a>`gutter-set-line-numbers-relative` | M-x only | Use relative numbering in the active view. |
| <a id="command-gutter-set-numbering-logical"></a>`gutter-set-numbering-logical` | M-x only | Use logical-line numbering in the active view. |
| <a id="command-gutter-set-numbering-visual"></a>`gutter-set-numbering-visual` | M-x only | Request visual-row numbering for the active view. |
| <a id="command-gutter-toggle-line-number-side"></a>`gutter-toggle-line-number-side` | M-x only | Move line numbers between the left and right Gutter. |
| <a id="command-gutter-toggle-line-numbers"></a>`gutter-toggle-line-numbers` | M-x only | Show or hide line numbers in the active view. |
| <a id="command-status-bar-actions"></a>`status-bar-actions` | M-x only | List actions exposed by visible Status Bar segments. |
| <a id="command-status-bar-activate-segment"></a>`status-bar-activate-segment` | M-x only | Select and invoke one visible Status Bar segment action. |
| <a id="command-status-bar-inspect"></a>`status-bar-inspect` | M-x only | Inspect visible Status Bar segments. |

## Editor lifecycle and tools

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-backward-kill-word"></a>`backward-kill-word` | Direct/Modal: `M-Backspace` | Kill the previous word. |
| <a id="command-call-last-kbd-macro"></a>`call-last-kbd-macro` | Direct/Modal: `C-x e` | Replay the most recently completed keyboard macro. |
| <a id="command-call-named-kbd-macro"></a>`call-named-kbd-macro` | M-x only | Replay a session-local named keyboard macro. |
| <a id="command-close-pane"></a>`close-pane` | Direct: `C-x 0`; Modal: `C-w c`, `C-x 0` | Close the active non-final pane. |
| <a id="command-comment-dwim"></a>`comment-dwim` | Direct/Modal: `M-;` | Add or remove a context-appropriate comment. |
| <a id="command-dabbrev-expand"></a>`dabbrev-expand` | Direct/Modal: `M-/` | Expand the word prefix before point from buffer text. |
| <a id="command-deactivate-mark"></a>`deactivate-mark` | M-x only | Deactivate the region while retaining mark. |
| <a id="command-display-buffer-other-pane"></a>`display-buffer-other-pane` | Direct/Modal: `C-x 4 C-o` | Display a selected buffer in another pane without changing focus. |
| <a id="command-downcase-word"></a>`downcase-word` | Direct/Modal: `M-l` | Lowercase the next word. |
| <a id="command-end-kbd-macro"></a>`end-kbd-macro` | Direct/Modal: `C-x )` | Finish recording and retain the current keyboard macro. |
| <a id="command-enlarge-pane-horizontally"></a>`enlarge-pane-horizontally` | Direct/Modal: `C-x }` | Enlarge the active pane horizontally by one column. |
| <a id="command-enlarge-pane-vertically"></a>`enlarge-pane-vertically` | Direct/Modal: `C-x ^` | Enlarge the active pane vertically by one row. |
| <a id="command-exchange-point-and-mark"></a>`exchange-point-and-mark` | Direct: `C-x C-x`; Modal: `C-x C-x`, `o` | Exchange point and mark and activate the region. |
| <a id="command-fill-paragraph"></a>`fill-paragraph` | Direct/Modal: `M-q` | Reflow the paragraph at point. |
| <a id="command-focus-next-pane"></a>`focus-next-pane` | Direct/Modal: `C-x o` | Focus the next pane in spatial order. |
| <a id="command-focus-pane-down"></a>`focus-pane-down` | Modal: `C-w j` | Focus the adjacent pane below. |
| <a id="command-focus-pane-left"></a>`focus-pane-left` | Modal: `C-w h` | Focus the adjacent pane to the left. |
| <a id="command-focus-pane-right"></a>`focus-pane-right` | Modal: `C-w l` | Focus the adjacent pane to the right. |
| <a id="command-focus-pane-up"></a>`focus-pane-up` | Modal: `C-w k` | Focus the adjacent pane above. |
| <a id="command-keep-only-pane"></a>`keep-only-pane` | Direct: `C-x 1`; Modal: `C-w o`, `C-x 1` | Keep only the active pane. |
| <a id="command-keyboard-quit"></a>`keyboard-quit` | M-x only | Cancel pending input or deactivate the active region. |
| <a id="command-kmacro-end-or-call-macro"></a>`kmacro-end-or-call-macro` | Direct/Modal: `F4` | Finish recording or replay the most recently completed keyboard macro. |
| <a id="command-list-language-diagnostics"></a>`list-language-diagnostics` | M-x only | Present current diagnostics for the active buffer or Project. |
| <a id="command-modal-enter-insert"></a>`modal-enter-insert` | Modal: `i` | Enter the modal profile Insert state at point. |
| <a id="command-modal-enter-insert-after"></a>`modal-enter-insert-after` | Modal: `a` | Move after the current grapheme and enter the modal profile Insert state. |
| <a id="command-modal-enter-insert-line-end"></a>`modal-enter-insert-line-end` | Modal: `A` | Move to the logical line end and enter the modal profile Insert state. |
| <a id="command-modal-enter-insert-line-first"></a>`modal-enter-insert-line-first` | Modal: `I` | Move to the first non-whitespace boundary and enter the modal profile Insert state. |
| <a id="command-modal-enter-normal"></a>`modal-enter-normal` | Modal: `C-[`, `C-v`, `ESC`, `V`, `v` | Cancel modal input and enter the modal profile Normal state. |
| <a id="command-modal-enter-replace"></a>`modal-enter-replace` | Modal: `R` | Enter the modal profile Replace state at point. |
| <a id="command-modal-enter-visual-block"></a>`modal-enter-visual-block` | Modal: `C-v` | Enter the modal profile Visual Block state over a logical rectangle. |
| <a id="command-modal-enter-visual-character"></a>`modal-enter-visual-character` | Modal: `v` | Enter the modal profile Visual Character state over the canonical region. |
| <a id="command-modal-enter-visual-line"></a>`modal-enter-visual-line` | Modal: `V` | Enter the modal profile Visual Line state over the canonical region. |
| <a id="command-modal-open-line-above"></a>`modal-open-line-above` | Modal: `O` | Insert one logical line above and enter the modal profile Insert state. |
| <a id="command-modal-open-line-below"></a>`modal-open-line-below` | Modal: `o` | Insert one logical line below and enter the modal profile Insert state. |
| <a id="command-modal-repeat-last-change"></a>`modal-repeat-last-change` | Modal: `.` | Repeat the most recent admitted modal change in the current context. |
| <a id="command-name-last-kbd-macro"></a>`name-last-kbd-macro` | Direct/Modal: `C-x C-k n` | Retain the most recent keyboard macro under a session-local name. |
| <a id="command-next-language-diagnostic"></a>`next-language-diagnostic` | M-x only | Move to the next current diagnostic. |
| <a id="command-normalize-indentation-to-spaces"></a>`normalize-indentation-to-spaces` | M-x only | Convert leading indentation to spaces. |
| <a id="command-normalize-indentation-to-tabs"></a>`normalize-indentation-to-tabs` | M-x only | Convert leading indentation to literal tabs. |
| <a id="command-open-directory"></a>`open-directory` | M-x only | Open one local Dir without creating a Project. |
| <a id="command-outdent-lines"></a>`outdent-lines` | Modal: `&lt;` | Outdent every logical line intersecting the active range. |
| <a id="command-previous-language-diagnostic"></a>`previous-language-diagnostic` | M-x only | Move to the previous current diagnostic. |
| <a id="command-recover-unsaved-work"></a>`recover-unsaved-work` | M-x only | Review retained unsaved-work recovery candidates. |
| <a id="command-reload-interaction-profile"></a>`reload-interaction-profile` | M-x only | Reload the staged interaction profile for this editor session. |
| <a id="command-reload-personal-commands"></a>`reload-personal-commands` | M-x only | Reload personal commands and their interaction profile. |
| <a id="command-replace-rectangle-text"></a>`replace-rectangle-text` | M-x only | Replace every range in the active logical rectangle atomically. |
| <a id="command-replace-regexp"></a>`replace-regexp` | M-x only | Replace every admitted regular-expression match atomically. |
| <a id="command-replace-string"></a>`replace-string` | M-x only | Replace every admitted literal match atomically. |
| <a id="command-request-editor-exit"></a>`request-editor-exit` | Direct/Modal: `C-x C-c` | Request orderly editor exit. |
| <a id="command-restart-language-service"></a>`restart-language-service` | Direct: `C-c C-l R`; Modal: `g l R` | Spend one bounded restart attempt for the selected failed language service. |
| <a id="command-rigid-indent-left"></a>`rigid-indent-left` | M-x only | Decrease active rigid indentation by one column. |
| <a id="command-rigid-indent-left-fast"></a>`rigid-indent-left-fast` | M-x only | Decrease active rigid indentation by one indentation width. |
| <a id="command-rigid-indent-right"></a>`rigid-indent-right` | M-x only | Increase active rigid indentation by one column. |
| <a id="command-rigid-indent-right-fast"></a>`rigid-indent-right-fast` | M-x only | Increase active rigid indentation by one indentation width. |
| <a id="command-shrink-pane-horizontally"></a>`shrink-pane-horizontally` | Direct/Modal: `C-x {` | Shrink the active pane horizontally by one column. |
| <a id="command-start-kbd-macro"></a>`start-kbd-macro` | Direct/Modal: `C-x (` | Start recording canonical commands into a fresh keyboard macro. |
| <a id="command-symbol-navigator"></a>`symbol-navigator` | M-x only | Open the active buffer symbol index. |
| <a id="command-toggle-read-only"></a>`toggle-read-only` | Direct/Modal: `C-x C-q` | Enable or disable mutation of the current text buffer. |
| <a id="command-upcase-word"></a>`upcase-word` | Direct/Modal: `M-u` | Uppercase the next word. |
| <a id="command-visit-slot"></a>`visit-slot` | Direct/Modal: `C-x r j` | Visit one persistent named position or layout. |
