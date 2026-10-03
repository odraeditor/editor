<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Commands

[Command and Keybinding Reference](index.md) | [Alphabetical Index](alphabetical-index.md)

Detailed behavior: [Jan Reference](../jan-structured-editing-commands/index.md).


## Visibility and navigation

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-jan-cycle"></a>`jan-cycle` | M-x only | Cycle visibility at the current Jan structure. |
| <a id="command-jan-cycle-list-bullet"></a>`jan-cycle-list-bullet` | M-x only | Cycle the current Jan list bullet. |
| <a id="command-jan-first-child-heading"></a>`jan-first-child-heading` | M-x only | Move to the first child Jan heading. |
| <a id="command-jan-next-block"></a>`jan-next-block` | M-x only | Move to the next Jan block. |
| <a id="command-jan-next-drawer"></a>`jan-next-drawer` | M-x only | Move to the next Jan drawer. |
| <a id="command-jan-next-footnote"></a>`jan-next-footnote` | M-x only | Move to the next Jan footnote. |
| <a id="command-jan-next-heading"></a>`jan-next-heading` | M-x only | Move to the next visible Jan heading. |
| <a id="command-jan-next-list-item"></a>`jan-next-list-item` | M-x only | Move to the next Jan list item. |
| <a id="command-jan-next-same-level-heading"></a>`jan-next-same-level-heading` | M-x only | Move to the next same-level Jan heading. |
| <a id="command-jan-next-structural-element"></a>`jan-next-structural-element` | M-x only | Move to the next Jan structural element. |
| <a id="command-jan-next-table-cell"></a>`jan-next-table-cell` | M-x only | Move to the next Jan table cell. |
| <a id="command-jan-next-table-row"></a>`jan-next-table-row` | M-x only | Move to the next Jan table row. |
| <a id="command-jan-parent-heading"></a>`jan-parent-heading` | M-x only | Move to the parent Jan heading. |
| <a id="command-jan-previous-block"></a>`jan-previous-block` | M-x only | Move to the previous Jan block. |
| <a id="command-jan-previous-drawer"></a>`jan-previous-drawer` | M-x only | Move to the previous Jan drawer. |
| <a id="command-jan-previous-footnote"></a>`jan-previous-footnote` | M-x only | Move to the previous Jan footnote. |
| <a id="command-jan-previous-heading"></a>`jan-previous-heading` | M-x only | Move to the previous visible Jan heading. |
| <a id="command-jan-previous-list-item"></a>`jan-previous-list-item` | M-x only | Move to the previous Jan list item. |
| <a id="command-jan-previous-same-level-heading"></a>`jan-previous-same-level-heading` | M-x only | Move to the previous same-level Jan heading. |
| <a id="command-jan-previous-structural-element"></a>`jan-previous-structural-element` | M-x only | Move to the previous Jan structural element. |
| <a id="command-jan-previous-table-cell"></a>`jan-previous-table-cell` | M-x only | Move to the previous Jan table cell. |
| <a id="command-jan-previous-table-row"></a>`jan-previous-table-row` | M-x only | Move to the previous Jan table row. |
| <a id="command-jan-show-all"></a>`jan-show-all` | M-x only | Reveal the complete Jan document. |
| <a id="command-jan-show-contents"></a>`jan-show-contents` | M-x only | Show Jan outline contents. |
| <a id="command-jan-show-overview"></a>`jan-show-overview` | M-x only | Show the Jan outline overview. |
| <a id="command-jan-sparse-view"></a>`jan-sparse-view` | M-x only | Derive a bounded sparse Jan outline view. |
| <a id="command-jan-subtree-end"></a>`jan-subtree-end` | M-x only | Move to the current Jan subtree end. |
| <a id="command-jan-subtree-start"></a>`jan-subtree-start` | M-x only | Move to the current Jan subtree start. |
| <a id="command-jan-toggle-drawer"></a>`jan-toggle-drawer` | M-x only | Toggle the current Jan drawer body in this view. |

