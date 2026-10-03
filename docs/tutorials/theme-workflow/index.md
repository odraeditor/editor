<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Select and Inspect a Session Theme

This tutorial starts Odra with its maintained dark theme, selects a different
factory theme, inspects the resulting session state, and verifies that
cancellation preserves the active choice.

## Start an Odin document

Build and open a small Odin source file:

```sh
make odra
printf 'package main\n\nmain :: proc() {}\n' > /tmp/odra-theme-demo.odin
.build/odra /tmp/odra-theme-demo.odin
```

The new session starts with `Wrocław Night`. Syntax, ordinary text, lists,
prompts, status rows, selections, search, and diagnostics all resolve through
the same session definition.

## Open the theme selector

Press `Meta-X`, enter `select-theme`, and press Enter. The shared candidate
view lists the four Wrocław themes and `Terminal Default`. Each row shows the
stable identity, provider, and selection status.

Type `sunset`. The list narrows to `Wrocław Sunset`. Press Enter.

Odra prepares and presents one complete logical UI generation before it
commits the new active selection. The editor content and syntax remain the
same; only the semantic style mapping changes.

## Inspect the active state

Press `Meta-X`, enter `describe-theme`, and press Enter. The read-only list
shows:

1. the selection, registry, and selection generations;
2. the active, fallback, and safe-baseline definitions;
3. the provider and definition lifecycle state;
4. every semantic role, logical color, attribute set, and value lowered for
   the active renderer;
5. registry usage and configured limits; and
6. the latest rejected operation.

Move with Up and Down. Press `q` or `Control-G` to return to the document.

## Verify cancellation

Run `select-theme` again, type `sunrise`, and press `Control-G` instead of
Enter. Run `describe-theme` once more. `Wrocław Sunset` remains active because
cancelling a candidate session does not start a theme transition.

## Try the safe baseline

Run `select-theme`, type `terminal-default`, and press Enter. `Terminal
Default` keeps every semantic role but leaves foreground and background colors
to the terminal. Attributes such as bold, dim, underline, and reverse preserve
the required distinctions.

Theme selection is session-wide and intentionally not persisted in this MVP.
A new Odra session starts with `Wrocław Night` again.

## Validate the workflow

Run the focused real-terminal acceptance scenario:

```sh
make theme-workflow-acceptance
```

The scenario selects every maintained factory theme, selects the safe
baseline, cancels a pending choice, inspects the final state, and exits through
a real PTY.

## Related material

- [Select, Inspect, and Validate Themes](../../how-to/select-and-inspect-themes/index.md)
- [Theme System Reference](../../reference/theme-system/index.md)
- [Why Themes Are Session-Owned Complete Definitions](../../explanation/session-theme-ownership/index.md)
