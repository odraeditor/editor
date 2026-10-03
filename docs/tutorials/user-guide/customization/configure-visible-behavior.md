<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Configure Visible Behavior

This chapter connects the personal configuration path to each delivered
interface and editing surface, distinguishes settings available now from
runtime extension contracts, and identifies the interfaces available to
personal configuration.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../getting-started/prepare-exercises.md).

Complete [Write and Reload a Personal Command](personal-commands.md). Keep the
isolated configuration generation active.

## Choose the Correct Boundary

Odra exposes several kinds of change. They are deliberately not
interchangeable:

| Surface | Supported personal path now | More detailed contract |
| --- | --- | --- |
| Themes | Select and inspect the current session through `M-x`; selection is not persisted. | Theme provider lifecycle is extension-scoped, not an `init.rkt` export. |
| Status Bar | Export `odra-status-bar-configuration`. | Programmable segment providers use a separate runtime-scoped capability. |
| Gutter | Export `odra-gutter-configuration` and optionally one `odra-gutter-provider`. | Provider generations replace or remove one complete personal lane and marker set. |
| Completion | Export `odra-completion-configuration`. | Provider, policy, presentation, session, and acceptance remain separate owners. |
| Commands | Export `odra-personal-commands`. | Each command runs through copied context, resource limits, and a private transaction. |
| Keymaps | Export `odra-interaction-profile`. | Contextual prompt and component maps remain lifetime-scoped native owners. |
| Search | Use interactive search policies and commands. | The programmable policy facade is not yet loaded from personal configuration. |
| Pane placement | Use pane and display commands. | The programmable display-policy facade is not yet a personal terminal setting. |
| Transient presentation | Select a theme and use the owning feature. | Arbitrary profile construction and render-time callbacks are not public personal APIs. |

A source module being written in Racket does not by itself make it a supported
personal import. Use the logical modules admitted by the personal resolver:
`odra/commands`, `odra/keymaps`, `odra/gutters`, and `odra/completion`.

## Keep Visible Settings Semantic

Status Bar configuration chooses position, eligible context, and compactness.
Gutter configuration chooses view defaults such as numbering mode, side,
digits, and separators. Completion configuration chooses admitted invocation,
filtering, presentation, and resource policy.

These values describe behavior and semantic roles. Do not place terminal
escape sequences, renderer-specific coordinates, or hard-coded theme colors
inside content, markers, command descriptions, or keymap provenance.

Run `M-x describe-theme` to inspect how the selected theme resolves interface
and transient-presentation roles for the current renderer. Run
`status-bar-inspect`, `gutter-inspect-numbering`, and
`describe-completion-state` to inspect the feature-owned state separately.

## Follow the Focused Procedures

Use the task-specific How-to Guide when changing a supported surface:

- [Select, Inspect, and Validate Themes](../../../how-to/select-and-inspect-themes/index.md)
- [Configure Personal Startup](../../../how-to/configure-personal-init/index.md)
- [Configure and Reload a Programmable Gutter](../../../how-to/configure-programmable-gutter/index.md)
- [Configure and Diagnose Language Completion](../../../how-to/configure-language-completion/index.md)
- [Define and Reload Personal Commands](../../../how-to/define-personal-commands/index.md)
- [Configure a Runtime Keymap Profile](../../../how-to/configure-keymaps/index.md)

The following procedures describe delivered repository-owned programmable
boundaries, not current `init.rkt` imports:

- [Configure Programmable Search Policy](../../../how-to/configure-search/index.md)
- [Configure Other-Pane Display Policy](../../../how-to/configure-pane-display-policy/index.md)

Their availability statements are part of the contract. Do not copy their
internal module paths into personal configuration.

## Use Reference for Exact Values

Tutorials establish the workflow; Reference owns exhaustive values and
limits:

- [Theme System Reference](../../../reference/theme-system/index.md)
- [Status Bar Reference](../../../reference/status-bar/index.md)
- [Gutter Reference](../../../reference/gutter/index.md)
- [Language Completion Reference](../../../reference/language-completion/index.md)
- [Personal Commands Reference](../../../reference/personal-commands/index.md)
- [Contextual Keymap Reference](../../../reference/contextual-keymaps/index.md)
- [Transient Presentation Profile Reference](../../../reference/transient-presentation-profiles/index.md)

Use the linked Explanation material when the question is why ownership,
generations, transactions, or fallback are structured that way rather than
which value to enter.

## Verify the Result

You have completed this chapter when each desired change is routed to a
current session command, admitted personal export, or explicitly
extension-scoped contract; visible configuration remains semantic and
theme-aware; internal module paths are not treated as personal APIs; and every
focused procedure and exact reference is reachable from the customization
path.

---

[Previous: Extend Ksawery](extend-ksawery.md) ·
[User Guide](../index.md) ·
[Customization](index.md)
