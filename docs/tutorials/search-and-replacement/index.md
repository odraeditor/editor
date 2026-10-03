<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Search and Replace Text Interactively

This tutorial exercises Odra's visible literal and regular-expression search
and query-replacement workflows. You will search in both directions, recover
from invalid input, confirm and skip individual replacements, replace the
remaining matches atomically, and undo one complete query session.

## Prepare a document

From the repository root, build the editor and create a small UTF-8 document:

```sh
make odra
printf 'zero alpha one alpha end\nPolish: Zażółć\nIDs: alpha-42 beta-7\n' > /tmp/odra-search.txt
.build/odra /tmp/odra-search.txt
```

Point begins at the start of the document.

## Search forward and repeat

Press `Control-S`. The final row changes to a `Search →` prompt. Type
`alpha`. Odra highlights the first occurrence and moves point to its end.

Press `Control-S` again. The second occurrence becomes current. Press
`Control-R` to reverse direction and return to the previous occurrence.

The query is interaction text: typing and Backspace change the search pattern
instead of editing the document.

## Recall and extend searches

Press `RET` to accept `alpha`, then press `Control-S` twice. The second press
reuses the accepted query because the new prompt is empty.

During an active search, `M-p` recalls older compatible queries and `M-n`
returns toward newer entries. Moving past the newest entry restores the text
you were entering before history navigation. `TAB` completes the current text
from the newest compatible history entry without accepting the search.

Press `Control-G`, move point before `Polish`, and start another search.
`Control-W` extends the query with the next textual unit. `Control-Meta-Y`
uses a larger nearby structural unit, and `Control-Y` uses the newest compatible
text-transfer entry. These commands change only the query.

## Change matching policy while searching

The following sequences re-run the current query without closing the prompt or
changing its captured origin:

- `M-s c` toggles case sensitivity.
- `M-s r` toggles literal and regular-expression interpretation.
- `M-s w` and `M-s _` select word or symbol boundaries.
- `M-s SPC` toggles exact and flexible whitespace.

The prompt reports case, boundary, whitespace, wrapping, invalid-expression,
and no-match state independently. Press `Control-G` to restore the captured
point and viewport.

## Observe smart case

Press `RET` to accept the current match, then press `Control-S` and type
`zażółć`. A lowercase query uses Unicode-aware case-insensitive matching and
finds `Zażółć`.

Press `Control-G` to abort this successful search. Point returns to the exact
position captured when this search began.

Press `Control-S` again and type `Zażółć`. The uppercase letter makes smart
case select case-sensitive matching. The prompt reports the effective mode.

## Recover from a failed suffix

With `Zażółć` matched, type `x`. The prompt changes to `Failing Search`, but
the last successful match stays highlighted and point does not move.

Press `Control-G` once. Odra removes the failed suffix and restores the last
successful query. Press `RET` to accept that match and keep point there.

## Search with a regular expression

Press `C-M-s` and type `([a-z]+)-([0-9]+)`. The prompt identifies the search as
`Regexp →`, highlights `alpha-42`, and moves point to the end of the
complete match. The two parenthesized groups are retained as numbered capture
ranges even though the terminal highlights the complete match.

Press `C-M-s` again to select `beta-7`. Press `C-M-r` to reverse direction and
return to `alpha-42`.

Type `(` after the valid expression. The prompt reports the parser error and
its byte offset while the last successful match remains selected. Press
`Control-G` once to discard the invalid suffix and restore the last valid
expression, then press `RET` to accept it.

## Observe wrapping and bounded work

Repeated search at an admitted scope boundary reports `Wrapped Search` or
`Wrapped Regexp` before continuing from the opposite boundary. A long
scan reports `Pending`; repeat with the binding for the active search kind and
direction to resume the next bounded turn. Neither state blocks terminal input
or changes document text.

## Materialize, navigate, and edit matches

Start a forward search for `alpha`, then press `M-s o` while the search is
active. Odra replaces the transient search prompt with a persistent result
surface containing the retained matches. Each row shows its line and column,
nearby source text, and the matched range in the active theme. Project-wide
results also show the source path before the location.

Use `M-n` and `M-p`, or Down and Up, to move through the visible results. `<`
and `>` select the first and last result. Unreserved text input filters the list; Backspace
broadens it again. Press `RET` to visit the selected location and return to the
document. From the editor, `M-g M-n` and `M-g M-p` continue through the active
location source.

