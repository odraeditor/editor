<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Edit an Odin File with Factory Syntax

This tutorial opens one Odin document, observes factory syntax presentation,
edits it through revisioned analysis, and inspects the active language state.

## 1. Create a sample document

From the repository root, create `/tmp/odra-syntax-demo.odin` with:

```odin
package main

import "core:fmt"

// Factory syntax presentation
answer :: 42

main :: proc() {
	fmt.println("answer", answer)
}
```

Build and start Odra in a color-capable terminal:

```sh
make odra
COLORTERM=truecolor TERM=xterm-256color .build/odra /tmp/odra-syntax-demo.odin
```

The factory provider recognizes the case-sensitive `.odin` suffix. Keywords,
comments, numbers, strings, types, functions, punctuation, and other admitted
captures are mapped to semantic roles and displayed through the ordinary
`TextView` pipeline.

## 2. Edit the analyzed revision

Insert text, then use `Control-/` to undo and invoke `redo` through `M-x` to
restore it. The buffer mutation publishes first. Syntax analysis then advances
to the new revision; Odra never applies spans from the previous revision to the
new text.

Start a search with `Control-S`, enter `answer`, and press Enter. Set a region
with `Control-Space` and move point. Search-current presentation overrides the
region, the region overrides syntax, and the underlying syntax roles remain
unchanged.

Save with `Control-X Control-S`.

## 3. Observe shared analysis across views

Press `Control-X 3` to split the active pane to the right. Both views refer to
the same buffer-owned analysis lifecycle while retaining independent viewport
state. Press `Control-X o` to change focus and Page Down to move one viewport.
Press `Control-X 1` to keep only the active pane.

## 4. Inspect the language state

Press `M-x`, enter `describe-language-state`, and press Enter. The shared list
reports:

- the `odin` association and factory provider selection;
- confirmed, parse, and syntax revisions;
- parser, tree, query, and syntax generations;
- semantic role, capture, span, and style information;
- terminal renderer capabilities;
- retained and temporary resource usage;
- pending work; and
- the latest contained rejection.

Press `q` or `Control-G` to return to the document.

## 5. Compare an unsupported document

Open a `.txt` file with `Control-X Control-F`, then invoke
`describe-language-state` again. The inspection reports a plain-text
association. The file remains fully editable, searchable, saveable, and
closable without a parser owner or syntax decorations.

Exit with `Control-X Control-C` and resolve any dirty-buffer prompts.

See [Configure and Validate Factory Syntax Presentation](../../how-to/configure-factory-syntax-presentation/)
for terminal capability selection, dependency checks, and focused acceptance
commands.
