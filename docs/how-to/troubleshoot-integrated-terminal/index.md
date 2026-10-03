<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Troubleshoot Integrated Terminals

Start with `M-x terminal-list`. A retained session can exist while no pane
presents it, and two panes can intentionally present the same session. Use
`M-x terminal-new` when the second pane needs an independent child process.

If input appears inert, confirm that the terminal pane is focused and copy mode
is not active. Finish copy mode with Return. Use `C-q` before a key that Odra's
terminal context would otherwise interpret locally.

If closing a pane appears to end work, distinguish detaching a presentation
from `terminal-terminate` and closing the retained terminal buffer. A process
exit keeps the final projection inspectable; a deliberate terminal-buffer
close coordinates final cleanup.

If output stops or an operation fails, inspect the diagnostic for a queue,
state, geometry, image, or aggregate limit. Bounds are enforced before large
allocations. Reducing output, scrollback, geometry, active images, or concurrent
sessions restores operating headroom; do not raise immutable safety ceilings.

Child clipboard requests, desktop notifications, external image media, and
unknown control sequences are intentionally denied or inert. Use Odra's
explicit copy, paste, link activation, and attention settings instead.

For a dependency or ABI failure, run `make terminal-dependency-check` first.
Then use `make terminal-emulator-test` for the isolated adapter. Ordinary
development does not require an installed Ghostty application or network
access because the admitted inputs are repository controlled.
