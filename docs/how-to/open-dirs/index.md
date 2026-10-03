<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Open Dirs

## Open from Startup

1. Run `.build/odra`.
2. Select `Open directory`.
3. Enter or complete an existing Dir path.
4. Press Enter.

The resulting file list is labeled `Files [active Dir]` unless the selected
Dir contains one exact valid local Project record.

## Open from the command line

Pass one existing Dir as the startup argument:

```sh
.build/odra /absolute/path/to/dir
```

Odra opens the Dir through the same normalized root and file-candidate path as
the Startup action.

## Open a Dir in Maksym

1. Press `C-x d`, or invoke `open-directory` through `M-x`.
2. Filter and select an existing Dir with the filesystem navigator.
3. Press Enter on the selected Dir.

The Dir opens as a Maksym buffer without changing Project registration or
writing local metadata. Cancellation or an unavailable path preserves the
previous editor surface.

## Navigate files

Move through Maksym entries with `n` or `p`, press `j` to filter entries by
name, and press `RET` to open the selected file or directory. `C-g`
closes an active candidate interaction. Empty Dirs remain valid empty Maksym
buffers.

If a listed file disappears or stops being regular before activation, Odra
rejects the stale candidate and keeps the editor recoverable.

## Verify ordinary Dir scope

An ordinary Dir does not acquire `.odra/` metadata merely by opening it.
`describe-project`, Project trust and configuration commands, and
Project-rooted language-service operations require an active Project and
report a Project-scope failure in a plain Dir.

A valid `<dir>/.odra/project.rkt` changes the admitted root to a Project using
the exact stored identity. Invalid, missing, or root-mismatched local metadata
does not establish Project scope.
