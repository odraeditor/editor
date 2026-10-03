<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Work with Jan Documents

This chapter opens one structured document, confirms Jan recognition, folds and
navigates its outline, performs structural edits, and saves the document.
Unrelated source remains byte-for-byte unchanged.

## Before You Begin

If you enter this chapter directly, first complete
[Prepare the User Guide Exercises](../getting-started/prepare-exercises.md).

Copy either `notes/structured-editing.org` or
`notes/structured-editing.jan` from the prepared Forecast Engine exercise into
`~/odra-guide/work/dirs/notes/`. The two playground files contain identical
bytes. You can also create a smaller document:

```org
#+TITLE: Jan Structured Editing

* Alpha
** Child
   - first item
   - second item

* Beta
| name | value |
| alpha | 1 |
```

Open the file in Odra. The `.org` suffix selects the bundled `jan` language.
The `.jan` suffix selects the identical language and provider; it is not a
separate dialect.

## Confirm Jan Recognition

Run `M-x jan-language-status`. The list identifies `jan`, the
`factory-jan-tree-sitter` provider, baseline `jan-org-9.8.10-v1`, current
revision and analysis generations, resource limits, and the capability ledger.
In a development build, domain contracts can exist before every editor command
is linked. Press `q` to return to the document.

Run `M-x jan-inspect-syntax` with point in the heading, link, and source block.
Each result names the deepest syntax path, its exact half-open UTF-8 byte range,
typed attributes, current generations, and any recovery state.

## Lint Current Syntax

Run `M-x jan-lint`. Jan reports bounded diagnostics derived from the current
confirmed analysis. Delete the final `#+end_src` line, run
`M-x jan-lint-refresh`, and observe the recovery diagnostic for the current
revision.

Undo the deletion and run `M-x jan-lint-refresh` again. Linting and inspection
never execute the source block, follow the link, open another file, or access
the network.

## Fold and Navigate the Outline

Place point on `Alpha`. Press `TAB` repeatedly to move through heading only,
direct children, and complete subtree visibility. `C-c j c` and
`M-x jan-cycle` invoke the same command in the Direct profile; `za` invokes it
in the modal profile. Press `S-TAB` to cycle the visibility of the complete
document.

Use `C-c C-n` and `C-c C-p` in the Direct profile, or `]h` and `[h` in the
modal profile, to visit the next or previous visible heading. The mnemonic
aliases `C-c j n` and `C-c j p` remain available. Run `M-x jan-show-all` at any
time to reveal the complete document. Folding belongs to the active view and
never deletes source text.

Move point onto `:NOTES:` under `Forecast review` in the prepared playground.
Run `M-x jan-toggle-drawer`; the drawer body disappears while `:NOTES:` and
`:END:` remain visible. Run the same command again to reveal the body. Open a
second view of the document to confirm that its drawer remains independently
visible. The command is available by the same name from `M-x` in the direct
profile and `:` in the modal profile.

## Perform One Structural Edit

Place point on `Alpha` and press `M-RET`. Jan inserts one sibling heading
through a checked transaction. Use `M-Left` and `M-Right` to promote or demote
it, and `M-Up` or `M-Down` to move its subtree. Undo once, redo once, and save
with `C-x C-s`. The heading edit, undo, and redo are ordinary editor history
operations.

Try the same pattern with a list item and `jan-insert-list-item-after`, or a
table row and `jan-insert-table-row`. A command invoked at an incompatible,
stale, malformed, or unavailable target reports a rejection and leaves source
unchanged.

## Inspect Context and Presentation

Run `M-x jan-context-action` or use `C-c C-c` in the Direct profile and `ga` in
the modal profile. The alias `C-c j a` remains available. The diagnostic
reports the syntax context, resolved command, status, and owning domain when
the source form is recognized but its operation is unavailable.

The familiar planning bindings use the same language-local map. For example,
`C-c C-t` changes TODO state, `C-c C-s` schedules the entry, `C-c C-d` sets a
deadline, and `C-c C-q` edits tags. Use `C-c a` for the agenda and `C-c c` for
capture. These bindings are active only in Jan documents.

Run `M-x jan-present`. The terminal keeps canonical source visible while using
the current Jan semantic projection. Run `M-x jan-inspect-availability` to
inspect the exact capability state for this build.

## Work with a Source Block

Place point inside a `#+begin_src` block. Press `C-c C-v h` to open the Jan
Babel binding reference. Use `C-c C-v u` to return to the block header and
`C-c C-o` to visit its adjacent `#+RESULTS:` owner. `C-c C-v I` presents the
resolved language, range, body size, result ownership, and effective source
hash.

Use `C-c C-v g` or `C-c C-v r` to select a named source or result. The
selection is tied to the document revision that produced it; a changed
document rejects stale navigation.

At a line boundary inside the body, `C-c C-v d` splits the block and preserves
its language and header arguments. To add a header argument, select the exact
`:key value` text and press `C-c C-v j`. Both edits are single undo units.

`C-c C-c` and `C-c C-v e` request execution. If no language adapter is
configured, Jan reports that outcome and leaves the source untouched. Invalid
source, rejected authority, cancellation, and execution failure use distinct
outcomes. Inside the source block, `M-Up` loads into the associated session and
`M-Down` displays it. Outside a source block, both keys continue to move Jan
subtrees.

## Save Exact Source

Jan does not serialize a syntax tree during save. The ordinary document path
writes canonical editor bytes, so untouched casing, indentation, line endings,
delimiters, unknown forms, and malformed fragments remain unchanged.

To check suffix parity, copy the file to `jan-stage-1.jan`, open the copy, and
run `M-x jan-language-status`. The language, provider, baseline, and syntax
meaning are the same for identical source bytes.

## Continue into Document Workflows

Stage 1 provides recognition, syntax presentation, revisioned analysis,
inspection, and linting. Stage 2 adds visibility, structural, list, table, rich
presentation, local footnote, completion, template, indentation, contextual,
and repetition command identities. Planning, computation, output, publishing,
and integration use the same confirmed analysis and checked effect boundaries.
Continue with [Structured Documents](../structured-documents/index.md) when the
required status reports those capabilities as operational.

## Verify the Result

You have completed this chapter when both suffixes select Jan, visibility and
navigation work, one structural edit survives undo, redo, and save, source
block inspection uses the familiar `C-c C-v` family, terminal presentation
preserves source, and unavailable operations preserve editable text without
gaining authority.

For a concise operating procedure, see
[Use and Diagnose Jan Documents](../../../how-to/use-jan-documents/index.md).
For the exact package and linked-application surface, see the
[Jan Capability Ledger](../../../reference/jan-stage-1-capabilities/index.md)
and [Jan Structured Editing Commands and Configuration](../../../reference/jan-structured-editing-commands/index.md).

---

[Previous: Use Syntax and Structure](syntax-and-structure.md) ·
[Language Intelligence](index.md) ·
[Next: Use Language Services and Diagnostics](language-services-and-diagnostics.md)