## Headings and subtrees

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-jan-clone-subtree"></a>`jan-clone-subtree` | M-x only | Clone the current Jan subtree. |
| <a id="command-jan-demote-heading"></a>`jan-demote-heading` | M-x only | Demote the current Jan heading and descendants. |
| <a id="command-jan-heading-to-list-item"></a>`jan-heading-to-list-item` | M-x only | Convert the current leaf heading to a list item. |
| <a id="command-jan-insert-heading-after"></a>`jan-insert-heading-after` | M-x only | Insert a sibling heading after the current heading. |
| <a id="command-jan-insert-heading-before"></a>`jan-insert-heading-before` | M-x only | Insert a sibling heading before the current heading. |
| <a id="command-jan-insert-heading-below"></a>`jan-insert-heading-below` | M-x only | Insert a child heading below the current heading. |
| <a id="command-jan-kill-subtree"></a>`jan-kill-subtree` | M-x only | Delete the current complete Jan subtree. |
| <a id="command-jan-list-item-to-heading"></a>`jan-list-item-to-heading` | M-x only | Convert the current list item to a heading. |
| <a id="command-jan-move-subtree-down"></a>`jan-move-subtree-down` | M-x only | Move the current Jan subtree after its sibling. |
| <a id="command-jan-move-subtree-up"></a>`jan-move-subtree-up` | M-x only | Move the current Jan subtree before its sibling. |
| <a id="command-jan-promote-heading"></a>`jan-promote-heading` | M-x only | Promote the current Jan heading and descendants. |
| <a id="command-jan-sort-child-headings"></a>`jan-sort-child-headings` | M-x only | Sort direct child headings by source key. |
| <a id="command-jan-split-heading"></a>`jan-split-heading` | M-x only | Split the current Jan heading at point. |

## Lists, drawers, and structures

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-jan-attachment-list"></a>`jan-attachment-list` | M-x only | List bounded attachments for the current heading. |
| <a id="command-jan-delete-list-item"></a>`jan-delete-list-item` | M-x only | Delete the current complete Jan list item. |
| <a id="command-jan-delete-structure"></a>`jan-delete-structure` | M-x only | Delete the current complete Jan drawer or block. |
| <a id="command-jan-demote-list-item"></a>`jan-demote-list-item` | M-x only | Demote the current Jan list item. |
| <a id="command-jan-duplicate-list-item"></a>`jan-duplicate-list-item` | M-x only | Duplicate the current Jan list item. |
| <a id="command-jan-insert-drawer"></a>`jan-insert-drawer` | M-x only | Insert a complete Jan drawer. |
| <a id="command-jan-insert-list-item-after"></a>`jan-insert-list-item-after` | M-x only | Insert a Jan list item after the current item. |
| <a id="command-jan-insert-list-item-before"></a>`jan-insert-list-item-before` | M-x only | Insert a Jan list item before the current item. |
| <a id="command-jan-move-list-item-down"></a>`jan-move-list-item-down` | M-x only | Move the current Jan list item down. |
| <a id="command-jan-move-list-item-up"></a>`jan-move-list-item-up` | M-x only | Move the current Jan list item up. |
| <a id="command-jan-move-structure-down"></a>`jan-move-structure-down` | M-x only | Move the current Jan drawer or block down. |
| <a id="command-jan-move-structure-up"></a>`jan-move-structure-up` | M-x only | Move the current Jan drawer or block up. |
| <a id="command-jan-promote-list-item"></a>`jan-promote-list-item` | M-x only | Promote the current Jan list item. |
| <a id="command-jan-repair-list-indentation"></a>`jan-repair-list-indentation` | M-x only | Repair indentation for the current Jan list item. |
| <a id="command-jan-select-structure"></a>`jan-select-structure` | M-x only | Select the current complete Jan drawer or block. |
| <a id="command-jan-session-list"></a>`jan-session-list` | M-x only | List bounded execution-session records. |
| <a id="command-jan-sort-list-items"></a>`jan-sort-list-items` | M-x only | Sort sibling Jan list items by source key. |

