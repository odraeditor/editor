<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Navigate Commands, Buffers, and Project Files

This tutorial follows the common candidate interaction through its four
factory sources: commands, session buffers, active-Project buffers, and
active-Project files.

## 1. Build and start Odra

From the repository root, create one isolated Project directory and start the
terminal editor with its first file:

```sh
mkdir -p /tmp/odra-candidate-project
printf 'alpha candidate navigation\n' \
  > /tmp/odra-candidate-project/alpha.txt
make odra
.build/odra /tmp/odra-candidate-project/alpha.txt
```

## 2. Navigate named commands

Press `Meta-X`. The command candidate root shows the active editor context, the
selected row, the total matching rows, and the editable query. The current
editor remains visible: its status bar moves upward, the query appears directly
below it, and matching commands grow downward beneath the query. Command names
are emphasized on the left, optional bindings occupy one aligned column, and
descriptions follow without exposing provider or availability metadata.

Type `cursor line`. Query components may appear in any order in the command
name or searchable description. Move with `Control-N`, `Control-P`, Down, or
Up. Press Enter to invoke the highlighted available command through its normal
registry route.

Open `Meta-X` again, type `[`, and observe that the invalid regular expression
remains useful literal text. Press `Control-G` to cancel. Cancellation invokes
nothing and records no usage.

## 3. Create and revisit a buffer

Press `Control-X`, then `b`. Type `candidate-notes` and press Enter. General
buffer navigation adds a synthetic creation row when no live buffer has the
valid exact name.

Type `temporary notes`, then press `Control-X b` again. Search for
`alpha`, select the file-backed row, and press Enter. The row
shows its document path, modified state, and backing kind; activation uses the
checked live-buffer identity rather than the displayed label.

## 4. Open and promote a Dir

Press `Control-X Control-C` and choose `d` to discard the temporary named
buffer, then restart without a path:

```sh
.build/odra
```

Move to `Open directory`, press Enter, enter
`/tmp/odra-candidate-project`, and select `alpha.txt`. The root is an ordinary
Dir, so candidate recency remains process-local and no durable Project usage
record is created.

Invoke `project-promote`, accept the proposed name, and return to the file.
The same root now has one exact local Project identity.

Press `Control-C p f`. Type `candidate alpha`; the Project-file source matches
both the relative label and canonical path. Press `Control-C p i` to replace
the complete file generation while retaining the selected canonical identity
when it still exists.

Press `Control-C p b` to see only live file-backed buffers owned by the active
Project. This scope never offers synthetic buffer creation.

## 5. Observe checked failure behavior

Leave a candidate root open and change its owning state through another
workflow when possible. A stale candidate cannot execute. Odra reports a
bounded diagnostic and asks you to refresh or reopen the selector instead of
using display text as authority.

Resource, source, history, and presentation failures follow the same rule:
the prior valid candidate state remains usable when it is still current. A
history failure affects ordering only; it never reverses a successful command,
buffer activation, or document opening.

## 6. Run the complete acceptance matrix

From the repository root:

```sh
make candidate-navigation-resource-study
make candidate-navigation-acceptance
```

The resource target measures all four source kinds at ordinary and demanding
profiles and then runs the independent matching and history studies. The
acceptance target runs reference models, generated parity, native owners,
Racket persistence, coordinator restart, fault containment, cleanup, and real
PTY workflows.

Continue with the [Candidate Session Reference](../../reference/candidate-session/)
for exact identities, limits, generations, failures, and persistence fields.
