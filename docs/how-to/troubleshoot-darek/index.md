<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Troubleshoot Darek

Use these procedures after the ordinary workflows in the
[Darek User Guide module](../../tutorials/user-guide/files-projects-workspaces/darek/index.md).
For the complete command and behavior contract, see the
[Darek Reference](../../reference/darek/index.md).

## Restore a missing root

Run `M-x darek-show-directory` and select an existing local directory through
filesystem candidate navigation. If a Project or Workspace was removed or
became unavailable, open a current registered context before showing Darek
again. Darek does not invent a replacement root or silently remove an
unavailable Workspace member.

## Recover from insufficient panel geometry

Press `=` to fit the panel to visible labels. If the terminal remains too
narrow, press `<` to reduce the width or `W` to leave extra-width mode. Run
`M-x darek-toggle-width-lock` when a retained width prevents normal layout
adjustment. Darek degrades its presentation before it changes ordinary pane
geometry beyond the shared layout limits.

## Diagnose an unavailable command

Run `M-x darek-help-advanced` to inspect the complete effective Darek map. The
factory binding is `C-?`, although traditional terminal input may report that
chord as Backspace inside Darek. The result identifies masked commands, user
remaps, binding provenance, and provider-dependent commands that are
unavailable. `darek-open-external` remains unavailable until an external
opener provider is registered.

## Recover preview behavior

Preview requires an eligible ordinary pane. Create or focus an ordinary
editing pane, return to Darek with `C-x t o`, and press `P` again. If a preview
document was modified or opened independently, it has been adopted and Darek
will not close it when preview stops.

## Retry a rejected filesystem action

Press `g` to refresh the current tree generation, select the resource again,
and repeat the action. Choose a different destination after a collision. Close
or save an affected open document before permanent deletion. Darek preserves
the prior tree and pane state when generation, permission, destination, or
document-coherence checks reject an operation.

## Show entries hidden by policy

The delivered local filesystem tree excludes hidden entries. This is a
bounded observation policy, not a refresh failure. Hidden-entry toggling is
outside the delivered Darek core.
