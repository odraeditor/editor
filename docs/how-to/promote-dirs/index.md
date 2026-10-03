<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Promote Dirs to Projects

## Promote the active Dir

1. Open an ordinary Dir.
2. Invoke `project-promote` through `Meta-X`.
3. Edit the proposed name, which begins with the Dir basename.
4. Press Enter.

Odra writes `<dir>/.odra/project.rkt`, publishes the rebuildable global
discovery reference, and changes the session root from Dir to Project. The
open buffers, views, and text remain unchanged.

The new Project is untrusted. Use the existing Project trust workflow before
admitting Project-local configuration, tools, language services, or
extensions.

## Decide when leaving an ordinary Dir

When replacing an ordinary Dir root or exiting Odra, select one response:

- `p` promotes the exact Dir and continues only after publication succeeds;
- `n` continues without persistent state;
- `c` cancels the pending replacement or exit; or
- `d` stores a global preference for the exact Dir and continues only after
  that preference is durable.

Modified-buffer decisions occur before the exit promotion decision. A failed
promotion or failed suppression write keeps the pending action from being
reported as complete.

## Verify the result

After promotion, reopen the same Dir. Odra resolves the local Project identity
instead of creating a new one. `describe-project` reports its identity and
untrusted state.

Choosing `No` or `Cancel` must leave the ordinary Dir without a newly created
`.odra/` dir. Choosing `d` writes only the global suppression record under the
Odra configuration root; it does not create local Project metadata.
