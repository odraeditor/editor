<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Themes Are Session-Owned Complete Definitions

Odra treats a theme as one complete mapping from semantic UI roles to
frontend-independent styles. It does not treat a theme as a collection of
terminal escape sequences or as a partial overlay on application code.

## One owner prevents mixed generations

The session owns one native registry, one active definition generation, one
fallback, and one safe baseline. Every current UI surface resolves its role
through that same selection. This makes a theme change apply consistently to
ordinary text, syntax, lists, prompts, status, diagnostics, selections, and
search without giving those features separate theme state.

Selection is a presentation transaction. Odra validates the exact selection,
target definition, current logical root, and renderer profile; prepares and
presents a complete candidate root; and commits the registry mutation only
after presentation succeeds. A failure republishes the prior complete
definition. No view can observe half of one theme and half of another.

## Semantic roles remain stable

Syntax and UI producers choose roles such as `Syntax_Keyword`, `Text_Region`,
or `Diagnostic_Rejected`. The active theme supplies colors and attributes for
those roles. The terminal renderer then lowers the resulting logical style to
true color, indexed color, basic color, or monochrome.

This ordering keeps language analysis and interaction state independent of
physical color capability:

```text
semantic role -> active theme definition -> logical UI style -> renderer profile
```

Changing themes cannot change syntax captures, search ranges, selection
ownership, or precedence between presentation layers.

## Racket composes data, not renderer authority

Racket can propose complete bounded definitions and request lifecycle
operations through a synchronous copied capability. Odin retains the registry,
generation checks, memory accounting, and publication authority. The terminal
renderer is never exposed to a provider.

Factory and admitted definitions therefore use the same validation and
selection workflow. Provider failure can be contained without changing the
renderer or abandoning a usable editor session.

## Fallback and baseline solve different problems

`Wrocław Night` is the maintained startup and restoration fallback. Odra
returns to it when an active admitted provider fails or leaves.

`Terminal Default` is the explicit color-minimal safe baseline. It keeps a
complete role mapping while delegating foreground and background colors to the
terminal and retaining semantic distinctions through attributes.

Neither choice removes the theme system. Keeping both as complete definitions
preserves the invariant that every logical UI generation has every required
style.

## Session scope is deliberate

Theme selection is not persisted in this MVP. A new process constructs a new
registry and starts with `Wrocław Night`. Project-local, buffer-local,
language-local, automatically scheduled, and cross-process selection remain
separate future decisions rather than hidden extensions of the session
contract.

## Related material

- [Select and Inspect a Session Theme](../../tutorials/theme-workflow/index.md)
- [Select, Inspect, and Validate Themes](../../how-to/select-and-inspect-themes/index.md)
- [Theme System Reference](../../reference/theme-system/index.md)