## Tables and formulas

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-jan-align-table"></a>`jan-align-table` | M-x only | Align the current Jan table source. |
| <a id="command-jan-create-table"></a>`jan-create-table` | M-x only | Create a bounded Jan table. |
| <a id="command-jan-delete-table-column"></a>`jan-delete-table-column` | M-x only | Delete the current Jan table column. |
| <a id="command-jan-delete-table-row"></a>`jan-delete-table-row` | M-x only | Delete the current Jan table row. |
| <a id="command-jan-delete-table-separator"></a>`jan-delete-table-separator` | M-x only | Delete the current Jan table separator. |
| <a id="command-jan-duplicate-table-column"></a>`jan-duplicate-table-column` | M-x only | Duplicate the current Jan table column. |
| <a id="command-jan-duplicate-table-row"></a>`jan-duplicate-table-row` | M-x only | Duplicate the current Jan table row. |
| <a id="command-jan-edit-table-cell"></a>`jan-edit-table-cell` | M-x only | Edit the current Jan table cell as canonical source. |
| <a id="command-jan-insert-table-column"></a>`jan-insert-table-column` | M-x only | Insert a column after the current Jan table cell. |
| <a id="command-jan-insert-table-row"></a>`jan-insert-table-row` | M-x only | Insert a row after the current Jan table row. |
| <a id="command-jan-insert-table-separator"></a>`jan-insert-table-separator` | M-x only | Insert a separator after the current Jan table row. |
| <a id="command-jan-move-table-column-left"></a>`jan-move-table-column-left` | M-x only | Move the current Jan table column left. |
| <a id="command-jan-move-table-column-right"></a>`jan-move-table-column-right` | M-x only | Move the current Jan table column right. |
| <a id="command-jan-move-table-row-down"></a>`jan-move-table-row-down` | M-x only | Move the current Jan table row down. |
| <a id="command-jan-move-table-row-up"></a>`jan-move-table-row-up` | M-x only | Move the current Jan table row up. |
| <a id="command-jan-table-debug-formula"></a>`jan-table-debug-formula` | M-x only | Inspect the current formula without changing its table. |
| <a id="command-jan-table-plot"></a>`jan-table-plot` | M-x only | Render a bounded text plot or request an admitted graphical plot. |
| <a id="command-jan-table-recalculate"></a>`jan-table-recalculate` | M-x only | Recalculate the current Jan table through its exact dependency graph. |
| <a id="command-jan-table-recalculate-all"></a>`jan-table-recalculate-all` | M-x only | Recalculate every admitted table in deterministic dependency order. |

