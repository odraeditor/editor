<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Jan Structured Editing Has Its Own Static Package

Structured editing sits between Jan analysis and the running application. It
needs parsed ranges, editor positions, transactions, view state, commands, and
presentation, but none of those owners should absorb the entire Stage 2 domain.

Putting the behavior in `src/language` would make parsing own editing policy.
Putting it in `src/odra` would make every structural change compile the complete
application. `src/jan_editing` keeps the dependency direction explicit and the
ordinary feedback loop small.

## Dependency direction

```text
Jan analysis in src/language
            |
            v
generic view state <- src/jan_editing -> checked rewrite and transaction contracts
            |                 |
            v                 v
 presentation owners     thin src/odra adapter in Slice 7
```

The boundary is compile-time package organization. It does not use dynamic
linking, load native code at runtime, or create a second extension mechanism.

## Why hidden ranges belong to views

Two panes can show the same buffer with different folds. Canonical bytes and
Jan analysis remain shared, so folding cannot live in the document or parser.
`src/view` retains generic anchored ranges and exposes reveal operations;
`src/jan_editing` decides which heading or subtree ranges should be hidden for
one Jan command.

This also keeps hidden-source safety outside frontend rendering. Movement and
editing adapters can ask the view owner to reveal a target before publishing a
canonical position or transaction.

## Why transitions are prepared

A visibility command starts from one analysis revision and one view state. The
user, another command, or an editor transaction can change either before the
new projection is published. A prepared transition copies its bounded ranges
and identities, then publication rejects any mismatch. The old view generation
remains intact on rejection.

## Development feedback

The package boundary makes this the complete ordinary Slice 1 check:

```sh
make jan-structured-editing-focused-test
```

The command checks independent Racket behavior and resource models, all generic
view tests, and all Jan editing tests. It does not build the Odra executable.
Later slices extend the same target. Only Slice 7 links the completed Stage 2
domain into `src/odra` and runs PTY acceptance once.
