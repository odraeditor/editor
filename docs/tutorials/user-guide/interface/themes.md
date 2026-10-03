<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Select and Read a Theme

This chapter selects one complete session theme, reads its effect across the
active interface, inspects the semantic style mapping, and verifies safe
presentation in reduced terminal capabilities and narrow layouts.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../getting-started/prepare-exercises.md).

Complete [Understand Provider Fallback](../language-intelligence/provider-fallback.md).
Launch the maintained tutorial Workspace with a one-off true-color capability
override:

```sh
COLORTERM=truecolor TERM=xterm-256color odra
```

This override is part of the capability exercise, not ordinary Odra startup.

Open `Forecast Engine/main.odin` and show Darek with `M-t`. Keep both the
source pane and tree visible so one theme transition can be observed across
text, syntax, selection, pane context, list rows, and interface chrome.

The exercise kit supplies the Workspace and Project file used here.

## Select One Complete Theme

Run `M-x select-theme`. The shared candidate surface lists every confirmed
definition. Filter by display name, stable identity, or provider.

Select `Wrocław Sunset` and press `RET`. Odra presents one complete interface
generation before committing the new session selection. Source text and
editor state do not change; their semantic roles resolve through the newly
selected definition.

The theme applies session-wide. The active and inactive panes retain distinct
context, the current Darek row remains distinguishable from ordinary rows,
and syntax, selections, search matches, diagnostics, Status Bars, and
transient surfaces use the same semantic vocabulary.

## Verify Cancellation

Run `M-x select-theme`, filter for `sunrise`, and press `C-g`. Reopen the
selector or run `M-x describe-theme`. `Wrocław Sunset` remains active because
cancellation closes the candidate interaction without beginning a theme
transition.

A candidate captured before the registry or selection changes is also
rejected rather than redirected to a newer definition. Reopen the selector to
obtain current candidates.

## Inspect Semantic Presentation

Run `M-x describe-theme`. The read-only list begins with the active, fallback,
and safe-baseline identities, provider state, renderer capability, current
generations, resource usage, and latest rejection.

Continue through the semantic role rows. Each row separates the stable role
from its logical foreground, background, and attributes and from the value
lowered for the current renderer. Providers publish roles such as ordinary
text, current list row, diagnostic rejection, comment, function, or keyword;
they do not choose terminal escape sequences or palette-specific behavior.

Use `Up` and `Down` to move. Press `q` or `C-g` to return without changing the
selection.

## Read Active Context

Move focus between Darek and the source pane with `M-t`. The focused pane and
its Status Bar use active semantic roles; the other pane remains deliberately
muted. Theme selection does not change which pane owns focus, which buffer it
shows, or which Project or Workspace supplies context.

Make a temporary edit in `main.odin`. The modified marker and filename remain
visually distinct without acquiring ownership of the modified state. Undo the
edit. The theme only presents current observations from their owning
subsystems.

## Observe Narrow Layout Behavior

Reduce the terminal width while keeping two panes visible. Lists, source,
Status Bars, and transient surfaces choose their bounded compact or fallback
forms. Long labels truncate at complete grapheme boundaries; required safety
state and active selection remain distinguishable.

If geometry cannot contain a transient surface, Odra reports the rejected
presentation and preserves the existing interface generation. Restore width
or simplify the pane layout, then invoke the interaction again.

## Use the Terminal Baseline

Run `M-x select-theme`, choose `Terminal Default`, and press `RET`. This safe
baseline leaves foreground and background colors to the terminal while
retaining required distinctions through attributes such as reverse,
underline, bold, and dim.

Launch another one-off session without true-color advertisement:

```sh
env -u COLORTERM TERM=xterm odra
```

Select a maintained colored theme and inspect it. Odra lowers the same logical
roles deterministically to the available indexed, basic, or monochrome
profile. Selecting a theme never changes the terminal capability detected for
that session.

Theme selection is currently session-wide and is not persisted. A new session
starts with `Wrocław Night`.

Exit the capability experiment. Resume ordinary guide work with:

```sh
odra
```

## Recover from Theme Problems

- If a selection is stale, reopen `select-theme` and choose from the current
  generation.
- If presentation rejects a candidate, run `describe-theme` and confirm the
  previous complete definition remains active.
- If an admitted active provider fails, the maintained factory fallback is
  restored as one complete transition.
- If terminal color output is unsuitable, select `Terminal Default`; do not
  encode terminal escapes or concrete colors into content.
- If a narrow layout cannot show an interaction, restore geometry and retry;
  the failed presentation does not mutate editor state.

## Verify the Result

You have completed this chapter when one selection updates every visible
surface coherently, cancellation preserves the active definition, inspection
connects semantic roles to renderer lowering, active-pane context remains
owned by the pane, narrow geometry fails safely, and `Terminal Default`
preserves meaning without editor-selected colors.

For focused selection and recovery, see
[Select, Inspect, and Validate Themes](../../../how-to/select-and-inspect-themes/index.md).
For exact identities, roles, lifecycle, and degradation, see the
[Theme System Reference](../../../reference/theme-system/index.md).
For the ownership rationale, see
[Why Themes Are Session-Owned Complete Definitions](../../../explanation/session-theme-ownership/index.md).

---

[Previous: Understand Provider Fallback](../language-intelligence/provider-fallback.md) ·
[User Guide](../index.md) ·
[Next: Read and Configure the Status Bar](status-bar.md)
