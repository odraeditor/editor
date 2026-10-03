<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Use Syntax and Structure

This chapter observes theme-aware syntax while editing, navigates and selects
language structure, applies one reversible structural indentation, and
confirms that unsupported documents remain ordinary editable text.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../getting-started/prepare-exercises.md).

Complete the Files, Projects, and Workspaces part. Recreate the maintained
tutorial Workspace if needed, then launch Odra normally:

```sh
"$HOME/odra-guide/kit/bin/odra-guide" reset workspace-state
odra
```

Open the `User Guide` Workspace and select
`Forecast Engine/src/forecast/model.odin`.

The exercise kit supplies both the Workspace definition and every source file
used in this chapter.

## Observe Semantic Syntax

The maintained provider associates the case-sensitive `.odin` suffix with
Odin syntax analysis. Keywords, comments, numbers, strings, types, functions,
parameters, punctuation, and other admitted captures appear through semantic
theme roles rather than provider-owned colors.

Insert a comment above `Observation`, then press `C-/` to undo and run
`M-x redo` to restore it. Text publishes first; syntax analysis advances to the
new exact revision afterward. Odra never applies spans from an older revision
to newer text.

Start a search with `C-s`, enter `station`, and press `RET`. Set mark with
`C-SPC` and move point across syntax-colored text. The current search match
takes presentation precedence over an active region, and the region takes
precedence over syntax. Cancelling search or selection reveals the unchanged
underlying syntax roles.

Undo the inserted comment before continuing so the maintained source returns
to its original text.

## Observe Shared Analysis Across Views

Press `C-x 3` to split to the right. Both panes display the same buffer-owned
text and language-analysis lifecycle, while each view retains its own point,
viewport, and history.

Press `C-x o`, move one viewport with `PageDown`, and edit one identifier.
Both panes receive syntax for the new buffer revision without forcing their
viewports to match. Undo the edit, then press `C-x 1` to keep only the active
pane.

## Navigate Named Structure

Move point into `sample_observations`. Use the direct bindings or the matching
named commands:

| Binding | Command | Result |
| --- | --- | --- |
| `C-M-f` | `structural-forward` | Move to the end of the next named node at the current level. |
| `C-M-b` | `structural-backward` | Move to the start of the previous named node at the current level. |
| `C-M-u` | `structural-up` | Move to the start of the nearest strict named ancestor. |
| `C-M-d` | `structural-down` | Move to the start of the first named child. |

At a boundary with no applicable sibling, ancestor, or child, the operation is
a checked no-op. It does not approximate a target from byte position alone.

## Select Structure

Place point inside one observation literal and press `C-M-SPC`. The first
invocation selects the smallest named node containing point. Repeat the binding
to expand the region through strict named ancestors.

Structural selection uses the ordinary buffer-owned point and mark. Every view
of the same buffer observes the canonical selection, while independent stored
view positions remain intact. Press `C-g` to deactivate the region.

## Indent and Reverse One Structural Edit

Open `Forecast Engine/main.odin`. Remove the leading indentation from one
`fmt.printf` line, then run `M-x structural-indent`. The provider changes only
the leading horizontal whitespace required for the current structural line.

Select two adjacent statement lines and run `M-x structural-indent` again.
Every admitted leading-whitespace replacement publishes as one text
transaction. Press `C-/` once to undo the complete operation, then run
`M-x redo` to restore it.

After each text publication, analysis refreshes before the next structural
operation can use a new exact tree generation. Save only after the maintained
source has returned to its original valid form.

## Inspect Current State

Run `M-x describe-language-state`. The shared list identifies the active
language and provider, confirmed and syntax revisions, parser and query
generations, semantic spans and roles, renderer capability, pending work,
resource usage, and the latest contained rejection. Press `q` to return.

Run `M-x describe-structural-state` to inspect the exact buffer, revision,
selection, analysis, grammar, last target, last operation, indentation range,
limits, and latest structural rejection. Inspection copies existing state; it
does not trigger parsing, movement, selection, or text mutation.

## Confirm Plain-Text Fallback

Open `~/odra-guide/work/dirs/notes/editing-practice.txt` and run
`M-x describe-language-state`. The document reports a plain-text association
without parser-owned syntax decoration.

Run `M-x structural-forward`. The unavailable structural operation changes no
point, selection, text, viewport, or history. Ordinary insertion, movement,
selection, search, save, pane, and buffer commands remain available.

## Recover from Syntax Problems

- If syntax has not reached the current revision, continue ordinary editing
  and inspect pending work before issuing a structural command.
- If a structural command reports stale analysis, wait for the current
  generation or make another ordinary edit and retry after maintenance.
- If a syntax error contains the target line, restore valid source or navigate
  with ordinary text commands; indentation does not guess through invalid
  structure.
- If colors are absent, inspect terminal capability and theme selection. Syntax
  remains semantic in indexed, basic, or monochrome presentation.
- Unsupported files need no recovery: plain text is the expected fallback.

## Verify the Result

You have completed this chapter when syntax follows edits and undo across two
views, all four structural movements use named nodes, structural selection
expands through ancestors, indentation is one reversible transaction,
inspection reports exact current state, and a plain-text file remains fully
usable without language analysis.

For focused recovery, see
[Use and Validate Structured Syntax](../../../how-to/use-structured-syntax/index.md)
and
[Configure and Validate Factory Syntax Presentation](../../../how-to/configure-factory-syntax-presentation/index.md).
For exact contracts, see the
[Semantic Syntax Presentation Reference](../../../reference/semantic-syntax-presentation/index.md)
and
[Structural Editor Operations Reference](../../../reference/structural-editor-operations/index.md).

---

[Previous: Language Intelligence](index.md) ·
[User Guide](../index.md) ·
[Next: Work with Jan Documents](work-with-jan-documents.md)
