<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Search and Replacement Reference

This reference defines the delivered incremental literal and
regular-expression search behavior, progressive query replacement, non-query
atomic replacement, and copied programmable Racket facade.

## Commands and bindings

| Command | Direct binding | Behavior |
| --- | --- | --- |
| `isearch-forward` | `C-s` | Start forward literal search or repeat in the forward direction. |
| `isearch-backward` | `C-r` | Start backward literal search or repeat in the backward direction. |
| `isearch-forward-regexp` | `C-M-s` | Start forward regular-expression search or repeat in the forward direction. |
| `isearch-backward-regexp` | `C-M-r` | Start backward regular-expression search or repeat in the backward direction. |
| `query-replace` | `M-%` | Prompt for literal pattern and replacement text, then confirm occurrences progressively. |
| `query-replace-regexp` | `C-M-%` | Prompt for a regular expression and replacement template, then confirm occurrences progressively. |
| `replace-string` | None | Replace every admitted non-overlapping literal occurrence in one atomic operation. |
| `replace-regexp` | None | Expand and replace every admitted non-overlapping regular-expression occurrence in one atomic operation. |
| `keyboard-quit` | `C-g` | Recover the last successful query after a failed suffix; otherwise abort and restore origin. |

`RET` accepts the active search and keeps point at the selected match edge.
Backspace removes one complete UTF-8 scalar from the query. Text commits append
to the query and do not enter the buffer while search is active.

While search owns input, these contextual bindings are active:

| Binding | Behavior |
| --- | --- |
| `M-p`, `M-n` | Recall older or newer compatible queries; moving past the newest entry restores the live input. |
| `TAB` | Complete from the newest compatible history entry that begins with the current query. |
| `C-w` | Append the next nearby textual unit. |
| `C-M-y` | Append the next nearby structural unit. |
| `C-y` | Append the newest compatible text-transfer entry. |
| `M-s c` | Toggle case sensitivity. |
| `M-s r` | Toggle literal and regular-expression interpretation. |
| `M-s w`, `M-s _` | Toggle word or symbol boundaries; the two modes are mutually exclusive. |
| `M-s SPC` | Toggle exact and flexible whitespace. |
| `M-s o` | Materialize current matches in the common result surface. |

Materialized rows place the source path when applicable, then `line:column`,
then a bounded source-line preview. The exact matched byte range carries the
theme's current-search style.

Repeating the active search command with an empty query reuses the newest
compatible accepted query. Accepted queries enter bounded session history;
cancelled incomplete input does not. History is released with the editor
session and is not persisted across process restarts.

The bindings are declared by the Racket factory keymap and copied into the
checked native command registry. The terminal decoder only normalizes physical
input, including the escape-prefixed control bytes used for `C-M-s` and
`C-M-r`. The conventional `0x1d` terminal encoding for `C-%` is normalized so
`C-M-%` remains an ordinary programmable keymap entry. The decoder contains no
search-specific command decision.

The related `M-s` namespace remains unassigned to unrelated factory behavior.
`search-reserved-bindings` exposes reservations for symbol, word, occurrence,
and highlight commands so later keymaps can extend the namespace without
silently colliding with the factory profile.

## Programmable facade

`src/command/search.rkt` is the cohesive public Racket surface.
`src/command/search-bridge.rkt` owns the lower-level fixed-record transport and
is not a second semantic search API.

| Procedure | Contract |
| --- | --- |
| `call-with-search` | Grants one opaque search context for a synchronous dynamic extent. |
| `inspect-search-scope` | Returns copied editor, authority, view, buffer, revision, command-registry, interaction, and policy identity. |
| `inspect-search-policy` | Returns the complete copied native policy. |
| `inspect-search-state` | Returns bounded copied session text, current and nearby occurrences, captures, progress, and resource usage. |
| `make-search-pattern` | Copies a valid UTF-8 literal or regular-expression value. |
| `make-replacement-template` | Copies a valid UTF-8 replacement value. |
| `make-search-range` | Creates one half-open revisioned byte scope. |
| `make-search-command` | Composes one admitted named semantic invocation from copied values. |
| `invoke-search-command!` | Invokes the native command and returns a copied result or structured failure. |
| `search-policy-inspect`, `search-policy-replace` | Inspect or derive one complete immutable policy value. |
| `reload-search-policy!`, `reset-search-policy!` | Replace or restore the live Racket policy transformation for later programmable turns. |
| `search-factory-bindings`, `search-reserved-bindings` | Return active factory bindings and unassigned related namespace reservations. |

The admitted semantic names are `isearch-forward`, `isearch-backward`,
`isearch-forward-regexp`, `isearch-backward-regexp`, `query-replace`,
`query-replace-regexp`, `replace-string`, and `replace-regexp`. A successful
invocation returns refreshed scope identity. It never returns a native pointer,
rope node, regex object, borrowed occurrence array, or transaction owner.

