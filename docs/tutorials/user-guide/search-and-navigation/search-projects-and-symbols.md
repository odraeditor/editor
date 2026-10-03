<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Search Projects and Symbols

This chapter searches text across an active Project, repeats the captured
query, opens a provider-neutral symbol index, searches the symbol at point, and
moves through each active location source with the same navigation commands.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../getting-started/prepare-exercises.md).

Complete [Navigate Result Sets](navigate-results.md). Project search requires
an active Project. Restore the kit-supplied Project identity and source tree,
then open its root:

```sh
"$HOME/odra-guide/kit/bin/odra-guide" reset workspace-state
odra ~/odra-guide/work/projects/forecast-engine
```

Select `main.odin` from the file candidate surface. The Files, Projects, and
Workspaces part explains this lifecycle in depth; here the restored Project
supplies a bounded search scope.

## Search Project Text

Run `M-x project-search-text`. Enter:

```text
Market Square
```

Odra searches the admitted files below the active Project root and opens the
common result surface. Rows are grouped by file and show a path, aligned
line-and-column fields, and nearby source text.

Filter and move with the same keys used for active-buffer results. Press Enter
on one row to open or reuse its file and visit the checked match. Press
`M-g M-n` or `M-g M-p` from the editor to continue through the Project result
source.

Project search excludes hidden, ignored, and binary files under its current
policy. It does not require a repository or external search executable.

## Search a Project with an Expression

Run `M-x project-search-text-regexp` and enter:

```text
(Observation|Summary)
```

The result surface uses the same navigation and refresh behavior. Project
results are read-only: `e` reports that the selected provider does not admit
result editing.

Press `q`, then run `M-x project-search-repeat`. Odra applies the newest Project
query and policies to the current active Project. If Project identity,
membership, or a source fingerprint has changed, stale authority is reported
without moving point or replacing a newer valid result generation.

## Search the Symbol at Point

Open:

```text
~/odra-guide/work/projects/forecast-engine/src/forecast/summary.odin
```

Move point onto `observations` and press `M-s .`. Odra resolves the symbol
under or adjacent to point and starts an ordinary forward search with symbol
boundaries enabled. Repeat with `C-s`, accept with Enter, or cancel and restore
the origin with `C-g`.

The current language or syntax provider supplies symbol boundaries when
available. Generic Unicode symbol rules provide the fallback.

## Open the Symbol Navigator

Run `M-x symbol-navigator`. The common result surface lists the active
buffer's symbols with provider-neutral kind and containing-scope annotations.
Type `summarize` to filter the rows, then press Enter to visit that declaration.

Open the navigator again. Use Up, Down, `M-p`, `M-n`, `<`, and `>` for result
movement. Press `g` to rebuild the index against the current buffer revision,
or `q` to close it and return to the source.

Odra prefers a revision-current language provider with symbol support. The
maintained Odin provider derives its index from the current syntax tree; when
no provider index is available, a bounded language-independent token index is
the fallback. Provider choice changes available detail, not the public command
or result navigation model.

## Use the Active Location Source

Active-buffer matches, Project matches, symbols, diagnostics, and other ordered
locations publish through the common location model. The most recently
activated compatible source owns `M-g M-n` and `M-g M-p`.

These commands move the source's checked selection and visit its target. They
do not guess among several providers from rendered text. Closing a result set
releases its location authority; a stale or unavailable target preserves the
current editor location.

## Recover from Provider Problems

- Project search requires one current active Project and fails plainly in an
  ordinary Dir or file-only session.
- A refreshed Project invalidates result authority from the prior membership
  generation.
- Changed files are fingerprint-checked before Project-result navigation.
- A stale language observation cannot publish a symbol index for a newer
  buffer revision.
- Bounded providers report incomplete work rather than presenting partial
  results as complete.
- `C-g` cancels an active query or closes a clean result interaction without
  changing source text.

## Verify the Result

You have completed this chapter when a literal Project query finds multiple
files, an expression query remains read-only, repeat uses the newest Project
query, `M-s .` searches one resolved symbol, the symbol navigator filters and
visits declarations, and `M-g M-n` or `M-g M-p` follows the active location
source from the editor.

Continue with
[Files, Projects, and Workspaces](../files-projects-workspaces/index.md).

For exact provider, result, fingerprint, symbol, fallback, and location-source
contracts, see the
[Search Result Navigation Reference](../../../reference/search-result-navigation/index.md)
and [Symbol Navigation Reference](../../../reference/symbol-navigation/index.md).

---

[Previous: Navigate Result Sets](navigate-results.md) ·
[User Guide](../index.md) ·
[Next: Files, Projects, and Workspaces](../files-projects-workspaces/index.md)
