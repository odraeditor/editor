<!--
SPDX-FileCopyrightText: 2026 Adrian PK
SPDX-License-Identifier: GPL-3.0-only

This file is part of Odra. See COPYING for license terms.
-->

# Why Programmable UI Roles Keep Native Fallbacks

The shared UI pipeline makes presentation replaceable only if packages can
participate without becoming a second owner of editor state or renderer
output. Odra therefore separates provider selection from semantic and physical
authority: Racket composes a bounded provider proposal, while Odin checks the
exact session, logical root, renderer profile, and provider generation before
selection.

## A role is a replacement boundary, not a widget kind

Startup, the Buffer Menu, candidate navigation, Project inventory, keymap
inspection, transient input, and status already use the same logical views,
surfaces, composition, styles, and renderer. Their differences come from the
semantic model and role they present, not from private widget classes.

A role provider can therefore be selected without adding another visual
primitive. Future consumers still have to justify any new primitive from real
behavior; registering a provider is not evidence for trees, tables, popups,
images, notifications, or progress histories.

## Copied values preserve one native owner

Racket receives complete pointer-free records for the current root,
projections, views, list items, input choices, surfaces, composition, compact
status, semantic styles, decorations, providers, requirements, and accounting.
The copy is useful for composition and inspection after the native call
returns, but it cannot mutate the registry that produced it.

Requests repeat the exact observed scope. Odin rejects a request when the
session, root, role registry, provider, renderer, or capability generation has
changed. This turns concurrent drift into an explicit stale result instead of
silently applying a package decision to a different visible generation.

## Confirmation and activation are separate

Proposal confirmation validates identity, copied limits, renderer
requirements, root freshness, callback budget, admitted command, and forbidden
focus or layout effects before the provider can become active. Activation then
checks the confirmed root and renderer again.

Separating the operations lets a package prepare an inactive provider and
inspect the result before selection. Atomic replacement remains available when
the package already owns a confirmed provider generation and needs one checked
transition.

## The fallback is part of correctness

Each role starts with one native confirmed fallback. The fallback is not a
best-effort error screen; it is the delivered built-in provider for that
semantic role. A rejected package proposal preserves the previous active
provider. An exception or callback-budget overrun in an active package marks
that package generation failed and restores the fallback before another turn.

Rollback is explicit and reversible. Teardown closes package ownership and
also restores fallback when needed. Starting a new session generation creates
a clean role registry rather than carrying provider handles across lifetimes.

## Bootstrap privilege remains narrow

The built-ins are package-like at the visible role boundary, but native code
creates their fallback identities before package execution and protects those
identities from package teardown. Odin also retains canonical model mutation,
logical publication, focus and pane-layout authority, renderer lowering,
terminal restoration, and runtime lifecycle.

These exceptions exist for bootstrap, safety, and process ownership. They do
not authorize a feature-specific renderer or a second presentation path.

## Synchronous turns need measured bounds

The embedded Racket runtime is process-long and cannot be restarted after
shutdown or failure. A role control therefore exists for one synchronous owner
thread turn, admits at most 256 callbacks, and clears its native callback state
on return. Exceptions are contained, but the host does not attempt unsafe
in-process preemption of arbitrary Racket code.

The resource study instead measures completed ordinary, demanding, and stress
turns, including the maximum proposal, all-role snapshots, activation,
callback, retained memory, and teardown. The callback budget bounds native
reentry; repository test harnesses bound overall process completion.

See [Programmable UI Roles Reference](../../reference/programmable-ui-roles/index.md)
for the exact API and [Why the UI Foundation Publishes Complete Logical Generations](../extensible-ui-foundation/index.md)
for the underlying publication model.
