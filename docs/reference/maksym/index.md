<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Maksym Reference

Maksym is Odra's directory editor. Each Maksym buffer owns one bounded directory
observation, a stable selection by filesystem identity, one listing policy,
and an optional editable filename baseline.

For a progressive workflow, start with the
[Maksym User Guide module](../../tutorials/user-guide/files-projects-workspaces/maksym/index.md).

## Opening commands

| Command | Factory binding | Behavior |
| --- | --- | --- |
| `maksym-open-directory` | `C-x d` | Select a directory with filesystem candidates and open it in the current pane. |
| `maksym-open-directory-other-pane` | `C-x 4 d` | Select and open a directory in another pane. |
| `maksym-open-directory-below` | none | Split below and open the selected directory. |
| `maksym-open-directory-right` | none | Split right and open the selected directory. |
| `maksym-open-containing-directory` | `C-x C-j` | Open the active document's containing directory. |
| `maksym-open-containing-directory-other-pane` | `C-x 4 C-j` | Open the containing directory in another pane. |

`open-directory` is a compatibility command for the canonical Maksym opening
workflow. It does not open the superseded standalone file-candidate surface.

## Buffer-local commands

| Command | Binding | Behavior |
| --- | --- | --- |
| `maksym-next-entry` | `n`, `C-n`, `SPC` | Select the next entry. |
| `maksym-previous-entry` | `p`, `C-p` | Select the previous entry. |
| `maksym-parent-directory` | `^` | Open the parent directory. |
| `maksym-jump-to-entry` | `j` | Filter current entries and select one by stable identity. |
| `maksym-open-entry` | `RET`, `f`, `e` | Open the selected entry. |
| `maksym-open-entry-other-pane` | `o` | Open the selected entry in another pane and focus it. |
| `maksym-display-entry-other-pane` | `C-o` | Display the selected entry elsewhere while retaining Maksym focus. |
| `maksym-refresh` | `g` | Replace the listing from a new directory observation. |
| `maksym-toggle-details` | `(` | Toggle metadata columns. |
| `maksym-cycle-sort` | `s` | Cycle directories-first and name ordering. |

Movement clamps at listing boundaries. Refresh, sorting, and detail changes
preserve the selected resource when it still exists.

## Editable listing commands

| Command | Binding | Behavior |
| --- | --- | --- |
| `maksym-toggle-editable-listing` | `C-x C-q` | Enter or leave filename editing when no unapplied changes remain. |
| `maksym-apply-editable-listing` | `C-c C-c`, `C-x C-s` | Validate the inspected editable projection and apply its admitted batch once. |
| `maksym-cancel-editable-listing` | `C-c C-k`, `C-c C-[` | Discard edits and refresh observed filesystem truth. |
| `maksym-editable-next-line` | `C-n`, Down | Move to the next editable filename. |
| `maksym-editable-previous-line` | `C-p`, Up | Move to the previous editable filename. |

Metadata and structural separators remain protected. Editing is restricted to
filename fields. Newlines, absolute destinations, empty path segments, `.` and
`..` segments, duplicate destinations, collisions, missing parents,
cross-device moves, and recursive moves are rejected.

An empty regular-file field prepares permanent deletion. The blank field is
the visible review state, and one apply command performs the admitted deletion;
there is no second confirmation. Empty directory fields are rejected because
recursive directory deletion is outside the delivered core.

## Presentation and configuration boundary

Detailed listings show a theme-colored directory marker, permission characters,
byte size, modification date, and filename. Simplified listings retain only
the editable names and directory suffixes. Narrow views clip through the shared
pane renderer while preserving names, selection, and destructive review state.

Detail and sort choices belong to the live Maksym buffer. They are not durable
personal configuration in the current delivery. `src/command/maksym.rkt`
publishes the complete command inventory, categorized browsing and editable
inventories, command-name inspection, and factory entry bindings without
exposing native implementation details.

## Bounds

- One directory observation admits at most 4,096 immediate entries.
- One textual projection admits at most 32 MiB.
- Candidate queries and projections use the shared bounded candidate policy.
- Filesystem operations revalidate the directory and each source identity
  immediately before mutation.
- Preflight rejection applies nothing. A started batch reports exact outcomes
  and refreshes observed truth after any partial result.

See [Manage Maksym Changes](../../how-to/manage-maksym-files/index.md) for
focused application and recovery procedures.