Materialize the search again and press `e` on one selected match. The bottom
prompt contains the exact matched source text. Change it and press `RET` to
stage the replacement. The document has not changed yet. Press `C-c C-c` on
the result surface to preflight and apply the staged edit as one undo unit.

Press `g` to refresh a clean result set. Press `q` to close it. A dirty result
set refuses `q`; use `C-c C-c` to apply its edits or `C-g` on the result
surface to discard them. `C-g` while the edit prompt itself is active cancels
only that prompt.

## Search the active Project

Open a registered or local Project, then run `M-x project-search-text`. Enter a
literal query and press `RET`. Odra searches admitted files below the Project
root and opens the common result surface. Use its ordinary filtering, movement,
`RET`, `g`, `q`, and unified `M-g M-n` or `M-g M-p` navigation.

Run `M-x project-search-text-regexp` for a regular-expression query. Run
`M-x project-search-repeat` to apply the most recent Project query to the
current active Project. Project results are read-only: editing commands remain
available for materialized active-buffer matches, not Project-wide matches.

Search excludes hidden, ignored, and binary files by default. A changed source
or refreshed Project is revalidated before navigation; stale authority reports
a diagnostic without moving point.

Press `Control-X`, then `Control-C` to exit. Search made no text changes, so
the document remains clean. Prepare a separate replacement exercise:

```sh
printf 'one one one one\nIDs: alpha-42 beta-7\n' > /tmp/odra-query-replace.txt
.build/odra /tmp/odra-query-replace.txt
```

## Replace selected occurrences

Press `M-%`, type `one`, press `RET`, type `two`, and press `RET` again. Odra
highlights the current occurrence and shows the pattern, replacement, effective
case, confirmed count, skipped count, and available responses.

Press `y` to replace the first occurrence. Press `n` to skip the second. Press
`SPC` to replace the third. The prompt now reports two confirmed replacements
and one skip. `DEL` is an alternative to `n`.

Press `!`. Odra replaces every remaining occurrence in the captured scope as
one atomic batch and finishes the interaction. The document now begins with:

```text
two one two two
```

The earlier confirmations and the final batch belong to one uninterrupted
query-replacement history group. Press `Control-/` (`Control-_` and
`Control-X`, then `u` are aliases); one undo restores all four original
occurrences.

## Keep confirmed work when leaving

Start `M-%` again with `one` and `two`. Press `y`, then `q`. The interaction
ends, but the confirmed first replacement remains. `RET` has the same quit
behavior while Odra is awaiting a response. `Control-G` also ends the active
interaction without reversing already confirmed replacements.

Start the interaction once more and press `.` at the first response. Odra
replaces that current occurrence and exits immediately.

## Replace with regular-expression captures

Move point to the `IDs:` line, press `C-M-%`, enter
`([a-z]+)-([0-9]+)`, then enter `\2/\1` as the replacement. Press `.` to
replace the current complete match and exit. Capture `2` supplies the digits,
and capture `1` supplies the word, producing `42/alpha` or `7/beta` according
to the first match found from point.

An active region restricts either query-replacement command to the ordered
range between point and mark. Without an active region, the captured scope is
the complete document.

Press `Control-X`, then `Control-S` to save. Press `Control-X`, then
`Control-C` to exit.

## Follow the programmable form

The visible commands above and Racket composition share the same native
operations. Open `src/command/search.rkt` and locate these three stages:

1. `make-search-pattern`, `make-replacement-template`, and
   `make-search-range` create immutable copied values.
2. `make-search-command` combines those values with a stable semantic command
   name, direction, interaction action, and exact identities.
3. `invoke-search-command!` enters the lower-level copied bridge and decodes a
   copied result; it does not receive a rope, buffer pointer, or transaction.

Run the facade tests and boundary benchmark:

```sh
raco test src/command/search.rkt
make search-command-benchmark
```

The benchmark reports 64 warmups, 512 measured calls, latency percentiles,
callback count, and retained native bytes. A passing run reports 576 callbacks
and zero retained native bytes.

The live Racket policy transformation and explicit per-command overrides are
covered by [Configure Programmable Search Policy](../../how-to/configure-search/index.md).

For the complete state, scope, and resource contracts, see the
[Search and Replacement Reference](../../reference/search-and-replacement/index.md).
Materialized result contracts and bindings are documented in the
[Search Result Navigation Reference](../../reference/search-result-navigation/index.md).
