<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Structural Syntax Contract Reference

The `language` package owns bounded structural traversal and indentation plans
over the exact Tree-sitter tree already retained for one buffer revision. This
contract is the language-side seam for later editor commands. It does not yet
publish point, selection, text, history, keymap, or application behavior.

## Exact Scope

`Structural_Scope` copies the complete identity required to use one retained
tree:

| Field | Meaning |
| --- | --- |
| `buffer_id` | Canonical editor buffer identity |
| `source_revision` | Immutable source revision parsed by the tree |
| `language` | Semantic language identity and generation |
| `provider` | Active provider identity and lifecycle generation |
| `selection_generation` | Exact buffer provider-selection state |
| `parser_generation` | Exact native parser owner |
| `tree_generation` | Exact retained parse tree |

Every query compares this scope with both the retained owner and the supplied
immutable `Buffer_Snapshot`. A stale identity rejects the complete operation.
Revision zero remains a valid initial editor revision; the owned language,
provider, selection, parser, and tree generations are nonzero.

## Operations and Targets

`Structural_Request` carries one `Structural_Operation`, exact scope, point,
and optional ordered region. The language contract recognizes:

| Operation | Language result |
| --- | --- |
| `Forward` | Next named sibling of the resolved node |
| `Backward` | Previous named sibling of the resolved node |
| `Up` | Nearest strict named ancestor |
| `Down` | First named child |
| `Select` | Deepest containing named node or strict ancestor expansion |
| `Indent` | Copied leading-whitespace edit plan |

Traversal considers named grammar nodes only. At a byte boundary, a named node
starting at that boundary wins before ordinary half-open containment. Region
selection resolves the smallest named node containing the complete ordered
range. When the range exactly matches that node, selection expansion returns
its nearest strict named ancestor.

`Structural_Target` copies the exact scope, half-open UTF-8 byte range, bounded
node-kind name, and named depth. No `TSNode`, cursor, pointer, borrowed source,
or foreign allocation leaves the synchronous query.

## Odin Indentation Plans

`tree_sitter_owner_plan_indentation` resolves the current logical line or all
lines intersecting the ordered region. A region ending exactly at a later line
start excludes that final line.

The factory Odin rules derive indentation from named grammar ownership. Blocks,
aggregate type bodies, foreign blocks, and switch cases introduce levels.
Opening and closing brace lines and switch labels remove the corresponding
presentation level. Blank lines remain blank. A line intersecting an error or
missing syntax node is omitted from the plan.

Each `Structural_Indent_Edit` contains only the leading horizontal-whitespace
range, indentation level, and prepared byte count. The plan changes no source;
the future command adapter must publish all admitted edits through one atomic
transaction and undo unit. Call `structural_indentation_plan_close` exactly
once for every successful plan; repeated close calls are safe.

## Selected Limits

`DEFAULT_STRUCTURAL_LIMITS` selects:

| Resource | Limit |
| --- | ---: |
| Named nodes visited per operation | 65,536 |
| Named traversal depth | 1,024 |
| Indentation lines | 16,384 |
| Prepared indentation bytes | 8 MiB |
| Copied node-kind name | 96 bytes |
| Copied diagnostic | 4 KiB |
| Copied inspection result | 1 MiB |

Structural work also inherits the 64 MiB analyzed-source and aggregate
language-analysis ceilings. Queries run synchronously on the owner thread and
retain no additional parse tree, worker, queue, or foreign cursor.

`Structural_Usage` reports visited nodes and depth, indentation lines,
prepared bytes, and copied temporary storage. The reproducible resource study
uses ordinary, demanding, and over-limit profiles and records cancellation,
allocation-fault, and cleanup behavior.

## Failure and Cleanup

Structural failures use the existing copied `Failure` record with
`Query_Structure` or `Plan_Indentation` ownership. Stable rejections include
unavailable capability, stale scope, missing target, invalid UTF-8 boundary,
syntax-error containment, node-kind, node, depth, line, prepared-text,
cancellation, allocation, and source-snapshot failures.

A rejection returns no applicable target or plan and changes no canonical
editor or analysis state. Cancellation uses the existing owner cancellation
state. Allocation failure releases partial plan storage before return. Owner
teardown remains responsible for the retained parser, tree, query, and cursor.

## Validation Commands

Run the focused gates from the repository root:

```sh
make structural-syntax-reference-test
make structural-syntax-equivalence-test
make structural-syntax-resource-study
odin test src/language -vet -warnings-as-errors \
  -define:ODRA_TREE_SITTER_LIBRARY="../../.build/syntax-vendor/libtree-sitter-odin.a"
```

The reference package is an independent pointer-free traversal and
indentation oracle. The equivalence test compares generated factory Odin
selection results with that oracle. Production coverage includes traversal,
expansion, indentation, stale generations, UTF-8 boundaries, incomplete
syntax, node and line limits, cancellation, allocation failure, accounting,
and cleanup.

The command adapter described by the
[Structural Editor Operations Reference](../structural-editor-operations/)
publishes these copied results through canonical editor movement, selection,
and transaction ownership. This language contract intentionally defines no
named command, binding, Racket procedure, list UI, or redraw path.

See the [Tree-sitter Odin Analysis Reference](../tree-sitter-odin-analysis/)
for parser ownership and the
[Structured Syntax MVP specification](../../../ops/default/spec/stable/structured-syntax-mvp.md)
for the complete four-slice behavior.
