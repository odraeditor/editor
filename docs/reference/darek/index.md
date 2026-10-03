<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Darek Reference

Darek is Odra's persistent hierarchical file explorer. The runtime owns one
session-local panel and one bounded tree. Its root may be an exclusive local
directory, an exclusive Project, or the ordered Project roots of an active
Workspace. Hiding the panel retains its expanded nodes and selection until the
editor session closes.

For a progressive workflow, start with the
[Darek User Guide module](../../tutorials/user-guide/files-projects-workspaces/darek/index.md).

## Global commands

| Command | Factory binding | Behavior |
| --- | --- | --- |
| `darek-toggle` | `C-x t t` | Show or hide Darek, resolving the active Workspace, Project, or document directory when needed. |
| `darek-select` | none | Show Darek and move input focus to its tree. |
| `darek-focus-toggle` | `C-x t o` | Exchange focus between Darek and the active ordinary pane. |
| `darek-show-directory` | none | Select a local directory through the filesystem candidate surface. |
| `darek-find-current-file` | none | Show the active document directory in Darek. |
| `darek-show-current-project` | none | Show the active Project as an exclusive root. |

All commands remain available through `M-x`. Factory bindings are ordinary
redefinable keymap entries.

## Tree commands

| Command | Binding | Behavior |
| --- | --- | --- |
| `darek-next-node`, `darek-previous-node` | `n`, `p`, `Down`, `Up` | Move in visible tree order. |
| `darek-next-sibling`, `darek-previous-sibling` | `M-n`, `M-p` | Move among visible siblings. |
| `darek-next-project`, `darek-previous-project` | `C-j`, `C-k` | Move among ordered Project roots. |
| `darek-parent-node` | `u` | Select the visible parent. |
| `darek-structure-action` | `TAB`, `l`, `M-l`, `Right` | Expand or collapse a directory, or visit a file. |
| `darek-visit-action` | `RET` | Expand a directory or visit a file in the ordinary active pane. |
| `darek-collapse-or-parent` | `h`, `M-h`, `Left` | Collapse an expanded directory or select its parent. |
| `darek-collapse-parent` | `H` | Select and collapse the parent directory. |
| `darek-root-parent` | `M-H` | Replace an exclusive root with its parent directory. |
| `darek-root-current-directory` | `M-L` | Make the selected directory the exclusive root. |
| `darek-refresh` | `r`, `g` | Replace selected expanded children from a new filesystem observation. |
| `darek-help` | `?` | Show common commands from the effective Darek keymap. |
| `darek-help-advanced` | `C-?` | Show the complete effective command and prefix map. Traditional terminal input reports this chord as Backspace inside Darek. |
| `darek-hide` | `q` | Hide Darek without discarding its tree state. |
| `darek-close` | `Q` | Close Darek and release its session-local tree state. |

Movement clamps at visible boundaries. Every available top-level root opens
with its first level expanded. Later explicit expansion and collapse remain
session-local Darek state. Directory publication is atomic. A refresh replaces
one complete child generation and never exposes a partial filesystem
observation.

## Workspace and Project commands

An active Workspace renders each member Project as a top-level sibling in its
stored order. There is no rendered Workspace wrapper. A one-Project Workspace
therefore has the same tree shape as an exclusive Project.

| Command | Binding | Behavior |
| --- | --- | --- |
| `darek-workspace-switch` | `C-c C-w s` | Select and open a registered Workspace through candidate navigation. |
| `darek-workspace-next` | `C-c C-w n` | Open the next registered Workspace under deterministic catalog ordering. |
| `darek-move-project-up`, `darek-move-project-down` | `M-Up`, `M-Down` | Move the current Project earlier or later through a checked Workspace update. |
| `darek-project-add` | `C-c C-p a` | Select a registered Project and append it to the active Workspace. |
| `darek-project-remove` | `C-c C-p d` | Remove the current Project from the active Workspace. |
| `darek-project-rename` | `C-c C-p r` | Rename the current Project through its canonical Project owner. |
| `darek-project-collapse` | `C-c C-p c c` | Collapse the current Project root. |
| `darek-project-collapse-others` | `C-c C-p c o` | Collapse every other Project root. |
| `darek-collapse-all-projects` | `C-c C-p c a` | Collapse every Project root. |

Workspace and Project mutations validate the current durable generation before
publication. Missing or unavailable Project roots remain visible as unavailable
instead of being silently removed. Root navigation changes only Darek view state;
it never promotes a Dir or changes Workspace membership.

