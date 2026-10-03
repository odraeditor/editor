<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Trace a Programmable and Contextual Keymap

This tutorial follows one complete interaction profile from Racket
construction to an immutable Odin resolution snapshot, then follows prompt
and contextual UI input through short-lived native maps. It uses the shipped
factory profile so the terminal-visible bindings remain unchanged.

## 1. Inspect the Racket profile

Open `src/command/keymaps.rkt` and find `factory-interaction-profile`. It adapts
the shipped bindings into one `odra-interaction-profile` containing one
`odra-keymap`.

The same module exposes checked constructors for the complete vocabulary:

- `keymap-bind`, `keymap-replace`, `keymap-unbind`, and `keymap-mask`;
- `keymap-remap` for semantic command redirection;
- `keymap-before` and `keymap-after` for stable same-class ordering; and
- `compose-interaction-profile` for ordered map contributions.

Run the Racket tests:

```sh
raco test src/command/keymaps.rkt
```

The tests construct every operation, preserve contribution order, stage one
candidate, and restore factory construction.

## 2. Follow the copied batch

Open `src/hosting/keymap-profile-bridge.rkt`. The bridge asks
`interaction-profile-candidate` for the staged or factory definition and
serializes it as one bounded batch. The batch contains a versioned header,
map, binding, remap, ordering, stroke, and UTF-8 text regions.

Run its tests:

```sh
raco test src/hosting/keymap-profile-bridge.rkt
```

The composed-profile case transfers two maps plus bind, replace, unbind, mask,
remap, and ordering records. Malformed, exceptional, oversized, garbage-
collected, and unsupported-version scenarios remain contained.

## 3. Observe native validation and ownership

`src/bridge/keymap_records.odin` defines the pointer-free record layouts and
checks exact counts, byte widths, text ranges, child ranges, identities,
sequences, provenance, and quotas.

`src/hosting/hosting.odin` performs one Racket call into private bounded
storage, validates the batch, adapts it into borrowed `interaction` values,
and releases every copied array through `keymap_profile_candidate_close`.

Run the boundary tests:

```sh
make hosting-test
```

## 4. Follow atomic activation

`src/interaction/profile_activation.odin` owns the active snapshot generation.
`profile_activation_replace` rejects stale or malformed candidates, compiles a
complete private snapshot, publishes only after success, and clears pending
multi-stroke input without replay. Any failure leaves the previous generation
and pending input untouched.

Run the focused native tests:

```sh
odin test src/interaction -vet -warnings-as-errors
```

## 5. Follow a contextual owner

Open `src/interaction/context_maps.odin`. `Context_Map_Stack` retains a bounded
set of active transient and list-tool maps. Each activation receives a fresh
context and owner generation. Completing, cancelling, or invalidating the
owner removes its map and clears any sequence pending in that generation.

Run the focused lifecycle tests:

```sh
odin test src/interaction -vet -warnings-as-errors
```

The tests place a transient prompt above a list-tool map, exercise
fallthrough, text insertion, rejection, pending-sequence invalidation, stale
owners, bounded activation, and cleanup.

## 6. Trace prompt and list routing

Open `src/odra/interaction.odin` and find
`command_context_activate_prompt_map`. File, buffer, save, dirty-state, exit,
search, and query-replacement prompts construct semantic bindings for their
current phase. Prompt handlers receive resolved command names rather than
interpreting raw keys.

Next open `src/odra/interaction_workflow.odin` and find
`command_context_sync_list_map`. The Startup and Buffer Menu lists activate
context-owned maps for movement, selection, marks, execution, and
cancellation. A prompt opened from either list temporarily outranks the list
map without destroying it.

Run the application and terminal behavior tests:

```sh
make native-command-test
make terminal-presentation-test
```

## 7. Navigate registered commands

Build Odra and open a local UTF-8 file:

```sh
make odra
.build/odra path/to/file.txt
```

Press `M-x`. The command navigator replaces the editor view with the complete
interactive command catalog. Each row shows the semantic name, every active
complete binding or `unbound`, the implementation provider, current
availability, and description. The bottom prompt identifies `Commands`, the
captured active editor context, the selected and visible-result counts, and
then `M-x` with the editable query.

Type `cursor-line-end`. The catalog narrows as the query changes. Press
`Backspace` or `DEL` to remove a query scalar, use `C-n`/`C-p` or `Down`/`Up`
to move the current row, and press `Enter` to execute the selected command.
Execution returns to the editor view and uses the same registry admission as
a key binding. Queries are case-insensitive and may combine literal or bounded
pattern components; invalid pattern syntax is treated literally.

Open `M-x` again and enter `uppercase-current-line`. This unbound command is
provided by `odra-racket`; executing it uppercases the current logical line
through the ordinary checked Racket command boundary. Open the navigator once
more, enter `copy-region`, and observe that it reports the active `M-w`
binding but remains unavailable until a region exists. `C-g` closes the
navigator without executing a command.

Run the terminal scenario that covers native and Racket execution, unbound
discovery, unavailable admission, cancellation, and restoration:

```sh
ODRA_PTY_EXECUTABLE="$PWD/.build/odra" \
  raco test tests/command_navigation/navigation_test.rkt
```

## 8. Inspect the active profile

Open `M-x`, enter `describe-key`, and press `Enter`. The bottom prompt changes
to `Describe key:`. Press `C-x u`. The inspection list shows the complete
sequence, effective `undo` command, availability, map revision, precedence,
priority, and source. Press `q` or `C-g` to return to the editor.

Repeat the trace with these registered commands:

- `where-is` prompts for a command name; enter `undo` to see every active
  effective sequence associated with it;
- `describe-bindings` lists active bindings in resolution order, including the
  protected `C-g` and `M-x` entries and their policy reasons;
- `describe-keymap` prompts for a positive map identifier and shows that map's
  bindings and remaps;
- `describe-keymap-conflicts` shows the most recent rejected profile
  candidate, when one exists; and
- `describe-keymap-state` shows snapshot and catalog generations, active and
  inactive profiles and states, state admission policy, context, pending input,
  resource usage, and command-entry surfaces.

Rows are copied from one immutable snapshot. They distinguish effective,
shadowed, masked, inactive, and rejected records without borrowing live
resolver storage.

Run the complete terminal inspection scenario:

```sh
ODRA_PTY_EXECUTABLE="$PWD/.build/odra" \
  raco test tests/keymap_inspection/inspection_terminal_test.rkt
```

## 9. Locate the admitted reload command

`reload-interaction-profile` is a registered native command. The application
routes it through `racket_profile_reload`, which obtains one staged Racket
candidate and replaces the session profile without restarting the editor.

The command has no factory key binding. Use `M-x`, enter
`reload-interaction-profile`, and press `Enter` to invoke it. Profile
persistence after process shutdown is deliberately not defined yet.

## 10. Complete the trace

Run the complete repository gate:

```sh
make verify
```

See [Configure a Runtime Keymap Profile](../../how-to/configure-keymaps/index.md)
for the construction procedure and the
[Contextual Keymap Reference](../../reference/contextual-keymaps/index.md)
for keymap layouts, limits, and failures. Continue with
[Inspect the Direct Interaction Profile](../interaction-profile-compatibility/index.md)
for the complete compatibility projection.