## Editing and metadata

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-jan-call"></a>`jan-call` | M-x only | Invoke the current named Jan call through explicit authority. |
| <a id="command-jan-column-view"></a>`jan-column-view` | M-x only | Present a bounded property-backed Jan column view. |
| <a id="command-jan-complete"></a>`jan-complete` | M-x only | Present bounded Jan completion candidates. |
| <a id="command-jan-computation-status"></a>`jan-computation-status` | M-x only | Inspect Computable Documents capabilities, generations, limits, and failures. |
| <a id="command-jan-context-action"></a>`jan-context-action` | M-x only | Invoke the deterministic Jan action at point. |
| <a id="command-jan-context-meta-down"></a>`jan-context-meta-down` | M-x only | Display the source session or move the current subtree down. |
| <a id="command-jan-context-meta-up"></a>`jan-context-meta-up` | M-x only | Load source into its session or move the current subtree up. |
| <a id="command-jan-copy-subtree"></a>`jan-copy-subtree` | M-x only | Copy the current complete subtree to a checked destination. |
| <a id="command-jan-create-footnote"></a>`jan-create-footnote` | M-x only | Create a local Jan footnote definition. |
| <a id="command-jan-decrypt-subtree"></a>`jan-decrypt-subtree` | M-x only | Decrypt the current subtree through an admitted provider. |
| <a id="command-jan-demarcate-source"></a>`jan-demarcate-source` | M-x only | Split the current source block at point. |
| <a id="command-jan-dynamic-block-update"></a>`jan-dynamic-block-update` | M-x only | Update the current dynamic block from one checked provider candidate. |
| <a id="command-jan-encrypt-subtree"></a>`jan-encrypt-subtree` | M-x only | Encrypt the current subtree through an admitted provider. |
| <a id="command-jan-expand-template"></a>`jan-expand-template` | M-x only | Expand a factory Jan structure template. |
| <a id="command-jan-extension-status"></a>`jan-extension-status` | M-x only | Inspect the active Jan extension generation. |
| <a id="command-jan-global-cycle"></a>`jan-global-cycle` | M-x only | Cycle global Jan document visibility. |
| <a id="command-jan-help-at-point"></a>`jan-help-at-point` | M-x only | Show Jan help for the syntax or workflow at point. |
| <a id="command-jan-indent"></a>`jan-indent` | M-x only | Apply explicit Jan source indentation. |
| <a id="command-jan-insert-block"></a>`jan-insert-block` | M-x only | Insert a complete Jan source block. |
| <a id="command-jan-mobile-pull"></a>`jan-mobile-pull` | M-x only | Pull and apply one non-conflicting Jan synchronization manifest. |
| <a id="command-jan-mobile-push"></a>`jan-mobile-push` | M-x only | Push one checked Jan synchronization manifest. |
| <a id="command-jan-mobile-reconcile"></a>`jan-mobile-reconcile` | M-x only | Reconcile an explicit Jan synchronization conflict. |
| <a id="command-jan-move-footnote-down"></a>`jan-move-footnote-down` | M-x only | Move the current Jan footnote definition down. |
| <a id="command-jan-move-footnote-up"></a>`jan-move-footnote-up` | M-x only | Move the current Jan footnote definition up. |
| <a id="command-jan-normalize-footnote"></a>`jan-normalize-footnote` | M-x only | Normalize the current Jan footnote form. |
| <a id="command-jan-noweb-inspect"></a>`jan-noweb-inspect` | M-x only | Inspect the effective noweb graph and expansion chain. |
| <a id="command-jan-pop-to-session"></a>`jan-pop-to-session` | M-x only | Display the execution session associated with the current source block. |
| <a id="command-jan-property-search"></a>`jan-property-search` | M-x only | Search headings by effective property values. |
| <a id="command-jan-protocol-handle"></a>`jan-protocol-handle` | M-x only | Handle one authenticated external Jan protocol request. |
| <a id="command-jan-provider-status"></a>`jan-provider-status` | M-x only | Inspect Jan provider availability and authority boundaries. |
| <a id="command-jan-renumber-footnotes"></a>`jan-renumber-footnotes` | M-x only | Renumber local Jan footnotes. |
| <a id="command-jan-repeat"></a>`jan-repeat` | M-x only | Repeat the latest Jan semantic action on a fresh target. |
| <a id="command-jan-restore-archive"></a>`jan-restore-archive` | M-x only | Restore an archived subtree to its checked origin. |
| <a id="command-jan-return-from-source"></a>`jan-return-from-source` | M-x only | Publish a revalidated focused source edit to its owner. |
| <a id="command-jan-set-effort"></a>`jan-set-effort` | M-x only | Set the current heading effort value. |
| <a id="command-jan-set-priority"></a>`jan-set-priority` | M-x only | Set the current heading priority. |
| <a id="command-jan-store-link"></a>`jan-store-link` | M-x only | Store one checked Jan link candidate. |
| <a id="command-jan-timer-pause"></a>`jan-timer-pause` | M-x only | Pause the active relative Jan timer. |
| <a id="command-jan-timer-reset"></a>`jan-timer-reset` | M-x only | Reset the active relative Jan timer. |
| <a id="command-jan-timer-resume"></a>`jan-timer-resume` | M-x only | Resume the paused relative Jan timer. |
| <a id="command-jan-timer-start"></a>`jan-timer-start` | M-x only | Start a relative Jan timer. |
| <a id="command-jan-timer-stop"></a>`jan-timer-stop` | M-x only | Stop the active relative Jan timer. |
| <a id="command-jan-timestamp"></a>`jan-timestamp` | M-x only | Insert or edit a compatible Jan timestamp. |
| <a id="command-jan-toggle-archive"></a>`jan-toggle-archive` | M-x only | Toggle compatible in-place archive state. |
| <a id="command-jan-toggle-checkbox"></a>`jan-toggle-checkbox` | M-x only | Cycle the current compatible checkbox. |
| <a id="command-jan-update-statistics"></a>`jan-update-statistics` | M-x only | Update derived checkbox statistics at the current owner. |
| <a id="command-jan-visit-archive-origin"></a>`jan-visit-archive-origin` | M-x only | Visit the recorded source of an archived subtree. |
| <a id="command-jan-visit-footnote"></a>`jan-visit-footnote` | M-x only | Visit the matching local Jan footnote. |

