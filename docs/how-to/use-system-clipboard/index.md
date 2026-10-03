<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Use the System Clipboard

Use Odra's copy and kill commands to export retained text to the clipboard of
the environment presenting the terminal. Internal text transfer remains
available when physical clipboard export is unavailable or fails.

## Check the supported path

The current physical integration is deliberately narrow:

- Odra runs in a direct terminal pane owned by Herdr;
- no tmux or Zellij session sits between Odra and Herdr;
- Herdr forwards OSC 52 output to the outer terminal client; and
- clipboard export is available, while clipboard import is not.

A generic SSH terminal, graphical clipboard utilities on the remote host, and
nested terminal multiplexers are not currently admitted as physical clipboard
paths. They still retain the complete internal kill-ring workflow.

## Export selected text

Build and open a UTF-8 document:

```sh
make odra
.build/odra notes.md
```

Inside Odra:

1. Press `Control-Space` to set mark and activate the region.
2. Move point to the other end of the text.
3. Press `M-w` to copy, or `Control-W` to kill.

Meta can normally be entered with Alt or by pressing Escape before `w`.

Odra first retains the complete text in its internal kill ring. A supported
frontend then receives one OSC 52 export. Clipboard failure cannot undo the
internal copy or a completed reversible kill.

## Verify the internal result

Press `Control-Y` to yank the newest retained entry. This check works with or
without physical clipboard support.

To verify the physical effect, paste through the outer terminal workstation or
another local application. The physical clipboard is owned by that
presentation environment, not by the Odra process host.

## Diagnose missing physical export

If `Control-Y` inserts the retained text but an external paste does not:

1. Confirm that Odra is running directly under Herdr.
2. Leave any nested tmux or Zellij session before starting Odra.
3. Confirm that the outer terminal permits application clipboard writes.
4. Retry with text no larger than 196,602 UTF-8 bytes.
5. Check Odra's bounded diagnostic line for an export failure.

Do not install or invoke a remote graphical clipboard utility for this path.
The supported mechanism writes through terminal output and does not require a
display server on the Odra host.

For exact capability, token, limit, and failure contracts, see the
[Text Transfer Reference](../../reference/text-transfer/index.md).
