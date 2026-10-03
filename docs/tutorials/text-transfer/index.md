<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Copy, Kill, Yank, and Rotate Text

This tutorial moves text through Odra's internal kill ring in the terminal. You
will copy one region, kill another, yank the newest retained text, rotate to an
older entry, undo the rotation, save, and exit.

## Prepare a document

From the repository root, build the editor and create a four-character file:

```sh
make odra
printf 'abcd' > /tmp/odra-transfer.txt
.build/odra /tmp/odra-transfer.txt
```

Point begins before `a`.

## Copy without changing the document

Press `Control-Space`, then Right twice. The active region contains `ab`.

Press `M-w` to run `copy-region`. In a terminal, Meta is commonly sent by
holding Alt or by pressing Escape before `w`.

The document remains `abcd`, its revision and history do not change, and `ab`
becomes the newest retained entry. When Odra runs through the supported direct
Herdr presentation path, the same complete entry is exported to the outer
terminal clipboard after internal retention succeeds.

## Kill a second region

Press `Control-G` to deactivate the current region. Point remains after `b`.

Press `Control-Space`, then Right twice. The active region now contains `cd`.
Press `Control-W` to run `kill-region`.

The visible document becomes `ab`. The complete `cd` entry is retained before
the deletion publishes, and the deletion is one reversible edit. A supported
clipboard export occurs only after that canonical result is complete.

## Yank and rotate

Press `Control-Y` to run `yank`. The newest entry, `cd`, is inserted at point,
so the document is `abcd` again.

The supported Herdr path is write-only, so this yank reads the internal ring.
A future or replacement frontend with clipboard-read capability may admit one
changed external value immediately before the same ordinary yank operation.

Immediately press `M-y` to run `yank-pop`. Odra replaces only the preceding
yank range with the next retained entry, `ab`. The document becomes `abab`.
The ring itself is not reordered.

Press `Control-X`, then `u`. Undo reverses the rotation and restores `abcd`.

## Save and exit

Press `Control-X`, then `Control-S` to save. Press `Control-X`, then
`Control-C` to exit. The file contains `abcd`.

For exact limits, chain rules, and failures, see the
[Text Transfer Reference](../../reference/text-transfer/index.md). For the
physical export procedure and troubleshooting, see
[Use the System Clipboard](../../how-to/use-system-clipboard/index.md).
