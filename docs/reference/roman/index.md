<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Roman Linked Knowledge Reference

Roman is the optional `odra.roman` package. It composes Odra's verified package
runtime, native Jan semantic analysis, checked text transactions, resource
authority, and package-owned SQLite storage without moving Roman policy into
editor core.

## Sources and Identity

The default brain is the user-configured personal `brain` resource. Roman discovers regular `.org`
and `.jan` files recursively and excludes `.git`, `.build`, and `compiled`
components. Jan documents remain canonical. The Roman index is derived state.

Document titles produce file nodes. Headings with `ID` or `CUSTOM_ID` produce
stable heading nodes. Titles, aliases, tags, references, properties, outline
paths, links, and citations retain exact source provenance. Index generations
are atomic; failed enrollment or analysis preserves the preceding confirmed
generation.

## Commands

All commands require an active buffer and document. Commands that edit current
text also declare the `text-mutation` effect.

| Command | Behavior |
| --- | --- |
| `roman-index-refresh` | Discover the personal brain corpus and atomically rebuild its semantic index. |
| `roman-index-rebuild` | Re-run the refresh and rebuild workflow. |
| `roman-index-status` | Report confirmed corpus generation, sources, bytes, and failures. |
| `roman-space-inspect` | Report default-brain storage state, generation, and record count. |
| `roman-node-find` | Open a bounded candidate session for indexed titles and aliases. Complete and partial aliases remain searchable and identify the owning node. Filtering, movement, Enter activation, and cancellation use Odra's ordinary candidate controls. |
| `roman-node-random` | Report one bounded random node candidate. |
| `roman-node-at-point` | Report the semantic title of the smallest indexed node containing point. |
| `roman-node-insert` | Open a searchable destination selector, then insert the confirmed stable `id:` link at point or replace the active region while preserving its prose as the description. |
| `roman-relations-toggle` | Report incoming and outgoing relation counts for the node at point. |
| `roman-relations-open` | Open a filterable surface containing a summary, backlinks, outgoing stable links, and outgoing external references; Enter visits an exact occurrence. |
| `roman-ref-find` | Open indexed canonical references. A region or the reference at point seeds the query; no contextual value lists all references. Enter visits the selected node. |
| `roman-graph` | Open a filterable bounded graph surface with semantic node rows and categorized edge rows. |
| `roman-graph-details` | Open the graph detail surface with brain-relative locations, internal identities, and bounded source previews. |
| `roman-graph-export` | Export deterministic Graphviz DOT below the brain-local `.build/roman/` directory and report the destination. |
| `roman-graph-render` | Render SVG below the brain-local `.build/roman/` directory through the admitted Graphviz tool, or retain the DOT export and textual graph when rendering is unavailable. |
| `roman-diagnose-node` | Report node identity, source range, state, and source/index generations. |
| `roman-alias-add`, `roman-alias-remove` | Edit `ROAM_ALIASES` from a region, the value at point, prompted input, or an existing value selected for removal. |
| `roman-tag-add`, `roman-tag-remove` | Edit `ROAM_TAGS` from a region, the value at point, prompted input, or an existing value selected for removal. |
| `roman-ref-add`, `roman-ref-remove` | Edit `ROAM_REFS` from a region, the value at point, prompted input, or an existing value selected for removal. |
| `roman-capture` | Append an identified heading to brain `roman-inbox.org`. |
| `roman-daily-capture` | Create or append to brain `daily/YYYY-MM-DD.org`. |
| `roman-daily-visit` | Open today's existing daily document. |
| `roman-daily-next`, `roman-daily-previous` | Open the next or previous existing daily document. |
| `roman-node-move`, `roman-node-extract` | Reject explicitly until the package context exposes checked Jan multi-resource publication. |

Roman contributes `C-c n l`, `f`, `g`, `i`, `c`, and `j` for relation
inspection, node finding, graph inspection, link insertion, capture, and daily
capture. The map is active only in Jan documents while Roman is enabled.

Node, relation, and graph results use Odra's generic candidate surface. Unique
nodes use their semantic title. Duplicate titles add tags or a path relative
to the brain. Ordinary rows never display absolute storage paths or internal
resource and node identities. Activation revalidates the copied source anchor
before navigation. Relation candidates remain retained until navigation or
cancellation; `g` refreshes the complete generation while preserving the
current filter.

## Package Runtime Contract

Roman requests `project-read`, `project-write`, `racket-extension`, and
`external-process`.
Resource authority is bound to the user-configured `brain` root supplied only
to Roman's command context. Switching Projects cannot replace it. Configure
`odra-package-resources` in personal `init.rkt` as described in the
[Roman User Guide](../../tutorials/user-guide/packages/use-roman-linked-knowledge.md#configure-the-personal-brain).
Package data is bound to Roman's package-specific operational root.
The verified declared module tree may import the public `odra/commands` API and
the restricted direct Racket library set admitted by the generic package
runtime.

The process authority admits Roman's semantic Graphviz request; it is not
general shell or arbitrary-process access. Graph export remains available
without Graphviz. A missing, denied, timed-out, failed, or invalid renderer
leaves the DOT artifact in place and preserves textual graph inspection.

Native Jan analysis crosses the package boundary as copied, pointer-free,
versioned nodes, attributes, recoveries, and index facts. The package neither
loads a second Jan parser nor imports private Jan implementation modules.

## Storage and Lifecycle

Roman stores `roman.sqlite3` under its package data root. The database contains
enrollment, source, index, relation, provider, recovery, and generation state;
it is not the canonical source for the default brain. Rebuilding from unchanged
Jan input produces equivalent logical records.

Activation publishes all package commands and contextual keymaps as one
contribution generation. Disablement removes that generation before retiring
its namespace and custodian. It preserves brain documents and package data.
Restart restores only a verified release named by confirmed active package
state.

Managed provider spaces use separate space, consumer, grant, generation, and
physical storage identities. A consumer cannot acquire default-brain authority
or another consumer's records through registration alone.

## Limits and Failures

Corpus discovery, source bytes, node and relation counts, query results, graph
depth and edges, command feedback, package memory, and command deadlines are
bounded. Expected absence, ambiguity, stale generations, invalid Jan source,
denied authority, and unavailable capabilities reject without source mutation.

Direct capture writes only below the admitted personal brain. Buffer edits publish
through the checked current-document transaction. Roman does not silently
fall back from native Jan semantics, verified package content, confirmed
authority, or atomic index generations.

See [Why Roman Remains an Optional Package](../../explanation/roman-architecture/index.md)
for the ownership rationale and
[Using Roman in Odra](../../tutorials/user-guide/packages/use-roman-linked-knowledge.md)
for the guided workflow.
