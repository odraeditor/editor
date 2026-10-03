<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Inline Syntax and Index Reference

Jan Document Language Slice 3 classifies the complete inline family for the
`jan-org-9.8.10-v1` baseline and derives bounded semantic source-fact indexes.
The analysis remains internal to `src/language`; `.org` and `.jan` buffer
selection is introduced only by Slice 5.

## Inline Node Taxonomy

The copied `Jan_Node_Record` vocabulary maps the concrete parser into these
inline groups:

| Group | Jan node kinds |
| --- | --- |
| Rich fragments | `Entity`, `Special_Symbol`, `Latex_Fragment`, `Export_Snippet` |
| Notes and citations | `Named_Footnote_Reference`, `Inline_Footnote_Reference`, `Anonymous_Footnote_Reference`, `Citation`, `Citation_Reference` |
| Embedded forms | `Inline_Call`, `Inline_Source`, `Explicit_Line_Break` |
| Links and targets | `Radio_Link`, `Plain_Link`, `Angle_Link`, `Regular_Link`, `Target`, `Radio_Target` |
| Expansion and statistics | `Macro`, `Percentage_Cookie`, `Fraction_Cookie` |
| Scripts and tables | `Subscript`, `Superscript`, `Table_Cell` |
| Time | `Active_Timestamp`, `Inactive_Timestamp`, `Diary_Timestamp`, `Point_Timestamp`, `Timestamp_Range`, `Repeating_Timestamp`, `Delayed_Timestamp` |
| Markup | `Bold_Markup`, `Italic_Markup`, `Underline_Markup`, `Verbatim_Markup`, `Code_Markup`, `Strike_Through_Markup` |
| Fallback | `Plain_Text` |

Every node has an exact half-open UTF-8 source range, structural and inline
depth, parent identity, bounded public label, attribute count, and the complete
analysis scope. Missing inline terminators add a recovery record without
discarding the recognized node or any source bytes.

## Context and Precedence

The grammar admits context-free delimiter shapes. Odin applies the confirmed
context and configuration before publishing copied records:

1. ordinary paragraphs use the standard object set;
2. table cells are distinct inline owners inside pipe-table rows;
3. citation references remain children of their citation;
4. active and inactive points remain children of `Point_Timestamp` where the
   concrete form is not a range, repeater, delay, or diary form;
5. timestamp ranges, repeaters, delays, radio targets, and regular links take
   precedence over their shorter delimiter prefixes; and
6. malformed or boundary-invalid content remains source-addressable and may
   produce recovery or lint facts rather than being normalized.

Code and verbatim bodies remain literal. Parsing does not recursively enable
the complete object set inside every delimited form.

## Confirmed Configuration

`Jan_Configuration` is fixed-capacity and copied. `jan_configuration_confirm`
validates its lists and policies, assigns a nonzero generation, and computes a
32-byte content digest. `jan_structural_owner_analyze_configured` accepts the
configuration only when its full identity equals the identity in
`Jan_Analysis_Scope`.

| Configuration field | Classification effect |
| --- | --- |
| Task keywords | A case-sensitive leading heading word becomes `task-state`; an unknown word remains title text. |
| Tag policy | Terminal heading tags retain source case and report the selected case policy. |
| Property policy | Property keys and values remain copied while case and inheritance policy are explicit attributes. |
| Link schemes | Schemes are matched case-insensitively against the confirmed registered set; no target is resolved. |
| Entities | Entity names report whether the confirmed set recognizes them. |
| Emphasis boundaries | Markup reports whether its outer source boundaries satisfy the selected Org-compatible policy. |
| Block names | Begin forms preserve spelling and report whether their name belongs to the confirmed set. |
| File-local settings | Recognized setting keywords receive a source-local setting attribute without acquiring authority. |
| Regular-expression dialect | Expression-bearing fields report `org-compatible`; they are not reinterpreted as Racket or host-library expressions. |
| Radio links | Plain occurrences become `Radio_Link` only when radio links are enabled and the same analysis contains the declared radio target. |

Changing any policy or configured name requires confirmation and changes the
digest. A consumer must match buffer, document, source revision, language,
provider, selection, parser, grammar, configuration, baseline, and analysis
generations before using a node, attribute, recovery, or index fact.

## Semantic Source-Fact Indexes

`jan_structural_analysis_indexes` returns copied `Jan_Index_Fact` values from
the same accepted tree and scope. The complete Stage 1 index vocabulary is:

| Group | Index kinds |
| --- | --- |
| Outline and planning | `Heading`, `Task_State`, `Priority`, `Tag`, `Planning`, `Clock`, `Timestamp` |
| Metadata | `Property`, `Identifier`, `Name`, `Affiliated_Keyword`, `File_Local_Setting` |
| Addressing | `Target`, `Radio_Target`, `Link`, `Code_Reference` |
| Long-form content | `Footnote`, `Citation`, `Bibliography`, `Table`, `Formula`, `Block`, `Call`, `Result` |
| Analysis health | `Lint_Fact`, `Recovery_Region` |

Each fact contains only its fact identity, kind, owning node identity, and
exact source range. Duplicate facts for the same node and kind are suppressed.
Fact count participates in `Jan_Resource_Usage` and cannot exceed the selected
`index_facts` limit.

## Operational Boundary

Parsing and indexing do not open links, read files, start processes, access the
network, resolve citations, calculate recurrences, execute calls or source
blocks, evaluate formulas, or render exports. Those operations remain owned by
later Jan stages. A recognized fact is source evidence, not an operational
result or permission.

## Focused Validation

Run:

```sh
make jan-document-language-focused-test
```

The target checks parser provenance and ABI, the native parser probe, the
34-family structural corpus, the 38-family inline corpus and evidence matrix,
resource profiles, contract parity, strict Odin compilation, deterministic
normalization, configuration generation checks, all index kinds, bounded
failure, allocation faults, and cleanup.