## Filesystem actions

| Command | Binding | Behavior |
| --- | --- | --- |
| `darek-create-file` | `c f` | Create a file beneath the selected directory or selected file's parent. |
| `darek-create-directory` | `c d` | Create a directory beneath the resolved current directory. |
| `darek-rename-node` | `R` | Rename the selected file or directory without overwriting an existing entry. |
| `darek-move-node` | `m` | Select a destination directory through filesystem candidate navigation and move the selected node. |
| `darek-copy-node` | `y f` | Select a destination directory and copy the selected file or bounded directory tree. |
| `darek-delete-node` | `d` | Confirm and permanently delete the selected file or directory tree. |
| `darek-copy-absolute-path` | `y a` | Retain the selected node's absolute path. |
| `darek-copy-project-relative-path` | `y r` | Retain the selected node's Project-relative path. |
| `darek-copy-project-root` | `y p` | Retain the containing Project root path. |
| `darek-copy-name` | `y n` | Retain only the selected filesystem name. |

Creation, rename, move, copy, and deletion revalidate the selected resource and
destination before applying changes. Rename and move update associated open
document paths. Permanent deletion reports that recovery is unavailable and is
rejected while an affected document remains open.

## Contextual operations

| Command | Binding | Behavior |
| --- | --- | --- |
| `darek-shell-command` | `!` | Run a shell command from the selected directory or the selected file's parent. |
| `darek-shell-command-project` | `M-!` | Run a shell command from the selected node's Project root. |
| `darek-bulk-actions` | `M-m` | Open the selected directory, or a selected file or symbol's parent, in Maksym for checked target-set operations. |
| `darek-context-actions` | `M-RET`, secondary-button press | Select the exact current row and present commands admitted by the current Darek context. |

Expanding a regular file through `darek-structure-action` requests document
symbols from the configured language provider. Confirmed symbols appear as
children of that file. Visiting one revalidates its provider generation,
source revision, file identity, and byte position before presentation.

Shell execution uses the shared process owner. Darek supplies a checked working
directory and command text, while the process workflow owns execution,
cancellation, output, and completion feedback. Bulk actions transfer only the
resolved directory context to Maksym; Maksym owns target sets, filesystem
mutations, review, and recovery.

Secondary-button dispatch accepts only a current semantic tree row. It applies
the same selection and command-registry path as `M-RET`. Double-click activation
and pointer drag payloads are not part of the terminal pointer contract.

## Opening placement

| Command | Binding | Behavior |
| --- | --- | --- |
| `darek-open` | `o o` | Open the selected file in the active ordinary pane. |
| `darek-open-split-below` | `o v` | Split below and open the selected file there. |
| `darek-open-split-right` | `o h` | Split right and open the selected file there. |
| `darek-open-and-hide` | `o c` | Open the selected file and hide Darek. |
| `darek-open-mru-pane` | `o r` | Open the selected file in the most recently used eligible pane. |
| `darek-open-external` | `o x` | Request an external opener; unavailable until a provider is registered. |

Every placement revalidates the selected node and current layout generation.
Cancellation or failure preserves the existing pane tree and active document.

## Preview and file follow

| Command | Binding | Behavior |
| --- | --- | --- |
| `darek-toggle-peek` | `P` | Toggle preview for the selected file without transferring focus. |
| `darek-other-pane-next-line` | `M-N` | Scroll the preview forward by one line. |
| `darek-other-pane-previous-line` | `M-P` | Scroll the preview backward by one line. |
| `darek-other-pane-next-page` | `PageDown` | Scroll the preview forward by one page. |
| `darek-other-pane-previous-page` | `PageUp` | Scroll the preview backward by one page. |
| `darek-toggle-file-follow` | `t f` | Toggle selection tracking for the active ordinary file. |

Preview-created documents remain owned by the preview until they are adopted,
modified, or referenced independently. Disabling preview or replacing a stale
selection closes only resources that remain preview-owned. File follow
coalesces rapid active-file changes and publishes only the newest checked
generation.

## Panel and tree presentation

