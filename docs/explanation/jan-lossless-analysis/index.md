<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Jan Separates Concrete Parsing from Document Meaning

Jan must preserve existing `.org` documents exactly while also making their
structure useful to later editing, planning, computation, and publishing
features. A parser tree alone cannot own that complete contract, and a semantic
model alone cannot safely recover the original source.

## Concrete parsing owns boundaries

Tree-sitter recognizes concrete source boundaries and can update its retained
tree from normalized editor edits. It is suited to line-oriented nesting,
incomplete input, and incremental replacement.

The generated parser does not become canonical document state. Its nodes are
foreign values with parser-owned lifetimes, and its error recovery describes a
concrete parse rather than Jan product semantics.

## Odin owns meaning and publication

The Odin Jan owner validates every candidate before it becomes observable. It
checks canonical UTF-8 ranges, complete byte ownership, containment,
configuration generation, baseline generation, resource accounting, and
deterministic recovery. It then copies typed nodes, attributes, indexes, and
diagnostics into pointer-free records.

This keeps product vocabulary independent of generated parser table layout.
Grammar changes can improve concrete recognition without silently changing the
meaning, availability, or identity of published Jan records.

## Losslessness needs both views

The concrete tree retains exact boundaries, spelling, delimiters, whitespace,
line endings, unknown forms, and malformed fragments. The typed analysis says
which ranges form headings, lists, tables, links, timestamps, citations, and
other accepted syntax.

Neither representation is used to serialize an unchanged document. Normal
save publishes canonical editor bytes. A later structured operation must
resolve typed meaning back to exact owned ranges and propose only minimal
splices through the ordinary transaction path.

## Configuration is part of identity

Task keywords, tag rules, property behavior, registered link schemes, entities,
emphasis boundaries, block names, file-local settings, and compatible regular
expressions can affect classification. A result therefore records the exact
configuration generation and digest that shaped it.

Changing configuration invalidates derived analysis just like changing source
or grammar. A stale tree may remain available for bounded inspection, but it
cannot authorize a command against the current document.

## Future behavior remains visible

Stage 1 recognizes source used by later Jan stages without executing it. A
formula, code block, external link, agenda field, bibliography declaration, or
export setting remains typed and preserved while its operational capability is
reported as unavailable.

This separation prevents feature-specific parsers from reinterpreting the same
bytes later. Structured editing, planning, computable documents, and publishing
must consume the shared Stage 1 analysis or explicitly amend its stable
contract.

## JavaScript does not enter the editor

Tree-sitter grammar authorship uses its `grammar.js` DSL to generate C parse
tables. The generated C is committed, checksummed, compiled offline, and linked
to the vendored C runtime. JavaScript, Node.js, npm, and the generator are not
runtime dependencies and do not run when Odra opens or edits a document.

The narrow generator boundary avoids hand-maintaining parser tables without
moving Jan semantics, authority, or document ownership out of Odin.
