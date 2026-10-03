<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Search Text

This chapter searches forward and backward as a query changes, recalls and
extends previous queries, changes matching policy, and recovers from failed or
invalid input while preserving the captured editing origin.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../getting-started/prepare-exercises.md).

Complete [Buffers and Panes](../buffers-and-panes/index.md). Open the
kit-supplied editing-practice file:

```sh
odra ~/odra-guide/work/dirs/notes/editing-practice.txt
```

Point begins before `Editing Practice`.

## Search Forward and Backward

Press `C-s`. The bottom interaction reports a forward `Search`. Type:

```text
Observation
```

Each inserted character updates the current match. Point moves to the end of
the first occurrence and the matched range uses the active theme's search
style. Press `C-s` again to select the next occurrence. Press `C-r` to reverse
direction within the same search and return to the previous one.

Backspace removes one complete query character. Search input changes only the
query; it does not edit the buffer.

Press Enter to accept the current match. The interaction closes and point
remains at the selected edge.

## Cancel and Restore the Origin

Move to a recognizable line and press `C-s`. Search for `night`, then press
`C-g`. Odra closes the interaction and restores the point, viewport, and
horizontal position captured when this search began.

An accepted search keeps its selected location. A cancelled search restores
its origin and does not add incomplete input to ordinary search history.

## Reuse Search History

Press `C-s`, then press `C-s` again while the query is empty. Odra reuses the
newest compatible accepted literal query and selects its next match.

During an active search, `M-p` recalls older compatible entries and `M-n`
moves toward newer ones. The recalled query runs immediately. Moving beyond
the newest entry returns to the live text you were entering before history
navigation.

Type a prefix of an earlier query and press Tab. Search history completes the
newest compatible entry without accepting or closing the search. History is
bounded to the current editor session and does not persist across restarts.

## Extend a Query from Existing Text

Press `C-g`, move point before an `Observation` line, and start a new forward
search. Press `C-w` to append the next nearby textual unit to the query.
Repeated presses extend it further.

`C-M-y` appends a larger nearby structural unit when the active syntax can
provide one. `C-y` appends the newest compatible text-transfer entry. These
commands copy text into the query only; they do not insert into the document.

## Change Matching Policy

While a search is active, use these local sequences:

| Binding | Search policy |
| --- | --- |
| `M-s c` | Toggle case sensitivity. |
| `M-s r` | Toggle literal and regular-expression interpretation. |
| `M-s w` | Toggle word-boundary matching. |
| `M-s _` | Toggle symbol-boundary matching. |
| `M-s SPC` | Toggle exact and flexible whitespace. |

Each change reruns the current query without closing the interaction. Word and
symbol modes are mutually exclusive. Flexible whitespace lets one query
whitespace run match one or more whitespace characters.

Factory smart case treats a query with an uppercase Unicode character as
case-sensitive and a query without uppercase characters as case-insensitive.
Search for `market square`, then compare it with `Market Square`; the bottom
interaction reports the effective case behavior.

## Recover from No Match

Search for `Market Square`, then append `x`. The interaction reports a failing
search while preserving the last successful query and match.

Press `C-g` once. Odra removes the failing suffix and returns to the last
successful query. Press Enter to accept it. When a query has never matched,
`C-g` cancels directly and restores the captured origin.

## Search with a Regular Expression

Press `C-M-s` and enter:

```text
Observation [0-9]+: (light rain|clearing)
```

The interaction reports a forward regular-expression search and selects the
first complete match. Press `C-M-s` again for the next match and `C-M-r` to
move backward.

Append `(` to make the expression invalid. Odra reports the expression error
and byte offset without terminating the interaction or losing the last valid
match. Press `C-g` once to restore the last valid expression, then press Enter
to accept it.

## Recognize Wrapping and Pending Work

Repeating beyond the captured scope boundary reports that search wrapped before
continuing from the opposite boundary. A scan that reaches its bounded work
limit reports `Pending`; repeat the active directional search command to
continue. Neither condition edits text or blocks cancellation.

An active region restricts search to the ordered range between point and mark.
Without one, the complete active buffer is searched.

## Verify the Result

You have completed this chapter when you can repeat and reverse a literal
search, distinguish acceptance from cancellation, recall and extend a query,
toggle matching policy, recover a failed suffix, and continue through a valid
regular expression after correcting invalid intermediate input.

Continue with [Replace Text](replace-text.md) to confirm, skip, batch, and undo
matched changes.

For exact scope, smart-case, expression, history, wrapping, and resource rules,
see the [Search and Replacement Reference](../../../reference/search-and-replacement/index.md).

---

[Previous: Restore Layouts](../buffers-and-panes/restore-layouts.md) ·
[User Guide](../index.md) ·
[Next: Replace Text](replace-text.md)
