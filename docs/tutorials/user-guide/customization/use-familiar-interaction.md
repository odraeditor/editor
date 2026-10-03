<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Use Familiar Interaction

This chapter uses Odra's default Direct profile, applies prefix arguments,
enters component-local maps, and verifies that packages and modules add only
the bindings they own.

## Before You Begin

Complete [Discover Commands and Bindings](discover-commands-and-bindings.md).
Keep one ordinary text file open and use `M-x describe-keymap-state` to confirm
that the selected interaction profile is `direct`.

Odra commands have stable semantic names. Direct and Modal provide different
keyboard grammars for those commands; Darek, Maksym, Ksawery, Jan, and Roman
add maps only while their own context is active.

## Exercise the Direct Foundation

In the ordinary text file, use these representative bindings:

| Binding | Command | Result |
| --- | --- | --- |
| `C-x C-f` | `find-file` | Open a path. |
| `C-x C-s` | `save-associated-document` | Save the current file. |
| `C-a`, `C-e` | `cursor-line-start`, `cursor-line-end` | Move within the logical line. |
| `M-f`, `M-b` | `cursor-next-word`, `cursor-previous-word` | Move by word. |
| `C-s`, `C-r` | `isearch-forward`, `isearch-backward` | Search incrementally. |
| `C-SPC` | `set-mark-command` | Start or finish a region. |
| `M-w`, `C-w`, `C-y` | `copy-region`, `kill-region`, `yank` | Copy, cut, and paste. |
| `C-_` or `C-x u` | `undo` | Undo one transaction. |
| `M-x` | `execute-extended-command` | Run a command by semantic name. |

Press `C-h k`, then one of the sequences above. The inspection result should
show the same command name as the table. Press `C-h w`, enter that command
name, and confirm that Odra can also find the route from command to binding.

## Apply a Prefix Argument

Place the cursor before several words. Press `M-3 M-f`; the cursor advances
three words. Press `C-u C-n`; the cursor advances four lines because one
universal argument starts at four. Repeating `C-u` multiplies the value by
four, and `M--` begins a negative numeric argument.

The prefix belongs to the next resolved Direct command, including one selected
through `M-x`. Press `C-g` to cancel a pending prefix. Switching profiles also
clears it; Modal counts belong to the Modal grammar instead.

## Enter Component-Local Maps

Open each component through its normal User Guide workflow. Its familiar keys
become active only while that component owns input.

| Owner | Representative entry or action | Familiar local bindings |
| --- | --- | --- |
| Maksym | `C-x d` | `f` opens, `m` marks, `g` refreshes, `q` closes. |
| Darek | `C-x t t` | `s` selects sorting; `t h`, `t i`, `t g`, and `t a` toggle presentation and watching. |
| Ksawery | `M-x ksawery-status` | `g` refreshes; `d`, `r`, `m`, `M`, and `C` open operation families; `?` opens the dispatcher. |
| Jan Babel | Open a `.jan` or `.org` document | `C-c C-c` performs the contextual action; `C-c C-v` introduces Babel operations. |
| Roman | Enable `odra.roman` and open a Jan document | `C-c n f` finds a node, `C-c n i` inserts one, and `C-c n g` opens the graph. |

Run `C-h m` inside a component and again after closing it. The active owner and
maps should change, while the semantic command registry remains available to
`M-x`. A key with a component-local meaning returns to its Direct meaning when
that context closes.

## Compare Direct and Modal

Run `M-x select-interaction-profile` and select `modal` for the current
session. Commands such as save, undo, Jan actions, and Roman actions retain
their public identities, but the profile resolves them through its own maps.
Component-owned prompts, candidates, Darek, Maksym, and Ksawery continue to
take local input while active.

Return to `direct` with the same command. Use `C-h m` after each transition to
inspect the selected profile and active context rather than inferring them
from one key.

## Observe Package and Module Lifecycle

Roman contributes commands and `C-c n` maps only while `odra.roman` is enabled.
Run `M-x package-disable`, select `odra.roman`, and confirm that `C-h w` no
longer finds an active route for `roman-node-find`. Enable the installed
package again and reopen a Jan document; the route returns with the new
contribution generation.

Darek and Maksym follow the same ownership rule at the module boundary. Their
local maps are present only when the module is loaded and its surface owns
input. Closing a surface must not leave one of its local bindings in the
ordinary editor map.

## Recognize Intentional Migrations

The register prefix follows familiar meanings: `C-x r s` stores the active
region, `C-x r SPC` stores the current location, and `C-x r j` visits a stored
location or layout. The older Odra routes remain available by command name
where they still represent useful operations.

Ksawery reserves its Status family keys for their repository meanings. The
previous unrelated actions moved instead of remaining as dangerous conflicts:
refresh is `g`, discard is `k`, fetch is `&`, and sequence inspection remains
available through `M-x ksawery-sequence`.

Terminal-only exclusions are deliberate. Operations that require graphical
frames or visual text scaling have no Direct binding. They remain explicit in
the compatibility ledger rather than resolving to an unrelated action.

## Diagnose a Surprising Binding

Use this order before changing configuration:

1. Press `C-h k` and capture the complete sequence.
2. Run `C-h m` to identify the selected profile and contextual owner.
3. Run `C-h w` with the expected command name.
4. Run `M-x describe-keymap-conflicts` after a rejected profile reload.
5. Press `C-g` to cancel retained prefix, prompt, candidate, or pending-key
   state and repeat the inspection.

A package or module replacement publishes a complete new contribution
generation. Old bindings must disappear with the old generation; they are not
silently redirected by display name.

## Verify the Result

You have completed this chapter when Direct movement, editing, search, and
help bindings resolve to their documented commands; prefix arguments apply to
one command; each component-local map appears and disappears with its owner;
Direct and Modal share command identities while retaining separate maps; and
inspection explains any migrated or unavailable binding.

For the complete reviewed ledger, exclusions, and migration tables, read the
[Interaction Compatibility Reference](../../../reference/interaction-compatibility/index.md).

---

[Previous: Discover Commands and Bindings](discover-commands-and-bindings.md) ·
[User Guide](../index.md) ·
[Next: Compose Keymaps and Profiles](keymaps-and-profiles.md)
