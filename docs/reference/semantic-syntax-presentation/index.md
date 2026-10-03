<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Semantic Syntax Presentation Reference

Odra presents syntax through the shared `language -> ui -> terminal` pipeline.
Language providers publish semantic byte ranges. The UI projects one complete
exact-revision range set as generic `Text_Range` decorations. The terminal
lowers the resulting generic UI snapshot for one explicit color capability.
No language provider owns colors, ANSI sequences, display cells, or canonical
text.

Application-level Odin selection and analysis scheduling use the factory syntax
workflow. Opening a file-backed path whose suffix is exactly `.odin`
automatically activates the maintained provider; unsupported documents remain
plain text.

## Ownership and Data Flow

```text
Syntax_Snapshot + Syntax_Span[]
             |
             v
exact TextView projection -> Style + Text_Range Decoration
             |
             v
immutable generic UI snapshot
             |
             v
terminal color-capability lowering -> bounded ANSI frame
```

`language` owns semantic analysis identities, normalized spans, provider
generations, and source revisions. `ui` owns copied style and decoration
records in one atomic root generation. `display` owns grapheme, tab, clipping,
and source-to-row boundary maps. `terminal` owns physical style state and ANSI
output. None of these presentation records can mutate an editor buffer or
view.

## Semantic Roles

The UI vocabulary maps every stable language role one-to-one:

| Language role | UI role | Startup foreground | Attributes |
| --- | --- | --- | --- |
| `Attribute` | `Syntax_Attribute` | `#BFBB40` | none |
| `Boolean` | `Syntax_Boolean` | `#BFBB40` | none |
| `Comment` | `Syntax_Comment` | `#848587` | dim |
| `Constant` | `Syntax_Constant` | `#51B6F5` | none |
| `Constructor` | `Syntax_Constructor` | `#5981E3` | none |
| `Function` | `Syntax_Function` | `#5981E3` | none |
| `Function_Builtin` | `Syntax_Function_Builtin` | `#51B6F5` | none |
| `Keyword` | `Syntax_Keyword` | `#78A0FA` | bold |
| `Label` | `Syntax_Label` | `#B47745` | none |
| `Number` | `Syntax_Number` | `#BFBB40` | none |
| `Operator` | `Syntax_Operator` | `#D6D6B3` | none |
| `Punctuation` | `Syntax_Punctuation` | `#848587` | none |
| `String` | `Syntax_String` | `#B2A44B` | none |
| `Type` | `Syntax_Type` | `#51B6F5` | none |
| `Variable` | `Syntax_Variable` | `#D6D6B3` | none |
| `Variable_Parameter` | `Syntax_Variable_Parameter` | `#B47745` | none |

The startup mapping comes from the session-selected `Wrocław Night`
definition, whose background is `#1A1B26`. The native
[Theme System](../theme-system/index.md) owns the complete 27-role definition
and resolves it into every application UI proposal. Semantic role identities
remain stable when selection changes and when multiple roles share
presentation.

## Style Contract

`Style_Definition` and `Style_Descriptor` contain:

- one unique semantic `Style_Role`;
- an optional eight-bit sRGB foreground;
- an optional eight-bit sRGB background; and
- any combination of bold, dim, underline, and reverse attributes.

An absent color means inherit the frontend default. Absence has one canonical
zero representation; a nonzero color with `present = false` is invalid. A
proposal rejects invalid roles, duplicate role definitions, invalid optional
colors, style exhaustion, or object-generation exhaustion before publication.
Style accounting is the exact retained `Style_Descriptor` byte count.

## Decoration Projection

`proposal_project_syntax_decorations` accepts one UI `TextView`, one
`Syntax_Snapshot`, one complete span slice, and one nonzero owner. It requires:

- exact buffer identity and source revision agreement with the `TextView`;
- nonzero snapshot, language, provider, selection, parser, and query
  generations;
- exact snapshot span count and retained-span accounting;
- the same provider and source revision on every span;
- non-empty in-bounds half-open byte ranges;
- sorted, non-overlapping spans; and
- a defined UI style for every mapped syntax role.