## Planning and agenda

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-jan-agenda"></a>`jan-agenda` | M-x only | Open the Jan agenda dispatcher. |
| <a id="command-jan-agenda-apply-selection"></a>`jan-agenda-apply-selection` | M-x only | Apply one checked operation to an explicit agenda selection. |
| <a id="command-jan-agenda-archive"></a>`jan-agenda-archive` | M-x only | Archive the exact agenda source target. |
| <a id="command-jan-agenda-calendar"></a>`jan-agenda-calendar` | M-x only | Invoke calendar navigation from the active agenda date. |
| <a id="command-jan-agenda-capture"></a>`jan-agenda-capture` | M-x only | Capture relative to the exact agenda source target. |
| <a id="command-jan-agenda-change-presentation"></a>`jan-agenda-change-presentation` | M-x only | Change grouping, sorting, grid, or prefix presentation. |
| <a id="command-jan-agenda-clock-in"></a>`jan-agenda-clock-in` | M-x only | Start a clock at the exact agenda source target. |
| <a id="command-jan-agenda-clock-out"></a>`jan-agenda-clock-out` | M-x only | Stop the clock represented by the agenda row. |
| <a id="command-jan-agenda-close"></a>`jan-agenda-close` | M-x only | Close the active agenda surface. |
| <a id="command-jan-agenda-deadline"></a>`jan-agenda-deadline` | M-x only | Set deadline at the exact agenda source target. |
| <a id="command-jan-agenda-delete"></a>`jan-agenda-delete` | M-x only | Delete the exact agenda source target through its canonical owner. |
| <a id="command-jan-agenda-export"></a>`jan-agenda-export` | M-x only | Hand the current immutable agenda result to Jan export. |
| <a id="command-jan-agenda-filter"></a>`jan-agenda-filter` | M-x only | Apply a bounded local agenda filter. |
| <a id="command-jan-agenda-next-date"></a>`jan-agenda-next-date` | M-x only | Move to the next represented agenda date. |
| <a id="command-jan-agenda-next-entry"></a>`jan-agenda-next-entry` | M-x only | Move to the next agenda entry. |
| <a id="command-jan-agenda-previous-date"></a>`jan-agenda-previous-date` | M-x only | Move to the previous represented agenda date. |
| <a id="command-jan-agenda-previous-entry"></a>`jan-agenda-previous-entry` | M-x only | Move to the previous agenda entry. |
| <a id="command-jan-agenda-quit"></a>`jan-agenda-quit` | M-x only | Quit the active agenda while retaining its surface. |
| <a id="command-jan-agenda-refile"></a>`jan-agenda-refile` | M-x only | Refile the exact agenda source target. |
| <a id="command-jan-agenda-refresh"></a>`jan-agenda-refresh` | M-x only | Refresh the active agenda from admitted sources. |
| <a id="command-jan-agenda-reveal-source"></a>`jan-agenda-reveal-source` | M-x only | Reveal the exact source represented by the current agenda row. |
| <a id="command-jan-agenda-schedule"></a>`jan-agenda-schedule` | M-x only | Set schedule at the exact agenda source target. |
| <a id="command-jan-agenda-set-effort"></a>`jan-agenda-set-effort` | M-x only | Set effort at the exact agenda source target. |
| <a id="command-jan-agenda-set-priority"></a>`jan-agenda-set-priority` | M-x only | Set priority at the exact agenda source target. |
| <a id="command-jan-agenda-set-property"></a>`jan-agenda-set-property` | M-x only | Set a property at the exact agenda source target. |
| <a id="command-jan-agenda-set-span"></a>`jan-agenda-set-span` | M-x only | Change the active agenda date span. |
| <a id="command-jan-agenda-set-tags"></a>`jan-agenda-set-tags` | M-x only | Set tags at the exact agenda source target. |
| <a id="command-jan-agenda-todo"></a>`jan-agenda-todo` | M-x only | Change task state at the exact agenda source target. |
| <a id="command-jan-agenda-toggle-follow"></a>`jan-agenda-toggle-follow` | M-x only | Toggle agenda source-follow behavior. |
| <a id="command-jan-archive-subtree"></a>`jan-archive-subtree` | M-x only | Archive the current subtree through its configured owner. |
| <a id="command-jan-clock-cancel"></a>`jan-clock-cancel` | M-x only | Cancel the active durable clock without publishing elapsed time. |
| <a id="command-jan-clock-in"></a>`jan-clock-in` | M-x only | Start a durable clock for the current heading. |
| <a id="command-jan-clock-out"></a>`jan-clock-out` | M-x only | Stop the active durable clock. |
| <a id="command-jan-clock-report"></a>`jan-clock-report` | M-x only | Present a bounded Jan clock report. |
| <a id="command-jan-clock-resume"></a>`jan-clock-resume` | M-x only | Resume a prior exact clock target. |
| <a id="command-jan-clock-switch"></a>`jan-clock-switch` | M-x only | Stop the active clock and start another exact target. |
| <a id="command-jan-deadline"></a>`jan-deadline` | M-x only | Set or clear the current heading deadline. |
| <a id="command-jan-planning-status"></a>`jan-planning-status` | M-x only | Inspect Planning and Agenda capabilities, generations, recovery, and failures. |
| <a id="command-jan-refile"></a>`jan-refile` | M-x only | Move the current complete subtree to a checked destination. |
| <a id="command-jan-schedule"></a>`jan-schedule` | M-x only | Set or clear the current heading schedule. |
| <a id="command-jan-set-property"></a>`jan-set-property` | M-x only | Set one locally owned Jan property. |
| <a id="command-jan-set-tags"></a>`jan-set-tags` | M-x only | Set locally stored tags on the current heading. |
| <a id="command-jan-todo"></a>`jan-todo` | M-x only | Move the current heading through its admitted task workflow. |

