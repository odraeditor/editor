<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Select, Inspect, and Validate Themes

## Select a theme

1. Press `Meta-X`.
2. Enter `select-theme` and press Enter.
3. Filter by display name, stable identity, or provider.
4. Press Enter on one confirmed definition.

The initial direct profile intentionally has no dedicated theme key. The
canonical entry point is `M-x select-theme`.

The maintained choices are `Wrocław Sunrise`, `Wrocław Morning`, `Wrocław
Sunset`, `Wrocław Night`, and the color-minimal `Terminal Default` safe
baseline. Admitted and confirmed Racket definitions appear in the same list.

Press `Control-G` to cancel without changing the active theme. If the registry
or selection changes while the list is open, Odra rejects the stale candidate
and asks you to reopen `select-theme`.

## Inspect the current theme

1. Press `Meta-X`.
2. Enter `describe-theme` and press Enter.
3. Use Up and Down to inspect the complete copied list.
4. Press `q` or `Control-G` to close it.

Use the summary rows to confirm active, fallback, baseline, provider,
renderer, usage, limits, and latest rejection state. The contextual
presentation rows show the selected profile generation, semantic chrome-slot
mappings, spacing, dimensions, border, capability degradation, fallback, and
latest profile rejection. The following theme-role rows show the logical
attributes and colors together with their deterministic monochrome, basic-16,
indexed-256, or true-color lowering.

## Recover from a rejected selection

1. Leave the selector with `Control-G` if it remains open.
2. Run `describe-theme` and confirm the prior complete definition is active.
3. Inspect the latest rejection operation and code.
4. Reopen `select-theme` to obtain current definition and selection
   generations.

A rejected, stale, malformed, unavailable, or failed definition does not
replace the active theme. Failure of an active admitted provider restores
`Wrocław Night`. Select `Terminal Default` when terminal-owned colors are the
desired safe presentation.

## Run focused validation

```sh
make theme-reference-test
make theme-equivalence-test
make theme-workflow-acceptance
make terminal-presentation-test
make docs-check
```

Use `make verify` for the complete repository gate.

## Related material

- [Select and Inspect a Session Theme](../../tutorials/theme-workflow/index.md)
- [Theme System Reference](../../reference/theme-system/index.md)
- [Transient Presentation Profile Reference](../../reference/transient-presentation-profiles/index.md)
- [Why Themes Are Session-Owned Complete Definitions](../../explanation/session-theme-ownership/index.md)
