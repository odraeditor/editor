<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Configure a Runtime Keymap Profile

Use the Racket API in `src/command/keymaps.rkt` to construct and stage one
complete session profile. Odin remains the owner of validation, compilation,
activation, pending input, and canonical editor state.

## Define provenance and sequences

Every map, binding, and remap carries bounded source metadata.

```racket
(define source
  (odra-provenance "user" "local configuration" "keymaps.rkt:1"))

(define control-x
  (key-sequence
   (odra-key-stroke 1 (char->integer #\x) #x01)))
```

Logical key kind `1` is a Unicode scalar. Modifier bits are Control `#x01`,
Meta `#x02`, Alt `#x04`, and Super `#x08`. A sequence contains between one and
sixteen normalized strokes.

## Build map operations

Use explicit operations rather than relying on declaration or module load
order:

```racket
(define bindings
  (list
   (keymap-bind control-x "keyboard-quit" source)
   (keymap-replace control-x "reload-interaction-profile" source)
   (keymap-unbind control-x source)))
```

`keymap-replace` and `keymap-unbind` require an earlier declaration of the
same sequence in that map. `keymap-mask` accepts no command and prevents a
lower-precedence map from supplying the sequence. `keymap-remap` redirects a
registered semantic command without duplicating its physical bindings.

## Construct maps and a profile

`odra-keymap` records stable identity and revision, precedence, priority,
optional context ownership, unmatched-input policy, operations, remaps,
ordering constraints, and provenance. Use `compose-interaction-profile` to
flatten contributions in their declared order.

Every referenced command name must already exist in the active command
registry. Map identifiers must be unique. Same-class maps with equal priority
need explicit ordering when their effective definitions collide.

Increment `odra-interaction-profile` revision whenever a staged definition
changes. Reusing the active profile identity and revision is rejected as
stale.

## Stage and reload

Stage only a complete value:

```racket
(stage-interaction-profile! profile)
```

The registered `reload-interaction-profile` command asks Racket for that
candidate, copies and validates it, and atomically replaces the active session
snapshot. A rejected candidate preserves the prior generation. Successful
replacement clears a pending key prefix without replaying it.

The terminal factory profile does not bind the reload command. Invoke it
through `M-x` by entering `reload-interaction-profile`. Tests and admitted
command dispatch can exercise the same path. `clear-staged-interaction-profile!`
restores lazy factory candidate construction for the next reload.

Staging and activation are session-only. This capability does not discover a
configuration file and does not write runtime changes back to disk.

## Preserve contextual behavior

Profile maps supply the global programmable layers. Prompts and shared UI lists
add native lifetime-scoped maps above those layers:

- transient prompt maps use `Transient_Interaction` precedence;
- startup and Buffer Menu maps use `Component_Tool` precedence;
- startup leaves unmatched input to the active profile so global sequences
  continue to work; and
- text prompts insert committed text, while fixed-choice prompts and the
  Buffer Menu reject unmatched input.

Bind global commands by semantic name. Do not reproduce prompt responses,
search continuation keys, startup movement, or Buffer Menu marks in the
Racket profile merely to keep those workflows working. Their owners activate
and retire the contextual maps automatically.

After reloading a profile, cancel any active prefix and verify both an ordinary
global binding and a contextual workflow. Successful replacement clears
generation-bound pending input; it does not replay the prefix inside the
current prompt or list workflow.

## Preserve recovery access

The active policy protects exactly two normalized sequences:

| Sequence | Command |
| --- | --- |
| `C-g` | `keyboard-quit` |
| `M-x` | `execute-extended-command` |

Do not bind, replace, unbind, mask, or shadow either sequence in an ordinary
profile or contextual map. The candidate will be rejected before publication.
`C-x C-c` and every alias not shown in this table remain ordinary configurable
bindings.

Every frontend used with the profile must declare that it can produce both
protected logical sequences. Failure to represent Control- or Meta-modified
Unicode input rejects activation instead of installing a recovery policy the
frontend cannot reach.

## Verify command discovery and reinforcement

Use `M-x` after activation to verify the effective user-facing result:

1. Enter the registered semantic command name.
2. Confirm that every expected complete active sequence appears in the row.
3. Confirm that an intentionally unbound interactive command says `unbound`.
4. Confirm that the provider identifies the native or Racket definition owner.
5. Confirm that context-dependent commands report `available` or an exact
   unavailable reason.
6. Confirm the `Commands [active editor context] selected/visible` label tracks
   filtering and `C-n`/`C-p` or arrow-key movement.
7. Press `Enter` to execute an available command or `C-g` to leave unchanged.

Bindings are reinforcement, not invocation identity. The navigator executes
the selected registered command directly through ordinary admission, so a
remap or profile replacement cannot be simulated by replaying display text.
If the active profile generation changes while a selection exists, discard
the stale navigator and open `M-x` again.

Runtime command registration is not part of the current profile API. An
extension that contributes a command must first admit a bounded
`Command_Definition` to the process command registry, including implementation
class, invocation contract, requirements, effects, description, and
provenance. Only definitions marked interactive appear in `M-x`; arbitrary
Racket procedures never enter the catalog.

## Inspect effective and rejected definitions

Use the inspection commands through `M-x` after activating a candidate:

| Command | Input | Result |
| --- | --- | --- |
| `describe-key` | One normalized sequence | Winner plus shadowed or masked alternatives. |
| `where-is` | Registered command name | Active effective bindings for that command. |
| `describe-bindings` | None | All active bindings in precedence order. |
| `describe-keymap` | Positive map identifier | The map record, bindings, and remaps. |
| `describe-keymap-conflicts` | None | The latest rejected candidate context. |
| `describe-keymap-state` | None | Snapshot and catalog generations, active and inactive profiles and states, state policy, pending sequence, usage, and command-entry surfaces. |

Use `Up` and `Down` to inspect rows and `q` or `C-g` to close the result. Use
`M-x` directly from the result to return to command navigation.

After a rejected reload, run `describe-keymap-conflicts` before staging another
candidate. The row identifies the failure code and available catalog, profile,
state, scope, selector, surface, map, context, owner, binding, stroke, limit,
and actual values. A rejection does not replace the active snapshot.

The Racket constructors in `src/command/keymap-inspection.rkt` support the same
query vocabulary for extension composition. Their results contain copied
immutable values; they do not expose Odin pointers or authorize arbitrary
resolver callbacks.

## Validate the configuration layer

```sh
raco test src/command/keymaps.rkt
raco test src/hosting/keymap-profile-bridge.rkt
odin test src/interaction -vet -warnings-as-errors
make hosting-test
make native-command-test
make terminal-presentation-test
make verify
```

See the [Contextual Keymap Reference](../../reference/contextual-keymaps/index.md)
for keymap quotas and copied layouts and
[Inspect Interaction Profile Compatibility](../inspect-interaction-profile-compatibility/index.md)
for the complete inspection procedure.