## Capture and intake

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-jan-attach"></a>`jan-attach` | M-x only | Attach a resource and publish a compatible checked link. |
| <a id="command-jan-attachment-delete"></a>`jan-attachment-delete` | M-x only | Delete one attachment and its compatible source link. |
| <a id="command-jan-attachment-open"></a>`jan-attachment-open` | M-x only | Open the selected attachment through its resource owner. |
| <a id="command-jan-attachment-rename"></a>`jan-attachment-rename` | M-x only | Rename one attachment and its compatible source link. |
| <a id="command-jan-attachment-reveal"></a>`jan-attachment-reveal` | M-x only | Reveal the selected attachment through Maksym. |
| <a id="command-jan-attachment-synchronize"></a>`jan-attachment-synchronize` | M-x only | Synchronize attachments through their configured resource owner. |
| <a id="command-jan-capture"></a>`jan-capture` | M-x only | Start a bounded Jan capture session. |
| <a id="command-jan-capture-abort"></a>`jan-capture-abort` | M-x only | Abort the active capture and discard its draft. |
| <a id="command-jan-capture-finalize"></a>`jan-capture-finalize` | M-x only | Finalize the active capture at its exact destination. |
| <a id="command-jan-feed-refresh"></a>`jan-feed-refresh` | M-x only | Refresh admitted feeds explicitly and retain bounded unseen entries. |

