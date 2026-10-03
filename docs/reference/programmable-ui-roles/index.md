<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Programmable UI Roles Reference

Odra exposes seven current visible-consumer roles through one checked,
session-scoped Racket capability. Packages can inspect the current logical UI
generation, register a provider, confirm and activate it, replace one confirmed
provider generation, invoke one admitted command, restore the built-in
fallback, and tear the package provider down. Odin retains the role registry,
logical UI registry, renderer contract, and publication authority.

## Responsibility map

| Package | Responsibility |
| --- | --- |
| `ui` | Own the session role registry, provider generations, built-in fallbacks, proposal checks, selection, rollback, failure containment, accounting, and teardown. |
| `bridge` | Define fixed pointer-free UI role records, operation values, byte-width checks, schema entries, and copied limits. |
| `hosting` and `adapter.c` | Lend one dynamic-extent capability to Racket, enforce the owner thread and non-reentrancy, contain exceptions, and clear callback state after return. |
| `command` | Encode immutable UI snapshots, decode package requests, check exact scopes, delegate admitted role operations, and dispatch admitted copied command names. |
| `ui-role-bridge.rkt` | Expose contracted Racket values and compose inspection, proposal, activation, replacement, rollback, teardown, and command requests. |

No Racket value contains a native pointer, terminal cell buffer, canonical
model owner, renderer object, or mutable Odin collection.

## Initial roles

| Racket symbol | Native role | Confirmed fallback |
| --- | --- | --- |
| `'startup` | `Startup` | built-in startup UI |
| `'buffer-menu` | `Buffer_Menu` | built-in Buffer Menu UI |
| `'candidate-navigation` | `Candidate_Navigation` | built-in candidate navigation UI |
| `'project-inventory` | `Project_Inventory` | built-in Project inventory UI |
| `'keymap-inspection` | `Keymap_Inspection` | built-in keymap inspection UI |
| `'transient-input` | `Transient_Input` | built-in transient input UI |
| `'status` | `Status` | built-in status UI |

The role boundary replaces presentation providers. It does not transfer
ownership of buffers, candidate sessions, Projects, prompt or search state,
keymaps, pane layout, focus mutation, terminal output, or physical rendering.

## Session scope and generations

`call-with-ui-role-control` creates one opaque control for a single synchronous
Racket turn. The control is valid only on the runtime owner thread and only
during that dynamic extent. Continuation escape, cross-thread use, nested
entry, or use after return rejects before a role operation reaches Odin.

Every copied `ui-role-scope` binds:

- the role capability schema and access contract;
- the exact editor session identity and generation;
- the logical UI registry and root generation;
- the role-registry generation;
- the role and active provider generation;
- the renderer profile; and
- the scoped-capability generation.

Any mismatch makes the request stale. A package must fetch a fresh scope after
another provider mutation. Starting a new editor-session generation creates a
new role registry with only the seven confirmed built-in fallbacks.

## Provider lifecycle

```text
built-in: confirmed -> active fallback for the session lifetime

package: registered -> confirmed -> active
                  \-> rejected
                  \-> failed -> built-in fallback active
                  \-> closed
```

`ui-role-propose` registers one package provider and confirms its proposal
without selecting it. `ui-role-activate` selects that exact confirmed provider
generation. `ui-role-replace` validates and selects the next generation of an
already confirmed package provider in one registry mutation.

`ui-role-rollback` restores the built-in fallback but leaves the package
provider inspectable. `ui-role-teardown` closes the package provider and also
restores fallback when that provider was active. A contained exception or
callback-budget overrun marks the active package generation failed and selects
the built-in fallback before the next turn.

## Racket values and procedures

| Value | Copied contents |
| --- | --- |
| `ui-role-provider-handle` | Role, provider identity, and provider generation. |
| `ui-role-scope` | Exact session, root, registry, role, renderer, provider, and capability generations. |
| `ui-role-provider` | Handle, built-in or package kind, lifecycle state, copied name and package name, renderer requirements, and confirmed root generation. |
| `ui-role-snapshot` | Exact decoded scope plus one immutable pointer-free snapshot payload. |
| `ui-role-proposal` | Role, copied provider and package names, renderer requirements, bounded package content, one admitted command, and callback budget. |
| `ui-role-outcome` | Refreshed scope, previous and selected providers, confirmed root, change and fallback flags, diagnostic fields, retained bytes, and callback count. |
| `ui-role-failure` | Native failure code plus optional limit and actual values. |

