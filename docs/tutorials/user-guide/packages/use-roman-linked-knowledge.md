<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Build a Linked Knowledge Base with Roman

Roman turns the `.org` and `.jan` documents in your personal brain into a linked
knowledge base. Jan text remains the source of truth. Roman's SQLite index is
derived state that you can rebuild after any source change.

Complete [Use Package Catalogs](use-package-catalogs.md) first so that package
discovery, authority confirmation, activation, and recovery are familiar.

## Install and Enable Roman

1. Run `M-x package-discover`.
2. Filter for `odra.roman` and select the exact curated release.
3. Review the requested `project-read`, `project-write`, `racket-extension`,
   and `external-process` authorities. The last authority admits only Roman's
   restricted Graphviz renderer.
4. Confirm enablement once. Roman's commands now appear in the ordinary `M-x`
   catalog.

Roman contributes a contextual `C-c n` map while a `.org` or `.jan` document
is active. Direct and Modal profiles resolve the same public command
identities, which also remain available through `M-x`.

| Binding | Workflow |
| --- | --- |
| `C-c n f` | Find a node. |
| `C-c n i` | Insert a stable node link. |
| `C-c n c` | Capture a note. |
| `C-c n j` | Capture today's daily note. |
| `C-c n l` | Inspect relations. |
| `C-c n g` | Inspect the graph. |

## Configure the Personal Brain

Create a directory for your knowledge documents. Add a named package resource
to personal `init.rkt`, preserving any resources already configured:

```racket
(require odra/commands)
(provide odra-package-resources)

(define odra-package-resources
  (list
   (make-package-resource
    #:package "odra.roman"
    #:name 'brain
    #:root (build-path (find-system-path 'home-dir) "Documents" "brain")
    #:access 'read-write)))
```

Use your chosen absolute directory and reload configuration or restart Odra.
The same brain is available from any Project or a standalone document. It does
not require Project registration. The package's confirmed read/write
authorities still control access.

To keep an existing brain, configure its existing source directory. Roman
preserves your documents and package SQLite state; it never silently adopts
the current Project as a replacement brain. Auxiliary provider spaces remain
explicit advanced uses and do not change the ordinary personal brain.
If Roman reports a root mismatch with the existing index, restore the
previously indexed directory. Changing this setting does not migrate a brain.

## Prepare a Small Brain

Create this `people.org` file in the configured brain:

```org
#+TITLE: People

* Ada Lovelace
:PROPERTIES:
:ID: person-ada
:ROAM_ALIASES: Ada
:ROAM_TAGS: :person:computing:
:END:

* Analytical Engine
:PROPERTIES:
:ID: topic-analytical-engine
:END:
Ada described the [[id:topic-analytical-engine][Analytical Engine]].
```

Roman discovers `.org` and `.jan` files recursively below the configured brain.
It ignores `.git`, `.build`, and `compiled` directory components. A heading
needs `ID` or `CUSTOM_ID` to become a stable Roman heading node.

## Build and Inspect the Index

1. Run `M-x roman-index-refresh` from any open document.
2. Read the reported source, identified-node, and generation counts.
3. Run `M-x roman-index-status` to inspect the confirmed corpus.
4. Run `M-x roman-space-inspect` to inspect Roman's package-owned storage.

Refresh is atomic. A rejected document or failed rebuild leaves the previous
confirmed generation active.

## Find and Link Nodes

1. Select `Ada` and run `M-x roman-node-find`.
2. Type to filter the candidate list, move with the ordinary candidate
   commands, and press Enter on `Ada Lovelace` to visit its source.
3. In ordinary prose, type and select `Analytical Engine`.
4. Run `M-x roman-node-insert`.
5. Confirm `Analytical Engine` in the searchable destination selector.
6. Confirm that the selection became
   `[[id:topic-analytical-engine][Analytical Engine]]`.
7. Undo once and redo once. One confirmed insertion is one text transaction.

Without a selection, Roman opens the same selector with an empty query and
inserts the confirmed node at point using its title. Cancellation or a stale
destination leaves the source unchanged.

Place point inside an identified heading and run `roman-node-at-point` for its
semantic title. Use `roman-diagnose-node` when you need internal identity,
source range, and generation details.

`roman-relations-open` opens a filterable list containing a summary, backlinks,
outgoing stable links, and outgoing external references. Enter visits the
selected exact occurrence. Press `g` to refresh the retained relation surface
without losing its current filter. `roman-graph` uses the same interaction for the
bounded complete graph: node rows visit their anchors and edge rows visit their
source occurrences. Ordinary rows use semantic labels and brain-relative
disambiguation; they do not expose absolute storage paths or internal IDs.

Run `roman-graph-export` to write deterministic Graphviz DOT below the
brain's `.build/roman/` directory. Run `roman-graph-render` to create SVG
there through the admitted Graphviz tool. Both commands report the concise
brain-relative destination. If Graphviz is absent or rendering fails, Roman
keeps the DOT export and returns to the textual graph surface. Use
`roman-graph-details` only when you need source-relative locations, internal
identities, or bounded source previews.

Place point inside a canonical reference such as `cite:lovelace`, or select
it, and run `roman-ref-find`. Roman seeds the searchable reference list from
that value. With no contextual value, the command lists all indexed
references.

## Edit Roman Metadata

Place point inside an identified heading. Select a value, place point anywhere
inside an existing Jan value, or let Roman prompt for a new value. Then run one
of:

- `roman-alias-add` or `roman-alias-remove`;
- `roman-tag-add` or `roman-tag-remove`; or
- `roman-ref-add` or `roman-ref-remove`.

Roman updates the matching property, inserts it into an existing property
drawer, or creates a complete property drawer below the heading. Duplicate
adds and absent removals reject without changing the buffer. Removal without a
contextual value offers the heading's existing values.

## Capture Notes and Dailies

Select text or place point on a non-empty line, then run `roman-capture`.
Roman appends an identified heading to `roman-inbox.org` below the brain.

Run `roman-daily-capture` to create or update
`daily/YYYY-MM-DD.org`. `roman-daily-visit`, `roman-daily-next`, and
`roman-daily-previous` open the relevant existing brain document. Save direct
edits and run `roman-index-refresh` to publish captured material into the
semantic index.

## Disable and Recover

Run `M-x package-disable` for `odra.roman`. Its commands and `C-c n` maps
disappear atomically, but brain documents and Roman package data remain.
Re-enable the confirmed release and run `roman-index-status`; refresh only when
source or derived state requires it.

When Roman reports that no brain or semantic index exists, run
`roman-index-refresh`. When a node is absent, verify its stable property and
valid Jan syntax. Use `package-doctor` for package activation failures and
`roman-diagnose-node` for an indexed node's exact source and generation state.
Expected command rejections remain inside the editor and leave the current
buffer unchanged.

`roman-node-move` and `roman-node-extract` are declared but currently reject
explicitly: the package runtime does not yet expose Jan's checked
multi-resource publication surface. Roman does not replace it with an unsafe
filesystem mutation.

The exhaustive command, storage, limit, and failure contracts are in the
[Roman Linked Knowledge Reference](../../../reference/roman/index.md).

---

[Previous: Work with Local Agents](use-local-agents.md) ·
[User Guide](../index.md) ·
[Next: Themes](../interface/themes.md)
