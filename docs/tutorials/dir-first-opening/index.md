<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Open and Navigate a Dir

This tutorial opens a filesystem Dir without creating Project metadata, finds a
nested file, and distinguishes the ordinary Dir workflow from a Project.

## 1. Start Odra

Build and launch the editor:

```sh
make odra
.build/odra
```

Move to `Open directory` and press Enter.

## 2. Select a Dir

Enter an absolute path or begin with `~/`. The path panel lists matching files
and Dirs below the prompt. Continue typing to filter, use Up or Down to select,
press Tab to accept the first candidate, and press Enter to open the selected
Dir.

Odra publishes the normalized path as an ordinary session Dir. It does not
create `.odra/`, a Project identity, or persistent state inside the Dir.

## 3. Find a file

The candidate header reads `Files [active Dir]`. Nested regular files appear
with paths relative to the active Dir.

Type any path fragment to filter the list. Use Up, Down, `Control-P`, or
`Control-N` to move. Press Enter to open the selected file. The document uses
the ordinary editing, syntax, buffer, view, and save workflows.

Press `Control-G` to close file navigation without opening a candidate.

## 4. Open the Dir in Maksym

Invoke `open-directory` through `Meta-X`, select an existing Dir with the
filesystem navigator, and press Enter. The selected root opens as a Maksym
buffer without requiring a Project or replacing Project identity. Navigate
entries with `n` and `p`, or press `j` to select an entry by name.

## 5. Recognize a Project

Open a Dir that contains one valid local `.odra/project.rkt` record whose root
matches the normalized Dir path. Its candidate header reads
`Files [active Project]`, and Project-scoped commands, trusted configuration,
and eligible language services may become available.

Opening a Dir without that exact local record never grants Project scope.
Project-only commands report that an active Project is required while safe
editor capabilities remain available.

Continue with [Open Dirs](../../how-to/open-dirs/) for concise procedures and
[Project Context Reference](../../reference/project-context/) for exact scope
and failure contracts.