| Procedure | Contract |
| --- | --- |
| `ui-role-current-scope` | Fetch and cache the current exact scope for one accepted role. |
| `ui-role-inspect` | Copy the complete current logical UI snapshot, selected provider, fallback, capability requirements, accounting, and content. |
| `ui-role-inspect-provider` | Copy one exact provider descriptor. |
| `ui-role-propose` | Register and confirm one inactive package provider. |
| `ui-role-activate` | Select one exact confirmed package provider. |
| `ui-role-replace` | Confirm and select a replacement generation atomically. |
| `ui-role-rollback` | Restore the confirmed built-in fallback for a role. |
| `ui-role-teardown` | Close one package provider and restore fallback if needed. |
| `ui-role-invoke-command` | Dispatch the active provider's one exact copied admitted command. |

The proposal `content` field is a copied package payload accounted against the
aggregate request ceiling. It grants no direct access to logical UI storage or
renderer output. Provider confirmation binds the proposal to the exact current
logical root and renderer profile; later root or renderer drift prevents
activation.

## Renderer requirements

Packages may require only the initial renderer capabilities:

- `cell-geometry`;
- `clipping`;
- `unicode-profile`;
- `text-cursor`;
- `input-cursor`;
- `semantic-attributes`;
- `atomic-generation`; and
- `full-redraw`.

Confirmation and activation reject when the current immutable renderer profile
does not include every required capability. Packages cannot claim deferred
overlap, image, native-window, shaping, pointer-input, or physical-output
authority.

## Copied record widths

| Record | Width |
| --- | ---: |
| Scope | 96 bytes |
| Snapshot header | 336 bytes |
| Projection | 88 bytes |
| View | 96 bytes |
| List item | 104 bytes |
| Input choice | 88 bytes |
| Surface | 160 bytes |
| Composition | 200 bytes |
| Status region | 168 bytes |
| Style | 56 bytes |
| Decoration | 120 bytes |
| Provider | 96 bytes |
| Renderer capability requirement | 16 bytes |
| Diagnostic | 80 bytes |
| Request header | 280 bytes |
| Outcome | 184 bytes |

`NATIVE_CONTRACT_SCHEMA_VERSION` is `5`. The runtime verifies all UI role
widths, limits, role values, renderer capabilities, operations, and failure
codes before exposing any capability. Odin and Racket expose a stable
human-readable diagnostic for every published role failure code.

## Selected limits

| Resource | Limit |
| --- | ---: |
| Current roles | 7 |
| Live built-in and package providers per session | 64 |
| Provider name | 96 bytes |
| Package name | 256 bytes |
| Admitted command name | 96 bytes |
| Renderer requirements per provider | 8 |
| Complete proposal request | 8 MiB |
| Provider callbacks per turn | 256 |
| Complete logical UI snapshot | 8 MiB |
| Concurrent hosted role turns | 1 |

The 8 MiB request limit includes the 280-byte header, capability requirement
records, names, content, and command. With the four-requirement fixture and its
standard names, the maximum content is 8,388,234 bytes.

## Privileged bootstrap exceptions

Built-ins use native bootstrap authority to create the seven confirmed
fallback providers before packages run. Package APIs cannot create a built-in
provider, remove or replace the fallback identity, mutate canonical models,
change pane layout or focus directly, publish physical output, or control the
process-long Racket lifecycle. These are documented safety and bootstrap
exceptions to the principle that built-ins and packages share visible role
capabilities.

## Failures and preservation

Role failures distinguish invalid or closed registries, invalid sessions,
roles, or providers, stale provider and scope generations, provider and text
limits, duplicates, wrong provider lifecycle state, renderer incompatibility,
stale roots, proposal and callback limits, forbidden focus or layout effects,
unadmitted commands, generation exhaustion, and allocation failure.

Malformed records, oversized payloads, wrong-thread calls, reentrancy, escaped
controls, and Racket exceptions are contained by the hosting boundary. A
rejected proposal leaves the active provider unchanged. A failed active
package restores the built-in fallback. Rollback and teardown return a fresh
scope, and registry close releases every provider allocation exactly once.

See [Extensible UI Foundation Reference](../extensible-ui-foundation/index.md)
for logical UI records and [Racket Runtime Boundary Reference](../racket-runtime-boundary/index.md)
for process-long hosting rules.
