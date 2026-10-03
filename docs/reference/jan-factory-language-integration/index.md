<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Jan Factory Language Integration Reference

Odra registers Jan as a distinct built-in document language alongside the
existing factory Odin language. The integration selects one language contract
per buffer, maintains one analysis owner for that buffer, and publishes syntax
through the existing semantic UI path.

## Factory Selection

Factory suffix matching is case-sensitive.

| Input | Selected language | Association source | Association value |
| --- | --- | --- | --- |
| `*.odin` | Odin | `Factory_Filename_Suffix` | `.odin` |
| `*.org` | Jan | `Factory_Filename_Suffix` | `.org` |
| `*.jan` | Jan | `Factory_Filename_Suffix` | `.jan` |
| another suffix with an explicit `jan` request | Jan | `Native_Request` | `jan` |
| another suffix without an explicit request | plain text | none | none |

Uppercase variants such as `.ORG`, `.JAN`, and `.ODIN` do not match factory
policy. An explicit Jan request changes only the selected language
responsibility; it does not rename the document or mutate source bytes.

Both Jan suffixes resolve to the same `jan` language identity, factory
provider, Tree-sitter grammar ABI, `jan-org-9.8.10-v1` baseline, and confirmed
default configuration. Their association value differs only so inspection can
report which suffix caused selection.

## Provider Registries

Odin and Jan have independent factory provider registries. Replacing,
disabling, failing, or restoring a Jan provider invalidates only Jan-derived
state. The Odin provider selection and every current Odin analysis remain
unchanged.

The Jan factory provider advertises initial parsing, incremental parsing,
visible queries, semantic syntax roles, and structural syntax. Stage 1 does not
grant execution, link resolution, export, agenda, or other later-stage effects.

## Buffer-Owned Analysis

One `Syntax_Analysis_Entry` owns the selected Jan parser, confirmed structural
analysis, retained source snapshot, pending commit data, and latest syntax
snapshot for one buffer. Additional views of that buffer reuse the same owner
and exact analysis generation.

Initial maintenance publishes a complete Jan analysis for the current buffer
revision. A committed editor transaction records copied normalized splices and
attempts an incremental update from the confirmed revision. A stale base,
unsupported splice batch, or incremental work-limit rejection schedules a
full refresh instead of applying old derived data to new text.

A confirmed Jan configuration change closes the old owner, clears derived
syntax, advances the buffer selection generation, and schedules a fresh
analysis. Invalid configuration is rejected before any current state changes.

Document removal closes the parser, structural analysis, retained snapshots,
pending splice copies, and syntax spans. Explicit buffer selections are also
removed when their buffer leaves the session.

## Syntax Presentation

Jan structural nodes are mapped to the shared `Syntax_Role` vocabulary.
Representative mappings include:

| Jan syntax | Semantic role |
| --- | --- |
| headings and targets | `Label` |
| keywords, planning lines, and structural block declarations | `Keyword` |
| drawers and node properties | `Attribute` |
| comments and recovery regions | `Comment` |
| source, example, export, LaTeX, inline source, and code forms | `String` |
| entities, symbols, macros, and timestamps | `Constant` |
| links, citations, and footnote references | `String` |
| statistics cookies | `Number` |
| lists, tables, separators, and explicit line breaks | `Punctuation` |

Visible queries include at most the existing adjacent-line halo. Overlapping
nodes are normalized deterministically by semantic precedence into nonempty
half-open byte spans. The resulting `Syntax_Snapshot` records the exact buffer,
source revision, Jan language and provider, selection, parser, query, and
snapshot generations before the shared UI projection accepts it.

## Degradation and Inspection

Absent, pending, stale, cancelled, malformed, over-limit, provider-failed, or
allocation-failed analysis never blocks ordinary text editing. A failed
candidate clears presentation for the affected revision and records a bounded
failure. The previous confirmed analysis may remain inspectable, but its scope
cannot authorize presentation or operations over newer text.

`syntax_workflow_inspect_buffer` is the application inspection seam. It returns
copied association, provider selection, analysis status, confirmed revision,
generations, usage, pending work, and latest failure. Slice 6 builds the public
Jan inspection and status commands on this state; this slice does not add a
Jan-specific frontend.

## Odin Compatibility

Factory `.odin` matching, provider identity, Tree-sitter query, structural
syntax, generic symbol behavior, visible-range presentation, replacement,
disable, restoration, and cleanup retain their existing contracts. Jan state
uses separate owners and a separate registry and cannot change an Odin
selection generation.