## Computation and source blocks

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-jan-babel-help"></a>`jan-babel-help` | M-x only | Display the active Jan Babel command family. |
| <a id="command-jan-cache-clear"></a>`jan-cache-clear` | M-x only | Clear bounded cache-owned entries without changing documents. |
| <a id="command-jan-cache-evict"></a>`jan-cache-evict` | M-x only | Evict one cache-owned entry without changing document results. |
| <a id="command-jan-cache-inspect"></a>`jan-cache-inspect` | M-x only | Inspect execution-cache keys and outcomes. |
| <a id="command-jan-check-source"></a>`jan-check-source` | M-x only | Check whether the current source block is valid and executable. |
| <a id="command-jan-edit-source"></a>`jan-edit-source` | M-x only | Open the current source body in a focused language view. |
| <a id="command-jan-execute"></a>`jan-execute` | M-x only | Execute the current source owner through explicit authority. |
| <a id="command-jan-execute-batch"></a>`jan-execute-batch` | M-x only | Execute an explicit bounded batch in deterministic order. |
| <a id="command-jan-execute-buffer"></a>`jan-execute-buffer` | M-x only | Execute admitted source owners in the current buffer. |
| <a id="command-jan-execute-subtree"></a>`jan-execute-subtree` | M-x only | Execute admitted source owners in the current subtree. |
| <a id="command-jan-expand-source"></a>`jan-expand-source` | M-x only | Preview the expanded current source block without executing it. |
| <a id="command-jan-goto-named-result"></a>`jan-goto-named-result` | M-x only | Select and visit a named source result. |
| <a id="command-jan-goto-named-source"></a>`jan-goto-named-source` | M-x only | Select and visit a named source block. |
| <a id="command-jan-goto-source-head"></a>`jan-goto-source-head` | M-x only | Move to the beginning of the current source block. |
| <a id="command-jan-insert-header-argument"></a>`jan-insert-header-argument` | M-x only | Insert or update an argument on the current source block. |
| <a id="command-jan-library-load"></a>`jan-library-load` | M-x only | Load definitions from an explicitly admitted Jan library. |
| <a id="command-jan-load-in-session"></a>`jan-load-in-session` | M-x only | Load the current source block into its associated execution session. |
| <a id="command-jan-open-result"></a>`jan-open-result` | M-x only | Move to and inspect the result owned by the current source block. |
| <a id="command-jan-result-inspect"></a>`jan-result-inspect` | M-x only | Inspect typed result provenance and accounting. |
| <a id="command-jan-result-remove"></a>`jan-result-remove` | M-x only | Remove only the result owned by the current source or call. |
| <a id="command-jan-session-close"></a>`jan-session-close` | M-x only | Close one explicit execution session and report cleanup. |
| <a id="command-jan-session-inspect"></a>`jan-session-inspect` | M-x only | Inspect one explicit execution session. |
| <a id="command-jan-source-hash"></a>`jan-source-hash` | M-x only | Calculate the effective current source block hash. |
| <a id="command-jan-switch-to-session-with-code"></a>`jan-switch-to-session-with-code` | M-x only | Display the current source in its associated execution session. |
| <a id="command-jan-tangle"></a>`jan-tangle` | M-x only | Prepare and publish admitted tangle targets for the current scope. |
| <a id="command-jan-tangle-file"></a>`jan-tangle-file` | M-x only | Prepare and publish admitted tangle targets for the current document. |
| <a id="command-jan-view-source-info"></a>`jan-view-source-info` | M-x only | Display resolved information for the current source block. |

