<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Discover Commands and Bindings

This chapter searches the interactive command catalog, distinguishes command
identity from availability and bindings, explains one effective key sequence,
and inspects active resolution order.

## Before You Begin

If you enter this chapter directly, first complete [Prepare the User Guide
Exercises](../getting-started/prepare-exercises.md).

Complete [Organize Personal Configuration](personal-configuration.md). Keep
the isolated tutorial `init.rkt` and `settings/interface.rkt` from that
chapter.

Commands have stable semantic identities. A key sequence is one configurable
route to a command, not the command itself.

## Search the Command Catalog

Press `M-x`. The contextual candidate surface shows registered interactive
commands for the captured editor state. Each row includes the semantic name,
active binding or `unbound`, provider, availability, and description.

Type `line start`. Filtering narrows the catalog without modifying the source.
Use `C-n`, `C-p`, `Down`, or `Up` to move and press `RET` on
`cursor-line-start`. The selected command executes directly through ordinary
admission; Odra does not replay the binding printed in the row.

Open `M-x`, search for `copy-region`, and observe its copied availability. It
is unavailable without an active region and available after `C-SPC` plus
movement. Press `C-g` to leave the navigator unchanged.

## Find a Command's Bindings

Run `M-x where-is`. Enter `save-buffer`. The result lists every active
effective sequence for that semantic command. Use `Up` and `Down` to inspect
rows and `q` or `C-g` to return.

Run `M-x describe-key`, then press `C-x C-s` at the capture prompt. The result
shows the effective command, map, precedence, operation, profile state,
availability, and provenance for the complete normalized sequence.

Use the remaining inspection commands as needed:

| Command | What it answers |
| --- | --- |
| `describe-bindings` | Which bindings are active, in resolution order? |
| `describe-keymap` | What does one positive map identity contribute? |
| `describe-keymap-state` | Which registry, profile, state, maps, pending input, and command-entry surfaces are active? |
| `describe-keymap-conflicts` | Why was the latest profile candidate rejected? |

The familiar help prefix provides direct entry points: `C-h ?` lists help
commands, `C-h a` searches commands and descriptions, `C-h f` describes one
interactive command, `C-h v` describes configuration owners, `C-h m`
describes active interaction state, `C-h s` describes structural syntax,
`C-h b` and `C-h k` inspect bindings, `C-h i` opens the User Guide index, and
`C-h t` opens the editing tutorial.

The results are copied immutable observations. They distinguish effective,
shadowed, masked, inactive, and rejected definitions without lending resolver
state to the UI.

## Recover from Discovery Problems

- Use `describe-key` for one surprising sequence before changing a profile.
- Use `where-is` when the command is known but its effective route is not.
- Use `describe-keymap-state` to separate profile, interaction state, pending
  prefix, and command-catalog generations.
- Reopen `M-x` after a profile generation changes; an old catalog row is never
  redirected by visible name.

## Verify the Result

You have completed this chapter when command discovery distinguishes identity,
binding, provider, and availability; `where-is` finds routes from a known
command; `describe-key` explains one sequence; and the broader inspection
commands expose active order, state, and current rejection context.

For exact catalog, resolution, and inspection records, see the
[Command and Keybinding Reference](../../../reference/command-and-keybinding-reference/index.md),
[Contextual Keymap Reference](../../../reference/contextual-keymaps/index.md)
and
[Interaction Profile Compatibility Reference](../../../reference/interaction-profile-compatibility/index.md).

---

[Previous: Organize Personal Configuration](personal-configuration.md) ·
[User Guide](../index.md) ·
[Next: Use Familiar Interaction](use-familiar-interaction.md)
