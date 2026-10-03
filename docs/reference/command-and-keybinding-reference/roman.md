<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Roman Commands

[Command and Keybinding Reference](index.md) | [Alphabetical Index](alphabetical-index.md)

Detailed behavior: [Roman Reference](../roman/index.md).


## Index and storage

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-roman-diagnose-node"></a>`roman-diagnose-node` | M-x only | Report identity, source range, state, and generations for the node at point. |
| <a id="command-roman-index-rebuild"></a>`roman-index-rebuild` | M-x only | Rebuild the complete Roman semantic index. |
| <a id="command-roman-index-refresh"></a>`roman-index-refresh` | M-x only | Discover the personal brain corpus and publish a complete Roman index. |
| <a id="command-roman-index-status"></a>`roman-index-status` | M-x only | Report confirmed Roman corpus and index state. |
| <a id="command-roman-space-inspect"></a>`roman-space-inspect` | M-x only | Report Roman storage and lifecycle state. |

## Nodes and links

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-roman-node-at-point"></a>`roman-node-at-point` | M-x only | Report the semantic title of the narrowest node at point. |
| <a id="command-roman-node-extract"></a>`roman-node-extract` | M-x only | Request extraction of the current Roman node when supported. |
| <a id="command-roman-node-find"></a>`roman-node-find` | Direct/Modal: `C-c n f` | Find and visit a Roman node by title or alias. |
| <a id="command-roman-node-insert"></a>`roman-node-insert` | Direct/Modal: `C-c n i` | Insert a stable link to a selected Roman node. |
| <a id="command-roman-node-move"></a>`roman-node-move` | M-x only | Request movement of the current Roman node when supported. |
| <a id="command-roman-node-random"></a>`roman-node-random` | M-x only | Report one node from the bounded confirmed candidate set. |

## Relations and graph

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-roman-graph"></a>`roman-graph` | Direct/Modal: `C-c n g` | Open the bounded Roman knowledge graph. |
| <a id="command-roman-graph-details"></a>`roman-graph-details` | M-x only | Open graph details with source-relative locations and bounded previews. |
| <a id="command-roman-graph-export"></a>`roman-graph-export` | M-x only | Export the Roman graph as deterministic Graphviz DOT. |
| <a id="command-roman-graph-render"></a>`roman-graph-render` | M-x only | Render the Roman graph as SVG through the admitted Graphviz tool. |
| <a id="command-roman-relations-open"></a>`roman-relations-open` | Direct/Modal: `C-c n l` | Open backlinks, outgoing links, and external references for the node at point. |
| <a id="command-roman-relations-toggle"></a>`roman-relations-toggle` | M-x only | Report incoming and outgoing relation counts for the node at point. |

## Metadata and references

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-roman-alias-add"></a>`roman-alias-add` | M-x only | Add an alias to the active Roman node. |
| <a id="command-roman-alias-remove"></a>`roman-alias-remove` | M-x only | Remove an alias from the active Roman node. |
| <a id="command-roman-ref-add"></a>`roman-ref-add` | M-x only | Add an external reference to the active Roman node. |
| <a id="command-roman-ref-find"></a>`roman-ref-find` | M-x only | Find nodes through their indexed external references. |
| <a id="command-roman-ref-remove"></a>`roman-ref-remove` | M-x only | Remove an external reference from the active Roman node. |
| <a id="command-roman-tag-add"></a>`roman-tag-add` | M-x only | Add a tag to the active Roman node. |
| <a id="command-roman-tag-remove"></a>`roman-tag-remove` | M-x only | Remove a tag from the active Roman node. |

## Capture and daily knowledge

| Command | Default binding | Description |
| --- | --- | --- |
| <a id="command-roman-capture"></a>`roman-capture` | Direct/Modal: `C-c n c` | Append an identified heading to the Roman inbox. |
| <a id="command-roman-daily-capture"></a>`roman-daily-capture` | Direct/Modal: `C-c n j` | Create or append to today's Roman daily document. |
| <a id="command-roman-daily-next"></a>`roman-daily-next` | M-x only | Open the next existing Roman daily document. |
| <a id="command-roman-daily-previous"></a>`roman-daily-previous` | M-x only | Open the previous existing Roman daily document. |
| <a id="command-roman-daily-visit"></a>`roman-daily-visit` | M-x only | Open today's existing Roman daily document. |
