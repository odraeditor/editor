<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Configure Integrated Terminals

Configure terminal policy in the terminal section of personal configuration.
The candidate is validated completely before replacing the last working
configuration.

Ordinary terminal commands open a lower pane and preserve the editing area.
Use `terminal-toggle` to hide or restore it, and `C-x o` to cycle pane focus.
Use `terminal-open-other-pane` for the ordinary other-pane display policy.
Shell and attention settings do not change pane placement.

```racket
(terminal-configuration
 #:global
 (terminal-settings
  #:shell "/bin/bash"
  #:attention 'visual)
 #:workspaces
 (hash "work"
       (terminal-settings
        #:shell "/bin/zsh"
        #:attention 'both)))
```

Attention accepts `'none`, `'audible`, `'visual`, or `'both`. Bell requests are
rate-limited and never select a buffer, move focus, create a pane, or reveal a
hidden terminal.

To reduce automation queues, construct `terminal-operating-limits` and pass it
with `#:limits`. Values may move within the documented safety ceilings; an
invalid or downward-incompatible candidate is rejected while the active policy
remains unchanged.

Terminal automations subscribe to copied events on Racket's owner thread:

```racket
(terminal-automation
 'prompt-log
 '(prompt-boundary process-exit)
 (lambda (events) (void)))
```

Callbacks receive bounded immutable values. They do not run from PTY, parser,
or emulator callbacks. Child clipboard operations, desktop notifications,
external image media, and unknown control sequences remain denied or inert.

See the [Integrated Terminal Reference](../../reference/integrated-terminal/index.md)
for exact defaults and event kinds.