The Racket bridge uses fixed little-endian records: 96-byte scope, 248-byte
policy, 568-byte session header, 48-byte occurrence, 24-byte capture, 264-byte
command header, and 256-byte command result. One inspection copies at most 256
occurrences, 2,816 captures, and 192 KiB of session text. Pattern and
replacement request values are each limited to 64 KiB and command names to 96
UTF-8 bytes.

The policy transformation applies when a programmable command does not carry
an explicit policy. Both forms preserve the native policy generation and pass
the complete behavior and resource profile back to Odin for validation. The
factory terminal interaction still uses the native factory defaults directly.
See [Configure Programmable Search Policy](../../how-to/configure-search/index.md).

## Scope and point

Starting search captures one buffer identity, revision, view origin, viewport,
direction, and scope. An active non-empty or empty region supplies the ordered
half-open scope between point and mark. Without an active region, the scope is
the complete active buffer.

Forward matches leave point at the occurrence end. Backward matches leave
point at the occurrence start. Repeating in either direction starts beyond the
current match in that direction. Reversing direction reuses the same session
and scope.

Accepting releases transient search state and retains point. Aborting restores
the captured point, viewport origin, and horizontal display column exactly.
A committed external buffer change invalidates occurrences from the older
revision and releases the session.

## Literal and case behavior

Patterns are raw, nonempty, well-formed UTF-8 text. No delimiter or escape
syntax is interpreted for literal search. Matching operates on immutable rope
snapshots and admits occurrences that cross rope leaves or scan windows.

Factory policy uses Unicode-aware smart case:

- a query containing an uppercase Unicode code point is case-sensitive;
- a query without uppercase code points is case-insensitive through Unicode
  case folding.

The prompt reports `smart/sensitive` or `smart/insensitive` after a query is
admitted. It also reports the active boundary and whitespace modes.

Boundary policy is `unrestricted`, `word`, or `symbol`. Word and symbol modes
require both match edges to align with the corresponding Unicode-aware generic
boundary rules.

Whitespace policy is `exact` or `flexible`. Flexible whitespace replaces each
nonempty query whitespace run with a match for one or more whitespace scalars;
it never matches an empty sequence or crosses the captured scope.

## Regular-expression dialect

Regular-expression queries use Odin `core:text/regex` through an Odra-owned
bounded adapter. Patterns are raw UTF-8 expressions: they have no surrounding
delimiter and do not accept embedded flag suffixes.

| Syntax | Meaning |
| --- | --- |
| `a|b` | Alternation. |
| `[0-9_]`, `[^0-9_]` | Character class and negated character class. |
| `\d`, `\s`, `\w` | ASCII digit, whitespace, and word shorthands. |
| `\D`, `\S`, `\W` | Negated ASCII shorthands. |
| `.` | One scalar wildcard. |
| `a*`, `a+`, `a?` | Zero-or-more, one-or-more, and optional repetition. |
| `a{N}`, `a{N,M}`, `a{N,}`, `a{,M}` | Exact and bounded repetition. |
| `(...)`, `(?:...)` | Capturing and noncapturing groups. |
| `^`, `$` | Start and end anchors under multiline mode. |
| `\b`, `\B` | ASCII word boundary and non-word boundary. |
| `*?`, `+?`, `??`, `{...}?` | Non-greedy repetition variants. |

Unicode and multiline modes are always enabled. Smart case selects the
case-insensitive flag unless the pattern contains an uppercase Unicode code
point. Explicit engine policy can force sensitive or insensitive matching.
The shorthand classes remain ASCII-based in Unicode mode:
`\d` is `[0-9]`, `\s` is `[\t\n\f\r ]`, and `\w` is `[0-9A-Z_a-z]`.

In the current standard-library dialect, a multiline `$` match consumes the
terminating newline when one is present. The complete occurrence therefore
includes that newline.

Capture group `0` is the complete match. Participating groups retain their
declared number; an absent optional group is omitted and does not renumber a
later group. The current build admits ten capture groups. Expressions must
compile to fewer than 32,767 program bytes and fewer than 255 distinct rune
classes.

## Replacement templates

Literal replacement treats the complete admitted template as exact text.
Backslashes and capture-looking text have no special meaning in a literal
template.

Regular-expression replacement recognizes only the following escapes:

| Syntax | Expansion |
| --- | --- |
| `\&` | The complete occurrence. |
| `\N` | Declared capture group `N`, from `1` through the admitted capture limit. |
| `\\` | One literal backslash. |