| Command | Binding | Behavior |
| --- | --- | --- |
| `darek-panel-left` | none | Place Darek on the left edge. |
| `darek-panel-right` | none | Place Darek on the right edge. |
| `darek-decrease-width` | `<` | Reduce the normal panel width by four columns. |
| `darek-increase-width` | `>` | Increase the normal panel width by four columns. |
| `darek-fit-width` | `=` | Fit the panel to the current visible labels within its bounds. |
| `darek-toggle-extra-width` | `W` | Exchange the normal width with the 48-column wide presentation. |
| `darek-toggle-width-lock` | `t w` | Toggle retention of the selected width during layout adjustment. |
| `darek-toggle-hidden-files` | `t h` | Show or hide dot-prefixed entries already retained by the filesystem observation. |
| `darek-toggle-vcs-ignored` | `t i` | Show or hide entries marked ignored by the current version-control annotation generation. |
| `darek-toggle-file-watch` | `t a` | Enable or disable bounded provider-supported filesystem watching. |
| `darek-toggle-vcs-decorations` | `t g`, `t d` | Show or hide copied version-control decorations. Both familiar presentation entries control the complete decoration generation. |
| `darek-toggle-diagnostics` | none | Show or hide copied diagnostic decorations. |
| `darek-select-sort` | `s` | Exchange ascending and descending deterministic name order. Directories remain grouped before files. |
| `darek-filter` | `/` | Enter a bounded case-sensitive name substring; submit an empty value to clear it. |
| `darek-toggle-directory-compression` | none | Toggle compact presentation of single-child directory chains. |
| `darek-narrow-current-project` | none | Show only the selected Project root from the active Workspace tree. |
| `darek-show-all-projects` | none | Restore all active Workspace Project roots. |

Commands without a factory binding remain available through `M-x` and may be
bound through the programmable keymap API. These controls affect only Darek
presentation. They do not change files, Project identity, or Workspace
membership. Visibility, sorting, and filtering preserve the selected resource
when it remains visible; otherwise selection moves to its nearest visible
ancestor or the first visible node.

File watching consumes bounded hints from the active filesystem provider. A
hint never edits the existing tree directly. Activity, event loss, or overflow
marks the tree for a complete checked refresh; `r` or `g` performs that refresh.
A provider restart establishes a new generation and rejects hints from the old
generation.

Version-control and diagnostic providers publish complete copied annotation
generations. A newer generation replaces the previous one, so absent or
unavailable data clears stale decoration. Initial tree publication does not
wait for either provider.

## Presentation and ownership

Darek uses the shared `TreeView` and edge `Panel` UI primitives. The layout
owner reserves panel columns and remains the only owner of ordinary pane
geometry and focus history. Themes supply semantic roles for Project roots,
hierarchy, active and inactive selection, loading, failure, destructive
actions, special directories, and common file categories. The terminal
renderer lowers semantic icon roles through an enriched Nerd Font catalog by
default. Set `ODRA_ICON_PROFILE=portable` to select the compact Unicode
fallback. Both catalogs reserve the same measured icon column, and theme roles
color icons without making them the sole indication of node kind.

The filesystem subsystem owns local resource identity and observations. Project
and Workspace subsystems own durable identity, membership, naming, ordering,
and publication. Filesystem, version-control, and diagnostic providers own
their live observations. Darek retains only copied generations and owns tree
expansion, selection, viewport, visibility, sorting, filtering, and focus
intent. Document and layout workflows own file visits and pane content.

## Bounds

- One Darek tree admits at most 4,096 visible nodes and depth 64.
- Copied labels and paths admit at most 16 MiB per instance.
- The panel ranges from 16 to 80 columns, uses 32 columns by default, and
  provides a 48-column wide presentation.
- The current tree is session-local and has no restart persistence.
- One name filter admits at most 256 UTF-8 bytes.
- Watch activity is coalesced up to 1,024 hints before a complete refresh is
  required.
- One copy admits at most 256 MiB, 16,384 entries, and depth 64.

## Programmable command surface

`src/command/darek.rkt` is the Racket facade for Darek commands and keymap
composition. It exports the complete global and contextual command catalogs,
`darek-command-name?`, `darek-bind-key`, `darek-mask-key`,
`darek-remap-command`, and `darek-factory-bindings`.

The facade produces copied keymap values. It does not expose native pointers,
filesystem authority, or renderer callbacks. Effective help is generated from
the active contextual keymap, so remaps, masks, provenance, and unavailable
commands are reported from current runtime state rather than a static table.

See [Troubleshoot Darek](../../how-to/troubleshoot-darek/index.md) for focused
recovery procedures.