## Export and publishing

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-jan-bibliography-insert"></a>`jan-bibliography-insert` | M-x only | Insert one checked bibliography declaration. |
| <a id="command-jan-citation-follow"></a>`jan-citation-follow` | M-x only | Follow one resolved citation through its admitted provider. |
| <a id="command-jan-citation-insert"></a>`jan-citation-insert` | M-x only | Insert one resolved citation candidate. |
| <a id="command-jan-export"></a>`jan-export` | M-x only | Open the Jan export dispatcher for the active document. |
| <a id="command-jan-export-beamer"></a>`jan-export-beamer` | M-x only | Export through the optional Beamer adapter. |
| <a id="command-jan-export-html"></a>`jan-export-html` | M-x only | Export with the factory HTML backend. |
| <a id="command-jan-export-icalendar"></a>`jan-export-icalendar` | M-x only | Export through the optional iCalendar adapter. |
| <a id="command-jan-export-info"></a>`jan-export-info` | M-x only | Export through the optional Info adapter. |
| <a id="command-jan-export-latex"></a>`jan-export-latex` | M-x only | Export through the optional LaTeX adapter. |
| <a id="command-jan-export-man-page"></a>`jan-export-man-page` | M-x only | Export through the optional man-page adapter. |
| <a id="command-jan-export-markdown"></a>`jan-export-markdown` | M-x only | Export with the factory Markdown backend. |
| <a id="command-jan-export-normalized-jan"></a>`jan-export-normalized-jan` | M-x only | Export normalized Jan source. |
| <a id="command-jan-export-odt"></a>`jan-export-odt` | M-x only | Export through the optional ODT adapter. |
| <a id="command-jan-export-pdf"></a>`jan-export-pdf` | M-x only | Export through the optional PDF adapter. |
| <a id="command-jan-export-plain-text"></a>`jan-export-plain-text` | M-x only | Export with the factory plain-text backend. |
| <a id="command-jan-export-region"></a>`jan-export-region` | M-x only | Export the active checked Jan region. |
| <a id="command-jan-export-texinfo"></a>`jan-export-texinfo` | M-x only | Export through the optional Texinfo adapter. |
| <a id="command-jan-output-status"></a>`jan-output-status` | M-x only | Inspect Jan output capabilities, backends, limits, and providers. |
| <a id="command-jan-publish"></a>`jan-publish` | M-x only | Publish one explicit Jan target. |
| <a id="command-jan-publish-all"></a>`jan-publish-all` | M-x only | Publish every explicitly selected Jan project. |
| <a id="command-jan-publish-project"></a>`jan-publish-project` | M-x only | Publish one configured Jan project. |

## Inspection and presentation

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-jan-inspect-availability"></a>`jan-inspect-availability` | M-x only | Inspect operational and later-stage Jan capabilities. |
| <a id="command-jan-inspect-syntax"></a>`jan-inspect-syntax` | M-x only | Inspect Jan syntax, attributes, generations, and recovery at point. |
| <a id="command-jan-language-status"></a>`jan-language-status` | M-x only | Inspect Jan recognition, provider, baseline, limits, and latest rejection. |
| <a id="command-jan-lint"></a>`jan-lint` | M-x only | Produce bounded read-only Jan diagnostics for the current revision. |
| <a id="command-jan-lint-refresh"></a>`jan-lint-refresh` | M-x only | Recompute bounded Jan diagnostics for the current revision. |
| <a id="command-jan-present"></a>`jan-present` | M-x only | Refresh rich Jan source presentation. |
| <a id="command-jan-request-preview"></a>`jan-request-preview` | M-x only | Request a bounded Jan preview or source fallback. |