Each admitted span becomes a generic `Decoration_Descriptor` with kind
`Text_Range`, owner, projection, source revision, byte range, style role, and
precedence. Individual text-range insertion also enforces ordering against the
prior range on that projection. The generic registry snapshot copies these
records without a syntax-specific snapshot or renderer entry point.

Capacity, validation, stale-revision, style, or object-generation failure
leaves the proposal's prior decoration count, bytes, and next object identity
unchanged. The affected view therefore remains ordinary text instead of
receiving a partial syntax set.

## Color Capabilities and Lowering

`Renderer_Color_Capability` has four profiles:

| Capability | Lowering |
| --- | --- |
| `True_Color` | ANSI `38;2;r;g;b` and `48;2;r;g;b` sequences. |
| `Indexed_256` | Nearest fixed xterm color-cube or grayscale entry in indexes 16 through 255. |
| `Basic_16` | Nearest fixed standard or bright ANSI color in indexes 0 through 15. |
| `Monochrome` | Colors are omitted; abstract attributes remain active. |

Nearest-color selection uses squared sRGB distance and keeps the lower palette
index on a tie. Indexed lowering avoids terminal-configurable indexes 0 through
15. The 16-color profile uses the fixed standard RGB reference palette and
then emits standard `30-37`, `40-47`, `90-97`, or `100-107` codes.

The application selects a terminal capability from process hints in this
order:

1. a present `NO_COLOR` or `TERM=dumb` selects monochrome;
2. `COLORTERM=truecolor`, `COLORTERM=24bit`, or a true-color/direct `TERM`
   selects true color;
3. a `TERM` containing `256color` selects indexed color;
4. any other non-empty `TERM` selects 16 colors; and
5. no hint selects monochrome.

Renderer configuration still carries the selected capability explicitly. The
same value appears in the immutable UI renderer profile and participates in
snapshot compatibility.

## Rendering and Precedence

The terminal resolves presentation in this order:

1. current search match;
2. active region;
3. syntax decoration; and
4. `Text_Normal`.

Each higher layer supplies the complete effective style over its range. The
renderer clips source ranges through the display snapshot's grapheme boundary
map, then writes only complete projected clusters. Syntax therefore preserves
UTF-8, combining sequences, wide graphemes, tab expansion, horizontal and
vertical clipping, multiple views, cursor placement, and resize compatibility.
A decoration endpoint that cannot be mapped to an admitted visible boundary
rejects the candidate presentation before physical output.

The frame retains one physical style state. Repeating the same lowered style
emits nothing. Transitions disable only fields that must be removed, enable
only newly required fields, and change only differing foreground or background
colors. Every rendered row returns to default attributes and colors, and the
frame confirms the default state before restoring the cursor.

## Limits, Failures, and Cleanup

One UI generation admits at most 64 styles and 65,536 decorations. Decoration
and style bytes participate in exact registry and snapshot accounting; the
generic snapshot remains bounded at 8 MiB. Terminal output remains bounded at
2 MiB and uses a conservative 96-byte-per-cell estimate that covers complete
attribute and true-color entry and reset sequences.

Invalid or stale UI state, missing styles, mismatched text projections,
incompatible geometry, unmappable boundaries, output limits, allocation
failure, write failure, and flush failure return contained failures. Candidate
frames are never written partially by validation or allocation failure.
Snapshot, frame, renderer, display, and registry owners retain their existing
exact close operations.

## Validation

Use the focused gates while changing this contract:

```sh
odin test src/ui -vet -warnings-as-errors
make terminal-test
make ui-reference-test ui-equivalence-test
make terminal-presentation-test
make terminal-benchmark
```

The generated terminal matrix covers Unicode, tabs, clipping, multiple
geometries, all four color profiles, stale projections, multiple views,
resize, output bounds, allocation faults, accounting, and cleanup.
The syntax PTY scenario adds real Odin captures, incremental editing, undo,
redo, save, search and region precedence, viewport movement, shared views,
inspection, unsupported text, resize, and orderly terminal restoration.
