<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Structural Syntax Reference

Jan Document Language Slice 2 introduced the complete structural family for
the accepted `jan-org-9.8.10-v1` baseline. Slice 3 retains that projection while
adding inline children and semantic indexes. The parser remains internal to
`src/language`; `.org` and `.jan` application selection is deferred to Slice 5.

## Concrete Tree Taxonomy

The generated Tree-sitter Jan grammar publishes these named structural nodes:

| Group | Named nodes |
| --- | --- |
| Root and outline | `document`, `zeroth_section`, `heading`, `heading_line`, `section` |
| Greater elements | `center_block`, `quote_block`, `special_block`, `drawer`, `property_drawer`, `dynamic_block`, `footnote_definition`, `inline_task`, `list_item`, `plain_list`, `pipe_table`, `table_provider_form` |
| Lesser blocks | `source_block`, `example_block`, `export_block`, `comment_block`, `lesser_block` |
| Lines and paragraphs | `clock`, `diary_expression`, `planning_line`, `line_comment`, `fixed_width_area`, `horizontal_rule`, `keyword`, `affiliated_keyword`, `latex_environment`, `node_property`, `paragraph` |
| Table contents | `table_row`, `table_separator_row`, with inline `table_cell` children |
| Preservation and recovery | `blank_line`, `line_ending`, `recovery`, and Tree-sitter error or missing nodes |

Block and keyword markers are matched with the baseline's case rules while
their original bytes remain unchanged. Source, example, export, comment, and
other lesser-block bodies remain verbatim at this layer.

## External Scanner

`src/scanner.c` owns three external boundary tokens. `line_ending` preserves
`LF`, `CRLF`, or `CR` exactly. `blank_line` recognizes a line containing only
horizontal whitespace and its terminator. The zero-width end-of-file token
allows a final inline line without a terminator to retain its exact range. The
scanner is stateless, serializes no payload, and has no allocation or cleanup
responsibility.

## Odin Structural Owner

`Jan_Structural_Owner` owns one ABI 15 parser, the latest concrete tree, and
its foreign allocation account. `jan_structural_owner_analyze` accepts one
exact `Jan_Analysis_Scope`, canonical UTF-8 bytes, and `Jan_Resource_Limits`.
It rejects a mismatched parser generation, invalid scope, malformed UTF-8,
source or work overflow, cancellation, allocation failure, or invalid parser
range before returning analysis.

`Jan_Structural_Analysis` owns copied, pointer-free records. Its accessors
return borrowed slices of:

1. `Jan_Node_Record` structural, inline, preserved-whitespace, and recovery nodes;
2. `Jan_Attribute_Record` heading levels and markers plus keyword and property
   keys and values;
3. `Jan_Recovery_Record` malformed or unterminated regions;
4. `Jan_Index_Fact` revision-bound semantic source facts; and
5. `Jan_Resource_Usage` for source, nodes, attributes, indexes, diagnostics, retained
   bytes, temporary traversal storage, depth, and logical work.

`jan_structural_analysis_close` releases copied analysis records.
`jan_structural_owner_close` releases the tree and parser, closes the
Tree-sitter memory owner, and asserts that no foreign allocation remains.

## Outline Projection

The concrete grammar recognizes heading lines without assigning product
semantics to a fixed maximum heading level. Odin counts the exact left-margin
star marker and projects headings into a forest:

1. the nearest preceding heading with a lower level becomes the parent;
2. a same-level or shallower heading closes the preceding subtree;
3. the final open subtree extends to the canonical source end; and
4. a level above the selected structural-depth limit rejects the candidate.

The zeroth section remains a child of the document root. Each heading's section
owns content before the next heading token. This keeps dynamic outline depth
out of generated parser tables while retaining exact source ranges.

## Context Rules

Structural admission is context-sensitive:

1. headings begin at the left margin;
2. planning lines and indented inline tasks are admitted only in a heading
   section;
3. node properties occur only inside a property drawer;
4. list items occur only inside a plain list;
5. table rows occur only inside a pipe table; and
6. begin and end delimiters preserve spelling and delimit a single owned
   structural range.

A near match outside its admitted context remains ordinary paragraph text. It
does not acquire planning, property, list, or table semantics from its spelling
alone.

## Source Ownership and Recovery

The document root covers `[0, source_bytes)`. Every projected range is
half-open, contained by its concrete parent, and aligned to canonical UTF-8
boundaries. Line terminators and blank lines have explicit
`Preserved_Whitespace` ownership. Heading, keyword, and property attributes
retain their raw lexical ranges and copied bounded values.

Malformed delimiter text is never discarded. Explicit `recovery` nodes become
`Jan_Node_Kind.Recovery`; missing block, drawer, or environment terminators add
an `Unterminated` recovery record to the owning structural node. Recovery does
not prevent ordinary text editing and does not authorize normalization.

## Inline Extension Boundary

Slice 3 divides admitted rich fields into typed inline objects, applies the
confirmed configuration generation in Odin, and derives semantic source-fact
indexes without introducing a second document parser. See the
[Jan Inline Syntax and Index Reference](../jan-inline-syntax-and-indexes/index.md)
for the complete taxonomy and configuration contract. Application language
selection, incremental publication, and operational later-stage semantics
remain outside this structural reference.

## Focused Validation

Run:

```sh
make jan-document-language-focused-test
```

The target verifies parser provenance and ABI, runs the compiled parser probe,
checks the 34-family structural and 38-family inline corpora, checks resource
profiles and contract parity, performs strict package checking, and runs
ownership, nesting, context, recovery, limit, cancellation, allocation-fault,
accounting, and cleanup tests.
