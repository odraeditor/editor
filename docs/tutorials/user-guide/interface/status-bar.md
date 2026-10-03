<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Read and Configure the Status Bar

This chapter reads buffer safety, position, Project, Workspace, and language
context from the active pane, invokes admitted segment actions, changes the
factory layout, and verifies deterministic behavior in narrow geometry.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../getting-started/prepare-exercises.md).

Complete [Select and Read a Theme](themes.md). Open the maintained `User Guide`
Workspace, select `Forecast Engine/main.odin`, and keep Darek visible beside
the source pane.

The exercise kit supplies this Workspace and Project file. The configuration
source introduced later is pasted by the reader from its complete block.

The Status Bar belongs to one pane. It observes current state from the buffer,
view, Project, Workspace, and language owners without owning or mutating any of
them.

## Read the Active Pane

At ordinary width, read the Status Bar from left to right:

```text
704 src/ main.odin 18:7 22%       W:User Guide P:Forecast Engine UTF-8 LF Odin LS
```

The exact values depend on the active document. The left group presents
buffer size, Project-relative directory, filename, one-based line and display
column, and viewport position. The right group presents only available
Workspace, Project, encoding, language, service, and diagnostic context.

Move point and scroll. Position and `Top`, `Bot`, or percentage update from the
active view. Press `M-t` to focus Darek, then return to the source pane. Each
pane presents its own buffer and view context; the selected theme distinguishes
the active row from inactive rows.

Unavailable context is absent. A document outside the active Project does not
acquire invented Project or Workspace labels.

## Read Safety and Language State

Insert one character. `**` appears before the filename while the document
differs from its saved base. Press `C-/` to restore the clean revision and
observe the marker disappear.

In a read-only or modified read-only context, `%%` or `%*` distinguishes write
policy from modification state. These markers report state; they are not text
and cannot change the buffer when selected or copied.

For a supported source document, the editing-context segment begins with the
language. An active language service adds `LS`; current error and warning
totals appear as `E` and `W`. Initializing, failed, and stopped service states
are explicit when current observations provide them.

## Inspect Visible Segments

Run `M-x status-bar-inspect`. The shared candidate surface lists the exact
segments composed for the active pane generation. Type part of a label or
inspection value to filter, move with `C-n`, `C-p`, `Down`, or `Up`, and press
`RET`.

Odra returns to the editor and places the selected bounded inspection value in
the shared feedback region. Press `C-g` instead to cancel without changing the
editing context.

## Invoke an Admitted Action

Run `M-x status-bar-actions`. Only visible segments whose owning subsystem has
an admitted primary command appear. The buffer identity opens buffer
navigation; Project and language context delegate to their ordinary command
surfaces.

Select one action with `RET`, then return to the document. The candidate
captures the exact Status Bar and command-registry generations. If either
changes before acceptance, Odra rejects the stale row instead of invoking a
different action.

## Observe Narrow-Pane Policy

Reduce the terminal width or split the source again. The Status Bar applies
one deterministic sequence:

1. use admitted compact forms;
2. omit optional low-priority context;
3. truncate the buffer label at a complete grapheme and append `…`; and
4. retain alerts, buffer safety, identity, and compact position.

Restore the width. Full forms return from current observations. Narrow
presentation never changes the underlying buffer, Project, Workspace, or
language state.

## Configure the Factory Layout

Open `~/odra-guide/config/odra/init.rkt`. Preserve existing exports and
add this complete Status Bar policy:

```racket
(provide odra-status-bar-configuration)

(define odra-status-bar-configuration
  '#hash((position . line-column)
          (visible . (project editing-context))
          (compact . prefer-compact)))
```

Save the file, restart Odra, and reopen the tutorial Workspace. Position now
uses `line:column` without a percentage, only Project and editing context are
eligible among optional segments, and their compact forms are preferred.

The admitted position policies are `line-column-percentage`, `line-column`,
and `byte-offset`. Visibility may include `encoding`, `pane-state`,
`workspace`, `project`, and `editing-context`. Compact policy may be
`automatic`, `prefer-compact`, or `essential-only`.

Introduce an invalid value, restart, and observe the bounded configuration
diagnostic. The complete candidate is rejected and the factory presentation
remains active. Restore the valid policy before continuing.

## Recover from Status Bar Problems

- If expected context is absent, verify the active pane, buffer association,
  Project or Workspace membership, and current language publication.
- If an action list is empty, inspect segments first; informational segments
  need not expose an action.
- If an accepted candidate is stale, reopen the command to capture current
  segment and command generations.
- If a label disappears in narrow geometry, restore width before treating the
  omitted optional segment as unavailable state.
- If personal configuration is rejected, correct the complete exported value
  and restart; partial policy is never applied.

## Verify the Result

You have completed this chapter when position follows the active view, safety
tracks the buffer revision, Project, Workspace, and language context appear
only when owned, inspection and actions use current segments, narrow panes
retain essential meaning, and one complete personal policy changes layout
without changing editor state.

For exact fields, order, compact forms, actions, and configuration values, see
the [Status Bar Reference](../../../reference/status-bar/index.md).

---

[Previous: Select and Read a Theme](themes.md) ·
[User Guide](../index.md) ·
[Next: Use the Gutter](gutter-and-transient-details.md)
