<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Read Pane Context in the Status Bar

This tutorial shows how to read the pane-local Status Bar while editing a
document, working inside a Project, and using language diagnostics.

## Open a Document

Build and open an Odin document:

```sh
make odra
.build/odra /path/to/project/main.odin
```

At ordinary terminal width, the bottom of the pane presents a subtle separator
and one contextual row. Buffer size, Project-relative directory, filename,
one-based line and display column, and `Top`, `Bot`, or a percentage appear as
separate fields on the left. The directory is absent outside an active Project.

For an associated UTF-8 document, `UTF-8 LF` appears in the contextual group
on the right when selected. An unassociated buffer omits that field.

## Read Safety and Pane State

Edit the document. `**` appears before the filename while the current revision
differs from its saved base. Saving removes the marker.

A dedicated pane adds `Soft` or `Hard`. Ordinary pane policy remains silent.
These labels describe state; editing the labels cannot change the buffer or
pane.

## Read Project and Workspace Context

Open a registered Project. A pane displaying a Project-owned document adds a
`P:` field with the Project name. When that Project is active through a
Workspace, the row also adds a separate `W:` field.

A document outside the active Project omits both fields. Their absence means
that no applicable owner supplied context; it is not an error.

## Read Language Context

Open an Odin document. The right group includes `Odin` when the syntax owner
has associated the buffer with that language.

When a language service is active, `LS` joins the same segment. Current
diagnostic totals use `E` and `W`, for example `Odin LS 1E 2W`. Initializing,
failed, or stopped service state is named explicitly.

## Resize the Pane

Reduce the terminal width. The Status Bar first selects compact forms such as
`U8`, `W`, `P`, and `Odin`, then removes optional low-priority context. It
retains alerts, buffer safety, buffer identity, and compact position. A long
filename ends at a complete Unicode grapheme and uses `…` rather than splitting
a character.

Restore the terminal width. The full contextual forms return from current
owner observations.

## Inspect and Activate Segments

Run `M-x status-bar-inspect`. A candidate list headed `Status Bar [active
pane]` presents every visible segment. Type part of a label or inspection value
to filter it, use the arrow keys to move, and press `RET` to return to editing
with that segment's inspection text in the Status Bar. Press `C-g` instead to
cancel without changing the editing context.

Run `M-x status-bar-actions` to show only segments that currently expose an
admitted primary action. Selecting the buffer name opens buffer navigation. A
Project or language segment delegates to its existing Project or language
command surface. The candidate is generation-checked, so a stale segment is
never redirected to a newer command.

## Configure the Factory Presentation

Add this binding to `${XDG_CONFIG_HOME:-$HOME/.config}/odra/init.rkt`:

```racket
#lang racket/base

(provide odra-status-bar-configuration)

(define odra-status-bar-configuration
  '#hash((position . line-column)
          (visible . (project editing-context))
          (compact . prefer-compact)))
```

Restart Odra. Position now uses `line:column` without a percentage, only the
selected optional context is eligible, and its compact form is preferred.
Invalid configuration reports a bounded startup diagnostic and leaves the
factory presentation active.

## Trace a Programmable Provider

The extension facade constructs one provider from bounded declarative
segments. A package can define a right-group task summary as follows:

```racket
(define task-segment
  (status-bar-segment
   'task-count "3 tasks"
   #:compact "3"
   #:group 'right
   #:order 20
   #:priority 10
   #:style 'context
   #:inspection "Three active tasks"
   #:primary-command 'tasks-open))

(define task-provider
  (status-bar-provider "Tasks" 'tasks-package (list task-segment)))
```

The runtime grants lifecycle authority separately. The package registers the
complete provider, retains the returned provider handle, and uses that exact
generation for replacement, removal, or teardown. Native composition then
uses the copied segment without invoking Racket during a pane frame.

Run the facade and boundary checks from the repository root:

```sh
raco test src/command/status-bar.rkt src/hosting/status-bar-bridge.rkt
make status-bar-resource-study
```

The resource study fills the current 20-segment programmable capacity and
reports average and maximum native composition latency.

For exact field order, limits, and failure behavior, see the
[Status Bar Reference](../../reference/status-bar/index.md).