An optional group declared by the expression but absent from one occurrence
expands to empty text. Group `0`, an undefined group, a trailing backslash, an
unknown escape, malformed UTF-8, arithmetic overflow, and an expansion beyond
the admitted limits reject the operation before publication.

Factory replacement policy uses smart case only when matching is effectively
case-insensitive and the replacement template contains no uppercase Unicode
literal. An all-uppercase occurrence makes the expansion uppercase; a
capitalized occurrence capitalizes it; other shapes preserve the expansion.
An explicit uppercase literal in the template suppresses adaptation. Policy
can also disable adaptation and preserve the expansion exactly.

## Query replacement

`query-replace` and `query-replace-regexp` first collect two bounded values:
the pattern and replacement template. The literal command interprets both as
literal text. The regular-expression command uses the documented expression
dialect and capture-template syntax. An invalid expression returns to pattern
entry with its diagnostic and byte offset; it does not create a live session.

Starting the command captures the current buffer identity, revision,
direction, point, and active-region scope. Without an active region, the scope
is the complete buffer. The view owns the live session and exposes its current
occurrence for display. The shared UI text projection copies the current
revision-checked occurrence and search status into the `Text_View`; the
terminal lowers the current occurrence through the semantic
`Text_Search_Current` role. The UI registry and terminal own neither canonical
occurrence ranges nor replacement state.

While a current occurrence is awaiting a response, these inputs are active:

| Input | Response |
| --- | --- |
| `y` or `SPC` | Replace the current occurrence and continue. |
| `n` or `DEL` | Skip the current occurrence and continue without changing text or history. |
| `!` | Replace every remaining admitted occurrence atomically and finish. |
| `.` | Replace the current occurrence and finish. |
| `q` or `RET` | Finish without changing the current occurrence. |
| `C-g` | Cancel the interaction without reversing confirmed replacements. |

The root-edge status reports the effective case mode, confirmed replacement
count, skip count, and response help. A checked `Input` projects
`pattern -> replacement` plus five named response actions. The current
occurrence is projected through the same revision-checked display path used by
incremental search. Wrapped and bounded-incomplete scans publish explicit
states and continue on a later response turn; they are not treated as absence.

Each `y`, `SPC`, or `.` confirmation publishes one valid native transaction.
Skipping publishes nothing. Quitting or canceling releases the session and
retains every transaction already confirmed. All confirmed publications from
one uninterrupted session share one query-replacement history group, so one
undo reverses the complete session when history policy admits it.

`!` delegates the remaining captured scope to atomic replacement. Every
remaining occurrence is analyzed against one immutable revision and the batch
publishes completely or not at all. Confirmations made before `!` remain
separate buffer revisions inside the same semantic undo group. If the atomic
remaining batch fails, those earlier confirmations remain valid.

After a confirmed replacement, the scope end is adjusted by the exact inserted
and removed byte counts before scanning continues. A zero-width expression
advances by one Unicode scalar boundary and cannot repeat indefinitely at one
position. A committed edit outside the workflow invalidates the current
occurrence. Complete-document scope may be recomputed against the observed
revision; a changed partial scope is rejected rather than displaced by guess.

## Atomic replacement

`replace-string` and `replace-regexp` capture the active region when one is
active and otherwise capture the complete buffer. They disable wrapping and
enumerate forward from the captured scope start. Literal occurrences that
overlap are reduced to the leftmost non-overlapping sequence. Zero-width
regular-expression matches advance on Unicode scalar boundaries and do not
repeat at one byte offset.

Every occurrence and replacement expansion is prepared against one immutable
buffer revision. The command then revalidates that revision, constructs one
base-relative transaction, prepares one logical-view update, reserves one
independent history unit, and publishes the complete normalized changeset.
Earlier replacements cannot affect the interpretation of later matches.

A successful nonempty batch advances the buffer revision once, deactivates the
region, maps point through the complete batch, and is undone or redone as one
unit. Point has left affinity at a zero-width insertion. A no-match result is a
successful no-op and creates neither a revision nor a history node.

## Interaction states

| Prompt state | Meaning |
| --- | --- |
| `Search →` | The query is empty or the current literal query has a selected forward match. |
| `Search ←` | The same active literal-search state with backward direction. |
| `Regexp →` | A selected forward regular-expression match or an empty regexp prompt. |
| `Regexp ←` | The same regexp state with backward direction. |
| `Failing Search` | The complete admitted traversal found no literal match; the last successful match remains selected. |
| `Failing Regexp` | The expression is valid but the complete admitted traversal found no match. |
| `Regexp (<diagnostic> at <byte>)` | The current expression is invalid; the last successful state remains selected. |
| `Wrapped Search` | The next bounded literal-search turn continues from the opposite scope boundary. |
| `Wrapped Regexp` | The same wrapped state for an expression query. |
| `Pending Search` | The literal scan window ended before the admitted traversal completed. |
| `Pending Regexp` | The same incomplete state for an expression query. |
| `Query replace` | A literal or expression occurrence is awaiting one response. |
| `Wrapped query replace` | The next bounded turn resumes from the opposite scope boundary. |
| `Pending query replace` | More admitted scan work remains before a response can be applied. |
| `Stale query replace` | The source revision changed and checked recomputation is required. |

Regexp diagnostics report the error class and pattern byte offset. `C-g` in a
failing or invalid-pattern state restores the copied last successful query and
match without rescanning. `C-g` in another state aborts the session. If no
query has ever matched, a failing-state `C-g` aborts directly.

## Display behavior

`view.Search_Snapshot` exposes revisioned current and nearby occurrences.
`display.Search_Match_Map` maps their canonical bounds through current
scrolling, horizontal clipping, and terminal geometry. The terminal renderer
shows the current visible occurrence through `Text_Search_Current` and never
reconstructs an occurrence from cells. The incremental-search query is a
checked `Input`; direction, case, active, failing, wrapped, pending, and regexp
diagnostic text are copied into a root-edge `StatusRegion`. Search styling
overrides active-region styling only on their overlapping cells.

## Initial resource policy

| Resource | Factory value | Validated range |
| --- | --- | --- |
| Search history entries | 64 per editor session | Fixed bounded capacity |
| Search history query bytes | 256 KiB per editor session | Fixed aggregate capacity |
| Pattern bytes | 4 KiB | 1 byte to 64 KiB |
| Logical bytes per scan turn | 64 KiB | 64 KiB to 16 MiB |
| Bytes between cancellation checkpoints | 256 KiB | 64 KiB to 4 MiB |
| Retained nearby occurrences | 256 | 64 to 65,536 |
| Temporary search storage | 16 MiB | 4 MiB to 1 GiB |
| Regular-expression match span | 64 KiB | 4 KiB to 16 MiB |
| Regular-expression captures | 10 | 10 in the current build |
| Replacement-template bytes | 4 KiB | 0 bytes to 64 KiB |
| Expanded bytes per occurrence | 16 MiB | 4 KiB to 256 MiB |
| Replacement scratch per occurrence | 16 MiB | 4 KiB to 512 MiB |
| Atomic replacement matches | 100,000 | 1 to 100,000 |
| Atomic removed plus expanded bytes | 256 MiB | 64 KiB to 1 GiB |
| Atomic replacement temporary storage | 512 MiB | 64 MiB to 512 MiB |
| Atomic replacement analysis bytes | 2 GiB | 64 KiB to 2 GiB |

One engine call scans at most one logical window and returns copied
occurrences, `Incomplete` progress, `No_Match`, or `Cancelled`. Physical rope
reads may include the bounded pattern overlap required to detect a match across
the window edge. Usage reports logical bytes, physical reads, turns,
cancellation checks, retained records, and temporary peak bytes.

The regular-expression adapter copies only one bounded contiguous rope window
for the standard-library matcher. With factory limits, one 64 KiB logical turn
reads at most 128 KiB plus boundary context so a match may cross a rope leaf,
line, or scan edge. The complete buffer is never permanently flattened.
Zero-width matches are admitted and then advance by one Unicode scalar
boundary; the end of a scope produces at most one final empty match.

## Failures and cleanup

Search rejects empty patterns, malformed expressions, compiler program or
class overflow, invalid directions and policies, wrong buffers, stale
revisions, invalid UTF-8 boundaries, out-of-scope origins, match-span and other
resource-limit violations, and allocator failure before replacing visible
session state. Canonical buffer text and history never change during search.

Atomic replacement also rejects a malformed template, invalid capture
reference, overlapping or otherwise invalid transaction batch, stale source
revision, cancellation, match or text ceiling, temporary-memory or analysis
ceiling, allocator failure, and history admission failure. These failures
publish none of the candidate replacements. Cancellation remains effective
through private analysis and transaction validation; the final transaction
publication itself is brief and non-cancelable.

Query replacement applies the same pattern, template, scope, expansion,
transaction, and history limits on every turn. A failure before publication
preserves canonical text. A failure while continuing after an already
committed confirmation ends the session and reports the contained failure; it
does not roll back the confirmed edit. Stale response ranges are never applied
directly.

Queries and results own copied storage until `query_close` and `result_close`.
The view consumes those owners only after a checked session publication.
Acceptance, abortion, query completion, cancellation, stale invalidation, view
closure, and buffer teardown release all transient resources deterministically.

Use `odin doc src/search -in-source-order`,
`odin doc src/view -in-source-order`, and
`odin doc src/command -in-source-order` for generated declaration reference.
